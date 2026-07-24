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

test_routes_reach_the_provision_hook() {
  # Two things at once. PARA_ROUTES is a comma-separated scalar, so para's blanket
  # PARA_* forwarder carries it into hooks like any other key — new, since as a
  # bash array it was skipped (%q on an array captures element 0 only) and a hook
  # needing its own routes had to re-source the Parafile. And the fixture declares
  # its route in the MULTI-LINE spelling, so what the hook receives also proves the
  # canonicalization: newlines and indentation in, one CSV token out. A raw value
  # would carry whitespace into the registry's positional field 3 and corrupt it.
  local got; got="$("$PARA" sh "$PARA_WS" -c 'cat ~/routes-seen' 2>/dev/null)"
  # EXACT, and two entries: this is the suite's only oracle for the canonical form,
  # so it has to pin the separator (a space here would corrupt the registry's
  # positional field 3) AND the fact that no entry was dropped.
  assert_eq "8080,api:8080" "$got" "the hook received both routes, comma-joined"
}

test_workspace_is_listed_and_running() {
  local names; names="$("$PARA" ls --names 2>/dev/null)"
  assert_contains "$names" "$PARA_WS" "ls --names includes the workspace" || return 1
  # Bind the state to THIS workspace's row (field 3), not "RUNNING appears
  # somewhere" — otherwise another row being RUNNING could mask a bad state here.
  local state; state="$("$PARA" ls 2>/dev/null | awk -v n="$PARA_WS" '$1==n{print $3}')"
  assert_eq "RUNNING" "$state" "the workspace's row reports RUNNING"
}

test_sh_c_runs_as_the_workspace_user() {
  # $PARA_USER/UID/GID are pinned by the sandbox (see test/lib/sandbox.sh) and
  # reach both the fixture's image-build.sh and para's runtime chowns, so assert
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

test_image_build_status_and_rm_lifecycle() {
  # The full `para image` seam on its OWN throwaway alias, so it never disturbs
  # the shared 'alpine-minimal' the other tests ride on. One build — cheap here
  # because the fixture is Docker-free (no stack images to pre-pull), so it's the
  # tiny-Alpine build, not the multi-minute Docker case. Only the published alias
  # is overridden; base/bootstrap/payload still come from the fixture's Parafile.
  local img="para-imgtest-$$"
  local rc=0 out

  # Write path: a clean build must succeed and stamp provenance onto the image.
  # An early return here can't leak: cmd_image_build's own trap tears down its
  # builder, and the publish is atomic, so a failed build leaves no '$img' alias.
  # Every step after this uses `|| rc=1` (no early return), so the unconditional
  # cleanup + `para image rm` at the end always run.
  env PARA_IMAGE="$img" "$PARA" image build -q >/dev/null 2>&1 \
    || { echo "  'para image build' of throwaway image '$img' failed" >&2; return 1; }
  local sha; sha="$(incus image get-property "$img" user.para.src_sha 2>/dev/null || true)"
  [ -n "$sha" ] || { echo "  build did not stamp user.para.src_sha" >&2; rc=1; }

  # Read path: right after a clean build the source is in sync, and status names
  # the image and its base.
  out="$(env PARA_IMAGE="$img" "$PARA" image status 2>&1)"
  assert_contains     "$out" "up to date"         "status is up to date right after a build" || rc=1
  assert_contains     "$out" "images:alpine/edge" "status reports the base image"            || rc=1

  # Drift: change a reproducibility input via the environment (env beats the
  # Parafile, so no file is mutated) — the current hash no longer matches the one
  # stamped at build time, so status must flip to drifted.
  out="$(env PARA_IMAGE="$img" PARA_IMAGE_BOOTSTRAP='apk add --no-cache bash coreutils' "$PARA" image status 2>&1)"
  assert_contains     "$out" "drifted"    "status detects a changed image input" || rc=1
  assert_not_contains "$out" "up to date" "a drifted image is not reported in sync" || rc=1

  # rm deletes it — verify the image is actually gone afterwards.
  env PARA_IMAGE="$img" "$PARA" image rm >/dev/null 2>&1 \
    || { echo "  'para image rm' failed" >&2; rc=1; }
  incus image info "$img" >/dev/null 2>&1 && { echo "  image survived 'para image rm'" >&2; rc=1; }

  # Unconditional final cleanup in case 'para image rm' itself failed above.
  incus image delete "$img" >/dev/null 2>&1 || true
  return "$rc"
}
