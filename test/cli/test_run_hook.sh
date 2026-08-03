#!/usr/bin/env bash
# CLI-tier tests for libexec/run-hook, the guest-side loop that turns one hook
# name into the project's hook plus each mod's. No incus: the runner takes its
# root from its own path, so it runs on the host against a fixture directory.
#
# Every test here builds a .paraspace/-shaped tree, drops run-hook into it the
# way push_paraspace does, and runs it. Hooks record what they saw by appending
# to files, because that is the only channel a hook has. It writes to the
# filesystem and never to its caller.
# shellcheck disable=SC2016  # hook bodies expand when the hook runs, not here

# a_paraspace [<mod>...]: a fixture tree with run-hook in place, echoed as a
# path. Owners get an empty hooks/ each; a test fills in the hooks it needs.
a_paraspace() {
  local root mod
  root="$(scratch)/.paraspace"
  mkdir -p "$root/hooks"
  for mod in "$@"; do mkdir -p "$root/mods/$mod/hooks"; done
  cp "$(cd "$(dirname "$PARA")/.." && pwd)/libexec/run-hook" "$root/run-hook"
  chmod +x "$root/run-hook"
  printf '%s\n' "$root"
}

# a_hook <owner-dir> <name> <body>: no exec bit, deliberately, since para runs a hook
# with `bash <path>`, and a checkout with core.fileMode=false has no exec bit to
# give. A test that chmod'd here would stop guarding that.
a_hook() {
  mkdir -p "$1/hooks"
  printf '%s\n' "$3" > "$1/hooks/$2"
}

# run_the_hook <root> <name>: run the runner, capturing output and status into
# HOOK_OUT/HOOK_RC. Never `if ! …`, for the same reason the runner doesn't.
run_the_hook() {
  HOOK_OUT="$("$1/run-hook" "$2" 2>&1)"
  HOOK_RC=$?
}

# --------------------------------------------------------------- the contract

test_run_hook_stops_at_a_failing_middle_command() {
  # THE test, and what it guards is the status: `if ! bash "$hook"; then
  # status=$?` reports the status of the `!`, which is zero, so the runner prints
  # `hook failed` and exits 0, and `run_hook`'s `|| die` never fires.
  # The missing tail line is a weaker guard than it looks: a sourced hook that
  # sets its own `-e` still stops, because the `set` builtin re-arms errexit.
  # The MIDDLE matters: a hook that fails on its last line reports correctly
  # under both broken shapes, so a test written that way guards nothing.
  local root; root="$(a_paraspace)"
  a_hook "$root" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    'echo started >> "$PWD/trace"' 'false' 'echo tail-ran >> "$PWD/trace"')"
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision
    [ "$HOOK_RC" -ne 0 ] || { echo "  a failing hook reported success (rc=$HOOK_RC)" >&2; exit 1; }
    assert_contains "$(cat trace)" "started" "the hook ran at all" || exit 1
    case "$(cat trace)" in
      *tail-ran*) echo "  the hook continued past a failed command" >&2; exit 1 ;;
    esac
    assert_contains "$HOOK_OUT" "hook failed" "the runner named the failure" )
}

test_run_hook_propagates_the_hooks_exit_status() {
  # `helpers`' die() is `exit 1`, but the status is the hook's to choose and
  # para hands it back unchanged rather than flattening it to 1.
  local root; root="$(a_paraspace)"
  a_hook "$root" boot "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 3')"
  run_the_hook "$root" boot
  assert_eq 3 "$HOOK_RC" "the hook's own exit status reached the caller"
}

