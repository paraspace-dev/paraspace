#!/usr/bin/env bash
# CLI-tier tests, no incus. Dispatch, project commands, configuration
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

# ---------------------------------------------------------- project commands

test_project_commands_extend_the_verb_set() {
  # The extension point: an executable in .paraspace/commands/ becomes `para
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

test_the_environment_overrides_the_parafile() {
  # The whole precedence model: a Parafile written with the `:=` idiom yields to
  # a real environment variable. Nothing in para implements this (bash does),
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
  assert_contains "$PARA_OUT" "origin=[git@github.com:acme/other.git]" "the Parafile won"
}

test_the_ready_host_defaults_to_paras_own_domain() {
  # Every workspace waits on guest DNS before a hook runs, so the gate needs a
  # name para can pick for itself. Its own, so the default presumes no git host.
  local p; p="$(a_project)"
  # shellcheck disable=SC2016  # the command's $vars are literal here
  a_project_command "$p" resolved '#!/bin/sh
echo "ready=[$PARA_READY_HOST]"'
  para_in "$p" resolved
  assert_contains "$PARA_OUT" "ready=[paraspace.dev]" "the gate defaults to paraspace.dev"
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
test_init_resolves_the_project_into_the_scaffolded_parafile() {
  # The scaffolded Parafile's commented defaults are meant to READ as what para
  # already resolved here, so ${PARA_PROJECT} is substituted on the way in. It
  # cannot be left for bash: para resolves PARA_PROJECT after sourcing the
  # Parafile, so an unsubstituted one is an unbound variable, not a default.
  local d out; d="$(scratch)"
  mkdir -p "$d/Acme.Web"
  git -C "$d/Acme.Web" init -q
  git -C "$d/Acme.Web" remote add origin git@github.com:acme/acme.git
  ( cd "$d/Acme.Web" && env -u PARA_PROJECT_DIR -u PARA_PROJECT "$PARA" init void-docker-gh >/dev/null 2>&1 )
  out="$(cat "$d/Acme.Web/.paraspace/Parafile")"
  assert_contains "$out" 'PARA_VOLUME:=para-home-acme-web'       "the volume default names this project" || return 1
  assert_contains "$out" 'PARA_IMAGE:=acme-web'                  "so does the image default"             || return 1
  assert_contains "$out" 'PARA_ORIGIN:=git@github.com:acme/acme' "and the origin is this checkout's"     || return 1
  # $PARA_PROJECT_DIR is a different variable, and para DOES set it before
  # sourcing, so the substitution must not eat its prefix.
  # shellcheck disable=SC2016  # literal Parafile text, not an expansion
  assert_contains     "$out" 'PARA_HOST_ENV:=$PARA_PROJECT_DIR/.env' "PARA_PROJECT_DIR survived intact" || return 1
  # shellcheck disable=SC2016  # ditto
  assert_not_contains "$out" '${PARA_PROJECT}'                       "no placeholder was left behind"  || return 1

  # With nowhere to read an origin from, the line names an app you can clone.
  mkdir -p "$d/no-repo"
  ( cd "$d/no-repo" && env -u PARA_PROJECT_DIR -u PARA_PROJECT "$PARA" init void-docker-gh >/dev/null 2>&1 )
  out="$(cat "$d/no-repo/.paraspace/Parafile")"
  assert_contains     "$out" 'PARA_ORIGIN:=https://github.com/paraspace-dev' "it falls back to the example app" || return 1
  # shellcheck disable=SC2016  # ditto
  assert_not_contains "$out" '${PARA_ORIGIN}'                                "and resolves that placeholder too"
}

test_init_refuses_to_clobber_an_existing_project() {
  # The guard between `para init` and a user's own Parafile and hooks. Untested,
  # it can be deleted outright and the whole tier stays green, while the first
  # command a new user runs eats their work.
  local d out; d="$(scratch)"
  mkdir -p "$d/.paraspace/hooks"
  printf 'MINE=yes\n'  > "$d/.paraspace/Parafile"
  printf '# my hook\n' > "$d/.paraspace/hooks/provision"

  out="$(cd "$d" && env -u PARA_PROJECT_DIR -u PARA_PROJECT "$PARA" init void-minimal 2>&1)"
  assert_eq "MINE=yes"  "$(cat "$d/.paraspace/Parafile")"        "the Parafile was left alone" || return 1
  assert_eq "# my hook" "$(cat "$d/.paraspace/hooks/provision")" "the hook was left alone"     || return 1
  assert_contains "$out" "skip (exists)" "it says what it skipped" || return 1

  # …and --force is how you say you meant it, for what the template owns. Not
  # the Parafile: refreshing a template's hooks is the whole point of --force,
  # and taking PARA_ROUTES with them would make it unusable for that.
  ( cd "$d" && env -u PARA_PROJECT_DIR -u PARA_PROJECT "$PARA" init void-minimal --force >/dev/null 2>&1 )
  assert_not_contains "$(cat "$d/.paraspace/hooks/provision")" "# my hook" "--force refreshed the hook" || return 1
  assert_eq "MINE=yes" "$(cat "$d/.paraspace/Parafile")"                   "…and spared the Parafile"
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
  local p; p="$(a_project PARA_PROJECT=derived-slug)"
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "PARA_IMAGE    derived-slug" "PARA_IMAGE derived from PARA_PROJECT"
}

test_the_image_base_and_its_bootstrap_default_together() {
  # A Parafile that names no distro gets Void, and the one `sh -c` line that
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
  # so a project that never renamed image-build.sh would get one line of
  # scrollback and a base image with no provisioning in it.
  local p; p="$(a_project 'PARA_IMAGE_BASE=images:alpine/edge')"
  assert_refuses "$p" "no 'image-build' hook" image build || return 1
  assert_backend_untouched
}

test_image_build_accepts_a_hook_from_a_mod() {
  # ...and it has to span mods, or vendoring the hook that builds your image
  # would be refused by the very check that exists to catch its absence.
  local p; p="$(a_project 'PARA_IMAGE_BASE=images:alpine/edge')"
  mkdir -p "$p/.paraspace/mods/tools/hooks"
  printf 'true\n' > "$p/.paraspace/mods/tools/hooks/image-build"
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
  # A template ships with no project name in its ACTIVE config: the engine
  # derives PARA_PROJECT from the directory name. (Scaffolding resolves the name
  # into the Parafile's commented defaults, which is a different test.)
  # PARA_PROJECT is unset for the same reason PARA_PROJECT_DIR is: the e2e
  # sandbox exports one, and an inherited value is exactly what this test must
  # not see. (It passed under `--cli` and failed under `--all` before this.)
  local d out; d="$(scratch)"
  mkdir -p "$d/My.App"
  ( cd "$d/My.App" && env -u PARA_PROJECT_DIR -u PARA_PROJECT "$PARA" init void-minimal >/dev/null 2>&1 )
  out="$(cd "$d/My.App" && env -u PARA_PROJECT_DIR -u PARA_PROJECT "$PARA" doctor 2>&1)"
  assert_contains "$out" "my-app" "the directory name became the project slug"
}

test_bundled_helpers_do_not_drift() {
  # helpers is byte-identical across everything this package ships (the
  # templates, the mods, and the libexec/ copy `para mod init` scaffolds from)
  # on purpose, and cannot be factored into a shared
  # overlay: it has to sit BESIDE the hooks that source it (shellcheck follows
  # `. "$PARA_HOOKS/helpers"` by basename, through .shellcheckrc's
  # source-path=SCRIPTDIR), para pushes .paraspace/ into a workspace whole, and
  # a mod resolves $PARA_HOOKS to its OWN directory, so it must ship one.
  local repo ref="" f rc=0 n=0
  repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  for f in "$repo"/libexec/helpers "$repo"/templates/*/.paraspace/hooks/helpers "$repo"/mods/*/hooks/helpers; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    if [ -z "$ref" ]; then ref="$f"; continue; fi
    cmp -s "$ref" "$f" || { echo "  drift: ${f#"$repo"/} differs from ${ref#"$repo"/}" >&2; rc=1; }
  done
  [ "$n" -ge 3 ] || { echo "  expected at least three bundled helpers, found $n" >&2; return 1; }
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
