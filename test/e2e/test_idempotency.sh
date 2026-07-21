#!/usr/bin/env bash
# e2e: `para up` is idempotent — re-running it on a live workspace reconverges
# (re-runs provision + boot) and succeeds, still serving. Runs against the shared
# primary workspace since a second up is harmless.

test_up_is_idempotent() {
  # A second up must return zero (reconverge, not error).
  "$PARA" up "$PARA_WS" >/dev/null 2>&1 || return 1
  # …and the route still serves the sentinel afterwards.
  local body; body="$(http_get "$PARA_WS")"
  assert_contains "$body" "para-e2e-ok" "still serving after re-up"
}
