#!/usr/bin/env bash
# CLI-tier tests — no incus. Argument handling, help text, and `para init`
# (pure filesystem). Fast enough to run on every push in CI.
#
# `para` is $PARA (the binary under test). PARA_PROJECT_DIR may be set by an
# --all run (pinning para at the e2e fixture); the init tests unset it and run in
# a fresh temp dir so they scaffold cleanly.

test_help_lists_the_command_surface() {
  local out; out="$("$PARA" --help 2>&1)"
  assert_contains "$out" "up"          "help mentions up"          || return 1
  assert_contains "$out" "image-build" "help mentions image-build" || return 1
  assert_contains "$out" "init"        "help mentions init"        || return 1
}

test_init_scaffolds_a_paraspace_dir() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-init.XXXXXX")"
  ( cd "$d" && env -u PARA_PROJECT_DIR "$PARA" init void-minimal >/dev/null 2>&1 )
  assert test -f "$d/.paraspace/Parafile"        || { rm -rf "$d"; return 1; }
  assert test -f "$d/.paraspace/hooks/provision" || { rm -rf "$d"; return 1; }
  assert test -f "$d/.paraspace/hooks/boot"      || { rm -rf "$d"; return 1; }
  rm -rf "$d"
}

test_init_names_lists_bundled_templates() {
  local out; out="$(env -u PARA_PROJECT_DIR "$PARA" init --names 2>&1)"
  assert_contains "$out" "void-minimal"   "template listed" || return 1
  assert_contains "$out" "void-docker-gh" "default listed"  || return 1
}

test_rejects_an_invalid_workspace_name() {
  # validate_name runs before any backend work, so this fails fast with no incus.
  assert_fails "$PARA" up "Bad_Name"
}

test_rejects_an_unknown_command() {
  assert_fails "$PARA" this-is-not-a-command
}

test_up_refuses_a_name_owned_by_another_project() {
  # para refuses to adopt a name owned by a different project, and does so BEFORE
  # any incus call (the project_of check in cmd_up) — so this data-clobbering
  # safeguard is CLI-testable. Seed a foreign-owned row into the sandbox registry.
  local reg="$XDG_STATE_HOME/para/workspaces"
  mkdir -p "$(dirname "$reg")"
  printf 'borrowed 10.0.0.9 8080 paraspace.dev someotherproject\n' >> "$reg"
  local out rc=0
  out="$(env PARA_PROJECT_DIR="$FIXTURE_DIR" PARA_PROJECT=mine "$PARA" up borrowed 2>&1)" || rc=$?
  # Remove the seeded row regardless of outcome (the registry may be shared with
  # e2e rows in an --all run).
  local tmp; tmp="$(mktemp)"; grep -v '^borrowed ' "$reg" > "$tmp" 2>/dev/null || true; mv "$tmp" "$reg"
  [ "$rc" -ne 0 ] || { echo "  up unexpectedly succeeded on a foreign-owned name" >&2; return 1; }
  assert_contains "$out" "someotherproject" "refusal names the owning project"
}

test_image_build_refuses_without_a_base_image() {
  # PARA_BASE_IMAGE has no default on purpose — para never picks your distro, and
  # a para update must not be able to change it under you. So image-build refuses
  # a project whose Parafile declares no base, and does so before it launches
  # anything (the check precedes ensure_backend) — hence CLI-testable. A bare
  # temp project, since the fixture's own Parafile does declare one.
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-nobase.XXXXXX")"
  mkdir -p "$d/.paraspace"
  printf 'PARA_PROJECT=nobase\n' > "$d/.paraspace/Parafile"
  local out rc=0
  out="$(env PARA_PROJECT_DIR="$d" "$PARA" image-build 2>&1)" || rc=$?
  rm -rf "$d"
  [ "$rc" -ne 0 ] || { echo "  image-build unexpectedly succeeded with no PARA_BASE_IMAGE" >&2; return 1; }
  assert_contains "$out" "PARA_BASE_IMAGE" "refusal names the missing key"
}

test_up_refuses_a_contract_version_mismatch() {
  # A Parafile pinning a different PARA_VERSION than para's PARA_CONTRACT must be
  # refused (require_project) — the whole point of the versioned seam. Also
  # pre-incus, so CLI-testable.
  local out rc=0
  out="$(env PARA_PROJECT_DIR="$FIXTURE_DIR" PARA_VERSION=999 "$PARA" up somews 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "  up unexpectedly succeeded on a contract mismatch" >&2; return 1; }
  assert_contains "$out" "contract" "refusal mentions the contract mismatch"
}
