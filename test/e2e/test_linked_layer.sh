#!/usr/bin/env bash
# e2e: a layer whose files are symlinks into the host tree, which is the shape
# npm and bun leave a linked package in, must land in the guest as real files.
# push_stack composes a dereferenced copy on the host before pushing; pushing
# the links raw would leave them dangling in the guest, where run-hook skips
# every hook they name.
# shellcheck disable=SC2016  # the guest expands these, not us

# A copy of the hello fixture with one extra layer whose provision hook is a
# symlink to a file elsewhere on the host. Echoes the project dir.
_a_project_with_a_linked_layer() {
  local proj src; proj="$(scratch)/hello" src="$(scratch)"
  cp -R "$FIXTURE_DIR" "$proj"
  cat > "$src/provision" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo linked-layer-ok > "$HOME/linked-layer-marker"
EOF
  a_layer "$proj" linked
  mkdir -p "$proj/.paraspace/layers/linked/hooks"
  ln -s "$src/provision" "$proj/.paraspace/layers/linked/hooks/provision"
  printf '%s\n' "$proj"
}

test_a_symlinked_layer_lands_as_real_files() {
  local ws="$PARA_WS4" proj got out line rc=0
  proj="$(_a_project_with_a_linked_layer)"

  if ! out="$(env PARA_PROJECT_DIR="$proj" "$PARA" up "$ws" 2>&1)"; then
    printf '    para up %s failed:\n' "$ws" >&2
    while IFS= read -r line; do printf '    | %s\n' "$line" >&2; done <<<"$out"
    return 1
  fi

  # The hook ran, so the layer's copy in the guest was readable and real.
  got="$("$PARA" sh "$ws" -c 'cat "$HOME/linked-layer-marker"' 2>/dev/null)"
  assert_eq "linked-layer-ok" "$got" "the symlinked hook ran in the guest" || rc=1

  # And the pushed file itself is a regular file, not a link back to the host.
  "$PARA" sh "$ws" -c 'test -f "$HOME/.paraspace/stack/linked/hooks/provision" \
    && ! test -L "$HOME/.paraspace/stack/linked/hooks/provision"' >/dev/null 2>&1 \
    || { echo "  the pushed hook is missing or still a symlink" >&2; rc=1; }

  "$PARA" rm "$ws" >/dev/null 2>&1 || true
  return "$rc"
}
