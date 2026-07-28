#!/usr/bin/env bash
# project.sh — fixtures for the CLI tier, so a test reads as a story rather than
# as eight lines of mktemp/printf/rm ceremony:
#
#   test_routes_reject_a_duplicate_apex() {
#     local p; p="$(a_project PARA_ROUTES='"3000,3001"')"
#     assert_refuses "$p" "more than one bare port"
#   }
#
# Two rules make that possible:
#
#   1. Every temp dir is registered and removed by the harness when the test ends
#      — on the FAILURE path too — so no test carries cleanup, and no early
#      `return 1` can leak state into the next test.
#   2. Every para invocation runs with the backend FENCED (see a_fenced_backend).
#      `para up` on a developer box otherwise creates a storage pool and volume
#      and starts a Caddy on the unsandboxable admin port :2019. Tests must never
#      depend on para "probably" dying before it gets there.

# Where the current test's throwaway dirs are recorded, so the harness can
# remove them when it ends — on the failure path too. See scratch(), below.
_SCRATCH_LIST="$(mktemp "${TMPDIR:-/tmp}/para-scratch.XXXXXX")"

# Every caller uses `d="$(scratch)"`, which runs this in a command-substitution
# SUBSHELL — so an array appended to here would be discarded, and the cleanup
# below would silently never remove anything (it didn't, for a long time; the
# machine had a thousand leaked dirs). A file survives the subshell.
# The trailing slash matters: macOS sets TMPDIR with one, and a path that
# reaches a test as `…/T//x` never compares equal to the same path a `cd`+`pwd`
# has normalized — which is how run-hook reports its own root.
scratch() { # scratch — a throwaway dir, auto-removed at end of test
  local tmp="${TMPDIR:-/tmp}" d
  d="$(mktemp -d "${tmp%/}/para-t.XXXXXX")"
  printf '%s\n' "$d" >> "$_SCRATCH_LIST"
  printf '%s\n' "$d"
}

scratch_cleanup() {
  local d
  [ -f "$_SCRATCH_LIST" ] || return 0
  while IFS= read -r d; do [ -n "$d" ] && rm -rf "$d"; done < "$_SCRATCH_LIST"
  : > "$_SCRATCH_LIST"
}

