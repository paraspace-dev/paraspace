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
  assert_contains "$out" "image build" "help mentions image build" || return 1
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
  # a para update must not be able to change it under you. So image build refuses
  # a project whose Parafile declares no base, and does so before it launches
  # anything (the check precedes ensure_backend) — hence CLI-testable. A bare
  # temp project, since the fixture's own Parafile does declare one.
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-nobase.XXXXXX")"
  mkdir -p "$d/.paraspace"
  printf 'PARA_PROJECT=nobase\n' > "$d/.paraspace/Parafile"
  local out rc=0
  out="$(env PARA_PROJECT_DIR="$d" "$PARA" image build 2>&1)" || rc=$?
  rm -rf "$d"
  [ "$rc" -ne 0 ] || { echo "  image build unexpectedly succeeded with no PARA_BASE_IMAGE" >&2; return 1; }
  assert_contains "$out" "PARA_BASE_IMAGE" "refusal names the missing key"
}

test_image_build_alias_is_still_accepted() {
  # `para image-build` is a deprecated alias for `para image build`. It must still
  # reach cmd_image_build (here: refuse the no-base project, same as the primary
  # spelling) and warn that it's deprecated — both CLI-testable, pre-backend.
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-alias.XXXXXX")"
  mkdir -p "$d/.paraspace"
  printf 'PARA_PROJECT=alias\n' > "$d/.paraspace/Parafile"
  local out rc=0
  out="$(env PARA_PROJECT_DIR="$d" "$PARA" image-build 2>&1)" || rc=$?
  rm -rf "$d"
  [ "$rc" -ne 0 ] || { echo "  image-build alias unexpectedly succeeded with no PARA_BASE_IMAGE" >&2; return 1; }
  assert_contains "$out" "deprecated"      "alias warns it is deprecated"  || return 1
  assert_contains "$out" "PARA_BASE_IMAGE" "alias still reaches the build refusal"
}

test_image_rejects_an_unknown_subcommand() {
  # The `para image <sub>` dispatcher rejects an unknown subcommand up front,
  # before any project/backend work — so it's CLI-testable with no incus.
  assert_fails "$PARA" image not-a-subcommand
}

test_up_refuses_undeclared_routes() {
  # PARA_ROUTES has no default port — which port your app listens on is project
  # policy, not para's. An UNSET key is refused (and, like the base-image refusal,
  # before any incus work), so a project can't silently lose its URL to a typo.
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-noroutes.XXXXXX")"
  mkdir -p "$d/.paraspace"
  printf 'PARA_VERSION=1\nPARA_PROJECT=noroutes\n' > "$d/.paraspace/Parafile"
  local out rc=0
  out="$(env PARA_PROJECT_DIR="$d" "$PARA" up somews 2>&1)" || rc=$?
  rm -rf "$d"
  [ "$rc" -ne 0 ] || { echo "  up unexpectedly succeeded with no PARA_ROUTES" >&2; return 1; }
  assert_contains "$out" "PARA_ROUTES" "refusal names the missing key" || return 1
  # The refusal must also teach the empty spelling, which is the whole point of
  # distinguishing unset from empty.
  assert_contains "$out" 'PARA_ROUTES=""' "refusal shows how to declare no routes"
}

