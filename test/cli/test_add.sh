#!/usr/bin/env bash
# CLI-tier tests for `para add` (aka `para init`), the verb that scaffolds
# .paraspace/ and edits the stack, and for the layer-command resolution that
# rides on the stack. No incus: it is file edits and a name expansion.
#
# Every test installs into a THROWAWAY project (a_project), never into
# test/fixtures/hello. The fixture is tracked, and teardown doesn't cover it,
# so a test that edited it would dirty the working tree and fail the second
# time it ran.
# shellcheck disable=SC2016  # command bodies expand when the command runs, not here

# a_para_pkg <entry>...: a package root of our own, a copy of para under bin/,
# and the given entries created under layers/ (a trailing / makes a directory).
# pkg_root resolves from $0, so `$d/bin/para` reads `$d/layers`, which is how a
# test can put things in layers/ that the real package must never ship.
a_para_pkg() {
  local d entry; d="$(scratch)"
  mkdir -p "$d/bin" "$d/libexec" "$d/layers"
  cp "$PARA" "$d/bin/para"
  cp "$(cd "$(dirname "$PARA")/.." && pwd)/libexec/helpers" "$d/libexec/helpers"
  for entry in "$@"; do
    case "$entry" in
      */) mkdir -p "$d/layers/$entry" ;;
      *)  mkdir -p "$(dirname "$d/layers/$entry")"
          printf 'not a layer\n' > "$d/layers/$entry" ;;
    esac
  done
  printf '%s\n' "$d/bin/para"
}

# assert_row <output> <row>: the catalog is line-oriented, and the two-space
# gutter is part of the row, so containment alone would match everywhere.
assert_row() {
  if printf '%s\n' "$1" | grep -qxF "$2"; then return 0; fi
  echo "  assert_row failed: no line '$2' in:" >&2
  printf '    %s\n' "$1" >&2
  return 1
}

# ------------------------------------------------------------------ the stack

test_add_writes_a_stack_line_and_copies_nothing() {
  local p; p="$(a_project)"
  a_linked_package "$p"
  para_in "$p" add git
  assert_eq 0 "$PARA_RC" "add succeeded: $PARA_OUT" || return 1
  # The line, before the project layer, and nothing vendored: the layer stays
  # where npm put it, which is the whole point.
  assert_eq "node_modules/paraspace/layers/git
.paraspace/layers/project" "$(cat "$p/.paraspace/stack")" "the stack gained one explicit line" || return 1
  assert test ! -e "$p/.paraspace/layers/git"
}

test_add_is_convergent() {
  local p; p="$(a_project)"
  a_linked_package "$p"
  para_in "$p" add git
  para_in "$p" add git
  assert_eq 0 "$PARA_RC" "adding it twice is fine" || return 1
  assert_contains "$PARA_OUT" "already in the stack" "and says it kept the line" || return 1
  assert_eq 1 "$(grep -c 'layers/git' "$p/.paraspace/stack")" "one line, not two"
}

test_add_keeps_the_project_layer_last() {
  local p; p="$(a_project)"
  a_linked_package "$p"
  para_in "$p" add git
  para_in "$p" add dotfiles
  assert_eq "node_modules/paraspace/layers/git
node_modules/paraspace/layers/dotfiles
.paraspace/layers/project" "$(cat "$p/.paraspace/stack")" "insertions land before the project layer"
}

test_init_scaffolds_around_a_named_layer() {
  # Given names in a fresh directory, the scaffold is the names plus the
  # project layer: no default base is smuggled in beside an explicit list.
  local d; d="$(scratch)"
  a_linked_package "$d"
  ( cd "$d" && env -u PARA_PROJECT_DIR "$PARA" init git >/dev/null 2>&1 )
  assert_eq "node_modules/paraspace/layers/git
.paraspace/layers/project" "$(cat "$d/.paraspace/stack")" "named layer plus the project layer" || return 1
  assert_eq "PARA_CONTRACT=1" "$(cat "$d/.paraspace/env")" "and a minimal env"
}

# ------------------------------------------------------------------ expansion

