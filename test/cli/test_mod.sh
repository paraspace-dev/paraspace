#!/usr/bin/env bash
# CLI-tier tests for `para mod add` — the verb that vendors a bundled mod into a
# project's .paraspace/mods/. No incus: it is a directory copy and a name check.
#
# Every test installs into a THROWAWAY project (a_project), never into
# test/fixtures/hello. The fixture is tracked, and teardown doesn't cover it — a
# test that added a mod there would dirty the working tree, hand bin/lint the
# installed copy to lint, and fail the second time it ran.
# shellcheck disable=SC2016  # command bodies expand when the command runs, not here

# a_para_pkg <entry>... — a package root of our own: a copy of para under bin/,
# and the given entries created under mods/ (a trailing / makes a directory).
# pkg_root resolves from $0, so `$d/bin/para` reads `$d/mods` — which is how a
# test can put things in mods/ that the real package must never ship.
a_para_pkg() {
  local d entry; d="$(scratch)"
  mkdir -p "$d/bin" "$d/mods"
  cp "$PARA" "$d/bin/para"
  for entry in "$@"; do
    case "$entry" in
      */) mkdir -p "$d/mods/$entry" ;;
      *)  mkdir -p "$(dirname "$d/mods/$entry")"
          printf 'not a mod\n' > "$d/mods/$entry" ;;
    esac
  done
  printf '%s\n' "$d/bin/para"
}

# ------------------------------------------------------------------ installing

test_mod_add_vendors_a_bundled_mod() {
  # Into a project with NO mods/ yet, which is the case that needs cmd_mod's
  # `mkdir -p`: cp creates the last path component but not the directory above
  # it, so without it the FIRST mod add in any project dies in raw cp.
  local p; p="$(a_project)"
  assert test ! -d "$p/.paraspace/mods" || return 1
  para_in "$p" mod add dotfiles-jchook
  assert_eq 0 "$PARA_RC" "mod add succeeded" || return 1
  assert test -f "$p/.paraspace/mods/dotfiles-jchook/hooks/provision" || return 1
  assert test -f "$p/.paraspace/mods/dotfiles-jchook/hooks/image-build" || return 1
  assert test -f "$p/.paraspace/mods/dotfiles-jchook/skel/zshrc" || return 1
  # The README travels with it: the copy in your repo documents the copy in
  # your repo, which is the whole reason a mod is vendored rather than fetched.
  assert test -f "$p/.paraspace/mods/dotfiles-jchook/README.md"
}

test_mod_add_says_which_verbs_a_mod_brought() {
  # The reader is told, because these run on the HOST with their privileges —
  # the one thing about a mod that isn't confined to a throwaway container.
  local p; p="$(a_project)"
  para_in "$p" mod add dotfiles-jchook
  assert_contains "$PARA_OUT" "YOUR machine" "the warning names where they run" || return 1
  assert_contains "$PARA_OUT" "claude, run"  "and which verbs landed"
}

test_mod_add_repairs_an_exec_bit_the_checkout_lost() {
  # A command honours its shebang, so unlike a hook it needs the exec bit, and
  # `exec` on a 644 file dies with a bare "permission denied" naming a path the
  # reader never installed. The SOURCE has to be non-executable to prove this:
  # every bundled mod's commands are 100755 in git, so cp -R carries the bit and
  # a test using one passes with the chmod deleted.
  local pkg d; pkg="$(a_para_pkg nx/commands/deploy)"
  d="$(a_project)"
  assert test ! -x "$(dirname "$pkg")/../mods/nx/commands/deploy" || return 1
  env PARA_PROJECT_DIR="$d" "$pkg" mod add nx >/dev/null 2>&1
  assert test -x "$d/.paraspace/mods/nx/commands/deploy"
}

test_mod_add_is_quiet_about_a_mod_with_no_commands() {
  # The warning has to mean something when it fires, so it must not fire on
  # every install. Needs a package of our own: every bundled mod ships commands.
  local pkg d out; pkg="$(a_para_pkg quiet-mod/hooks/)"; d="$(a_project)"
  out="$(env PARA_PROJECT_DIR="$d" "$pkg" mod add quiet-mod 2>&1)"
  assert_contains     "$out" "Vendored"     "it still installed" || return 1
  assert_not_contains "$out" "YOUR machine" "no verbs, no warning"
}

