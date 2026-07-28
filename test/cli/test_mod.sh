#!/usr/bin/env bash
# CLI-tier tests for `para mod add` — the verb that vendors a bundled mod into a
# project's .paraspace/mods/. No incus: it is a directory copy and a name check.
#
# Every test installs into a THROWAWAY project (a_project), never into
# test/fixtures/hello. The fixture is tracked, and teardown doesn't cover it — a
# test that added a mod there would dirty the working tree, hand bin/lint the
# installed copy to lint, and fail the second time it ran.

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
      *)  printf 'not a mod\n' > "$d/mods/$entry" ;;
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

  # is_engine_verb: a project command called `mod` must never shadow the engine.
  a_project_command "$p" mod '#!/bin/sh
echo SHADOWED-THE-ENGINE'
  para_in "$p" mod add --list
  assert_not_contains "$PARA_OUT" "SHADOWED-THE-ENGINE" "the engine verb won" || return 1
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "shadowed" "doctor warns about the shadowed command"
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
