#!/usr/bin/env bash
# e2e: what adding a layer to a project whose shared volume is ALREADY seeded
# actually does. Not a claim that it's desirable, since the docs call it
# half-applied and give the manual path out; this asserts that IS the reality,
# so nobody "fixes" it by accident.
#
# Runs on $PARA_WS3, self-cleaning with rm, so the shared primary is untouched.
# The project is a COPY of the tracked fixture with one more layer in it:
# editing test/fixtures/ would dirty the working tree and change what every
# other test composes.
# shellcheck disable=SC2016  # the guest expands these, not us

# A copy of the hello fixture carrying one extra layer, whose provision seeds
# a path of its own and one the earlier layers already wrote. Echoes the
# project dir.
_a_project_with_a_late_layer() {
  local proj; proj="$(scratch)/hello"
  cp -R "$FIXTURE_DIR" "$proj"
  mkdir -p "$proj/.paraspace/layers/late-layer/hooks"
  cat > "$proj/.paraspace/layers/late-layer/hooks/provision" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Its own new path. Nothing else claims it, so it lands on any volume.
echo late-layer-ok > "$PARA_SHARED/late-layer-marker"
# A path an earlier layer already wrote, guarded on the DESTINATION, the shape
# most layers are written in, and the one that silently does nothing on a
# live volume.
if [ ! -e "$PARA_SHARED/late-conflict" ]; then
  echo late-layer-wrote-this > "$PARA_SHARED/late-conflict"
fi
EOF
  # In the stack where add would put it: before the project layer.
  printf '%s\n' '.paraspace/layers/e2e-mod' '.paraspace/layers/late-layer' \
    '.paraspace/layers/project' > "$proj/.paraspace/stack"
  printf '%s\n' "$proj"
}

# para_do, but against a project dir other than the sandbox's fixture. It also
# exports a bogus PARA_LAYER_DIR, because para sets that for a layer's command
# and such a command calling back into `para up` is the ordinary way to write
# one, so this is the real path by which a host directory could reach a guest.
_up_with_project() { # _up_with_project <project-dir> <workspace>
  local out line
  if ! out="$(env PARA_PROJECT_DIR="$1" PARA_LAYER_DIR=/on/the/host "$PARA" up "$2" 2>&1)"; then
    printf '    para up %s failed:\n' "$2" >&2
    while IFS= read -r line; do printf '    | %s\n' "$line" >&2; done <<<"$out"
    return 1
  fi
}

test_a_layer_added_to_a_seeded_volume_is_half_applied() {
  local ws="$PARA_WS3" proj got rc=0
  proj="$(_a_project_with_a_late_layer)"

  # Stand in for something an earlier layer seeded before this one existed.
  # The suite's own /para/shared/marker is off limits, because another test
  # reads it back.
  "$PARA" sh "$PARA_WS" -c 'echo base-wrote-this > /para/shared/late-conflict' \
    >/dev/null 2>&1 || return 1

  _up_with_project "$proj" "$ws" || return 1

  # The `up` above carried a host PARA_LAYER_DIR; guest_env must have dropped
  # it. It has to ride an `up` to test anything, since `para sh` never
  # regenerates ~/.paraspace/env, so asserting on an `sh` proves only that
  # incus doesn't forward the host environment.
  got="$("$PARA" sh "$ws" -c 'echo "${PARA_LAYER_DIR-unset}"' 2>/dev/null)"
  assert_eq "unset" "$got" "PARA_LAYER_DIR is not baked into the guest env" || rc=1

  # The layer's own new path lands: there was nothing there to skip.
  got="$("$PARA" sh "$ws" -c 'cat /para/shared/late-layer-marker' 2>/dev/null)"
  assert_eq "late-layer-ok" "$got" "the layer's new path reached a live volume" || rc=1

  # And the half that surprises people: the earlier value survives, because
  # the layer guarded on the destination and the destination was already there.
  got="$("$PARA" sh "$ws" -c 'cat /para/shared/late-conflict' 2>/dev/null)"
  assert_eq "base-wrote-this" "$got" "the layer did NOT replace what was already seeded" || rc=1

  # The manual path the docs give: delete it by hand, converge again.
  if [ "$rc" -eq 0 ]; then
    "$PARA" sh "$ws" -c 'rm /para/shared/late-conflict' >/dev/null 2>&1 || rc=1
    _up_with_project "$proj" "$ws" || rc=1
    got="$("$PARA" sh "$ws" -c 'cat /para/shared/late-conflict' 2>/dev/null)"
    assert_eq "late-layer-wrote-this" "$got" "removing it by hand lets the layer seed" || rc=1
  fi

  "$PARA" rm "$ws" >/dev/null 2>&1 || true
  return "$rc"
}