test_up_accepts_an_explicitly_empty_route_list() {
  # An empty value is a DECLARATION ("serves no HTTP"), not an omission — the
  # distinction cmd_up refuses an unset key over. void-minimal ships an empty
  # PARA_ROUTES, so this is also the guard on that template being usable at all.
  # (It regressed once already: while PARA_ROUTES was a bash array, `${a+set}`
  # tested element zero, which an empty array hasn't got, so `PARA_ROUTES=()`
  # read as unset and the template could not be brought up.)
  #
  # Asserted by checking that whatever stops the run afterwards is no longer the
  # routes refusal. `up` must NOT be allowed to run past that point: on a machine
  # that has incus, the very next steps (ensure_pool/ensure_volume) create real
  # storage. So the run is stopped deterministically with an `incus` stub that
  # always fails — ensure_backend is the first thing after the routes check, and
  # nothing has touched disk by then.
  local d stub
  d="$(mktemp -d "${TMPDIR:-/tmp}/para-emptyroutes.XXXXXX")"
  stub="$(mktemp -d "${TMPDIR:-/tmp}/para-stub.XXXXXX")"
  # All three backend commands are stubbed, not just incus: ensure_backend probes
  # a different one first per platform (colima on Darwin, and `need caddy` runs
  # before the daemon check on Linux), so stubbing only incus made the failure
  # message environment-dependent — CI has no caddy and died there instead.
  printf '#!/bin/sh\nexit 1\n' > "$stub/incus";  chmod +x "$stub/incus"
  printf '#!/bin/sh\nexit 1\n' > "$stub/caddy";  chmod +x "$stub/caddy"
  printf '#!/bin/sh\nexit 1\n' > "$stub/colima"; chmod +x "$stub/colima"
  mkdir -p "$d/.paraspace"
  printf 'PARA_VERSION=1\nPARA_PROJECT=emptyroutes\nPARA_ROUTES=""\n' > "$d/.paraspace/Parafile"
  local out; out="$(env PATH="$stub:$PATH" PARA_PROJECT_DIR="$d" "$PARA" up somews 2>&1)" || true
  rm -rf "$d" "$stub"
  # Whatever stopped the run, it must not have been about routes — that covers
  # both the unset refusal and any route-validation error, and says nothing about
  # which backend command happens to be missing on this machine.
  assert_not_contains "$out" "PARA_ROUTES" "an empty value is a declaration, not an omission"
}

test_routes_reject_malformed_entries() {
  # PARA_ROUTES entries are spliced into Caddy site addresses AND into the
  # registry's space-separated field 3, so an entry with a space — or an empty one
  # from a stray comma — would shift every reader's parse: `para ls` drops the
  # workspace, and gen_caddyfile emits an upstream Caddy rejects, which fails
  # `caddy reload` and kills routing for every workspace on the machine.
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-badroutes.XXXXXX")"
  mkdir -p "$d/.paraspace"
  local out rc bad
  for bad in '3000,,api:3001' '80 90' 'no-port' '-'; do
    printf 'PARA_VERSION=1\nPARA_PROJECT=badroutes\nPARA_ROUTES="%s"\n' "$bad" > "$d/.paraspace/Parafile"
    rc=0; out="$(env PARA_PROJECT_DIR="$d" "$PARA" ls 2>&1)" || rc=$?
    [ "$rc" -ne 0 ] || { rm -rf "$d"; echo "  PARA_ROUTES=\"$bad\" was accepted" >&2; return 1; }
  done
  rm -rf "$d"
  assert_contains "$out" "[sub:]port" "refusal shows the expected shape"
}

test_routes_can_come_from_the_environment() {
  # As a plain scalar, PARA_ROUTES follows the same precedence as every other key
  # — so a one-off `PARA_ROUTES=… para up` works. That was impossible while it was
  # a bash array (the environment carries only scalars), and is the visible half of
  # why it stopped being one. A Parafile-declared value is still overridden by the
  # environment, like any other scalar key.
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-envroutes.XXXXXX")"
  mkdir -p "$d/.paraspace"
  printf 'PARA_VERSION=1\nPARA_PROJECT=envroutes\nPARA_ROUTES="8080"\n' > "$d/.paraspace/Parafile"
  local rc=0
  env PARA_PROJECT_DIR="$d" PARA_ROUTES="3000,api:3001" "$PARA" ls >/dev/null 2>&1 || rc=$?
  rm -rf "$d"
  [ "$rc" -eq 0 ] || { echo "  a valid PARA_ROUTES from the environment was rejected" >&2; return 1; }
}

test_image_defaults_to_the_project_slug() {
  # PARA_IMAGE DERIVES from PARA_PROJECT rather than a fixed literal: incus image
  # aliases are daemon-global, so a shared default would put two projects that both
  # leave the key unset on ONE image — and a build in either would delete and
  # republish the other's. `--help` prints the resolved config, so this is testable
  # with no incus.
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-imgdef.XXXXXX")"
  mkdir -p "$d/.paraspace"
  printf 'PARA_VERSION=1\nPARA_PROJECT=derived-slug\n' > "$d/.paraspace/Parafile"
  local out; out="$(env PARA_PROJECT_DIR="$d" "$PARA" --help 2>&1)"
  rm -rf "$d"
  # Anchored on the config table's own row, not a bare substring: PARA_VOLUME
  # (para-home-derived-slug) contains the slug too and would match either way.
  printf '%s\n' "$out" | grep -qE '^[[:space:]]*PARA_IMAGE[[:space:]]+derived-slug$' || {
    echo "  PARA_IMAGE did not derive from PARA_PROJECT:" >&2
    printf '%s\n' "$out" | grep -E 'PARA_IMAGE' >&2
    return 1
  }
}

