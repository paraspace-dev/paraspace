#!/usr/bin/env bash
# CLI-tier tests, no incus. Dispatch, layer commands, configuration
# precedence, `para init`. Fast enough to run on every push in CI.
#
# Fixtures come from test/lib/project.sh: `a_project` builds a throwaway project,
# `para_in`/`assert_refuses` run para against it with the backend fenced, and the
# harness removes everything afterwards. Tests should read as a story: arrange
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
  # "sh", not "sh <name>", would also match the "bash" in `para completions bash`
  assert_contains "$out" "sh <name>"   "help mentions sh"          || return 1
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

test_hands_off_to_the_projects_own_para() {
  # A project that ships its own para is run by that copy, whichever para was
  # invoked. The probe goes through the package, never node_modules/.bin,
  # whose pnpm spelling is a script shim that would re-enter the handoff
  # forever; the booby-trapped shim proves the probe stays off it.
  local p; p="$(a_project)"
  a_project_para "$p"
  mkdir -p "$p/node_modules/.bin"
  printf '#!/bin/sh\necho "the .bin shim ran"\n' > "$p/node_modules/.bin/para"
  chmod +x "$p/node_modules/.bin/para"
  para_in "$p" ls --names
  assert_eq "project para got: ls --names" "$PARA_OUT" \
    "the package's bin receives the argv, and the handoff itself says nothing" || return 1
  assert_not_contains "$PARA_OUT" "the .bin shim ran" "the .bin shim is never probed"
}

test_which_names_the_para_that_answers() {
  # The handoff is silent, and this verb is how you see it WITHOUT trusting
  # the checkout: it names the project's para but never executes it, so it is
  # safe to run in a clone you have not read yet.
  local p; p="$(a_project)"
  para_in "$p" which
  assert test "$PARA_OUT" -ef "$PARA" || return 1
  a_project_para "$p"
  para_in "$p" which
  assert_eq "$p/node_modules/paraspace/bin/para" "$PARA_OUT" \
    "the project's install is named, not executed"
}

test_a_hoisted_paraspace_is_found() {
  # Workspace managers hoist node_modules above the package that declares the
  # dependency, so the probe walks upward from the project root.
  local repo p; repo="$(scratch)"; p="$repo/packages/app"
  mkdir -p "$p/.paraspace/layers/project"
  printf 'PARA_CONTRACT=1\n' > "$p/.paraspace/env"
  printf '.paraspace/layers/project\n' > "$p/.paraspace/stack"
  a_project_para "$repo"
  para_in "$p" ls --names
  assert_contains "$PARA_OUT" "project para got: ls --names" "the hoisted install receives the argv"
}

test_a_linked_paraspace_is_already_the_projects_para() {
  # A linked package resolves to the very file that is running, so there is
  # nothing to hand off to, and no handoff loop to fall into.
  local p; p="$(a_scaffolded_project)"
  para_in "$p" commands
  [ "$PARA_RC" -eq 0 ] || { printf '  para commands failed:\n    %s\n' "$PARA_OUT" >&2; return 1; }
  para_in "$p" which
  assert test "$PARA_OUT" -ef "$PARA" || return 1
}

test_warns_when_a_project_pins_no_paraspace() {
  # No install to hand off to, so a command that depends on the project warns
  # and names the fix; a verb like --help stays quiet.
  local p; p="$(a_project)"
  para_in "$p" add
  assert_contains "$PARA_OUT" "npm install --save-dev paraspace" "the warn names the fix" || return 1
  para_in "$p" --help
  assert_not_contains "$PARA_OUT" "npm install" "help is not the place to nag"
}

test_names_plain_npm_install_when_already_pinned() {
  # package.json already declares paraspace, so the fix is installing what is
  # pinned, not re-pinning it (--save-dev would rewrite the version range).
  local p; p="$(a_project)"
  printf '{ "devDependencies": { "paraspace": "0.3.0" } }\n' > "$p/package.json"
  para_in "$p" add
  assert_contains "$PARA_OUT" "npm install" "the warn names the fix" || return 1
  assert_not_contains "$PARA_OUT" "--save-dev" "an existing pin is not rewritten"
}

