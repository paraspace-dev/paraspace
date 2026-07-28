#!/usr/bin/env bash
# e2e: assertions against the shared primary workspace ($PARA_WS), brought up
# once by test/run. These are read-only — they must not stop, remove, or
# otherwise disturb it (lifecycle tests use their own workspaces).

# The whole point: an HTTP request over TLS, through para's Caddy, to the busybox
# httpd inside the container — returning the exact sentinel the boot hook wrote,
# tagged with THIS workspace's name (proving it routed to the right container).
test_http_route_serves_the_sentinel() {
  assert_serves "$PARA_WS" || return 1
  local body; body="$(http_get "$PARA_WS")"
  assert_contains "$body" "para-e2e-ok $PARA_WS" "sentinel body carries the workspace name"
}

test_subdomain_route_serves_the_same_workspace() {
  # The fixture declares TWO routes (8080 and api:8080) and until now only the
  # apex was ever requested — so route_host's `sub:port` branch, the entire
  # subdomain mechanism, was asserted only as a string a hook received. Any
  # change that yields a different-but-valid hostname kept the tier green while
  # every subdomain URL para prints 404s.
  assert_serves "$PARA_WS" 30 api || return 1
  local body; body="$(http_get "$PARA_WS" api)"
  assert_contains "$body" "para-e2e-ok $PARA_WS" "the subdomain reached THIS workspace"
}

test_routes_reach_the_provision_hook() {
  # Two things at once. PARA_ROUTES rides para's blanket PARA_* forwarder into
  # hooks like any other key; and the fixture declares its routes in the
  # MULTI-LINE spelling, so what the hook receives also proves the
  # canonicalization — newlines and indentation in, one space-separated token
  # list out, which is what the container stamp and `for r in $PARA_ROUTES` both
  # expect.
  local got; got="$("$PARA" sh "$PARA_WS" -c 'cat ~/routes-seen' 2>/dev/null)"
  # EXACT, and two entries: this is the suite's only oracle for the canonical
  # form, so it pins the separator AND the fact that no entry was dropped.
  assert_eq "8080 api:8080" "$got" "the hook received both routes, space-joined"
}

# shellcheck disable=SC2016  # the guest expands these, not us
test_guest_paths_are_injected() {
  # PARA_HOOKS/PARA_SKEL are guest-only — para appends them to ~/.paraspace/env
  # so a hook names what it reads instead of rebuilding the layout out of $HOME.
  # Assert the value AND that it resolves: an export pointing at nothing would
  # still read as "set", and every template's `. "$PARA_HOOKS/helpers"` rides on it.
  local hooks; hooks="$("$PARA" sh "$PARA_WS" -c 'echo "$PARA_HOOKS"' 2>/dev/null)"
  assert_eq "/home/$PARA_USER/.paraspace/hooks" "$hooks" "PARA_HOOKS names the guest hooks dir" || return 1
  local found; found="$("$PARA" sh "$PARA_WS" -c '[ -f "$PARA_HOOKS/helpers" ] && echo ok' 2>/dev/null)"
  assert_eq "ok" "$found" "the helpers every hook sources is reachable through it" || return 1

  # Exported even though the hello fixture ships no skel/ — the variable names
  # the path either way, which is what lets a hook guard with a plain [ -f ].
  local skel; skel="$("$PARA" sh "$PARA_WS" -c 'echo "$PARA_SKEL"' 2>/dev/null)"
  assert_eq "/home/$PARA_USER/.paraspace/skel" "$skel" "PARA_SKEL names the guest skel dir" || return 1

  # The one that names a file on BOTH sides: push_project overrides the host's
  # value so the copy in here is what a hook reads.
  local hostenv; hostenv="$("$PARA" sh "$PARA_WS" -c 'echo "$PARA_HOST_ENV"' 2>/dev/null)"
  assert_eq "/home/$PARA_USER/.paraspace/host.env" "$hostenv" "PARA_HOST_ENV names the guest copy" || return 1

  # The host-only paths stay unset in here, so a hook can't reach a host file.
  local host; host="$("$PARA" sh "$PARA_WS" -c 'echo "${PARA_PROJECT_DIR-unset}"' 2>/dev/null)"
  assert_eq "unset" "$host" "PARA_PROJECT_DIR is not leaked into the guest" || return 1

  # PARA_MOD_DIR is the one most likely to actually BE in scope: para exports it
  # for a mod's own command, and such a command calling back into `para sh` is
  # the ordinary way to write one. Exported here to reproduce exactly that.
  local mod
  mod="$(env PARA_MOD_DIR=/on/the/host "$PARA" sh "$PARA_WS" -c 'echo "${PARA_MOD_DIR-unset}"' 2>/dev/null)"
  assert_eq "unset" "$mod" "PARA_MOD_DIR is not leaked into the guest"
}