test_run_hook_fails_on_a_helpers_style_die() {
  # How a hook actually fails: helpers' die(), from a function, after a source.
  # The bare `exit 3` above is the top-level case only. This is the one every
  # bundled template's hooks reach for.
  local root; root="$(a_paraspace)"
  printf '%s\n' 'die() { echo "error: $*" >&2; exit 1; }' > "$root/hooks/helpers"
  a_hook "$root" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    '. "$PARA_HOOKS/helpers"' 'die "no origin configured"' 'echo TAIL_RAN')"
  run_the_hook "$root" provision
  assert_eq 1 "$HOOK_RC" "a helpers-style die failed the run" || return 1
  assert_contains "$HOOK_OUT" "no origin configured" "the hook's own message survived" || return 1
  assert_not_contains "$HOOK_OUT" "TAIL_RAN" "die ended the hook there"
}

test_run_hook_aborts_the_remaining_owners_on_failure() {
  # A failure stops the whole run where it happened. Without this, a mod's hook
  # runs on top of a project provision that already failed.
  local root; root="$(a_paraspace alpha)"
  a_hook "$root"            provision "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 4')"
  a_hook "$root/mods/alpha" provision "$(printf '%s\n' 'echo alpha >> "$PWD/order"')"
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision
    assert_eq 4 "$HOOK_RC" "the failing owner's status reached the caller" || exit 1
    assert_contains "$HOOK_OUT" "hooks/provision" "the error names the failing hook" || exit 1
    if [ -f order ]; then echo "  a later owner ran after a failure" >&2; exit 1; fi )
}

test_run_hook_announces_each_hook_it_runs() {
  # The only record of who did what in a run. Owner-relative, so the project's
  # hook and a mod's hook of the same name don't read identically.
  local root; root="$(a_paraspace alpha)"
  a_hook "$root"            provision "$(printf '%s\n' 'true')"
  a_hook "$root/mods/alpha" provision "$(printf '%s\n' 'true')"
  run_the_hook "$root" provision
  assert_contains "$HOOK_OUT" "hook: hooks/provision" "the project's hook was announced" || return 1
  assert_contains "$HOOK_OUT" "hook: mods/alpha/hooks/provision" "the mod's hook was announced"
}

test_run_hook_runs_every_owner_project_first() {
  local root; root="$(a_paraspace alpha beta)"
  a_hook "$root"           provision "$(printf '%s\n' 'echo project >> "$PWD/order"')"
  a_hook "$root/mods/beta" provision "$(printf '%s\n' 'echo beta >> "$PWD/order"')"
  # alpha has no provision hook: it must be skipped, not error.
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision
    assert_eq 0 "$HOOK_RC" "resolution succeeded" || exit 1
    # Order between mods is explicitly not promised, only that the project ran
    # first, and that the mod with no such hook contributed nothing.
    assert_eq "project" "$(head -n1 order)" "the project's hook ran first" || exit 1
    assert_eq "2" "$(wc -l < order | tr -d ' ')" "exactly the two owners with the hook ran" )
}

test_run_hook_reports_an_absent_hook_without_failing() {
  # An unfilled hook is the normal state, so it reports as a note rather than a
  # warning, since refusing where absence is a bug is the host's job, which is what
  # cmd_image_build's own check is for.
  local root; root="$(a_paraspace)"
  run_the_hook "$root" provision
  assert_eq 0 "$HOOK_RC" "an absent hook is not a failure" || return 1
  assert_contains "$HOOK_OUT" "no 'provision' hook" "and it says so"
}

test_run_hook_skips_a_stray_file_under_mods() {
  # `mods/*` globs whatever is there. A README beside the mods is not an owner.
  local root; root="$(a_paraspace alpha)"
  printf 'not a mod\n' > "$root/mods/README.md"
  a_hook "$root" provision "$(printf '%s\n' 'true')"
  run_the_hook "$root" provision
  assert_eq 0 "$HOOK_RC" "a stray file under mods/ is skipped, not treated as an owner"
}

# ------------------------------------------------- what a hook can see