test_completions_do_not_hand_off() {
  # Shell rcs source completions at startup from any directory, so this one
  # verb answers from the copy invoked even when the project ships its own.
  local p; p="$(a_project)"
  a_project_para "$p"
  para_in "$p" completions bash
  assert_contains "$PARA_OUT" "complete -F _para para" "the invoked copy answers" || return 1
  assert_not_contains "$PARA_OUT" "project para got:" "completions are not handed off"
}

test_completions_do_not_nag() {
  # The same startup path in a project that pins nothing must stay quiet.
  local p; p="$(a_project)"
  para_in "$p" completions bash
  assert_not_contains "$PARA_OUT" "npm install" "sourcing completions stays quiet"
}

# ---------------------------------------------------------- project commands

test_project_commands_extend_the_verb_set() {
  # The extension point: an executable in .paraspace/commands/ becomes `para
  # <verb>`, running on the host with every PARA_* exported and its arguments
  # passed through untouched.
  local p; p="$(a_project)"
  # shellcheck disable=SC2016  # the guest script's $vars are literal here
  a_project_command "$p" greet '#!/bin/sh
# summary: say hello
echo "greeted $1 for $PARA_PROJECT_NAME via $PARA_BIN"'

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
  # A template must not be able to silently replace `para ls`, since the engine's
  # namespace wins, and doctor is where that gets pointed out.
  local p; p="$(a_project)"
  a_project_command "$p" ls '#!/bin/sh
echo SHADOWED-THE-ENGINE'
  para_in "$p" ls
  assert_not_contains "$PARA_OUT" "SHADOWED-THE-ENGINE" "the engine verb ran, not the project's" || return 1
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "shadowed" "doctor warns about the shadowed command"
}

test_every_verb_main_dispatches_is_an_engine_verb() {
  # is_engine_verb is what doctor warns from, so a spelling main dispatches but
  # is_engine_verb omits leaves a command that silently never runs and is never
  # reported. `-h` was exactly that: main matches `""|-h|--help|help`.
  local p verb; p="$(a_project)"
  for verb in -h --help --version; do
    a_project_command "$p" "$verb" '#!/bin/sh
echo SHADOWED-THE-ENGINE'
  done
  para_in "$p" -h
  assert_not_contains "$PARA_OUT" "SHADOWED-THE-ENGINE" "the engine won for -h" || return 1
  para_in "$p" doctor
  for verb in -h --help --version; do
    assert_contains "$PARA_OUT" "'$verb' is shadowed" "doctor names $verb" || return 1
  done
}

# ------------------------------------------------------------- configuration

test_the_environment_overrides_the_project_env() {
  # The whole precedence model: an env file written with the `:=` idiom yields
  # to a real environment variable. Nothing in para implements this (bash
  # does), so the test exists to prove the idiom is what layers should use.
  local p out
  # shellcheck disable=SC2016  # a literal env line, not an expansion
  p="$(a_project ': "${PARA_DOMAIN:=from-project-env}"')"
  out="$(_para_env "$p" PARA_DOMAIN=from-the-environment doctor)"
  assert_contains     "$out" "from-the-environment" "the environment won"      || return 1
  assert_not_contains "$out" "from-project-env"     "the env file default lost"
}

