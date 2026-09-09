#!/usr/bin/env bash
# e2e: the down -> up (resume) -> rm lifecycle, on its own throwaway workspace
# ($PARA_WS2) so it never disturbs the shared primary. Self-cleans with rm; if it
# aborts, teardown reclaims $PARA_WS2 (pre-tracked in test/run).

# Read the named workspace's STATE cell, or return empty if its row is absent.
_ls_state() { "$PARA" ls 2>/dev/null | awk -v n="$1" '$1==n{print $2}'; }

test_down_up_resume_and_rm() {
  local ws="$PARA_WS2"

  # Bring it up and confirm it serves.
  para_do up "$ws" || return 1
  assert_serves "$ws" || return 1

  # The stopped container remains listed with state STOPPED.
  para_do down "$ws" || return 1
  assert_eq "STOPPED" "$(_ls_state "$ws")" "row reports STOPPED after down" || return 1
  # down on an already-stopped workspace is idempotent (warn + succeed).
  para_do down "$ws" || return 1

  # Resume the workspace and rerun its boot hook.
  para_do up "$ws" || return 1
  assert_eq "RUNNING" "$(_ls_state "$ws")" "row reports RUNNING after resume" || return 1
  assert_serves "$ws" || return 1

  # Remove the container, listing, and Caddy route.
  para_do rm "$ws" || return 1
  local names; names="$("$PARA" ls --names 2>/dev/null)"
  assert_not_contains "$names" "$ws" "dropped from the listing after rm" || return 1
  assert_fails incus info "para-$ws" || return 1
  assert_stops_serving "$ws" || return 1
  # Check the Caddyfile too: a stale site could route to a future workspace
  # assigned the same IP. The HTTP check alone cannot detect that.
  assert_not_contains "$(cat "$XDG_STATE_HOME/para/Caddyfile")" "$ws.${PARA_DOMAIN:-paraspace.dev}" \
    "rm regenerated the Caddyfile without the workspace" || return 1

  # rm of an already-absent workspace is a forgiving no-op (teardown relies on it).
  para_do rm "$ws"
}
