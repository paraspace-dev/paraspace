#!/usr/bin/env bash
# CLI-tier tests — no incus. Dispatch, project commands, configuration
# precedence, `para init`. Fast enough to run on every push in CI.
#
# Fixtures come from test/lib/project.sh: `a_project` builds a throwaway project,
# `para_in`/`assert_refuses` run para against it with the backend fenced, and the
# harness removes everything afterwards. Tests should read as a story — arrange
# one project, assert one behavior.
#
# Two habits worth keeping, both learned the hard way on this suite:
#   * assert the RESOLVED VALUE, not just a non-zero exit. Several tests here once
#     passed while the thing they claimed to check was broken, because something
#     else in the setup already guaranteed the failure they were asserting.
#   * never let `para up` reach the backend. `para_in` fences it; a bare
#     invocation on a developer box creates real storage and starts a real Caddy.
#
# `para doctor` is this tier's oracle for resolved configuration: it prints the
# values para actually resolved, before it goes looking at the host. It exits
# non-zero against the fence (incus is unreachable there, and doctor's whole job
# is to say so), so these tests read its OUTPUT and ignore its status.

MIN_INCUS_EXPECTED=6.22   # keep in step with bin/para's MIN_INCUS

# ------------------------------------------------------------------ dispatch

test_help_lists_the_command_surface() {
  local out; out="$("$PARA" --help 2>&1)"
  assert_contains "$out" "up"          "help mentions up"          || return 1
  assert_contains "$out" "sh"          "help mentions sh"          || return 1
  assert_contains "$out" "image"       "help mentions image"       || return 1
  assert_contains "$out" "caddy"       "help mentions caddy"       || return 1
  assert_contains "$out" "doctor"      "help mentions doctor"
}

test_rejects_an_unknown_command() {
  # Outside a project there is nowhere a project command could come from, so an
  # unknown verb is simply unknown.
  local out rc=0
  out="$(env -u PARA_PROJECT_DIR "$PARA" this-is-not-a-command 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "  an unknown command was accepted" >&2; return 1; }
  assert_contains "$out" "unknown command" "the refusal names the problem"
}

