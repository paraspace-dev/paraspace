#!/usr/bin/env bash
# e2e: repeated `para up` reruns provision and boot on the primary workspace
# and leaves its route serving.

test_up_is_idempotent() {
  # A second up must succeed.
  para_do up "$PARA_WS" || return 1
  # assert_serves retries while Caddy reloads, then checks this workspace's sentinel.
  assert_serves "$PARA_WS" || return 1
  local body; body="$(http_get "$PARA_WS")"
  assert_contains "$body" "para-e2e-ok $PARA_WS" "still serving after re-up"
}
