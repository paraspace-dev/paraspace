#!/usr/bin/env bash
# e2e: the per-project shared volume is genuinely shared — a file written into
# /para/shared from one workspace is visible in another workspace of the same
# project. Uses $PARA_WS (primary) as the writer and a second workspace
# ($PARA_WS3) as the reader.

test_shared_volume_is_visible_across_workspaces() {
  local reader="$PARA_WS3"
  # A value unique to this run, so we're not reading a stale marker.
  local token="xfer-$$-$SECONDS"

  # Write it into the shared volume from the primary workspace.
  "$PARA" sh "$PARA_WS" -c "echo '$token' > /para/shared/xfer" >/dev/null 2>&1 || return 1

  # Bring up a second workspace of the SAME project — it attaches the same
  # para-home-<project> volume at /para/shared.
  para_do up "$reader" || return 1

  # The reader sees the writer's file.
  local got; got="$("$PARA" sh "$reader" -c 'cat /para/shared/xfer' 2>/dev/null)"
  "$PARA" rm "$reader" >/dev/null 2>&1 || true
  assert_eq "$token" "$got" "shared volume carries the file across workspaces"
}
