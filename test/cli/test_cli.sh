#!/usr/bin/env bash
# CLI-tier tests — no incus. Argument handling, help text, configuration
# validation and `para init`. Fast enough to run on every push in CI.
#
# Fixtures come from test/lib/project.sh: `a_project` builds a throwaway project,
# `assert_refuses`/`assert_allows` run para against it with the backend fenced,
# and the harness removes everything afterwards. Tests should read as a story —
# arrange one project, assert one behavior.
#
# Two habits worth keeping, both learned the hard way on this suite:
#   * assert the RESOLVED VALUE, not just a non-zero exit. Several tests here once
#     passed while the thing they claimed to check was broken, because something
#     else in the setup already guaranteed the failure they were asserting.
#   * never let `para up` reach the backend. `assert_*` fences it; a bare
#     invocation on a developer box creates real storage and starts a real Caddy.

# ---------------------------------------------------------------- help + usage

test_help_lists_the_command_surface() {
  local out; out="$("$PARA" --help 2>&1)"
  assert_contains "$out" "up"          "help mentions up"          || return 1
  assert_contains "$out" "image build" "help mentions image build" || return 1
  assert_contains "$out" "init"        "help mentions init"        || return 1
}

test_help_reports_the_resolved_config() {
  # --help doubles as the config table, and bin/para designates it the
  # authoritative copy of precedence. Outside a project PARA_IMAGE has no real
  # value, so it must say so rather than print the placeholder literal.
  local out; out="$(env -u PARA_PROJECT_DIR "$PARA" --help 2>&1)"
  assert_not_contains "$out" "para-dev" "no placeholder image literal is advertised" || return 1
  assert_contains "$out" "user config" "precedence names the user config"
}

test_rejects_an_unknown_command() {
  assert_fails "$PARA" this-is-not-a-command
}

test_rejects_an_invalid_workspace_name() {
  # Asserts the MESSAGE, not just non-zero: outside a project `require_project`
  # would fail this command anyway, so an exit-status-only check would pass even
  # with validate_name removed entirely.
  local p; p="$(a_project PARA_ROUTES='"3000"')"
  para_in "$p" up "Bad_Name"
  [ "$PARA_RC" -ne 0 ] || { echo "  an invalid workspace name was accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "invalid name" "the refusal names the rule" || return 1
  assert_backend_untouched
}

# --------------------------------------------------------------------- routes

test_routes_must_be_declared() {
  # No default port: which port your app listens on is project policy. An UNSET
  # key is refused; the message must also teach the empty spelling, which is the
  # entire reason unset and empty are distinguished.
  local p; p="$(a_project)"
  para_in "$p" up ws
  [ "$PARA_RC" -ne 0 ] || { echo "  up succeeded with no PARA_ROUTES" >&2; return 1; }
  assert_contains "$PARA_OUT" "PARA_ROUTES is not set" "refusal names the missing key" || return 1
  assert_contains "$PARA_OUT" 'PARA_ROUTES=""'         "refusal shows how to declare none" || return 1
  assert_backend_untouched
}

test_routes_may_be_declared_empty() {
  # Empty is a DECLARATION ("serves no HTTP"), not an omission. void-minimal ships
  # it, so this also guards that template being usable at all.
  assert_allows "$(a_project PARA_ROUTES='""')"
}

test_routes_accept_flexible_separators() {
  # Commas, spaces, tabs and newlines all separate entries, so a project with
  # several routes can lay them out to be read.
  local p
  for p in '"3000,api:3001"' '"3000, api:3001, db:8081"' '"3000 api:3001"' '"
  3000
  api:3001
"'; do
    assert_allows "$(a_project "PARA_ROUTES=$p")" || { echo "  rejected: $p" >&2; return 1; }
  done
}

test_routes_reject_malformed_entries() {
  # Entries land in a Caddy site address AND in the registry's space-separated
  # positional field 3. '3000:app' is sub:port reversed — left is where you
  # arrive, as in `docker -p`; an all-digit DNS label is legal so the two orders
  # cannot be told apart, and the reverse is refused rather than guessed.
  local bad
  for bad in '3000,,api:3001' '80 90x' 'no-port' '-' '3000:app' '0080'; do
    assert_refuses "$(a_project "PARA_ROUTES=\"$bad\"")" "PARA_ROUTES" \
      || { echo "  accepted: $bad" >&2; return 1; }
  done
}

