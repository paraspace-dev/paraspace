#!/usr/bin/env bash
# CLI-tier tests for libexec/run-hook, the guest-side loop that turns one hook
# name into every layer's hook, in stack order. No incus: the runner walks
# $PARA_STACK, so it runs on the host against a guest-shaped fixture tree.
#
# Every test here builds a ~/.paraspace-shaped tree, drops run-hook into it the
# way push_stack does, and runs it with a PARA_STACK naming the layers in
# order. Hooks record what they saw by appending to files, because that is the
# only channel a hook has: it writes to the filesystem, never to its caller.
# shellcheck disable=SC2016  # hook bodies expand when the hook runs, not here

# a_stack [<layer>...]: a guest-shaped .paraspace root with the named layers
# under stack/ and run-hook + helpers in place, echoed as a path.
a_stack() {
  local root layer repo
  root="$(scratch)/.paraspace"
  repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  mkdir -p "$root/stack"
  for layer in "$@"; do mkdir -p "$root/stack/$layer/hooks"; done
  cp "$repo/libexec/run-hook" "$root/run-hook"
  cp "$repo/libexec/helpers" "$root/helpers"
  chmod +x "$root/run-hook"
  printf '%s\n' "$root"
}

# a_hook <layer-dir> <name> <body>: no exec bit, deliberately, since para runs
# a hook with `bash <path>`, and a checkout with core.fileMode=false has no
# exec bit to give. A test that chmod'd here would stop guarding that.
a_hook() {
  mkdir -p "$1/hooks"
  printf '%s\n' "$3" > "$1/hooks/$2"
}

# stack_of <root> <layer>...: the PARA_STACK value naming those layers, in
# that order, the way para's generated env does.
stack_of() {
  local root="$1" out="" l; shift
  for l in "$@"; do out="${out:+$out
}$root/stack/$l"; done
  printf '%s' "$out"
}

# run_the_hook <root> <name> [<layer>...]: run the runner over those layers,
# capturing output and status into HOOK_OUT/HOOK_RC. Never `if ! …`, for the
# same reason the runner doesn't.
run_the_hook() {
  local root="$1" name="$2"; shift 2
  HOOK_OUT="$(env PARA_STACK="$(stack_of "$root" "$@")" "$root/run-hook" "$name" 2>&1)"
  HOOK_RC=$?
}

# --------------------------------------------------------------- the contract

test_run_hook_stops_at_a_failing_middle_command() {
  # THE test, and what it guards is the status: `if ! bash "$hook"; then
  # status=$?` reports the status of the `!`, which is zero, so the runner prints
  # `hook failed` and exits 0, and `run_hook`'s `|| die` never fires.
  # The MIDDLE matters: a hook that fails on its last line reports correctly
  # under both broken shapes, so a test written that way guards nothing.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    'echo started >> "$PWD/trace"' 'false' 'echo tail-ran >> "$PWD/trace"')"
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision project
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
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" boot "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 3')"
  run_the_hook "$root" boot project
  assert_eq 3 "$HOOK_RC" "the hook's own exit status reached the caller"
}

test_run_hook_fails_on_a_helpers_style_die() {
  # How a hook actually fails: helpers' die(), from a function, after a source.
  # The bare `exit 3` above is the top-level case only. This is the one every
  # bundled layer's hooks reach for.
  local root; root="$(a_stack project)"
  printf '%s\n' 'die() { echo "error: $*" >&2; exit 1; }' > "$root/stack/project/hooks/helpers"
  a_hook "$root/stack/project" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    '. "$PARA_LAYER_DIR/hooks/helpers"' 'die "no origin configured"' 'echo TAIL_RAN')"
  run_the_hook "$root" provision project
  assert_eq 1 "$HOOK_RC" "a helpers-style die failed the run" || return 1
  assert_contains "$HOOK_OUT" "no origin configured" "the hook's own message survived" || return 1
  assert_not_contains "$HOOK_OUT" "TAIL_RAN" "die ended the hook there"
}

test_run_hook_aborts_the_remaining_layers_on_failure() {
  # A failure stops the whole run where it happened. Without this, a later
  # layer's hook runs on top of a provision that already failed.
  local root; root="$(a_stack alpha project)"
  a_hook "$root/stack/alpha"   provision "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 4')"
  a_hook "$root/stack/project" provision "$(printf '%s\n' 'echo project >> "$PWD/order"')"
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision alpha project
    assert_eq 4 "$HOOK_RC" "the failing layer's status reached the caller" || exit 1
    assert_contains "$HOOK_OUT" "hooks/provision" "the error names the failing hook" || exit 1
    if [ -f order ]; then echo "  a later layer ran after a failure" >&2; exit 1; fi )
}

