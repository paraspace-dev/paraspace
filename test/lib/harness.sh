#!/usr/bin/env bash
# harness.sh — the tiny test runner. Autodiscovers `test_*` functions (like the
# steg CLI suite) and runs each, reporting pass/fail with timing. A test PASSES
# when its function returns zero; the assert.sh helpers return non-zero to fail.
#
# Unlike the steg harness this does NOT exit on first failure — an e2e run is
# expensive to reach, so we run every test and summarize, then exit non-zero if
# any failed. Set PARA_TEST_FAILFAST=1 to stop at the first failure instead.

# Colors only on a tty.
if [ -t 1 ]; then
  _t_grn=$'\033[32m'; _t_red=$'\033[31m'; _t_gray=$'\033[90m'; _t_off=$'\033[0m'
else
  _t_grn='' _t_red='' _t_gray='' _t_off=''
fi

_t_pass=0
_t_fail=0
declare -a _t_failed=()

# Run one test function. A subshell so a test's `cd`, `set -x`, or stray exit
# can't leak into the next — but note `set -e` is NOT applied inside: tests use
# explicit asserts and may run commands expected to fail, so an early non-zero
# shouldn't abort the function before its assert runs.
run_test() {
  local fn="$1" desc start rc
  desc="${fn#test_}"; desc="${desc//_/ }"
  # Progress line only on a tty, where the \r below overwrites it in place; piped
  # output (CI, logs) has no working \r, so skip it and print just the result.
  [ -t 1 ] && printf '%s+ %s%s ' "$_t_gray" "$desc" "$_t_off"
  start="$SECONDS"
  # `|| rc=$?` keeps the runner's `set -e` from aborting on a failing test — the
  # subshell's non-zero is data here, not an error to propagate.
  rc=0
  ( "$fn" ) || rc=$?
  local took=$((SECONDS - start))
  if [ "$rc" -eq 0 ]; then
    printf '\r%s✓%s %s %s(%ds)%s\n' "$_t_grn" "$_t_off" "$desc" "$_t_gray" "$took" "$_t_off"
    _t_pass=$((_t_pass + 1))
  else
    printf '\r%s✗%s %s %s(%ds)%s\n' "$_t_red" "$_t_off" "$desc" "$_t_gray" "$took" "$_t_off"
    _t_fail=$((_t_fail + 1))
    _t_failed+=("$desc")
    [ "${PARA_TEST_FAILFAST:-0}" = 1 ] && return 1
  fi
  return 0
}

# Discover and run every test_* function currently defined, optionally filtered
# by a substring of the (underscores-as-spaces) description. Returns non-zero if
# any test failed.
run_all() {
  local filter="${1:-}" fn desc
  for fn in $(declare -F | awk '/ test_/ {print $NF}'); do
    desc="${fn#test_}"; desc="${desc//_/ }"
    if [ -n "$filter" ]; then
      case "$desc" in *"$filter"*) ;; *) continue ;; esac
    fi
    run_test "$fn" || break
  done
  echo
  if [ "$_t_fail" -eq 0 ]; then
    printf '%s%d passed%s\n' "$_t_grn" "$_t_pass" "$_t_off"
    return 0
  fi
  printf '%s%d passed, %d failed%s: %s\n' \
    "$_t_red" "$_t_pass" "$_t_fail" "$_t_off" "${_t_failed[*]}"
  return 1
}
