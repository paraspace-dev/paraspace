#!/usr/bin/env bash
# e2e: the down -> up (resume) -> rm lifecycle, on its own throwaway workspace
# ($PARA_WS2) so it never disturbs the shared primary. Self-cleans with rm; if it
# aborts, teardown reclaims $PARA_WS2 (pre-tracked in test/run).

test_down_up_resume_and_rm() {
  local ws="$PARA_WS2"

  # Bring it up and confirm it serves.
  "$PARA" up "$ws" >/dev/null 2>&1 || return 1
  eventually 30 sh -c "curl -sk --max-time 10 --resolve \"$ws.${PARA_DOMAIN:-paraspace.dev}:$PARA_HTTPS_PORT:127.0.0.1\" \"https://$ws.${PARA_DOMAIN:-paraspace.dev}:$PARA_HTTPS_PORT/\" | grep -q para-e2e-ok" \
    || return 1

  # down: container stops, registry row preserved.
  "$PARA" down "$ws" >/dev/null 2>&1 || return 1
  local ls; ls="$("$PARA" ls 2>/dev/null)"
  assert_contains "$ls" "$ws"     "still listed after down" || return 1
  assert_contains "$ls" "STOPPED" "reports STOPPED"         || return 1

  # up again: resumes the SAME workspace (idempotent up on a stopped one) and
  # reconverges the boot hook, so it serves again.
  "$PARA" up "$ws" >/dev/null 2>&1 || return 1
  eventually 30 sh -c "curl -sk --max-time 10 --resolve \"$ws.${PARA_DOMAIN:-paraspace.dev}:$PARA_HTTPS_PORT:127.0.0.1\" \"https://$ws.${PARA_DOMAIN:-paraspace.dev}:$PARA_HTTPS_PORT/\" | grep -q para-e2e-ok" \
    || return 1

  # rm: gone from the registry and from incus.
  "$PARA" rm "$ws" >/dev/null 2>&1 || return 1
  local names; names="$("$PARA" ls --names 2>/dev/null)"
  assert_not_contains "$names" "$ws" "dropped from the registry after rm" || return 1
  assert_fails incus info "para-$ws"
}
