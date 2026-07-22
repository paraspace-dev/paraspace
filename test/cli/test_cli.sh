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