test_run_hook_gives_each_owner_its_own_paths() {
  # The point of the whole design: a mod's hook is written identically to a
  # project's, because $PARA_HOOKS/$PARA_SKEL name whoever owns the hook.
  local root; root="$(a_paraspace alpha)"
  local body='printf "%s %s\n" "$PARA_HOOKS" "$PARA_SKEL" >> "$PWD/seen"'
  a_hook "$root"            provision "$body"
  a_hook "$root/mods/alpha" provision "$body"
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision
    assert_contains "$(cat seen)" "$root/hooks $root/skel" "the project's hook saw its own dirs" || exit 1
    assert_contains "$(cat seen)" "$root/mods/alpha/hooks $root/mods/alpha/skel" \
      "the mod's hook saw the mod's dirs" )
}

test_run_hook_gives_a_hook_its_own_path_as_dollar_zero() {
  # $0 is the hook, so `. "$(dirname "$0")/helpers"` resolves, naming the same
  # directory $PARA_HOOKS does. A sourced hook would see the runner here instead,
  # and every hook written against the older spelling would break.
  local root; root="$(a_paraspace)"
  printf 'echo helpers-sourced\n' > "$root/hooks/helpers"
  a_hook "$root" provision "$(printf '%s\n' '. "$(dirname "$0")/helpers"' 'echo "zero=$0"')"
  run_the_hook "$root" provision
  assert_eq 0 "$HOOK_RC" "the hook resolved its own directory" || return 1
  assert_contains "$HOOK_OUT" "helpers-sourced" "a sibling file sourced through \$0" || return 1
  assert_contains "$HOOK_OUT" "zero=$root/hooks/provision" "\$0 is the hook's own path"
}

test_run_hook_passes_a_hook_no_arguments() {
  # A sourced hook would inherit the runner's $1, the hook name. A hook takes
  # no arguments; everything it needs is a PARA_*.
  local root; root="$(a_paraspace)"
  a_hook "$root" provision "$(printf '%s\n' 'echo "count=$#"')"
  run_the_hook "$root" provision
  assert_contains "$HOOK_OUT" "count=0" "the hook saw no positional parameters"
}

test_run_hook_never_runs_helpers_as_a_hook() {
  # hooks/helpers is a library every template's hooks source. It sits in the
  # same directory, and only an exact name match may run.
  local root; root="$(a_paraspace)"
  printf 'echo helpers-ran-as-a-hook\n' > "$root/hooks/helpers"
  a_hook "$root" provision "$(printf '%s\n' 'true')"
  run_the_hook "$root" provision
  case "$HOOK_OUT" in
    *helpers-ran-as-a-hook*) echo "  helpers was run as a hook" >&2; return 1 ;;
  esac
  return 0
}

test_run_hook_reaches_every_owner_from_a_nested_point() {
  # The named-point feature: a hook opens a point of its own, and the point
  # resolves every owner exactly as para's three do. $PARA_RUN_HOOK is what a
  # hook reaches it through, so this also asserts the variable arrived.
  local root; root="$(a_paraspace alpha)"
  a_hook "$root" provision "$(printf '%s\n' '"$PARA_RUN_HOOK" clone:before')"
  a_hook "$root"            clone:before "$(printf '%s\n' 'echo project-point >> "$PWD/point"')"
  a_hook "$root/mods/alpha" clone:before "$(printf '%s\n' 'echo mod-point >> "$PWD/point"')"
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision
    assert_eq 0 "$HOOK_RC" "the nested point ran" || exit 1
    assert_contains "$(cat point)" "project-point" "the project filled its own point" || exit 1
    assert_contains "$(cat point)" "mod-point"     "and the mod filled it too" )
}