test_mod_add_replaces_rather_than_merging() {
  # Adding again is the update path, so it must be a REPLACE. `cp -R` alone
  # merges into what is already there, which would leave a file the new version
  # of the mod deleted sitting in the tree forever.
  local p; p="$(a_project)"
  para_in "$p" mod add dotfiles-jchook
  printf 'stale\n' > "$p/.paraspace/mods/dotfiles-jchook/GONE-IN-THE-NEXT-VERSION"
  para_in "$p" mod add dotfiles-jchook
  assert_eq 0 "$PARA_RC" "adding it twice is fine" || return 1
  assert test ! -e "$p/.paraspace/mods/dotfiles-jchook/GONE-IN-THE-NEXT-VERSION" || return 1
  assert test -f "$p/.paraspace/mods/dotfiles-jchook/hooks/provision"
}

# ----------------------------------------------------------------------- --list

test_mod_add_list_names_what_this_para_ships() {
  # From OUTSIDE a project, which is the claim: --list answers before
  # require_project, because "what can I install" comes before having somewhere
  # to put it. Without the cd it would pass from anywhere inside this repo.
  local out; out="$(cd "$(scratch)" && env -u PARA_PROJECT_DIR "$PARA" mod add --list 2>&1)"
  assert_contains "$out" "dotfiles-jchook" "the bundled mod is listed"
}

test_mod_add_list_skips_a_stray_file() {
  # `mods/*` globs whatever is there, and the runner has the same assert from
  # the other side: a README beside the mods is not a mod.
  local pkg out; pkg="$(a_para_pkg real-mod/ NOTES.md)"
  out="$(cd "$(scratch)" && env -u PARA_PROJECT_DIR "$pkg" mod add --list 2>&1)"
  assert_contains     "$out" "real-mod"  "the directory is a mod" || return 1
  assert_not_contains "$out" "NOTES.md"  "a stray file is not"
}

test_mod_add_list_says_nothing_when_this_para_ships_none() {
  # What the `[ -d ]` in bundled_names is actually for. The stray-file test
  # above passes without it — a trailing-slash glob never matches a plain file —
  # but an EMPTY mods/ leaves the glob unmatched, and para would print a bare
  # `*` as though it were a mod you could install.
  local pkg out; pkg="$(a_para_pkg)"
  out="$(cd "$(scratch)" && env -u PARA_PROJECT_DIR "$pkg" mod add --list 2>&1)"
  assert_eq "" "$out" "an empty mods/ lists nothing, not a literal glob"
}

# ------------------------------------------------------------------- refusals

test_mod_add_outside_a_project_fails_with_paras_own_error() {
  # Without require_project the destination is /.paraspace/mods/<name> and the
  # failure is raw cp's, which names a path the reader never typed.
  local d out rc=0; d="$(scratch)"
  out="$(cd "$d" && env -u PARA_PROJECT_DIR "$PARA" mod add dotfiles-jchook 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "  mod add succeeded outside a project" >&2; return 1; }
  assert_contains "$out" "not inside a para project" "para's own error, not cp's"
}

test_mod_add_refuses_a_path_as_a_mod_name() {
  # Same containment as `para init`, and it matters more here: the destination
  # is a directory this deletes before it writes. Asserted on the MESSAGE — each
  # of these would fail anyway once the source path missed, so an
  # exit-status-only check would still pass with the name check removed.
  local p out rc name; p="$(a_project)"
  for name in ../x . ..; do
    rc=0
    out="$(env PARA_PROJECT_DIR="$p" "$PARA" mod add "$name" 2>&1)" || rc=$?
    [ "$rc" -ne 0 ] || { echo "  mod add accepted '$name'" >&2; return 1; }
    assert_contains "$out" "plain directory name" "'$name' hit the containment check" || return 1
  done
  assert test ! -e "$p/.paraspace/mods"
}