test_routes_reject_what_caddy_would_refuse() {
  # Shape is not enough — these all look like "[sub:]port" but make Caddy reject
  # the WHOLE config. caddy_reload swallows that error, so para would report the
  # workspace ready while it served nothing, and the next cold start would fail
  # for every workspace on the machine.
  assert_refuses "$(a_project 'PARA_ROUTES="99999"')"          "1-65535"            || return 1
  assert_refuses "$(a_project 'PARA_ROUTES="0"')"              "1-65535"            || return 1
  assert_refuses "$(a_project 'PARA_ROUTES="3000,3001"')"      "more than one bare" || return 1
  assert_refuses "$(a_project 'PARA_ROUTES="api:3000,api:3001"')" "more than once"  || return 1
  # DNS is case-insensitive: these are ONE host, and Caddy would silently serve
  # only the first — quieter than the ambiguous-site error, so worth its own case.
  assert_refuses "$(a_project 'PARA_ROUTES="API:3000,api:3001"')" "more than once"
}

test_routes_keep_every_entry() {
  # Guards the founding bug of this key, in the one form the CLI tier can see:
  # if the parser kept only the first entry, "3000,3000" would collapse to a
  # single route and be ACCEPTED instead of caught as a duplicate apex.
  assert_refuses "$(a_project 'PARA_ROUTES="3000,3000"')" "more than one bare"
}

test_routes_do_not_glob_against_the_cwd() {
  # The split must be unquoted to divide on IFS, which also exposes it to PATHNAME
  # expansion — so without `set -f` a value like "30*" resolved against whatever
  # files sat in $PWD. Asserted on the VALUE echoed back in the error, because the
  # verdict alone is identical from both directories.
  local p g; p="$(a_project 'PARA_ROUTES="30*"')"; g="$(scratch)"
  : > "$g/3000"; : > "$g/3005"
  PARA_CWD="$g" para_in "$p" up ws
  assert_contains "$PARA_OUT" "'30*'" "the literal survived, unexpanded by the cwd"
}

test_routes_refuse_the_legacy_array_form() {
  # `$PARA_ROUTES` on an array yields element ZERO, so the pre-scalar spelling
  # would publish :3000 and drop the rest silently.
  local d; d="$(scratch)"; mkdir -p "$d/.paraspace"
  printf 'PARA_VERSION=1\nPARA_PROJECT=arr\nPARA_ROUTES=( "3000" "api:3001" )\n' > "$d/.paraspace/Parafile"
  assert_refuses "$d" "not an array"
}

test_routes_come_from_the_environment() {
  # A plain scalar follows ordinary precedence, so a one-off override works —
  # impossible while this was an array. Asserted with a value para MUST reject:
  # if the scaffolded Parafile's own valid routes won instead, `up` would get past
  # validation and this would not appear. (A previous version of this test checked
  # only the exit code, and passed while every template clobbered the environment.)
  local p out; p="$(a_scaffolded_project)"
  PARA_FENCE="$(a_fenced_backend)"
  out="$(env PATH="$PARA_FENCE:$PATH" PARA_PROJECT_DIR="$p" PARA_ROUTES='@@notaroute@@' "$PARA" up ws 2>&1)" || true
  assert_contains "$out" "@@notaroute@@" "the environment's value is the one para validated"
}

