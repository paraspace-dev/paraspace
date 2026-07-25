#!/usr/bin/env bash
# e2e: the down -> up (resume) -> rm lifecycle, on its own throwaway workspace
# ($PARA_WS2) so it never disturbs the shared primary. Self-cleans with rm; if it
# aborts, teardown reclaims $PARA_WS2 (pre-tracked in test/run).

# The STATE cell for a specific workspace's `para ls` row (or empty). Binds an
# assertion to THIS workspace's row rather than "does the word appear anywhere".
_ls_state() { "$PARA" ls 2>/dev/null | awk -v n="$1" '$1==n{print $2}'; }

test_down_up_resume_and_rm() {
  local ws="$PARA_WS2"

  # Bring it up and confirm it serves.
  para_do up "$ws" || return 1
  assert_serves "$ws" || return 1

  # down: container stops, registry row preserved, THIS row reports STOPPED.
  para_do down "$ws" || return 1
  assert_eq "STOPPED" "$(_ls_state "$ws")" "row reports STOPPED after down" || return 1
  # down on an already-stopped workspace is idempotent (warn + succeed).
  para_do down "$ws" || return 1

  # up again: resumes the SAME workspace (idempotent up on a stopped one) and
  # reconverges the boot hook, so it serves again and reports RUNNING.
  para_do up "$ws" || return 1
  assert_eq "RUNNING" "$(_ls_state "$ws")" "row reports RUNNING after resume" || return 1
  assert_serves "$ws" || return 1

  # rm: gone from the registry and from incus.
  para_do rm "$ws" || return 1
  local names; names="$("$PARA" ls --names 2>/dev/null)"
  assert_not_contains "$names" "$ws" "dropped from the registry after rm" || return 1
  assert_fails incus info "para-$ws" || return 1

  # rm of an already-absent workspace is a forgiving no-op (teardown relies on it).
  para_do rm "$ws"
}