# shellcheck disable=SC2016  # the guest expands this, not us
test_image_carries_no_project_tree() {
  # image build pushes .paraspace/ to /opt to build from, then removes it before
  # publishing. Without that one line every workspace cloned from the image finds
  # the project's whole tree in there — including the generated env, so every
  # PARA_* and whatever the user's config carries.
  local found
  found="$("$PARA" sh "$PARA_WS" -c 'if [ -e /opt/.paraspace ]; then echo leaked; fi' 2>/dev/null)"
  assert_eq "" "$found" "the published image has no /opt/.paraspace"
}

test_a_stray_hook_stack_does_not_stop_the_hooks() {
  # para_env forwards every PARA_* the caller exported — including one that only
  # the runner is supposed to set. Inherited, PARA_HOOK_STACK reads as "we are
  # already inside that hook", so the cycle guard fires on the first hook of
  # every `up` and the workspace converges having run nothing.
  #
  # Exporting it for the `up` is the whole test: without it this asserts nothing,
  # because the suite's own environment never has the variable set.
  local out
  out="$(PARA_HOOK_STACK=provision "$PARA" up "$PARA_WS" 2>&1)" \
    || { echo "  'para up' failed with a stray PARA_HOOK_STACK exported" >&2
         echo "$out" | tail -5 >&2; return 1; }
  assert_not_contains "$out" "hook cycle" "no bogus cycle from an inherited stack" || return 1
  assert_contains     "$out" "hook: hooks/provision" "the provision hook still ran"
}

test_a_mod_fills_the_same_hooks_the_project_does() {
  # The multi-owner rule, end to end: one hook name resolves to the project's
  # hook and then each mods/*/hooks/<name>. The fixture ships one mod, and the
  # runner is the only thing that makes any of this happen.
  local seen; seen="$("$PARA" sh "$PARA_WS" -c 'cat ~/owners-seen' 2>/dev/null)"
  assert_eq "project-provision" "$(head -n1 <<<"$seen")" "the project's hook ran first" || return 1
  assert_contains "$seen" "mod-provision e2e-mod" "the mod's provision ran too" || return 1

  # And a point the PROJECT opened, which para never learns the name of. It runs
  # mid-provision, so it lands between the two lines above.
  assert_contains "$seen" "mod-clone-before" "the mod filled the fixture's own hook point"
}

test_workspace_is_listed_and_running() {
  local names; names="$("$PARA" ls --names 2>/dev/null)"
  assert_contains "$names" "$PARA_WS" "ls --names includes the workspace" || return 1
  # Bind the state to THIS workspace's row (field 2), not "RUNNING appears
  # somewhere" — otherwise another row being RUNNING could mask a bad state here.
  local state; state="$("$PARA" ls 2>/dev/null | awk -v n="$PARA_WS" '$1==n{print $2}')"
  assert_eq "RUNNING" "$state" "the workspace's row reports RUNNING"
}