test_config_set_refuses_a_per_project_key() {
  # Per-project identity and build keys are Parafile-only: a box-wide value applies
  # to EVERY project on the machine (one user-config PARA_PROJECT would collapse
  # every project's ownership, `para ls` scoping, and shared volume onto one name).
  local out rc=0
  out="$("$PARA" config-set PARA_PROJECT hijacked 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "  config-set unexpectedly accepted PARA_PROJECT" >&2; return 1; }
  assert_contains "$out" "Parafile" "refusal points at the Parafile" || return 1
  # It's a DENYlist, not an allowlist: any other PARA_* must still persist, because
  # that namespace is how a project passes its own knobs through to its hooks.
  # Cleaned up unconditionally — the sandbox config file is shared with every other
  # test in the run, so a leftover line here would leak into them (test/README.md
  # requires order-independence).
  rc=0; "$PARA" config-set PARA_DEMO_KNOB yes >/dev/null 2>&1 || rc=$?
  _cli_strip_config PARA_DEMO_KNOB
  [ "$rc" -eq 0 ] || { echo "  config-set refused a non-project PARA_* key" >&2; return 1; }
}

# Drop KEY's line from the sandboxed user config. Used by the tests that have to
# write one, so they restore shared state on the FAILURE path too, not just on
# success. Never touches a real config: XDG_CONFIG_HOME is sandboxed by test/run.
_cli_strip_config() {
  local cfg="$XDG_CONFIG_HOME/para/config" tmp
  [ -f "$cfg" ] || return 0
  tmp="$(mktemp)"; grep -v "^$1=" "$cfg" > "$tmp" 2>/dev/null || true; mv "$tmp" "$cfg"
}

test_user_config_ignores_per_project_keys() {
  # The same denylist where it actually bites: a stale per-project line in the user
  # config must not silently beat the Parafile. (XDG_CONFIG_HOME is sandboxed, so
  # this writes to a throwaway config, never the developer's.)
  local cfg="$XDG_CONFIG_HOME/para/config"
  mkdir -p "$(dirname "$cfg")"
  printf 'PARA_IMAGE=hijacked-image\n' >> "$cfg"
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/para-cfgdeny.XXXXXX")"
  mkdir -p "$d/.paraspace"
  printf 'PARA_VERSION=1\nPARA_PROJECT=cfgdeny\n' > "$d/.paraspace/Parafile"
  local out; out="$(env PARA_PROJECT_DIR="$d" "$PARA" --help 2>&1)"
  rm -rf "$d"
  # Restore shared state BEFORE any assertion can return early.
  _cli_strip_config PARA_IMAGE
  assert_not_contains "$out" "hijacked-image" "user-config PARA_IMAGE does not take effect" || return 1
  assert_contains "$out" "ignoring PARA_IMAGE" "para says out loud that it ignored the key"
}

test_template_helpers_do_not_drift() {
  # hooks/helpers is byte-identical across the bundled templates on purpose, and
  # deliberately NOT factored into templates/_common: it has to sit BESIDE the
  # hooks that source it — shellcheck resolves `. "$(dirname "$0")/helpers"` via
  # source-path=SCRIPTDIR, and sync_project pushes only .paraspace/hooks/ into a
  # workspace. So the copies are asserted to stay in step instead.
  local repo ref="" f rc=0 n=0
  repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  for f in "$repo"/templates/*/.paraspace/hooks/helpers; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    if [ -z "$ref" ]; then ref="$f"; continue; fi
    cmp -s "$ref" "$f" || { echo "  drift: ${f#"$repo"/} differs from ${ref#"$repo"/}" >&2; rc=1; }
  done
  [ "$n" -ge 2 ] || { echo "  expected at least two template helpers, found $n" >&2; return 1; }
  return "$rc"
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