test_a_plain_env_assignment_insists() {
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

test_config_edit_opens_the_file_and_seeds_it_first() {
  # `para config edit` is meant to be the only one of these anyone learns, so
  # it seeds the file on first use rather than opening nothing. $EDITOR is
  # word-split on purpose (people set it with flags), which is the half of
  # this that quoting would silently break.
  local d path; d="$(scratch)"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > %s/argv\n' "$d" > "$d/fake-editor"
  chmod +x "$d/fake-editor"
  path="$("$PARA" config path)"
  rm -f "$path"

  EDITOR="$d/fake-editor --wait" "$PARA" config edit \
    || { echo "  config edit failed" >&2; return 1; }
  local argv; argv="$(cat "$d/argv")"
  assert_contains "$argv" "--wait" "the editor's own flags survived" || return 1
  assert_contains "$argv" "$path"  "the editor was given the config path" || return 1
  [ -f "$path" ] || { echo "  config edit did not seed the file" >&2; return 1; }
  assert_contains "$(cat "$path")" "PARA_DOMAIN" "the seeded file is the template" || return 1

  # VISUAL wins over EDITOR, the usual convention.
  printf '#!/bin/sh\nprintf visual > %s/who\n' "$d" > "$d/fake-visual"
  chmod +x "$d/fake-visual"
  VISUAL="$d/fake-visual" EDITOR="$d/fake-editor" "$PARA" config edit
  local who; who="$(cat "$d/who")"
  rm -f "$path"
  assert_eq "visual" "$who" "VISUAL took precedence over EDITOR"
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

test_the_origin_comes_from_the_project_checkout() {
  # A .paraspace/ that lives in the repo it describes shouldn't have to repeat
  # that repo's URL, so para reads it off the checkout. Nowhere to read one from
  # is a real answer (empty), and doctor is where you hear about it, because the
  # next thing that would is a provision hook, minutes later, inside a container.
  local p; p="$(a_project)"
  git -C "$p" init -q
  git -C "$p" remote add origin git@github.com:acme/acme.git
  # shellcheck disable=SC2016  # the command's $vars are literal here
  a_project_command "$p" resolved '#!/bin/sh
echo "origin=[$PARA_ORIGIN]"'
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "origin=[git@github.com:acme/acme.git]" "derived from the checkout" || return 1

  git -C "$p" remote remove origin
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "origin=[]"      "a repo with no origin resolves to none" || return 1
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "no PARA_ORIGIN" "doctor reports it rather than guessing"
}

test_a_declared_origin_beats_the_one_in_the_checkout() {
  # The derivation is a DEFAULT, so it changes no precedence: a project that
  # declares PARA_ORIGIN is cloning something other than itself on purpose.
  local p; p="$(a_project 'PARA_ORIGIN=git@github.com:acme/other.git')"
  git -C "$p" init -q
  git -C "$p" remote add origin git@github.com:acme/acme.git
  # shellcheck disable=SC2016  # the command's $vars are literal here
  a_project_command "$p" resolved '#!/bin/sh
echo "origin=[$PARA_ORIGIN]"'
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "origin=[git@github.com:acme/other.git]" "the env file won"
}

test_the_ready_host_defaults_to_paras_own_domain() {
  # Every workspace waits on guest DNS before a hook runs, so the gate needs a
  # name para can pick for itself. Its own, so the default presumes no git host,
  # and a project declares nothing to get it.
  local p; p="$(a_project)"
  # shellcheck disable=SC2016  # the command's $vars are literal here
  local oracle='#!/bin/sh
echo "ready=[$PARA_READY_HOST]"'
  a_project_command "$p" resolved "$oracle"
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "ready=[paraspace.dev]" "the gate defaults to paraspace.dev" || return 1

  # Empty is the off switch, and it has to survive: `:=` would fill it back in.
  p="$(a_project 'PARA_READY_HOST=""')"
  a_project_command "$p" resolved "$oracle"
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "ready=[]" "an explicit empty skips the wait"
}

test_a_scaffolded_env_is_one_line() {
  # The scaffold pins only its contract. Layers may propose optional settings
  # later, and a project with no routes is valid.
  local d; d="$(a_scaffolded_project)"
  assert_eq "PARA_CONTRACT=1" "$(cat "$d/.paraspace/env")" "a fresh env pins only the contract"
}

test_routes_are_canonicalized() {
  # Commas, spaces, tabs and newlines all separate entries, so a project can lay
  # several routes out to be read. Whatever the spelling, para resolves ONE
  # canonical form (space-separated and lowercased), which is what it stamps on
  # the container and injects into hooks.
  local spelling out
  for spelling in '"8080,API:3001"' '"8080, api:3001"' '"8080 api:3001"' '"
    8080
    api:3001
  "'; do
    out="$(para_in "$(a_project "PARA_ROUTES=$spelling")" doctor; printf '%s' "$PARA_OUT")"
    assert_contains "$out" "PARA_ROUTES        8080 api:3001" "canonical form from: $spelling" || return 1
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
  # distro can backport, and the failure this catches is the nasty one, an
  # incus that can't do it makes para see every workspace as address-less.
  local stub out
  stub="$(a_stub_incus 6.2 no)"
  out="$(cd "$(a_project)" && env -u PARA_PROJECT_DIR PATH="$stub:$PATH" "$PARA" doctor 2>&1)" || true
  assert_contains "$out" "6.2 cannot select device columns" "an incapable incus is named and failed" || return 1
  assert_contains "$out" "$MIN_INCUS_EXPECTED" "the message says what to upgrade to" || return 1
  # And it keeps going. A diagnostic that stops at the first thing it cannot
  # read is useless exactly when you need it, so this reached the later checks.
  assert_contains "$out" "storage pool" "doctor finished its report after a failed check" || return 1

  # Capable but older than what para is tested against: a warning, not a refusal.
  stub="$(a_stub_incus 6.14 yes)"
  out="$(cd "$(a_project)" && env -u PARA_PROJECT_DIR PATH="$stub:$PATH" "$PARA" doctor 2>&1)" || true
  assert_contains "$out" "6.14 is older than" "an untested-but-capable incus warns" || return 1

  # Current: neither.
  stub="$(a_stub_incus 6.30 yes)"
  out="$(cd "$(a_project)" && env -u PARA_PROJECT_DIR PATH="$stub:$PATH" "$PARA" doctor 2>&1)" || true
  assert_not_contains "$out" "6.30 is older than"          "a current incus does not warn" || return 1
  assert_not_contains "$out" "cannot select device columns" "…nor fail"
}

test_init_converges_on_an_existing_project() {
  # init and add are one convergent verb, so re-running it on a project edits
  # nothing that already exists and eats nothing the user wrote.
  local p out; p="$(a_project)"
  mkdir -p "$p/.paraspace/layers/project/hooks"
  printf '# my hook\n' > "$p/.paraspace/layers/project/hooks/provision"
  out="$(env PARA_PROJECT_DIR="$p" "$PARA" init 2>&1)" \
    || { echo "  init failed on an existing project:" >&2; printf '    %s\n' "$out" >&2; return 1; }
  assert_eq "# my hook" "$(cat "$p/.paraspace/layers/project/hooks/provision")" "the hook was left alone" || return 1
  assert_eq ".paraspace/layers/project" "$(cat "$p/.paraspace/stack")" "the stack was left alone" || return 1
  assert_contains "$(cat "$p/.paraspace/env")" "PARA_PROJECT_NAME=fixture" "the env was left alone"
}

test_up_allocates_an_ip_that_is_not_already_taken() {
  # The highest-consequence silent failure in the engine: a mis-parse here hands
  # a new workspace an address a LIVE one already holds. incus annotates the
  # runtime column as "10.9.9.200 (eth0)" and fills the device column only for
  # instances para pinned, so an address held by a RUNNING container para did
  # NOT create appears in the annotated form and nowhere else. That is the shape
  # this pins: .200 is such a container, .201 a stopped para workspace. Driven through `para up` with a stub incus that fails at
  # launch, so nothing is created and the requested address is still observable.
  local d; d="$(scratch)"
  cat > "$d/incus" <<STUB
#!/bin/sh
case "\$*" in
  "info")                 exit 0 ;;   # daemon reachable
  info\ *)                exit 1 ;;   # …but this instance does not exist
  *--all-projects*)       printf '%s\\n' '"10.9.9.200 (eth0)",' ',10.9.9.201'; exit 0 ;;
  "network get "*)        echo 10.9.9.1/24; exit 0 ;;
  "image info "*)         exit 0 ;;
  "storage volume show "*) exit 0 ;;
  launch\ *)              echo "\$*" > "$d/launch-args"; exit 1 ;;
  *)                      exit 0 ;;