test_sh_c_runs_as_the_workspace_user() {
  # $PARA_USER/UID/GID are pinned by the sandbox (see test/lib/sandbox.sh) and
  # reach both the fixture's hooks/image-build and para's runtime chowns, so assert
  # against them rather than a literal — that's what makes the ids overridable.
  local uid; uid="$("$PARA" sh "$PARA_WS" -c 'id -u' 2>/dev/null)"
  assert_eq "$PARA_UID" "$uid" "workspace user is uid $PARA_UID" || return 1
  local gid; gid="$("$PARA" sh "$PARA_WS" -c 'id -g' 2>/dev/null)"
  assert_eq "$PARA_GID" "$gid" "workspace user is gid $PARA_GID" || return 1
  local user; user="$("$PARA" sh "$PARA_WS" -c 'id -un' 2>/dev/null)"
  assert_eq "$PARA_USER" "$user" "workspace user is named $PARA_USER"
}

test_shared_volume_is_mounted() {
  # The provision hook seeded /para/shared/marker; the shared volume is attached
  # at /para/shared and linked into $HOME.
  local marker; marker="$("$PARA" sh "$PARA_WS" -c 'cat /para/shared/marker' 2>/dev/null)"
  assert_eq "shared-volume-ok" "$marker" "shared volume mounted + seeded"
}

test_sh_c_propagates_exit_status() {
  # para sh -c must exit with the guest command's status, so it composes. The
  # `|| return 1` is load-bearing: the harness runs tests without `set -e`, so a
  # non-final assert whose result isn't checked would be masked by the trailing
  # `exit 0` and the test could never fail on broken propagation.
  assert_fails "$PARA" sh "$PARA_WS" -c 'exit 7' || return 1
  "$PARA" sh "$PARA_WS" -c 'exit 0'
}

test_project_commands_extend_para() {
  # The extension seam: a project drops an executable in .paraspace/commands/
  # and `para <verb>` runs it — on the HOST, with every PARA_* exported, args
  # passed through. The fixture's `hello` reports its context with no argument,
  # and calls back into `para sh` with one.
  local out
  out="$("$PARA" hello 2>/dev/null)"
  assert_contains "$out" "project-command-ok"      "the project's verb ran"        || return 1
  assert_contains "$out" "project=$PARA_PROJECT"   "para's context reached it"     || return 1
  assert_contains "$out" "contract=1"              "including the contract version" || return 1

  # $PARA_BIN is how a command calls back into the same para that ran it.
  out="$("$PARA" hello "$PARA_WS" 2>/dev/null)"
  assert_eq "project-command-in-workspace-ok" "$out" "it reached into the workspace" || return 1

  # Discoverable, so nothing a project added runs invisibly.
  assert_contains "$("$PARA" commands 2>/dev/null)" "hello" "para commands lists it" || return 1
  assert_contains "$("$PARA" --help 2>&1)" "PROJECT COMMANDS" "para --help lists it" || return 1

  # An unknown verb is still an error, not a silent no-op.
  assert_fails "$PARA" definitely-not-a-verb
}

# shellcheck disable=SC2016  # the guest expands this, not us
test_the_pushed_env_stays_private() {
  # push_paraspace widens the tree so a build hook can read $PARA_SKEL after a
  # `su -`, and pushes env at 0600 afterwards. Swap those two and every PARA_*
  # the Parafile carries — tokens included — goes world-readable in the guest.
  local mode; mode="$("$PARA" sh "$PARA_WS" -c 'stat -c %a ~/.paraspace/env' 2>/dev/null)"
  assert_eq "600" "$mode" "the generated env is readable only by its owner"
}

