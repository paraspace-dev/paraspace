#!/usr/bin/env bash
# e2e: assertions against the shared primary workspace ($PARA_WS), brought up
# once by test/run. These are read-only — they must not stop, remove, or
# otherwise disturb it (lifecycle tests use their own workspaces).

# The whole point: an HTTP request over TLS, through para's Caddy, to the busybox
# httpd inside the container — returning the exact sentinel the boot hook wrote,
# tagged with THIS workspace's name (proving it routed to the right container).
test_http_route_serves_the_sentinel() {
  eventually 30 sh -c "curl -sk --max-time 10 --resolve \"$PARA_WS.${PARA_DOMAIN:-paraspace.dev}:$PARA_HTTPS_PORT:127.0.0.1\" \"https://$PARA_WS.${PARA_DOMAIN:-paraspace.dev}:$PARA_HTTPS_PORT/\" | grep -q para-e2e-ok" \
    || return 1
  local body; body="$(http_get "$PARA_WS")"
  assert_contains "$body" "para-e2e-ok $PARA_WS" "sentinel body carries the workspace name"
}

test_workspace_is_listed_and_running() {
  local names; names="$("$PARA" ls --names 2>/dev/null)"
  assert_contains "$names" "$PARA_WS" "ls --names includes the workspace" || return 1
  # Bind the state to THIS workspace's row (field 3), not "RUNNING appears
  # somewhere" — otherwise another row being RUNNING could mask a bad state here.
  local state; state="$("$PARA" ls 2>/dev/null | awk -v n="$PARA_WS" '$1==n{print $3}')"
  assert_eq "RUNNING" "$state" "the workspace's row reports RUNNING"
}

test_sh_c_runs_as_the_uid_1000_user() {
  local uid; uid="$("$PARA" sh "$PARA_WS" -c 'id -u' 2>/dev/null)"
  assert_eq "1000" "$uid" "workspace user is uid 1000"
}

test_shared_volume_is_mounted() {
  # The provision hook seeded /para/shared/marker; the shared volume is attached
  # at /para/shared and linked into $HOME.
  local marker; marker="$("$PARA" sh "$PARA_WS" -c 'cat /para/shared/marker' 2>/dev/null)"
  assert_eq "shared-volume-ok" "$marker" "shared volume mounted + seeded"
}

test_sh_c_propagates_exit_status() {
  # para sh -c must exit with the guest command's status, so it composes. The
  # `|| return 1` is load-bearing: the harness runs tests without `set -e`, so a
  # non-final assert whose result isn't checked would be masked by the trailing
  # `exit 0` and the test could never fail on broken propagation.
  assert_fails "$PARA" sh "$PARA_WS" -c 'exit 7' || return 1
  "$PARA" sh "$PARA_WS" -c 'exit 0'
}