esac
STUB
  chmod +x "$d/incus"
  ( cd "$(a_project 'PARA_ROUTES="8080"')" \
      && env -u PARA_PROJECT_DIR PATH="$d:$PATH" "$PARA" up ws >/dev/null 2>&1 ) || true
  [ -f "$d/launch-args" ] || { echo "  para never reached 'incus launch'" >&2; return 1; }
  assert_contains "$(cat "$d/launch-args")" "ipv4.address=10.9.9.202" \
    "skipped the running .200 and the stopped .201"
}

test_refuses_a_contract_version_mismatch() {
  # A project pins the contract its hooks target; para refuses rather than
  # running them under a contract that has changed underneath.
  local p; p="$(a_project PARA_CONTRACT=999)"
  assert_refuses "$p" "contract" || return 1
  assert_backend_untouched
}

# -------------------------------------------------------------------- image

test_image_defaults_to_the_project_slug() {
  # Incus image aliases are daemon-global, so a fixed default would put two
  # projects that both left the key unset on ONE image.
  local p; p="$(a_project PARA_PROJECT_NAME=derived-slug)"
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "PARA_IMAGE_NAME    derived-slug" "PARA_IMAGE_NAME derived from PARA_PROJECT_NAME"
}

test_the_image_base_and_its_bootstrap_default_together() {
  # An env file that names no distro gets Void, and the one `sh -c` line that
  # leaves bash in the builder follows from whatever the base is. The oracle is a
  # project command, since para exports every resolved PARA_* to one.
  local p; p="$(a_project)"
  # shellcheck disable=SC2016  # the command's $vars are literal here
  a_project_command "$p" resolved '#!/bin/sh
echo "base=[$PARA_IMAGE_BASE] bootstrap=[$PARA_IMAGE_BOOTSTRAP]"'
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "base=[images:voidlinux]"                  "the base defaults to Void" || return 1
  assert_contains "$PARA_OUT" "bootstrap=[xbps-install -Syu xbps bash]"  "the bootstrap followed it"
}

