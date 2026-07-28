#!/usr/bin/env bash
# e2e: what adding a mod to a project whose shared volume is ALREADY seeded
# actually does. Not a claim that it's desirable — docs/mods.md calls it
# half-applied and gives the manual path out; this asserts that IS the reality,
# so nobody "fixes" it by accident.
#
# Runs on $PARA_WS3, self-cleaning with rm, so the shared primary is untouched.
# The project is a COPY of the tracked fixture with one more mod in it: adding a
# mod to test/fixtures/ would dirty the working tree and hand bin/lint the
# installed copy to lint.

# A copy of the hello fixture carrying one extra mod, whose provision seeds in
# the two shapes a mod seeds in. Echoes the project dir.
_a_project_with_a_late_mod() {
  local proj; proj="$(scratch)/hello"
  cp -R "$FIXTURE_DIR" "$proj"
  mkdir -p "$proj/.paraspace/mods/late-mod/hooks"
  cat > "$proj/.paraspace/mods/late-mod/hooks/provision" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Its own new path. Nothing else claims it, so it lands on any volume.
echo late-mod-ok > "$PARA_SHARED/late-mod-marker"
# A path the base already wrote, guarded on the DESTINATION — the shape most
# mods are written in, and the one that silently does nothing on a live volume.
if [ ! -e "$PARA_SHARED/late-conflict" ]; then
  echo late-mod-wrote-this > "$PARA_SHARED/late-conflict"
fi
EOF
  printf '%s\n' "$proj"
}

# para_do, but against a project dir other than the sandbox's fixture.
_up_with_project() { # _up_with_project <project-dir> <workspace>
  local out line
  if ! out="$(env PARA_PROJECT_DIR="$1" "$PARA" up "$2" 2>&1)"; then
    printf '    para up %s failed:\n' "$2" >&2
    while IFS= read -r line; do printf '    | %s\n' "$line" >&2; done <<<"$out"
    return 1
  fi
}

test_a_mod_added_to_a_seeded_volume_is_half_applied() {
  local ws="$PARA_WS3" proj got rc=0
  proj="$(_a_project_with_a_late_mod)"

  # Stand in for something the base seeded before the mod existed. The suite's
  # own /para/shared/marker is off limits — another test reads it back.
  "$PARA" sh "$PARA_WS" -c 'echo base-wrote-this > /para/shared/late-conflict' \
    >/dev/null 2>&1 || return 1

  _up_with_project "$proj" "$ws" || return 1

  # The mod's own new path lands: there was nothing there to skip.
  got="$("$PARA" sh "$ws" -c 'cat /para/shared/late-mod-marker' 2>/dev/null)"
  assert_eq "late-mod-ok" "$got" "the mod's new path reached a live volume" || rc=1

  # And the half that surprises people: the base's value survives, because the
  # mod guarded on the destination and the destination was already there.
  got="$("$PARA" sh "$ws" -c 'cat /para/shared/late-conflict' 2>/dev/null)"
  assert_eq "base-wrote-this" "$got" "the mod did NOT replace what the base wrote" || rc=1

  # The manual path docs/mods.md gives: delete it by hand, converge again.
  if [ "$rc" -eq 0 ]; then
    "$PARA" sh "$ws" -c 'rm /para/shared/late-conflict' >/dev/null 2>&1 || rc=1
    _up_with_project "$proj" "$ws" || rc=1
    got="$("$PARA" sh "$ws" -c 'cat /para/shared/late-conflict' 2>/dev/null)"
    assert_eq "late-mod-wrote-this" "$got" "removing it by hand lets the mod seed" || rc=1
  fi

  "$PARA" rm "$ws" >/dev/null 2>&1 || true
  return "$rc"
}
