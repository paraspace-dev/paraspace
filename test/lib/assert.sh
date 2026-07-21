#!/usr/bin/env bash
# assert.sh — assertions for the para test suite. Each prints a diagnostic to
# stderr and returns non-zero on failure; the harness (harness.sh) treats any
# non-zero return from a test_* function as a failed test, so a bare `assert_*`
# call is a hard checkpoint. Keep them small and shellcheck-clean.

# assert <cmd...> — the command must succeed.
assert() {
  if ! "$@"; then echo "  assert failed: $*" >&2; return 1; fi
}

# assert_eq <expected> <actual> [label]
assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "  assert_eq${3:+ ($3)} failed: expected '$1', got '$2'" >&2
    return 1
  fi
}

# assert_contains <haystack> <needle> [label]
assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) echo "  assert_contains${3:+ ($3)} failed: '$2' not in:" >&2
       printf '    %s\n' "$1" >&2; return 1 ;;
  esac
}

# assert_not_contains <haystack> <needle> [label]
assert_not_contains() {
  case "$1" in
    *"$2"*) echo "  assert_not_contains${3:+ ($3)} failed: found '$2' in:" >&2
            printf '    %s\n' "$1" >&2; return 1 ;;
    *) return 0 ;;
  esac
}

# assert_fails <cmd...> — the command must FAIL (non-zero). For "para rejects X".
assert_fails() {
  if "$@" >/dev/null 2>&1; then
    echo "  assert_fails failed: '$*' unexpectedly succeeded" >&2
    return 1
  fi
}

# eventually <timeout-s> <cmd...> — retry until the command succeeds or the
# timeout elapses (0.25s between tries). For race-free waits on async state
# (an HTTP endpoint, a state transition) without a fixed sleep.
eventually() {
  local timeout="$1"; shift
  local deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 0.25
  done
  echo "  eventually: '$*' never succeeded within ${timeout}s" >&2
  return 1
}

# curl a workspace URL through the run's para Caddy, hermetically (--resolve, so
# it never depends on public DNS for *.paraspace.dev) and without cert fussing
# (-k, para's internal CA). Echoes the body; non-zero on transport failure.
http_get() { # http_get <workspace>
  local ws="$1" host
  host="$ws.${PARA_DOMAIN:-paraspace.dev}"
  curl -sk --max-time 10 --resolve "$host:$PARA_HTTPS_PORT:127.0.0.1" \
    "https://$host:$PARA_HTTPS_PORT/"
}