test_the_bootstrap_follows_the_base_it_is_given() {
  # Derived per base, and assigned only when UNSET: a base that needs nothing
  # says so with PARA_IMAGE_BOOTSTRAP="", and that empty value has to survive,
  # or para would run someone else's package manager in their builder.
  # shellcheck disable=SC2016  # the command's $vars are literal here
  local p oracle='#!/bin/sh
echo "bootstrap=[$PARA_IMAGE_BOOTSTRAP]"'

  p="$(a_project PARA_IMAGE_BASE=images:alpine/edge)"
  a_project_command "$p" resolved "$oracle"
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "bootstrap=[apk add --no-cache bash]" "Alpine gets apk" || return 1

  p="$(a_project PARA_IMAGE_BASE=images:debian/13)"
  a_project_command "$p" resolved "$oracle"
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "bootstrap=[]" "a base para has no line for gets none" || return 1

  p="$(a_project PARA_IMAGE_BASE=images:voidlinux 'PARA_IMAGE_BOOTSTRAP=""')"
  a_project_command "$p" resolved "$oracle"
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "bootstrap=[]" "an explicit empty beat the derived default"
}

test_image_build_refuses_without_an_image_build_hook() {
  # Refusing is the host's job, not the runner's. The runner's note prints
  # inside the builder, minutes in, and the build then publishes and exits 0,
  # so a project missing the hook would get one line of scrollback and a base
  # image with no provisioning in it.
  local p; p="$(a_project 'PARA_IMAGE_BASE=images:alpine/edge')"
  assert_refuses "$p" "no 'image-build' hook" image build || return 1
  assert_backend_untouched
}