test_run_hook_announces_each_hook_it_runs() {
  # The only record of who did what in a run. Layer-relative, so two layers'
  # hooks of the same name don't read identically.
  local root; root="$(a_stack alpha project)"
  a_hook "$root/stack/alpha"   provision "$(printf '%s\n' 'true')"
  a_hook "$root/stack/project" provision "$(printf '%s\n' 'true')"
  run_the_hook "$root" provision alpha project
  assert_contains "$HOOK_OUT" "hook: alpha/hooks/provision"   "the first layer's hook was announced" || return 1
  assert_contains "$HOOK_OUT" "hook: project/hooks/provision" "and the last layer's"
}

test_run_hook_runs_the_layers_in_stack_order() {
  # Order is promised now, and it is the stack's: a layer with no such hook
  # contributes nothing and shifts nobody.
  local root; root="$(a_stack alpha beta project)"
  a_hook "$root/stack/alpha"   provision "$(printf '%s\n' 'echo alpha >> "$PWD/order"')"
  a_hook "$root/stack/project" provision "$(printf '%s\n' 'echo project >> "$PWD/order"')"
  # beta has no provision hook: it must be skipped, not error.
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision alpha beta project
    assert_eq 0 "$HOOK_RC" "resolution succeeded" || exit 1
    assert_eq "alpha
project" "$(cat order)" "exactly the two layers with the hook ran, in stack order" )
}

test_run_hook_reports_an_absent_hook_without_failing() {
  # An unfilled hook is the normal state, so it reports as a note rather than
  # a warning; refusing where absence is a bug is the host's job, which is
  # what cmd_image_build's own check is for.
  local root; root="$(a_stack project)"
  run_the_hook "$root" provision project
  assert_eq 0 "$HOOK_RC" "an absent hook is not a failure" || return 1
  assert_contains "$HOOK_OUT" "hook: provision (none)" "and it says so"
}

test_run_hook_treats_an_empty_stack_as_no_hooks() {
  # An empty or unset PARA_STACK composes nothing, the same note as an
  # unfilled hook, so a project with no layers still converges.
  local root; root="$(a_stack)"
  run_the_hook "$root" provision
  assert_eq 0 "$HOOK_RC" "an empty stack is not a failure" || return 1
  assert_contains "$HOOK_OUT" "hook: provision (none)" "and it says so"
}

# ------------------------------------------------- what a hook can see

test_run_hook_gives_each_layer_its_own_dir() {
  # The point of the whole design: every layer's hook is written identically,
  # because $PARA_LAYER_DIR names whoever owns the hook.
  local root; root="$(a_stack alpha project)"
  local body='printf "%s\n" "$PARA_LAYER_DIR" >> "$PWD/seen"'
  a_hook "$root/stack/alpha"   provision "$body"
  a_hook "$root/stack/project" provision "$body"
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision alpha project
    assert_eq "$root/stack/alpha
$root/stack/project" "$(cat seen)" "each hook saw its own layer's dir" )
}

test_run_hook_gives_a_hook_its_own_path_as_dollar_zero() {
  # $0 is the hook, so `. "$(dirname "$0")/helpers"` resolves, naming the same
  # directory $PARA_LAYER_DIR/hooks does. A sourced hook would see the runner
  # here instead, and every hook written against that spelling would break.
  local root; root="$(a_stack project)"
  printf 'echo helpers-sourced\n' > "$root/stack/project/hooks/helpers"
  a_hook "$root/stack/project" provision "$(printf '%s\n' '. "$(dirname "$0")/helpers"' 'echo "zero=$0"')"
  run_the_hook "$root" provision project
  assert_eq 0 "$HOOK_RC" "the hook resolved its own directory" || return 1
  assert_contains "$HOOK_OUT" "helpers-sourced" "a sibling file sourced through \$0" || return 1
  assert_contains "$HOOK_OUT" "zero=$root/stack/project/hooks/provision" "\$0 is the hook's own path"
}