# shellcheck disable=SC2016  # the builder expands these, not us
test_image_build_reads_skel_after_a_restrictive_umask() {
  # push_paraspace hands the builder the host checkout's own modes, so a tree
  # written under `umask 077` lands 0700 and the $PARA_USER a build hook steps
  # down to cannot read $PARA_SKEL through it — which is the whole stated reason
  # the tree goes to /opt rather than root's 0700 $HOME.
  local img="para-umasktest-$$" proj rc=0
  proj="$(scratch)/hello"
  ( umask 077
    cp -R "$FIXTURE_DIR" "$proj"
    mkdir -p "$proj/.paraspace/skel"
    printf 'skel-readable\n' > "$proj/.paraspace/skel/marker" )
  # The su - spelling docs/hooks.md teaches, appended after the fixture's hook
  # has created the user. Single-quoted: these expand in the builder, not here.
  { printf '%s\n' 'echo "==> PARA_SKEL readable after su -"'
    printf '%s\n' 'su - "$PARA_USER" -c "cat $PARA_SKEL/marker" >/dev/null'
  } >> "$proj/.paraspace/hooks/image-build"

  env PARA_PROJECT_DIR="$proj" PARA_IMAGE="$img" "$PARA" image build >/dev/null 2>&1 \
    || { echo "  a build hook could not read \$PARA_SKEL as \$PARA_USER" >&2; rc=1; }
  incus image delete "$img" >/dev/null 2>&1 || true
  return "$rc"
}

test_image_build_status_and_rm_lifecycle() {
  # The full `para image` seam on its OWN throwaway alias, so it never disturbs
  # the shared 'alpine-minimal' the other tests ride on. One build — cheap here
  # because the fixture is Docker-free (no stack images to pre-pull), so it's the
  # tiny-Alpine build, not the multi-minute Docker case. Only the published alias
  # is overridden; base/bootstrap/payload still come from the fixture's Parafile.
  local img="para-imgtest-$$"
  local rc=0 out

  # Write path: a clean build must succeed and publish the alias.
  # An early return here can't leak: cmd_image_build's own trap tears down its
  # builder, and the publish is atomic, so a failed build leaves no '$img' alias.
  # Every step after this uses `|| rc=1` (no early return), so the unconditional
  # cleanup + `para image rm` at the end always run.
  env PARA_IMAGE="$img" "$PARA" image build >/dev/null 2>&1 \
    || { echo "  'para image build' of throwaway image '$img' failed" >&2; return 1; }

  # Read path: status names the image, when it was built, and its base. `built`
  # and `base` are both read back out of incus, and each prints the literal
  # 'unknown' if its read broke — which is what the last assert is for.
  out="$(env PARA_IMAGE="$img" "$PARA" image status 2>&1)"
  assert_contains "$out" "$img"               "status names the image"          || rc=1
  assert_contains "$out" "images:alpine/edge" "status reports the stamped base" || rc=1
  assert_not_contains "$out" "unknown"        "status resolved built and base"  || rc=1

  # The mod's image-build hook ran in the builder, resolved the same way a
  # workspace's are. Asserted against THIS image, not the shared alpine-minimal:
  # that one is cached across runs and can predate the fixture's mods/.
  local ct="imgtest-$$" marker=""
  if incus launch "$img" "$ct" >/dev/null 2>&1; then
    eventually 30 incus exec "$ct" -- true || rc=1
    marker="$(incus exec "$ct" -- cat /etc/para-mod-marker 2>/dev/null)"
    incus delete -f "$ct" >/dev/null 2>&1 || true
  else
    echo "  could not launch a container from '$img'" >&2
    rc=1
  fi
  assert_eq "e2e-mod-was-here" "$marker" "the mod's image-build hook reached the image" || rc=1

  # rm deletes it — verify the image is actually gone afterwards.
  env PARA_IMAGE="$img" "$PARA" image rm >/dev/null 2>&1 \
    || { echo "  'para image rm' failed" >&2; rc=1; }
  incus image info "$img" >/dev/null 2>&1 && { echo "  image survived 'para image rm'" >&2; rc=1; }

  # Unconditional final cleanup in case 'para image rm' itself failed above.
  incus image delete "$img" >/dev/null 2>&1 || true
  return "$rc"
}