test_a_bad_parafile_does_not_brick_recovery_commands() {
  # Route validation runs at `up`, not config load. It used to exit during load,
  # so one stray character in one project disabled `ls`, `rm`, `reconcile` and
  # `--help` for every project — including the help documenting the fix.
  local p; p="$(a_project 'PARA_ROUTES="3000, ,8080"')"
  para_in "$p" ls    >/dev/null; [ "$PARA_RC" -eq 0 ] || { echo "  'para ls' was bricked" >&2; return 1; }
  para_in "$p" --help >/dev/null; [ "$PARA_RC" -eq 0 ] || { echo "  'para --help' was bricked" >&2; return 1; }
  assert_refuses "$p" "PARA_ROUTES"   # …while up, which consumes them, still refuses
}

# --------------------------------------------------------------------- domain

test_domain_is_validated_on_write_and_at_use() {
  # PARA_DOMAIN is registry field 4 and a Caddy site address, so a space corrupts
  # both. It is checked on the way IN and at `up` — never at config load, because
  # a bad stored value must not disable `config-set` itself, the only way to fix it.
  local out rc=0
  out="$("$PARA" config-set PARA_DOMAIN "my dev" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { "$PARA" config-set PARA_DOMAIN paraspace.dev >/dev/null 2>&1
                       echo "  config-set accepted a domain with a space" >&2; return 1; }
  assert_contains "$out" "hostname" "the refusal names the rule" || return 1
  assert_refuses "$(a_project 'PARA_ROUTES="3000"' 'PARA_DOMAIN="my dev"')" "hostname"
}

test_a_bad_stored_domain_does_not_brick_recovery_commands() {
  # The same lockout lesson as routes, for the key that is deliberately settable
  # box-wide. Seeded directly, since config-set now refuses to write it.
  local cfg="$XDG_CONFIG_HOME/para/config"
  mkdir -p "$(dirname "$cfg")"
  printf 'PARA_DOMAIN=my dev\n' >> "$cfg"
  local rc=0
  "$PARA" ls >/dev/null 2>&1 || rc=$?
  "$PARA" --help >/dev/null 2>&1 || rc=$?
  _cli_strip_config PARA_DOMAIN
  [ "$rc" -eq 0 ] || { echo "  a bad stored PARA_DOMAIN bricked ls/--help" >&2; return 1; }
}

# ------------------------------------------------------------------ registry readers

test_ls_shows_no_url_without_an_apex_route() {
  # https://<name>.<domain> exists only when a bare port routes the apex. A
  # route-less workspace and a subdomain-only one both have no apex site.
  a_registry_row noroutes 10.0.0.31 -         paraspace.dev fixture
  a_registry_row subonly  10.0.0.32 api:3000  paraspace.dev fixture
  a_registry_row apexed   10.0.0.33 3000      paraspace.dev fixture
  local out; out="$("$PARA" ls --all 2>/dev/null)"
  forget_registry_row noroutes; forget_registry_row subonly; forget_registry_row apexed
  case "$out" in
    *"https://noroutes."*) echo "  a route-less workspace advertised a URL" >&2; return 1 ;;
    *"https://subonly."*)  echo "  a subdomain-only workspace advertised an apex URL" >&2; return 1 ;;
  esac
  assert_contains "$out" "https://apexed." "a workspace WITH an apex route still shows its URL"
}

test_web_refuses_a_workspace_with_no_site_to_open() {
  a_registry_row noroutes 10.0.0.34 -        paraspace.dev fixture
  a_registry_row subonly  10.0.0.35 api:3000 paraspace.dev fixture
  local out1 out2 rc1=0 rc2=0 rc3=0
  out1="$("$PARA" web noroutes 2>&1)" || rc1=$?
  out2="$("$PARA" web subonly 2>&1)"  || rc2=$?
  "$PARA" web nosuchworkspace >/dev/null 2>&1 || rc3=$?
  forget_registry_row noroutes; forget_registry_row subonly
  [ "$rc1" -ne 0 ] || { echo "  web opened a route-less workspace" >&2; return 1; }
  [ "$rc2" -ne 0 ] || { echo "  web opened a subdomain-only workspace's dead apex" >&2; return 1; }
  [ "$rc3" -ne 0 ] || { echo "  web accepted an unregistered workspace" >&2; return 1; }
  assert_contains "$out1" "no HTTP routes" "route-less refusal explains why" || return 1
  assert_contains "$out2" "subdomain-only" "subdomain-only refusal explains why"
}