test_run_hook_passes_a_hook_no_arguments() {
  # A sourced hook would inherit the runner's $1, the hook name. A hook takes
  # no arguments; everything it needs is a PARA_*.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision "$(printf '%s\n' 'echo "count=$#"')"
  run_the_hook "$root" provision project
  assert_contains "$HOOK_OUT" "count=0" "the hook saw no positional parameters"
}

test_run_hook_never_runs_helpers_as_a_hook() {
  # A layer may keep support code under hooks/. It sits in the same directory,
  # and only an exact name match may run.
  local root; root="$(a_stack project)"
  printf 'echo helpers-ran-as-a-hook\n' > "$root/stack/project/hooks/helpers"
  a_hook "$root/stack/project" provision "$(printf '%s\n' 'true')"
  run_the_hook "$root" provision project
  case "$HOOK_OUT" in
    *helpers-ran-as-a-hook*) echo "  helpers was run as a hook" >&2; return 1 ;;
  esac
  return 0
}

test_run_hook_reaches_every_layer_from_a_nested_point() {
  # The named-point feature: a hook opens a point of its own, and the point
  # resolves every layer exactly as para's three do. $PARA_RUN_HOOK is what a
  # hook reaches it through, so this also asserts the variable arrived.
  local root; root="$(a_stack alpha project)"
  a_hook "$root/stack/alpha" provision "$(printf '%s\n' '"$PARA_RUN_HOOK" clone:before')"
  a_hook "$root/stack/alpha"   clone:before "$(printf '%s\n' 'echo alpha-point >> "$PWD/point"')"
  a_hook "$root/stack/project" clone:before "$(printf '%s\n' 'echo project-point >> "$PWD/point"')"
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision alpha project
    assert_eq 0 "$HOOK_RC" "the nested point ran" || exit 1
    assert_eq "alpha-point
project-point" "$(cat point)" "the point resolved every layer, in stack order" )
}

test_run_hook_traces_a_failure_through_nested_points() {
  # A hook three points deep used to fail with a path and no answer to "how
  # did para get here". Every level reports as the failure unwinds: the
  # per-level line names the FILE, the chain names the POINTS, and the exit
  # status is carried up unchanged rather than flattened to 1.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision    "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '"$PARA_RUN_HOOK" clone:before')"
  a_hook "$root/stack/project" clone:before "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '"$PARA_RUN_HOOK" keys:setup')"
  a_hook "$root/stack/project" keys:setup   "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 7')"
  run_the_hook "$root" provision project
  assert_eq 7 "$HOOK_RC" "the deepest hook's status survived three levels" || return 1
  assert_contains "$HOOK_OUT" "chain: provision > clone:before > keys:setup" \
    "the deepest failure names the whole chain" || return 1
  assert_contains "$HOOK_OUT" "hooks/keys:setup" "and the file that failed"
}

test_run_hook_does_not_trace_a_flat_failure() {
  # The inverse, and the one that matters more: a provision that opens no
  # point fails in ONE line. Without this the tracing becomes noise on the
  # path every project actually takes.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 1')"
  run_the_hook "$root" provision project
  assert_eq 1 "$HOOK_RC" "it still failed" || return 1
  case "$HOOK_OUT" in
    *chain:*) echo "  a flat failure printed a chain line" >&2; return 1 ;;
  esac
  return 0
}

test_run_hook_refuses_a_hook_point_cycle() {
  # A point that invokes itself recursed until the container's limits bit.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '"$PARA_RUN_HOOK" provision')"
  run_the_hook "$root" provision project
  [ "$HOOK_RC" -ne 0 ] || { echo "  a self-invoking point was allowed" >&2; return 1; }
  assert_contains "$HOOK_OUT" "hook cycle: provision > provision" "the cycle names the chain"
}

test_run_hook_allows_the_same_point_twice_in_sequence() {
  # The guard is about re-entrancy, not repetition: two calls in a row are two
  # children with the same parent chain. Getting this wrong would break the
  # ordinary case of filling one point at two moments.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision "$(printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    '"$PARA_RUN_HOOK" seed' '"$PARA_RUN_HOOK" seed')"
  a_hook "$root/stack/project" seed "$(printf '%s\n' 'echo seeded')"
  run_the_hook "$root" provision project
  assert_eq 0 "$HOOK_RC" "calling one point twice in a row is fine" || return 1
  assert_eq 2 "$(grep -c seeded <<<"$HOOK_OUT")" "and it ran both times"
}

