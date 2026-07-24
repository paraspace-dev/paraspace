#!/usr/bin/env bash
# e2e: `para up` is idempotent — re-running it on a live workspace reconverges
# (re-runs provision + boot) and succeeds, still serving. Runs against the shared
# primary workspace since a second up is harmless.

test_up_is_idempotent() {
  # A second up must return zero (reconverge, not error).
  para_do up "$PARA_WS" || return 1
  # …and the route still serves the sentinel for THIS workspace afterwards. Via
  # assert_serves, not a bare http_get: `up` regenerates and reloads the
  # Caddyfile, so the request has to tolerate the reload window.
  assert_serves "$PARA_WS" || return 1
  local body; body="$(http_get "$PARA_WS")"
  assert_contains "$body" "para-e2e-ok $PARA_WS" "still serving after re-up"
}
