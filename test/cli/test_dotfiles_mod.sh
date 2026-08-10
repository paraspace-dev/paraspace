#!/usr/bin/env bash
# CLI-tier tests for the bundled mods/dotfiles hook, content rather than
# engine, and here for one reason: this hook once deleted a user's Claude Code
# login and history, their editor config and their own scripts, on the migration
# it exists to serve. Nothing in the suite caught it, because `para mod add`
# tests only assert the files land.
#
# The hook is ordinary shell over $PARA_SKEL and $PARA_SHARED, so it runs on the
# host with no incus, the same trick test_run_hook.sh uses. $HOME is redirected
# at a throwaway, because the hook symlinks into it and deletes what it finds.

# a_used_shared_volume: a $PARA_SHARED shaped like one somebody has been living
# in for months, which is what the old void-jchook template left behind. Echoes it.
a_used_shared_volume() {
  local v; v="$(scratch)/shared"
  mkdir -p "$v/nvim" "$v/claude/projects" "$v/tmux" "$v/bin"
  printf 'MY EDITED ZSHRC\n'  > "$v/zshrc"
  printf 'MY PLUGIN CONFIG\n' > "$v/nvim/init.lua"
  printf 'OAUTH TOKEN\n'      > "$v/claude/.credentials.json"
  printf 'MONTHS OF IT\n'     > "$v/claude/projects/history.jsonl"
  printf 'MY HELPER\n'        > "$v/bin/my-tool"
  printf '%s\n' "$v"
}

# run_mod_provision <shared>: the bundled mod's provision hook, run the way the
# runner would: $PARA_HOOKS and $PARA_SKEL pointed at the mod's own directories.
run_mod_provision() {
  local repo home; repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  home="$(scratch)/home"; mkdir -p "$home"
  env HOME="$home" \
      PARA_HELPERS="$repo/libexec/helpers" \
      PARA_HOOKS="$repo/mods/dotfiles/hooks" \
      PARA_SKEL="$repo/mods/dotfiles/skel" \
      PARA_SHARED="$1" \
      bash "$repo/mods/dotfiles/hooks/provision" 2>&1
}

test_the_dotfiles_mod_keeps_what_is_already_on_the_volume() {
  # THE test. A shared volume outlives every workspace on it, so a mod arriving
  # late finds real work there. Each assert names data a user would not forgive
  # losing, and every one of them was destroyed by the first version of this hook.
  local v out; v="$(a_used_shared_volume)"
  out="$(run_mod_provision "$v")" || { printf '    | %s\n' "$out" >&2; return 1; }
  assert_eq "OAUTH TOKEN"      "$(cat "$v/claude/.credentials.json")"      "a tool's login survives"   || return 1
  assert_eq "MONTHS OF IT"     "$(cat "$v/claude/projects/history.jsonl")" "and its history"           || return 1
  assert_eq "MY PLUGIN CONFIG" "$(cat "$v/nvim/init.lua")"                 "an edited config survives"  || return 1
  assert_eq "MY HELPER"        "$(cat "$v/bin/my-tool")"                   "your own scripts survive"   || return 1
  # Including the flat zshrc the base template owns: this mod seeds into its own
  # directory instead of contending for that name, so there is nothing to replace.
  assert_eq "MY EDITED ZSHRC"  "$(cat "$v/zshrc")"                         "even the contended zshrc"   || return 1
  assert_contains "$(cat "$v/dotfiles/zshrc")" "para shared zshrc" "and the mod's own is beside it"
}

test_the_dotfiles_mod_seeds_a_volume_that_has_nothing() {
  # The other half: on a fresh volume it must actually install everything, or
  # the test above would pass on a hook that did nothing at all.
  local v out; v="$(scratch)/fresh"; mkdir -p "$v"
  out="$(run_mod_provision "$v")" || { printf '    | %s\n' "$out" >&2; return 1; }
  assert test -f "$v/dotfiles/zshrc" || return 1
  assert test -d "$v/nvim"           || return 1
  assert test -d "$v/claude"         || return 1
  assert test -x "$v/bin/open-url"   || return 1
  assert test -f "$v/claude.json"    || return 1
  assert test -d "$v/nvim-data"
}

test_the_dotfiles_mod_provision_is_idempotent() {
  # para re-runs provision on every `para up`, so runs 2 and 3 must change
  # nothing, including after you edit what it seeded, which is the point of
  # seeding once.
  local v; v="$(a_used_shared_volume)"
  run_mod_provision "$v" >/dev/null || return 1
  printf 'I EDITED THIS\n' > "$v/dotfiles/zshrc"
  run_mod_provision "$v" >/dev/null || return 1
  run_mod_provision "$v" >/dev/null || return 1
  assert_eq "I EDITED THIS" "$(cat "$v/dotfiles/zshrc")"      "your edits survive every up" || return 1
  assert_eq "OAUTH TOKEN"   "$(cat "$v/claude/.credentials.json")"   "and nothing else moved"
}

test_the_dotfiles_mod_reseeds_what_you_delete() {
  # The documented recovery: delete a seed, converge, get it back. It works
  # because seeding guards on the destination, so there is no mark to get out of
  # step with the file, which is what makes "rm and re-up" a reliable gesture.
  local v; v="$(a_used_shared_volume)"
  run_mod_provision "$v" >/dev/null || return 1
  rm -rf "$v/dotfiles/zshrc" "$v/nvim"
  run_mod_provision "$v" >/dev/null || return 1
  assert_contains "$(cat "$v/dotfiles/zshrc")" "para shared zshrc" "the zshrc came back" || return 1
  assert test -d "$v/nvim"
}