test_rejects_an_invalid_workspace_name() {
  # Asserts the MESSAGE, not just non-zero: a name that reaches the fenced
  # backend fails there anyway, so an exit-status-only check would pass even
  # with validate_name removed entirely.
  local p; p="$(a_project)"
  para_in "$p" up "Bad_Name"
  [ "$PARA_RC" -ne 0 ] || { echo "  an invalid workspace name was accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "invalid workspace name" "the refusal names the rule" || return 1
  assert_backend_untouched
}

# ---------------------------------------------------------- project commands

test_project_commands_extend_the_verb_set() {
  # The extension seam: an executable in .paraspace/commands/ becomes `para
  # <verb>`, running on the host with every PARA_* exported and its arguments
  # passed through untouched.
  local p; p="$(a_project)"
  # shellcheck disable=SC2016  # the guest script's $vars are literal here
  a_project_command "$p" greet '#!/bin/sh
# summary: say hello
echo "greeted $1 for $PARA_PROJECT via $PARA_BIN"'

  para_in "$p" greet world
  [ "$PARA_RC" -eq 0 ] || { echo "  the project command failed:" >&2
                            printf '    %s\n' "$PARA_OUT" >&2; return 1; }
  assert_contains "$PARA_OUT" "greeted world"    "arguments passed through"  || return 1
  assert_contains "$PARA_OUT" "for fixture"      "PARA_* reached it"         || return 1
  assert_contains "$PARA_OUT" "$PARA"            "PARA_BIN points back here"
}

test_project_commands_are_discoverable() {
  # Nothing a project adds should run invisibly: it is listed by `para commands`
  # and in `para --help`, with the summary line if the file carries one.
  local p; p="$(a_project)"
  a_project_command "$p" greet '#!/bin/sh
# summary: say hello
echo hi'
  para_in "$p" commands
  assert_contains "$PARA_OUT" "greet" "para commands lists it" || return 1
  para_in "$p" --help
  assert_contains "$PARA_OUT" "PROJECT COMMANDS" "help has a section for them" || return 1
  assert_contains "$PARA_OUT" "say hello"        "help shows the summary line"
}

test_engine_verbs_shadow_project_commands() {
  # A template must not be able to silently replace `para ls` — the engine's
  # namespace wins, and doctor is where that gets pointed out.
  local p; p="$(a_project)"
  a_project_command "$p" ls '#!/bin/sh
echo SHADOWED-THE-ENGINE'
  para_in "$p" ls
  assert_not_contains "$PARA_OUT" "SHADOWED-THE-ENGINE" "the engine verb ran, not the project's" || return 1
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "shadowed" "doctor warns about the shadowed command"
}

# ------------------------------------------------------------- configuration

test_the_environment_overrides_the_parafile() {
  # The whole precedence model: a Parafile written with the `:=` idiom yields to
  # a real environment variable. Nothing in para implements this — bash does —
  # so the test exists to prove the idiom is what the templates should use.
  local p out
  # shellcheck disable=SC2016  # a literal Parafile line, not an expansion
  p="$(a_project ': "${PARA_DOMAIN:=from-parafile}"')"
  out="$(_para_env "$p" PARA_DOMAIN=from-the-environment doctor)"
  assert_contains     "$out" "from-the-environment" "the environment won"      || return 1
  assert_not_contains "$out" "from-parafile"        "the Parafile default lost"
}

test_a_plain_parafile_assignment_insists() {
  # The other half of the model, and a deliberate feature: a project that must
  # pin a value writes a plain assignment, and the environment does not win.
  local p out; p="$(a_project 'PARA_DOMAIN=insisted.example')"
  out="$(_para_env "$p" PARA_DOMAIN=from-the-environment doctor)"
  assert_contains "$out" "insisted.example" "the project's plain assignment held"
}

test_config_init_seeds_a_user_config_and_path_finds_it() {
  # `para config init` is the only thing that writes the user config; nothing
  # else does, so a value there is always something a person put there.
  local path out
  path="$("$PARA" config path)"
  assert_contains "$path" "$XDG_CONFIG_HOME" "path points into the sandboxed XDG dir" || return 1
  [ ! -f "$path" ] || rm -f "$path"
  "$PARA" config init >/dev/null 2>&1 || { echo "  config init failed" >&2; return 1; }
  out="$(cat "$path")"
  rm -f "$path"
  assert_contains "$out" 'PARA_DOMAIN' "the seeded file lists the box-level knobs" || return 1
  # Seeded entirely commented out, so writing one is an explicit act.
  case "$out" in
    *$'\n'[!#]*) echo "  the seeded config has an active line" >&2; return 1 ;;
  esac
}

test_config_init_refuses_to_clobber() {
  local path rc=0
  path="$("$PARA" config path)"
  mkdir -p "$(dirname "$path")"
  printf '# mine\n' > "$path"
  "$PARA" config init >/dev/null 2>&1 || rc=$?
  local kept; kept="$(cat "$path")"
  rm -f "$path"
  [ "$rc" -ne 0 ] || { echo "  config init overwrote an existing config" >&2; return 1; }
  assert_eq "# mine" "$kept" "the existing file was left alone"
}

test_routes_are_canonicalized() {
  # Commas, spaces, tabs and newlines all separate entries, so a project can lay
  # several routes out to be read. Whatever the spelling, para resolves ONE
  # canonical form — space-separated and lowercased — which is what it stamps on
  # the container and injects into hooks.
  local spelling out
  for spelling in '"8080,API:3001"' '"8080, api:3001"' '"8080 api:3001"' '"
    8080
    api:3001
  "'; do
    out="$(para_in "$(a_project "PARA_ROUTES=$spelling")" doctor; printf '%s' "$PARA_OUT")"
    assert_contains "$out" "PARA_ROUTES   8080 api:3001" "canonical form from: $spelling" || return 1
  done
}

test_routes_do_not_glob_against_the_cwd() {
  # Canonicalization is a string transform, not a word split, so a value like
  # "30*" cannot expand against whatever files happen to sit in $PWD. This was a
  # real bug in the predecessor, where the split needed `set -f` to be safe.
  local p g; p="$(a_project 'PARA_ROUTES="30*"')"; g="$(scratch)"
  : > "$g/3000"; : > "$g/3005"
  PARA_CWD="$g" para_in "$p" doctor
  assert_contains "$PARA_OUT" "30*" "the literal survived, unexpanded by the cwd"
}

test_doctor_checks_incus_can_do_what_para_needs() {
  # para reads every workspace out of incus in one query, using device keys as
  # `incus list` columns. The CAPABILITY decides, not the version number: a
  # distro can backport, and the failure this catches is the nasty one — an
  # incus that can't do it makes para see every workspace as address-less.
  local stub out
  stub="$(a_stub_incus 6.2 no)"
  out="$(cd "$(a_project)" && env PATH="$stub:$PATH" "$PARA" doctor 2>&1)" || true
  assert_contains "$out" "6.2 cannot select device columns" "an incapable incus is named and failed" || return 1
  assert_contains "$out" "$MIN_INCUS_EXPECTED" "the message says what to upgrade to" || return 1
  # And it keeps going. A diagnostic that stops at the first thing it cannot
  # read is useless exactly when you need it — this reached the later checks.
  assert_contains "$out" "storage pool" "doctor finished its report after a failed check" || return 1

  # Capable but older than what para is tested against: a warning, not a refusal.
  stub="$(a_stub_incus 6.14 yes)"
  out="$(cd "$(a_project)" && env PATH="$stub:$PATH" "$PARA" doctor 2>&1)" || true
  assert_contains "$out" "6.14 is older than" "an untested-but-capable incus warns" || return 1

  # Current: neither.
  stub="$(a_stub_incus 6.30 yes)"
  out="$(cd "$(a_project)" && env PATH="$stub:$PATH" "$PARA" doctor 2>&1)" || true
  assert_not_contains "$out" "6.30 is older than"          "a current incus does not warn" || return 1
  assert_not_contains "$out" "cannot select device columns" "…nor fail"
}
test_refuses_a_contract_version_mismatch() {
  # A project pins the contract its hooks target; para refuses rather than
  # running them under a seam that has changed underneath.
  local p; p="$(a_project PARA_VERSION=999)"
  assert_refuses "$p" "contract" || return 1
  assert_backend_untouched
}

# -------------------------------------------------------------------- image

test_image_defaults_to_the_project_slug() {
  # Incus image aliases are daemon-global, so a fixed default would put two
  # projects that both left the key unset on ONE image.
  local p; p="$(a_project PARA_PROJECT=derived-slug)"
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "PARA_IMAGE    derived-slug" "PARA_IMAGE derived from PARA_PROJECT"
}

test_image_build_refuses_without_a_base_image() {
  # para never picks your distro, and a para update must not change it under
  # you. Checked before the daemon, so an incomplete Parafile is what you hear
  # about — which `assert_backend_untouched` is here to pin.
  local p; p="$(a_project)"
  printf 'true\n' > "$p/.paraspace/image-build.sh"
  assert_refuses "$p" "PARA_BASE_IMAGE" image build || return 1
  assert_backend_untouched
}

test_image_rejects_an_unknown_subcommand() {
  local p; p="$(a_project)"
  para_in "$p" image not-a-subcommand
  [ "$PARA_RC" -ne 0 ] || { echo "  an unknown image subcommand was accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "usage: para image" "the dispatcher named the problem"
}

# --------------------------------------------------------------------- init

test_init_scaffolds_a_paraspace_dir() {
  local d; d="$(a_scaffolded_project void-minimal)"
  assert test -f "$d/.paraspace/Parafile"        || return 1
  assert test -f "$d/.paraspace/hooks/provision" || return 1
  assert test -f "$d/.paraspace/hooks/boot"      || return 1
  assert test -x "$d/.paraspace/hooks/provision"
}

test_init_lists_bundled_templates() {
  local out; out="$(env -u PARA_PROJECT_DIR "$PARA" init --list 2>&1)"
  assert_contains "$out" "void-minimal"   "template listed" || return 1
  assert_contains "$out" "void-docker-gh" "default listed"
}

test_init_refuses_a_path_as_a_template_name() {
  # Without containment, `para init ../..` scaffolds an arbitrary tree into $PWD.
  # Asserted on the MESSAGE: `para init ../..` would fail anyway once the path
  # missed, so an exit-status-only check would pass with the guard removed.
  local d out rc=0; d="$(scratch)"
  out="$(cd "$d" && env -u PARA_PROJECT_DIR "$PARA" init ../.. 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "  init accepted a path traversal" >&2; return 1; }
  assert_contains "$out" "plain directory name" "the refusal is the containment check" || return 1
  [ ! -e "$d/.paraspace" ] || { echo "  init scaffolded something anyway" >&2; return 1; }
}

test_a_scaffolded_project_takes_its_identity_from_the_directory() {
  # No template rewriting at scaffold time: the engine derives PARA_PROJECT from
  # the directory name, so a template ships without a project name baked in.
  # PARA_PROJECT is unset for the same reason PARA_PROJECT_DIR is — the e2e
  # sandbox exports one, and an inherited value is exactly what this test must
  # not see. (It passed under `--cli` and failed under `--all` before this.)
  local d out; d="$(scratch)"
  mkdir -p "$d/My.App"
  ( cd "$d/My.App" && env -u PARA_PROJECT_DIR -u PARA_PROJECT "$PARA" init void-minimal >/dev/null 2>&1 )
  out="$(cd "$d/My.App" && env -u PARA_PROJECT_DIR -u PARA_PROJECT "$PARA" doctor 2>&1)"
  assert_contains "$out" "my-app" "the directory name became the project slug"
}

test_template_helpers_do_not_drift() {
  # hooks/helpers is byte-identical across the bundled templates on purpose, and
  # cannot be factored into a shared overlay: it has to sit BESIDE the hooks that
  # source it — shellcheck resolves `. "$(dirname "$0")/helpers"` via
  # source-path=SCRIPTDIR, para pushes .paraspace/ into a workspace whole, and
  # each template dir is documented as runnable on its own.
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

# Run para against <project> with one extra environment variable, backend
# fenced. The precedence tests are ABOUT the environment, so they set it
# explicitly rather than going through para_in.
_para_env() { # _para_env <project> <VAR=VALUE> <args>...
  local proj="$1" assignment="$2"; shift 2
  [ -n "$PARA_FENCE" ] || PARA_FENCE="$(a_fenced_backend)"
  env PATH="$PARA_FENCE:$PATH" PARA_PROJECT_DIR="$proj" "$assignment" "$PARA" "$@" 2>&1
}