test_mod_names_an_unknown_mod_and_an_unknown_subcommand() {
  # Two different mistakes, two different messages, both pointing somewhere.
  local p; p="$(a_project)"
  para_in "$p" mod add no-such-mod
  [ "$PARA_RC" -ne 0 ] || { echo "  an unknown mod was accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "no such mod"    "an unknown mod names --list" || return 1
  assert_contains "$PARA_OUT" "--list"         "and the command that lists them" || return 1
  para_in "$p" mod rm dotfiles-jchook
  [ "$PARA_RC" -ne 0 ] || { echo "  'para mod rm' was accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "usage: para mod add" "the dispatcher named the problem"
}

# --------------------------------------------------------------- registration

test_mod_is_registered_everywhere() {
  # A verb registered in three of the four places half-exists: it dispatches but
  # is undiscoverable, or it is advertised and then falls through to "unknown
  # command". Each site is a separate assert so a red test names which one.
  local p out; p="$(a_project)"
  para_in "$p" --help
  assert_contains "$PARA_OUT" "mod add <name>" "usage lists it under PROJECT" || return 1

  out="$("$PARA" completions bash 2>&1)"
  assert_contains "$out" "config image init mod" "completion knows the verb" || return 1
  assert_contains "$out" "mod)"                  "and completes its arguments" || return 1

  # main()'s `mod)` case: a project command called `mod` must never shadow the
  # engine. (is_engine_verb is what makes doctor say so, asserted just below.)
  a_project_command "$p" mod '#!/bin/sh
echo SHADOWED-THE-ENGINE'
  para_in "$p" mod add --list
  assert_not_contains "$PARA_OUT" "SHADOWED-THE-ENGINE" "the engine verb won" || return 1
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "shadowed" "doctor warns about the shadowed command"
}

# -------------------------------------------------------------- a mod's verbs

test_a_mods_command_becomes_a_verb() {
  # The whole point: `para <verb>` resolves against the project's commands/ AND
  # each mod's, so a mod that ships a tool can ship the verb that drives it.
  local p; p="$(a_project)"
  a_mod_command "$p" tools deploy '#!/bin/sh
# summary: ship it
echo RAN-THE-MODS-COMMAND'
  para_in "$p" deploy
  assert_contains "$PARA_OUT" "RAN-THE-MODS-COMMAND" "the mod's command ran" || return 1
  para_in "$p" commands
  assert_contains "$PARA_OUT" "deploy" "para commands lists it" || return 1
  # Named, not anonymous: a verb you didn't write should say where it came from.
  para_in "$p" --help
  assert_contains "$PARA_OUT" "ship it"  "help shows its summary" || return 1
  assert_contains "$PARA_OUT" "[tools]"  "help names the mod it came from"
}

test_a_project_command_shadows_a_mods() {
  # Your own commands/ is the override: same precedence as engine-over-project,
  # one step down. This is the documented way to replace a verb you dislike.
  local p; p="$(a_project)"
  a_mod_command     "$p" tools deploy '#!/bin/sh
echo MOD'
  a_project_command "$p"       deploy '#!/bin/sh
echo PROJECT'
  para_in "$p" deploy
  assert_contains     "$PARA_OUT" "PROJECT" "the project's command won" || return 1
  assert_not_contains "$PARA_OUT" "MOD"     "the mod's did not run"     || return 1
  # Listed once, not twice, and attributed to nobody: it's yours now.
  para_in "$p" commands
  assert_eq 1 "$(grep -c '^deploy$' <<<"$PARA_OUT")" "listed once across both owners" || return 1
  para_in "$p" --help
  assert_not_contains "$PARA_OUT" "[tools]" "help no longer credits the mod"
}

test_two_mods_defining_one_verb_are_refused() {
  # Nothing promises an order between mods, so running one would be a coin toss
  # the reader can't see the result of. Refuse, and name both files.
  local p; p="$(a_project)"
  a_mod_command "$p" alpha deploy '#!/bin/sh
echo ALPHA'
  a_mod_command "$p" beta  deploy '#!/bin/sh
echo BETA'
  para_in "$p" deploy
  [ "$PARA_RC" -ne 0 ] || { echo "  a contested verb was dispatched anyway" >&2; return 1; }
  assert_not_contains "$PARA_OUT" "ALPHA" "neither mod ran" || return 1
  assert_not_contains "$PARA_OUT" "BETA"  "neither mod ran" || return 1
  assert_contains "$PARA_OUT" "mods/alpha/commands/deploy" "the refusal names one" || return 1
  assert_contains "$PARA_OUT" "mods/beta/commands/deploy"  "and the other"        || return 1

  # --help must survive it, and must not advertise it. A conflict is a project
  # you have to go fix, and help is what you run when you're lost — killing it
  # there would be hostile, but crediting one mod for a verb that refuses is
  # worse than saying nothing.
  para_in "$p" --help
  assert_eq 0 "$PARA_RC" "help still works with a contested verb" || return 1
  assert_contains     "$PARA_OUT" "never runs" "help says the verb won't run" || return 1
  assert_not_contains "$PARA_OUT" "[alpha]"    "and credits neither mod"      || return 1
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "more than one mod defines 'deploy'" "doctor reports it before you trip"
}

test_a_third_mod_does_not_make_it_two() {
  # The message counts, so it must not say "two" when three collide — an error
  # that misdescribes the world sends you looking for the wrong thing.
  local p m; p="$(a_project)"
  for m in alpha beta gamma; do
    a_mod_command "$p" "$m" deploy '#!/bin/sh
echo RAN'
  done
  para_in "$p" deploy
  assert_contains "$PARA_OUT" "more than one mod" "the refusal does not miscount" || return 1
  # gamma is the assert that matters: a "first two" shape would name alpha and
  # beta and look right.
  assert_contains "$PARA_OUT" "mods/gamma/commands/deploy" "and it names every one"
}

test_an_engine_verb_beats_a_mods_command() {
  # An engine verb wins over every owner, so a mod claiming one must be reported
  # as shadowed — NOT as a mod-vs-mod tie, which would be a false claim that
  # `para ls` refuses, and would make `para doctor` fail over nothing.
  local p; p="$(a_project)"
  a_mod_command "$p" rogue  ls '#!/bin/sh
echo HIJACKED'
  a_mod_command "$p" rogue2 ls '#!/bin/sh
echo HIJACKED-TOO'
  para_in "$p" ls
  assert_not_contains "$PARA_OUT" "HIJACKED" "the engine verb ran" || return 1
  para_in "$p" doctor
  # BOTH of them. Naming only the one that "would have run" picks a file by glob
  # order — which is locale-dependent — to report about a verb where neither runs.
  assert_contains     "$PARA_OUT" "mod rogue's command 'ls' is shadowed"  "doctor names one loser" || return 1
  assert_contains     "$PARA_OUT" "mod rogue2's command 'ls' is shadowed" "and the other"          || return 1
  assert_not_contains "$PARA_OUT" "more than one mod defines 'ls'" "and does not claim a refusal that never happens" || return 1
  para_in "$p" --help
  assert_contains "$PARA_OUT" "the engine verb wins" "help says why it never runs"
}

test_a_mods_command_gets_para_mod_dir() {
  # A host-side command has no other way to find its own files: $PARA_HOOKS and
  # $PARA_SKEL name GUEST paths and para keeps them unset on the host.
  local p; p="$(a_project)"
  a_mod_command "$p" tools whereami '#!/bin/sh
echo "at:$PARA_MOD_DIR"'
  para_in "$p" whereami
  assert_contains "$PARA_OUT" "at:$p/.paraspace/mods/tools" "it points at the mod's own directory" || return 1

  # And a project's own command must not see one — including a stale value from
  # the environment, which is exactly what a mod command calling back would leave.
  a_project_command "$p" whoami '#!/bin/sh
echo "at:${PARA_MOD_DIR-<unset>}"'
  PARA_OUT="$(env PARA_PROJECT_DIR="$p" PARA_MOD_DIR=/leaked "$PARA" whoami 2>&1)"
  assert_contains "$PARA_OUT" "at:<unset>" "a project command owns no mod dir"
}

test_a_command_never_sees_guest_paths() {
  # PARA_HOOKS and PARA_SKEL name directories inside a WORKSPACE. On the host
  # they name nothing, so an inherited pair would point a command at paths that
  # don't exist — and docs/hooks.md promises they are unset here.
  local p; p="$(a_project)"
  a_project_command "$p" probe '#!/bin/sh
echo "hooks=[${PARA_HOOKS-unset}] skel=[${PARA_SKEL-unset}]"'
  PARA_OUT="$(env PARA_PROJECT_DIR="$p" PARA_HOOKS=/host/evil PARA_SKEL=/host/evil2 "$PARA" probe 2>&1)"
  assert_contains "$PARA_OUT" "hooks=[unset]" "PARA_HOOKS does not reach a host command" || return 1
  assert_contains "$PARA_OUT" "skel=[unset]"  "nor does PARA_SKEL"
}

# ------------------------------------------------------------------ packaging

test_mods_are_packaged() {
  # Same exposure as templates/ and libexec/: omit `mods` from package.json's
  # `files` and `para mod add` breaks for every published para, with a "no such
  # mod" that reads like the user's typo. Its own assert, so a red test says which.
  local repo out; repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  out="$(cd "$repo" && npm pack --dry-run --json 2>/dev/null)" \
    || { echo "  npm pack --dry-run failed" >&2; return 1; }
  assert_contains "$out" "mods/dotfiles-jchook/hooks/provision" \
    "the bundled mod is in the published tarball"
}
