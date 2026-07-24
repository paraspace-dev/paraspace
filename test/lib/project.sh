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

# Temp dirs to remove when the current test finishes. The harness runs each test
# in a subshell and calls scratch_cleanup on the way out, so this is per-test.
declare -a _scratch_dirs=()

scratch() { # scratch — a throwaway dir, auto-removed at end of test
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-t.XXXXXX")"
  _scratch_dirs+=("$d")
  printf '%s\n' "$d"
}

scratch_cleanup() {
  local d
  for d in ${_scratch_dirs[@]+"${_scratch_dirs[@]}"}; do rm -rf "$d"; done
  _scratch_dirs=()
}

# a_project [PARAFILE_LINE]... — a throwaway project whose Parafile declares the
# given lines. PARA_VERSION and PARA_PROJECT are supplied first, so a caller can
# override either by passing its own (plain assignments: last wins). Echoes the
# project dir.
#
#   p="$(a_project PARA_ROUTES='"3000"' PARA_BASE_IMAGE=images:alpine/edge)"
a_project() {
  local d line; d="$(scratch)"
  mkdir -p "$d/.paraspace"
  {
    printf 'PARA_VERSION=1\n'
    printf 'PARA_PROJECT=fixture\n'
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$d/.paraspace/Parafile"
  printf '%s\n' "$d"
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

# assert_allows <project> [args...] — para must get PAST configuration validation.
# It still fails on the fenced backend, so this asserts the absence of a
# configuration refusal rather than overall success.
assert_allows() {
  local proj="$1"; shift
  [ "$#" -gt 0 ] || set -- up ws
  para_in "$proj" "$@"
  case "$PARA_OUT" in
    *"PARA_ROUTES"*|*"PARA_DOMAIN"*|*"not inside a para project"*)
      echo "  unexpected configuration refusal from 'para $*':" >&2
      printf '    %s\n' "$PARA_OUT" >&2
      return 1 ;;
  esac
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

# a_registry_row <name> <ip> <routes> <domain> <project> — seed one workspace row
# into the sandboxed registry, for the readers (`ls`, `web`) that consume it
# without needing a live workspace. Rows are removed with the sandbox.
a_registry_row() {
  local reg="$XDG_STATE_HOME/para/workspaces"
  mkdir -p "$(dirname "$reg")"
  printf '%s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5" >> "$reg"
}

# forget_registry_row <name> — drop it again, so a test that seeds a row leaves
# the shared registry as it found it even on the failure path.
forget_registry_row() {
  local reg="$XDG_STATE_HOME/para/workspaces" tmp
  [ -f "$reg" ] || return 0
  tmp="$(mktemp)"; grep -v "^$1 " "$reg" > "$tmp" 2>/dev/null || true; mv "$tmp" "$reg"
}