test_up_refuses_a_name_owned_by_another_project() {
  a_registry_row borrowed 10.0.0.9 8080 paraspace.dev someotherproject
  local p; p="$(a_project 'PARA_ROUTES="3000"' PARA_PROJECT=mine)"
  para_in "$p" up borrowed
  forget_registry_row borrowed
  [ "$PARA_RC" -ne 0 ] || { echo "  up adopted a foreign-owned name" >&2; return 1; }
  assert_contains "$PARA_OUT" "someotherproject" "refusal names the owning project" || return 1
  assert_backend_untouched
}

# ----------------------------------------------------------------- user config

test_config_set_refuses_every_per_project_key() {
  # Table-driven over the whole denylist: covering one key would let the other
  # eight be dropped without a test failing.
  local key out
  for key in PARA_PROJECT PARA_IMAGE PARA_BASE_IMAGE PARA_IMAGE_BOOTSTRAP \
             PARA_VERSION PARA_ORIGIN PARA_CLONE_DIR PARA_VOLUME PARA_ROUTES; do
    out="$("$PARA" config-set "$key" somevalue 2>&1)" && {
      _cli_strip_config "$key"
      echo "  config-set accepted the per-project key $key" >&2; return 1; }
    assert_contains "$out" "Parafile" "$key refusal points at the Parafile" || return 1
  done
}

test_config_set_persists_other_keys() {
  # The inverse of the denylist, and asserted on the FILE rather than the exit
  # status — the namespace staying open is how a project passes its own knobs to
  # its hooks. (Exit status alone passes even if persist_config does nothing.)
  local cfg="$XDG_CONFIG_HOME/para/config" out
  "$PARA" config-set PARA_DEMO_KNOB yes >/dev/null 2>&1 || {
    echo "  config-set refused a non-project key" >&2; return 1; }
  out="$(cat "$cfg" 2>/dev/null || true)"
  _cli_strip_config PARA_DEMO_KNOB
  assert_contains "$out" "PARA_DEMO_KNOB=yes" "the value reached the config file"
}

test_user_config_ignores_per_project_keys() {
  # The denylist where it bites: a stale per-project line must not beat the
  # Parafile. XDG_CONFIG_HOME is sandboxed, so this never touches a real config.
  local cfg="$XDG_CONFIG_HOME/para/config"
  mkdir -p "$(dirname "$cfg")"
  printf 'PARA_IMAGE=hijacked-image\n' >> "$cfg"
  local p; p="$(a_project 'PARA_ROUTES="3000"')"
  para_in "$p" --help
  _cli_strip_config PARA_IMAGE
  assert_not_contains "$PARA_OUT" "hijacked-image" "the user-config value did not take effect" || return 1
  assert_contains "$PARA_OUT" "ignoring PARA_IMAGE" "para says out loud that it ignored it"
}

# Drop KEY's line from the sandboxed user config. Called before assertions so the
# shared file is restored on the failure path too.
_cli_strip_config() {
  local cfg="$XDG_CONFIG_HOME/para/config" tmp
  [ -f "$cfg" ] || return 0
  tmp="$(mktemp)"; grep -v "^$1=" "$cfg" > "$tmp" 2>/dev/null || true; mv "$tmp" "$cfg"
}

# ------------------------------------------------------------------------ image

test_image_defaults_to_the_project_slug() {
  # Incus image aliases are daemon-global, so a fixed default would put two
  # projects that both left the key unset on ONE image.
  local p; p="$(a_project 'PARA_ROUTES="3000"' PARA_PROJECT=derived-slug)"
  para_in "$p" --help
  printf '%s\n' "$PARA_OUT" | grep -qE '^[[:space:]]*PARA_IMAGE[[:space:]]+derived-slug$' || {
    echo "  PARA_IMAGE did not derive from PARA_PROJECT:" >&2
    printf '%s\n' "$PARA_OUT" | grep -E 'PARA_IMAGE' >&2; return 1; }
}