test_add_refuses_an_unknown_layer() {
  local p; p="$(a_project)"
  a_linked_package "$p"
  para_in "$p" add no-such-layer
  [ "$PARA_RC" -ne 0 ] || { echo "  an unknown layer was accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "no layer 'no-such-layer'" "the unknown name is named" || return 1
  assert_contains "$PARA_OUT" "--list" "and the command that lists them" || return 1
  assert_not_contains "$(cat "$p/.paraspace/stack")" "no-such-layer" "nothing was written"
}

test_add_names_npm_install_when_the_package_is_absent() {
  # A bundled name expands under node_modules/paraspace, so without an npm
  # install there is nothing to point at, and the error carries the fix.
  local p; p="$(a_project)"
  para_in "$p" add docker
  [ "$PARA_RC" -ne 0 ] || { echo "  add invented a path for an uninstalled layer" >&2; return 1; }
  assert_contains "$PARA_OUT" "npm install" "the refusal names the fix"
}

test_add_refuses_an_ambiguous_name() {
  # A real directory in the project can collide with a bundled name. Refuse
  # naming each candidate; the fix the error names is writing the full path.
  local p; p="$(a_project)"
  a_linked_package "$p"
  mkdir -p "$p/git"
  para_in "$p" add git
  [ "$PARA_RC" -ne 0 ] || { echo "  an ambiguous name was resolved by luck" >&2; return 1; }
  assert_contains "$PARA_OUT" "more than one layer" "the refusal says it is ambiguous" || return 1
  assert_contains "$PARA_OUT" "node_modules/paraspace/layers/git" "…naming the bundled candidate" || return 1
  assert_contains "$PARA_OUT" "full path" "and the fix"
}

test_add_expands_a_plugin_layer() {
  # paraspace-plugin-* is the ecosystem convention: the vendor name is the
  # package name minus the prefix, and `acme/mod-a` reaches its layers/.
  local pkg root p
  pkg="$(a_para_pkg mod-a/hooks/)"; root="$(cd "$(dirname "$pkg")/.." && pwd)"
  p="$(a_project)"
  PARA_PKG_ROOT="$root" a_linked_package "$p" paraspace-plugin-acme
  para_in "$p" add acme/mod-a
  assert_eq 0 "$PARA_RC" "the vendor name expanded: $PARA_OUT" || return 1
  assert_row "$(cat "$p/.paraspace/stack")" "node_modules/paraspace-plugin-acme/layers/mod-a"
}

test_add_accepts_a_plain_directory_path() {
  # No search paths and no shadowing: a path is tried literally, so a git
  # submodule or a hand-vendored copy works with no npm anywhere.
  local p; p="$(a_project)"
  mkdir -p "$p/vendor/mylayer/hooks"
  para_in "$p" add vendor/mylayer
  assert_eq 0 "$PARA_RC" "a literal path was accepted: $PARA_OUT" || return 1
  assert_row "$(cat "$p/.paraspace/stack")" "vendor/mylayer"
}

test_two_stack_lines_sharing_a_layer_name_are_refused() {
  # Guest layer names come from the stack line, so a project layer named like
  # a bundled one cannot compose with it; resolution refuses and says why.
  local p; p="$(a_project)"
  a_linked_package "$p"
  a_layer "$p" git
  para_in "$p" add git
  [ "$PARA_RC" -ne 0 ] || { echo "  two layers named 'git' were accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "share a layer name" "the refusal names the collision"
}

# ---------------------------------------------------------------------- --new

test_add_new_stubs_a_layer_you_own() {
  local p m; p="$(a_project)"
  para_in "$p" add --new billing
  assert_eq 0 "$PARA_RC" "--new succeeded: $PARA_OUT" || return 1
  m="$p/.paraspace/layers/billing"
  assert test -f "$m/hooks/image-build" || return 1
  assert test -f "$m/hooks/provision"   || return 1
  assert test -f "$m/hooks/boot"        || return 1
  assert_eq ".paraspace/layers/billing
.paraspace/layers/project" "$(cat "$p/.paraspace/stack")" "stubbed before the project layer" || return 1
  # And the stub has to RUN. A missing injected helper fails on the first
  # `para up`, minutes in, inside a container.
  assert env PARA_HELPERS="$(cd "$(dirname "$PARA")/.." && pwd)/libexec/helpers" \
    bash "$m/hooks/provision"
}

test_add_new_leaves_an_existing_layer_alone() {
  # The layer holds work you did by hand, so converging must not eat it.
  local p; p="$(a_project)"
  para_in "$p" add --new billing
  printf 'MINE\n' > "$p/.paraspace/layers/billing/hooks/provision"
  para_in "$p" add --new billing
  assert_eq 0 "$PARA_RC" "--new converges" || return 1
  assert_eq "MINE" "$(cat "$p/.paraspace/layers/billing/hooks/provision")" "the edit survived"
}

test_add_new_refuses_a_name_that_escapes_layers() {
  local p name; p="$(a_project)"
  for name in ../x /abs .; do
    para_in "$p" add --new "$name"
    [ "$PARA_RC" -ne 0 ] || { echo "  --new accepted '$name'" >&2; return 1; }
    assert_contains "$PARA_OUT" "relative path under .paraspace/layers/" "'$name' hit the containment check" || return 1
  done
}

# --------------------------------------------------------------------- --list

test_add_list_is_one_flat_checked_catalog() {
  # Bundled layers, plugin layers, and the project's own in one sorted list,
  # named exactly as add accepts them, the added ones checked, so the flagless
  # list answers both "what can I add" and "what do I have".
  local p out; p="$(a_project)"
  a_linked_package "$p"
  mkdir -p "$p/.paraspace/layers/base/custom-base"
  para_in "$p" add git
  para_in "$p" add --list
  out="$PARA_OUT"
  assert_row "$out" "✔ .paraspace/layers/project"          || return 1
  assert_row "$out" "✔ git"                                || return 1
  assert_row "$out" "  docker"                             || return 1
  assert_row "$out" "  base/void"                          || return 1
  assert_row "$out" "  .paraspace/layers/base/custom-base"
}

test_add_list_indexes_installed_plugins() {
  local pkg root p
  pkg="$(a_para_pkg mod-a/hooks/ base/debian13/hooks/)"
  root="$(cd "$(dirname "$pkg")/.." && pwd)"
  p="$(a_project)"
  PARA_PKG_ROOT="$root" a_linked_package "$p" paraspace-plugin-acme
  para_in "$p" add --list
  assert_row "$PARA_OUT" "  acme/mod-a"        || return 1
  assert_row "$PARA_OUT" "  acme/base/debian13"
}

# ------------------------------------------------------------------ configure

test_add_runs_the_configure_chain_in_stack_order() {
  local pkg root p out
  pkg="$(a_para_pkg alpha/ beta/)"; root="$(cd "$(dirname "$pkg")/.." && pwd)"; p="$(a_project)"
  PARA_PKG_ROOT="$root" a_linked_package "$p"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "alpha cwd=%s layer=%s custom=%s\n" "$PWD" "$PARA_LAYER_DIR" "$PARA_CUSTOM" >> "$PARA_PROJECT_DIR/order"' \
    > "$root/layers/alpha/configure"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "beta\n" >> "$PARA_PROJECT_DIR/order"' > "$root/layers/beta/configure"
  printf 'PARA_CUSTOM=present\n' >> "$p/.paraspace/env"

  out="$(env PARA_PROJECT_DIR="$p" "$pkg" add alpha beta 2>&1)" || return 1
  assert_contains "$out" "YOUR machine with your privileges" "host execution is explicit" || return 1
  assert_eq "alpha cwd=$p layer=$p/node_modules/paraspace/layers/alpha custom=present
beta" "$(cat "$p/order")" "configure order and environment"
}

test_a_configure_failure_leaves_its_writes_and_converges_on_rerun() {
  # Direct writes, deliberately: a failed chain leaves what already applied,
  # and because existing declarations win, rerunning after the fix converges.
  local pkg root p out rc=0
  pkg="$(a_para_pkg alpha/ beta/)"; root="$(cd "$(dirname "$pkg")/.." && pwd)"; p="$(a_project)"
  PARA_PKG_ROOT="$root" a_linked_package "$p"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "PARA_ADDITIVE=yes\n" >> "$PARA_PROJECT_DIR/.paraspace/env"' 'exit 23' \
    > "$root/layers/alpha/configure"
  printf '%s\n' '#!/usr/bin/env bash' 'touch "$PARA_PROJECT_DIR/beta-configured"' \
    > "$root/layers/beta/configure"

  out="$(env PARA_PROJECT_DIR="$p" "$pkg" add alpha beta 2>&1)" || rc=$?
  assert_eq 23 "$rc" "the configure status fails add" || return 1
  assert_contains "$(cat "$p/.paraspace/env")" "PARA_ADDITIVE=yes" "the applied write survives" || return 1
  assert test ! -e "$p/beta-configured" || return 1
  assert_contains "$out" "Configuring 'alpha'" "the failing owner is visible" || return 1
  assert_contains "$out" "re-run: para add" "and the retry is named" || return 1

  # The fix, then a bare add: the whole chain reruns and the tail applies.
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$root/layers/alpha/configure"
  env PARA_PROJECT_DIR="$p" "$pkg" add >/dev/null 2>&1 || return 1
  assert test -e "$p/beta-configured"
}

# --------------------------------------------------------------- layer verbs

test_a_layers_command_becomes_a_verb() {
  # `para <verb>` resolves across every layer in the stack, so a layer that
  # ships a tool can ship the verb that drives it.
  local p; p="$(a_project)"
  a_layer_command "$p" tools deploy '#!/bin/sh
# summary: ship it
echo RAN-THE-LAYERS-COMMAND'
  para_in "$p" deploy
  assert_contains "$PARA_OUT" "RAN-THE-LAYERS-COMMAND" "the layer's command ran" || return 1
  para_in "$p" commands
  assert_contains "$PARA_OUT" "deploy" "para commands lists it" || return 1
  # Named, not anonymous: a verb you didn't write should say where it came from.
  para_in "$p" --help
  assert_contains "$PARA_OUT" "ship it"  "help shows its summary" || return 1
  assert_contains "$PARA_OUT" "[tools]"  "help names the layer it came from"
}

test_the_later_layer_wins_a_contested_verb() {
  # The same conflict rule as skel files: composition order decides, later
  # wins, and the project layer sits last, so its command is the override.
  local p; p="$(a_project)"
  a_layer_command "$p" alpha deploy '#!/bin/sh
echo ALPHA'
  a_layer_command "$p" beta  deploy '#!/bin/sh
echo BETA'
  para_in "$p" deploy
  assert_contains     "$PARA_OUT" "BETA"  "the later layer's command won" || return 1
  assert_not_contains "$PARA_OUT" "ALPHA" "the earlier layer's did not run" || return 1

  a_project_command "$p" deploy '#!/bin/sh
echo PROJECT'
  para_in "$p" deploy
  assert_contains "$PARA_OUT" "PROJECT" "the project layer, last, wins them all" || return 1
  # Listed once, and credited to the layer that actually answers.
  para_in "$p" commands
  assert_eq 1 "$(grep -c '^deploy$' <<<"$PARA_OUT")" "listed once across owners" || return 1
  para_in "$p" --help
  assert_contains     "$PARA_OUT" "[project]" "help credits the winning layer" || return 1
  assert_not_contains "$PARA_OUT" "[beta]"    "and not the one it replaced"
}

test_an_engine_verb_beats_a_layers_command() {
  # An engine verb wins over every layer, and doctor is where that is said.
  local p; p="$(a_project)"
  a_layer_command "$p" rogue ls '#!/bin/sh
echo HIJACKED'
  para_in "$p" ls
  assert_not_contains "$PARA_OUT" "HIJACKED" "the engine verb ran" || return 1
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "layer rogue's command 'ls' is shadowed" "doctor names the loser" || return 1
  para_in "$p" --help
  assert_contains "$PARA_OUT" "the engine verb wins" "help says why it never runs"
}

test_every_shadowed_owner_is_reported() {
  # Each owner has a different file to go fix, so each is named as itself.
  local p; p="$(a_project)"
  a_project_command "$p"       ls '#!/bin/sh
echo MINE'
  a_layer_command   "$p" tools ls '#!/bin/sh
echo LAYER'
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "layer project's command 'ls' is shadowed" "the project layer's is named" || return 1
  assert_contains "$PARA_OUT" "layer tools's command 'ls' is shadowed"   "and the other layer's"       || return 1
  assert_eq 2 "$(grep -c "is shadowed by the engine verb" <<<"$PARA_OUT")" "one line per owner"
}

test_a_command_gets_its_own_para_layer_dir() {
  # A host-side command has no other way to find its own files, and a stale
  # value inherited from a calling command must never leak through.
  local p; p="$(a_project)"
  a_layer_command "$p" tools whereami '#!/bin/sh
echo "at:$PARA_LAYER_DIR"'
  para_in "$p" whereami
  assert_contains "$PARA_OUT" "at:$p/.paraspace/layers/tools" "it points at the owning layer" || return 1

  a_project_command "$p" whoami '#!/bin/sh
echo "at:$PARA_LAYER_DIR"'
  PARA_OUT="$(env PARA_PROJECT_DIR="$p" PARA_LAYER_DIR=/leaked "$PARA" whoami 2>&1)"
  assert_contains "$PARA_OUT" "at:$p/.paraspace/layers/project" "an inherited value was reasserted"
}

# ------------------------------------------------------------------ refusals

test_add_outside_a_project_scaffolds_here() {
  # There is no "outside a project" for init/add: with no enclosing
  # .paraspace/ the current directory becomes the project, which is day one.
  local d; d="$(scratch)"
  a_linked_package "$d"
  ( cd "$d" && env -u PARA_PROJECT_DIR "$PARA" add >/dev/null 2>&1 )
  assert test -f "$d/.paraspace/stack" || return 1
  assert test -f "$d/.paraspace/env"
}

test_add_inside_a_project_edits_the_enclosing_project() {
  # From a subdirectory the enclosing project is the target, like git and
  # compose, so a monorepo subdir never sprouts a second .paraspace/.
  local p; p="$(a_project)"
  a_linked_package "$p"
  mkdir -p "$p/apps/web"
  ( cd "$p/apps/web" && env -u PARA_PROJECT_DIR "$PARA" add git >/dev/null 2>&1 )
  assert test ! -e "$p/apps/web/.paraspace" || return 1
  assert_row "$(cat "$p/.paraspace/stack")" "node_modules/paraspace/layers/git"
}

test_add_rejects_unknown_flags() {
  local p; p="$(a_project)"
  para_in "$p" add --frobnicate
  [ "$PARA_RC" -ne 0 ] || { echo "  an unknown flag was accepted" >&2; return 1; }
  assert_contains "$PARA_OUT" "usage: para add" "the dispatcher named the problem"
}

# --------------------------------------------------------------- registration

test_add_is_registered_everywhere() {
  # A verb registered in three of the four places half-exists: it dispatches
  # but is undiscoverable, or is advertised and falls through to "unknown
  # command". Each site is a separate assert so a red test names which one.
  local p out; p="$(a_project)"
  para_in "$p" --help
  assert_contains "$PARA_OUT" "init | add" "usage lists the merged verb under PROJECT" || return 1

  out="$("$PARA" completions bash 2>&1)"
  assert_contains "$out" "config image init add" "completion knows the verb" || return 1
  assert_contains "$out" "init|add)"             "and completes its arguments" || return 1

  # main()'s dispatch: a layer command called `add` must never shadow the engine.
  a_project_command "$p" add '#!/bin/sh
echo SHADOWED-THE-ENGINE'
  para_in "$p" add --list
  assert_not_contains "$PARA_OUT" "SHADOWED-THE-ENGINE" "the engine verb won" || return 1
  para_in "$p" doctor
  assert_contains "$PARA_OUT" "shadowed" "doctor warns about the shadowed command"
}

# ------------------------------------------------------------------ packaging

test_layers_are_packaged() {
  # Same exposure as libexec/: omit `layers` from package.json's `files` and
  # every bundled name breaks for every published para, with an error that
  # reads like the user's typo. One assert per moving part, so a red test
  # says which.
  local repo out; repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  out="$(cd "$repo" && npm pack --dry-run --json 2>/dev/null)" \
    || { echo "  npm pack --dry-run failed" >&2; return 1; }
  assert_contains "$out" "layers/base/void/hooks/image-build" \
    "the bundled base is in the published tarball" || return 1
  assert_contains "$out" "layers/dotfiles/hooks/provision" \
    "a bundled capability layer is in the published tarball" || return 1
  assert_contains "$out" "layers/docker/configure" \
    "the configure entry point is in the published tarball" || return 1
  assert_contains "$out" "layers/docker/configure.js" \
    "the Docker parser is in the published tarball"
}