# a_project [PARAFILE_LINE]... — a throwaway project whose Parafile declares the
# given lines. PARA_CONTRACT and PARA_PROJECT are supplied first, so a caller can
# override either by passing its own (plain assignments: last wins). Echoes the
# project dir.
#
#   p="$(a_project PARA_ROUTES='"3000"' PARA_IMAGE_BASE=images:alpine/edge)"
#
# Note the spelling: these are PLAIN assignments, which under para's precedence
# model means "the project insists". A test about the environment winning must
# pass the `: "${KEY:=value}"` form instead — see test_cli.sh.
a_project() {
  local d line; d="$(scratch)"
  mkdir -p "$d/.paraspace"
  {
    printf 'PARA_CONTRACT=1\n'
    printf 'PARA_PROJECT=fixture\n'
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$d/.paraspace/Parafile"
  printf '%s\n' "$d"
}

# a_project_command <project> <verb> <body> — drop an executable into the
# project's .paraspace/commands/, which is how a project extends para.
a_project_command() {
  mkdir -p "$1/.paraspace/commands"
  printf '%s\n' "$3" > "$1/.paraspace/commands/$2"
  chmod +x "$1/.paraspace/commands/$2"
}

# a_mod_command <project> <mod> <verb> <body> — the same, from a vendored mod.
# The twin of a_project_command, so a test about which one wins reads as two
# lines that differ only in the owner.
a_mod_command() {
  mkdir -p "$1/.paraspace/mods/$2/commands"
  printf '%s\n' "$4" > "$1/.paraspace/mods/$2/commands/$3"
  chmod +x "$1/.paraspace/mods/$2/commands/$3"
}

# a_scaffolded_project [<template>] — what `para init` actually produces, for
# tests that must exercise the shipped templates rather than a hand-written
# Parafile. Echoes the project dir.
a_scaffolded_project() {
  local d; d="$(scratch)"
  ( cd "$d" && env -u PARA_PROJECT_DIR "$PARA" init ${1:+"$1"} >/dev/null 2>&1 )
  printf '%s\n' "$d"
}

# a_fenced_backend — a PATH dir whose backend commands all FAIL and RECORD being
# called. Fencing serves two purposes: para can never reach the real daemon from
# a CLI test, and `assert_backend_untouched` can prove para stopped before trying.
# Several tests assert in a comment that a check happens "before any incus call";
# the fence turns that claim into something the suite verifies.
a_fenced_backend() {
  local d c; d="$(scratch)"
  for c in incus caddy colima lxc; do
    { printf '#!/bin/sh\n'
      printf 'printf "%%s\\n" "%s $*" >> %s/calls\n' "$c" "$d"
      printf 'exit 1\n'
    } > "$d/$c"
    chmod +x "$d/$c"
  done
  printf '%s\n' "$d"
}

# Results of the last para_in. Globals rather than an echoed string, because a
# `$(para_in …)` capture would run the helper in a SUBSHELL and lose the exit
# status and the fence path with it — the whole point is to assert on both.
PARA_OUT=""
PARA_RC=0
PARA_FENCE=""

# para_in <project> <args>... — run para against <project> with the backend
# fenced. Sets $PARA_OUT (combined output) and $PARA_RC. Never fails the test, so
# a caller decides what a non-zero status means. Set $PARA_CWD to run from a
# particular directory.
para_in() {
  local proj="$1"; shift
  [ -n "$PARA_FENCE" ] || PARA_FENCE="$(a_fenced_backend)"
  PARA_RC=0
  PARA_OUT="$(cd "${PARA_CWD:-$PWD}" && env PATH="$PARA_FENCE:$PATH" PARA_PROJECT_DIR="$proj" "$PARA" "$@" 2>&1)" || PARA_RC=$?
  return 0
}

# assert_refuses <project> <needle> [args...] — para must FAIL and say why.
# Defaults to `up ws`, the command most config is consumed by.
assert_refuses() {
  local proj="$1" needle="$2"; shift 2
  [ "$#" -gt 0 ] || set -- up ws
  para_in "$proj" "$@"
  if [ "$PARA_RC" -eq 0 ]; then
    echo "  expected 'para $*' to fail, but it succeeded:" >&2
    printf '    %s\n' "$PARA_OUT" >&2
    return 1
  fi
  assert_contains "$PARA_OUT" "$needle" "the refusal explains why"
}

# a_stub_incus <version> <yes|no device columns> — a PATH dir with an `incus`
# that answers the two questions `para doctor` asks about the daemon: what
# version it is, and whether it can select device columns (which is how para
# reads workspace state). Everything else fails, which doctor reports as its own
# check. Echoes the dir.
a_stub_incus() {
  local d; d="$(scratch)"
  {
    printf '#!/bin/sh\n'
    printf 'version=%s\n' "$1"
    printf 'devices=%s\n' "$2"
    cat <<'STUB'
case "$1" in
  version) printf 'Client version: %s\nServer version: %s\n' "$version" "$version"; exit 0 ;;
  info)    exit 0 ;;
  list)    case "$*" in *devices:*) [ "$devices" = yes ] || exit 1 ;; esac; exit 0 ;;
esac
exit 1
STUB
  } > "$d/incus"
  chmod +x "$d/incus"
  printf '%s\n' "$d"
}

# assert_backend_untouched — no fenced command was executed. Pairs with the
# tests whose whole point is that a check fires before any backend work.
assert_backend_untouched() {
  [ -n "$PARA_FENCE" ] || { echo "  no fenced backend in this test" >&2; return 1; }
  if [ -s "$PARA_FENCE/calls" ]; then
    echo "  expected no backend calls, got:" >&2
    sed 's/^/    /' "$PARA_FENCE/calls" >&2
    return 1
  fi
}