test_run_hook_wraps_a_name_in_its_before_and_after_points() {
  # Every plain name runs between its :before and :after points, so a layer
  # can slot in around another layer's hook without that hook opening a thing.
  local root; root="$(a_stack alpha project)"
  a_hook "$root/stack/alpha"   provision:before 'echo before >> "$PWD/order"'
  a_hook "$root/stack/project" provision        'echo main >> "$PWD/order"'
  a_hook "$root/stack/alpha"   provision:after  'echo after >> "$PWD/order"'
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision alpha project
    assert_eq 0 "$HOOK_RC" "the wrapped run succeeded" || exit 1
    assert_eq "before
main
after" "$(cat order)" "the points ran around the name, in order" )
}

test_run_hook_gives_a_point_no_points_of_its_own() {
  # :before and :after names are terminal. Wrapping them too would open
  # provision:before:before without end, past any cycle guard, since the name
  # changes at every level.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision               'true'
  a_hook "$root/stack/project" provision:before        'echo point >> "$PWD/order"'
  a_hook "$root/stack/project" provision:before:before 'echo too-deep >> "$PWD/order"'
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision project
    assert_eq 0 "$HOOK_RC" "the run terminated" || exit 1
    assert_eq "point" "$(cat order)" "only the point itself ran" )
}

test_run_hook_says_nothing_for_an_empty_point() {
  # A point is optional by nature, so an unfilled one runs nothing and says
  # nothing, whether para opened it or a hook did. Without this every up
  # prints four lines of noise around provision and boot.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision '"$PARA_RUN_HOOK" clone:before'
  run_the_hook "$root" provision project
  assert_eq 0 "$HOOK_RC" "empty points are not failures" || return 1
  assert_not_contains "$HOOK_OUT" "provision:before" "the auto point stayed silent" || return 1
  assert_not_contains "$HOOK_OUT" "clone:before" "and so did the opened one"
}

test_run_hook_lets_a_failing_before_point_stop_the_run() {
  # :before exists to put things in place for the name it wraps, so a failure
  # there means the hook itself must not run, and the status is the point's.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision:before "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 5')"
  a_hook "$root/stack/project" provision 'echo main >> "$PWD/order"'
  ( cd "$(dirname "$root")" && run_the_hook "$root" provision project
    assert_eq 5 "$HOOK_RC" "the point's status reached the caller" || exit 1
    if [ -f order ]; then echo "  the hook ran after its :before failed" >&2; exit 1; fi
    assert_contains "$HOOK_OUT" "chain: provision > provision:before" "the chain names the route" )
}

test_run_hook_reports_a_failing_after_point() {
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision 'true'
  a_hook "$root/stack/project" provision:after "$(printf '%s\n' '#!/usr/bin/env bash' 'exit 6')"
  run_the_hook "$root" provision project
  assert_eq 6 "$HOOK_RC" "the :after point's status reached the caller"
}

test_run_hook_leaves_stdin_with_the_hook() {
  # provision is documented to prompt, so the hook must inherit the caller's
  # stdin. A loop written as `find | while read` would feed it the hook list.
  local root; root="$(a_stack project)"
  a_hook "$root/stack/project" provision "$(printf '%s\n' 'read -r line' 'echo "read=$line"')"
  HOOK_OUT="$(printf 'from-the-caller\n' \
    | env PARA_STACK="$(stack_of "$root" project)" "$root/run-hook" provision 2>&1)"
  assert_contains "$HOOK_OUT" "read=from-the-caller" "the hook read the caller's stdin"
}

# ------------------------------------------------------------------ packaging

test_run_hook_is_packaged() {
  # package.json's `files` lists bin/para, not bin/, so every tree para pushes
  # has to be named there. Its own assert, not one combined check: "something
  # is missing" costs another five minutes to diagnose.
  local repo out; repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  out="$(cd "$repo" && npm pack --dry-run --json 2>/dev/null)" \
    || { echo "  npm pack --dry-run failed" >&2; return 1; }
  assert_contains "$out" "libexec/run-hook" "libexec/run-hook is in the published tarball" || return 1
}

test_helpers_are_packaged() {
  local repo out; repo="$(cd "$(dirname "$PARA")/.." && pwd)"
  out="$(cd "$repo" && npm pack --dry-run --json 2>/dev/null)" \
    || { echo "  npm pack --dry-run failed" >&2; return 1; }
  assert_contains "$out" "libexec/helpers" "libexec/helpers is in the published tarball"
}