test_image_build_refuses_without_a_base_image() {
  # para never picks your distro, and a para update must not change it under you.
  local p; p="$(a_project)"
  assert_refuses "$p" "PARA_BASE_IMAGE" image build || return 1
  assert_backend_untouched
}

test_image_build_alias_is_still_accepted() {
  local p; p="$(a_project)"
  para_in "$p" image-build
  [ "$PARA_RC" -ne 0 ] || { echo "  the deprecated alias succeeded with no base image" >&2; return 1; }
  assert_contains "$PARA_OUT" "deprecated"      "alias warns it is deprecated" || return 1
  assert_contains "$PARA_OUT" "PARA_BASE_IMAGE" "alias still reaches the build refusal"
}

test_image_rejects_an_unknown_subcommand() {
  # Asserts the message: `cmd_image_status` would also exit non-zero here (no
  # project), so an exit-status-only check would pass with the dispatcher broken.
  local p; p="$(a_project)"
  para_in "$p" image not-a-subcommand
  [ "$PARA_RC" -ne 0 ] || { echo "  an unknown image subcommand was accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "unknown 'para image' command" "the dispatcher named the problem"
}

# ------------------------------------------------------------------------- init

test_init_scaffolds_a_paraspace_dir() {
  local d; d="$(a_scaffolded_project void-minimal)"
  assert test -f "$d/.paraspace/Parafile"        || return 1
  assert test -f "$d/.paraspace/hooks/provision" || return 1
  assert test -f "$d/.paraspace/hooks/boot"      || return 1
  assert test -x "$d/.paraspace/hooks/provision"
}

test_init_names_the_project_after_its_directory() {
  # PARA_IMAGE derives from PARA_PROJECT, so this sed is now the ONLY thing giving
  # a scaffolded project its identity — and nothing asserted it.
  local d out; d="$(scratch)"
  mkdir -p "$d/My.App"
  ( cd "$d/My.App" && env -u PARA_PROJECT_DIR "$PARA" init >/dev/null 2>&1 )
  out="$(cat "$d/My.App/.paraspace/Parafile")"
  assert_contains "$out" 'PARA_PROJECT:=my-app' "the dir name became the project slug"
}

test_init_lists_bundled_templates() {
  local out; out="$(env -u PARA_PROJECT_DIR "$PARA" init --names 2>&1)"
  assert_contains "$out" "void-minimal"   "template listed" || return 1
  assert_contains "$out" "void-docker-gh" "default listed"
}

test_init_refuses_a_path_as_a_template_name() {
  # Without containment, `para init ../..` scaffolds an arbitrary tree into $PWD.
  # Asserted on the MESSAGE: without the guard `para init ../..` still fails, just
  # for an unrelated reason ("nothing to scaffold"), so an exit-status-only check
  # would pass with the containment removed.
  local d out rc=0; d="$(scratch)"
  out="$(cd "$d" && env -u PARA_PROJECT_DIR "$PARA" init ../.. 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "  init accepted a path traversal" >&2; return 1; }
  assert_contains "$out" "plain directory name" "the refusal is the containment check" || return 1
  [ ! -e "$d/.paraspace" ] || { echo "  init scaffolded something anyway" >&2; return 1; }
}

test_template_helpers_do_not_drift() {
  # hooks/helpers is byte-identical across the bundled templates on purpose, and
  # cannot be factored into a shared overlay: it has to sit BESIDE the hooks that
  # source it — shellcheck resolves `. "$(dirname "$0")/helpers"` via
  # source-path=SCRIPTDIR, sync_project pushes only .paraspace/hooks/ into a
  # workspace, and each template dir is documented as runnable on its own.
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

# --------------------------------------------------------------------- contract

test_up_refuses_a_contract_version_mismatch() {
  local p; p="$(a_project 'PARA_ROUTES="3000"' PARA_VERSION=999)"
  assert_refuses "$p" "contract" || return 1
  assert_backend_untouched
}