test_image_build_accepts_a_hook_from_any_layer() {
  # ...and it has to span the stack, or adding the layer that builds your
  # image would be refused by the very check that exists to catch its absence.
  local p; p="$(a_project 'PARA_IMAGE_BASE=images:alpine/edge')"
  a_layer "$p" tools
  mkdir -p "$p/.paraspace/layers/tools/hooks"
  printf 'true\n' > "$p/.paraspace/layers/tools/hooks/image-build"
  para_in "$p" image build
  assert_not_contains "$PARA_OUT" "no 'image-build' hook" "a mod's hook was counted" || return 1
  # Reaching the daemon is the positive half: have_hook runs before
  # require_incus, so a fence that was never called means it refused after all.
  if [ ! -s "$PARA_FENCE/calls" ]; then
    echo "  para stopped before reaching the daemon" >&2
    return 1
  fi
}

test_image_rejects_an_unknown_subcommand() {
  local p; p="$(a_project)"
  para_in "$p" image not-a-subcommand
  [ "$PARA_RC" -ne 0 ] || { echo "  an unknown image subcommand was accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "usage: para image" "the dispatcher named the problem"
}

# --------------------------------------------------------------------- init

test_init_scaffolds_a_project() {
  local d; d="$(a_scaffolded_project)"
  assert test -f "$d/.paraspace/env"   || return 1
  assert test -f "$d/.paraspace/stack" || return 1
  assert test -f "$d/.paraspace/layers/project/hooks/provision" || return 1
  assert test -f "$d/.paraspace/layers/project/hooks/boot"      || return 1
  # The default stack: the bundled base first, the project's own layer last.
  assert_eq "node_modules/paraspace/layers/base/void
.paraspace/layers/project" "$(cat "$d/.paraspace/stack")" "base then project"
}

test_void_base_establishes_zsh_extension_paths() {
  local repo hook
  repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  hook="$repo/layers/base/void/hooks/image-build"
  assert_contains "$(cat "$hook")" "pkgs=\"zsh" "the base installs zsh" || return 1
  assert_contains "$(cat "$hook")" "/etc/zsh/zshrc.d" "the base creates zsh drop-ins" || return 1
  assert_contains "$(cat "$hook")" "/usr/share/zsh/site-functions" \
    "the base creates the completion path"
}

test_a_scaffolded_project_takes_its_identity_from_the_directory() {
  # The scaffold ships no project name in its ACTIVE config: the engine
  # derives PARA_PROJECT_NAME from the directory name. PARA_PROJECT_NAME is
  # unset for the same reason PARA_PROJECT_DIR is: the e2e sandbox exports
  # one, and an inherited value is exactly what this test must not see.
  local d out; d="$(scratch)"
  mkdir -p "$d/My.App"
  a_linked_package "$d/My.App"
  ( cd "$d/My.App" && env -u PARA_PROJECT_DIR -u PARA_PROJECT_NAME "$PARA" init >/dev/null 2>&1 )
  # Fenced, like every doctor run here: a real incus would be probed otherwise.
  [ -n "$PARA_FENCE" ] || PARA_FENCE="$(a_fenced_backend)"
  out="$(cd "$d/My.App" && env -u PARA_PROJECT_DIR -u PARA_PROJECT_NAME PATH="$PARA_FENCE:$PATH" "$PARA" doctor 2>&1)"
  assert_contains "$out" "my-app" "the directory name became the project slug"
}

# Run para against <project> with one extra environment variable, backend
# fenced. The precedence tests are ABOUT the environment, so they set it
# explicitly rather than going through para_in.
_para_env() { # _para_env <project> <VAR=VALUE> <args>...
  local proj="$1" assignment="$2"; shift 2
  [ -n "$PARA_FENCE" ] || PARA_FENCE="$(a_fenced_backend)"
  env PATH="$PARA_FENCE:$PATH" PARA_PROJECT_DIR="$proj" "$assignment" "$PARA" "$@" 2>&1
}