test_run_hook_traces_a_failure_through_nested_points() {
  # A hook three points deep used to fail with a path and no answer to "how did
  # para get here". Every level reports as the failure unwinds, where the
  # per-level line names the FILE and the stack names the POINTS, and the exit status is
  # carried up unchanged rather than flattened to 1.
  local root; root="$(a_paraspace)"
  a_hook "$root" provision    "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '"$PARA_RUN_HOOK" clone:before')"
  a_hook "$root" clone:before "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '"$PARA_RUN_HOOK" keys:setup')"
  a_hook "$root" keys:setup   "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 7')"
  run_the_hook "$root" provision
  assert_eq 7 "$HOOK_RC" "the deepest hook's status survived three levels" || return 1
  assert_contains "$HOOK_OUT" "stack: provision > clone:before > keys:setup" \
    "the deepest failure names the whole chain" || return 1
  assert_contains "$HOOK_OUT" "hooks/keys:setup" "and the file that failed"
}

test_run_hook_does_not_trace_a_flat_failure() {
  # The inverse, and the one that matters more: a provision that opens no point
  # fails in ONE line. Without this the tracing becomes noise on the
  # path every project actually takes.
  local root; root="$(a_paraspace)"
  a_hook "$root" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 1')"
  run_the_hook "$root" provision
  assert_eq 1 "$HOOK_RC" "it still failed" || return 1
  case "$HOOK_OUT" in
    *stack:*) echo "  a flat failure printed a stack line" >&2; return 1 ;;
  esac
  return 0
}

test_run_hook_refuses_a_hook_point_cycle() {
  # A point that invokes itself recursed until the container's limits bit.
  local root; root="$(a_paraspace)"
  a_hook "$root" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '"$PARA_RUN_HOOK" provision')"
  run_the_hook "$root" provision
  [ "$HOOK_RC" -ne 0 ] || { echo "  a self-invoking point was allowed" >&2; return 1; }
  assert_contains "$HOOK_OUT" "hook cycle: provision > provision" "the cycle names the chain"
}

test_run_hook_allows_the_same_point_twice_in_sequence() {
  # The guard is about re-entrancy, not repetition: two calls in a row are two
  # children with the same parent stack. Getting this wrong would break the
  # ordinary case of filling one point at two moments.
  local root; root="$(a_paraspace)"
  a_hook "$root" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    '"$PARA_RUN_HOOK" seed' '"$PARA_RUN_HOOK" seed')"
  a_hook "$root" seed "$(printf '%s\n' 'echo seeded')"
  run_the_hook "$root" provision
  assert_eq 0 "$HOOK_RC" "calling one point twice in a row is fine" || return 1
  assert_eq 2 "$(grep -c seeded <<<"$HOOK_OUT")" "and it ran both times"
}

test_run_hook_leaves_stdin_with_the_hook() {
  # provision is documented to prompt, so the hook must inherit the caller's
  # stdin. A loop written as `find | while read` would feed it the hook list.
  local root; root="$(a_paraspace)"
  a_hook "$root" provision "$(printf '%s\n' 'read -r line' 'echo "read=$line"')"
  HOOK_OUT="$(printf 'from-the-caller\n' | "$root/run-hook" provision 2>&1)"
  assert_contains "$HOOK_OUT" "read=from-the-caller" "the hook read the caller's stdin"
}

# ------------------------------------------------------------------ packaging

test_run_hook_is_packaged() {
  # package.json's `files` lists bin/para, not bin/, so every tree para pushes
  # has to be named there. Its own assert, not one combined check: "something is
  # missing" costs another five minutes to diagnose.
  local repo out; repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  out="$(cd "$repo" && npm pack --dry-run --json 2>/dev/null)" \
    || { echo "  npm pack --dry-run failed" >&2; return 1; }
  assert_contains "$out" "libexec/run-hook" "libexec/run-hook is in the published tarball"
}

test_templates_are_packaged() {
  # Same exposure, and it has been shipping untested: omit `templates` and
  # `para init` breaks for every published para.
  local repo out; repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  out="$(cd "$repo" && npm pack --dry-run --json 2>/dev/null)" \
    || { echo "  npm pack --dry-run failed" >&2; return 1; }
  assert_contains "$out" "templates/void-docker-gh/.paraspace/Parafile" \
    "the default template is in the published tarball"
}
