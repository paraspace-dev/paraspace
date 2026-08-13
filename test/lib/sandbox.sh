#!/usr/bin/env bash
# sandbox.sh - isolate an e2e run from the developer's real para state.
#
# Sourced by test/run. para keeps its Caddyfile, pidfile and user config under
# XDG dirs, so pointing those at throwaway temp dirs, plus its own Caddy port
# and admin endpoint, gives a run that starts its OWN Caddy and never touches,
# or is touched by, a real one.
#
# Two things are machine-global and cannot be sandboxed, both fine:
#   * container IPs. para allocates them from what incus reports as in use
#     across all projects (stopped instances included), so a run cannot take an
#     address a real workspace holds.
#   * the workspace list. para reads it from incus rather than a registry of its
#     own, so this run's Caddyfile also carries the developer's real workspaces.
#     Harmless, since it is served on this run's own port, but do not write a test
#     that asserts the Caddyfile has nothing else in it.

# Absolute path to the para under test and the hello fixture. Set by test/run.
: "${PARA:?sandbox.sh: PARA must point at bin/para}"
: "${FIXTURE_DIR:?sandbox.sh: FIXTURE_DIR must point at the hello fixture}"

SANDBOX_ROOT=""          # temp dir holding the throwaway XDG tree
declare -a SANDBOX_WORKSPACES=()   # workspaces we created, torn down on exit

# Apply the base sandbox: throwaway XDG dirs + a non-default Caddy port + the
# non-interactive/idempotent flags every scripted para call wants. Safe for the
# CLI tier too (it just means `para init`/config land in the temp tree).
sandbox_base() {
  SANDBOX_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/para-e2e.XXXXXX")"
  export XDG_STATE_HOME="$SANDBOX_ROOT/state"
  export XDG_CONFIG_HOME="$SANDBOX_ROOT/config"
  export XDG_DATA_HOME="$SANDBOX_ROOT/data"
  export XDG_CACHE_HOME="$SANDBOX_ROOT/cache"
  mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  # Neutralize any inherited para identity from the caller's environment. This is
  # SAFETY-CRITICAL, and for two distinct reasons:
  #   - teardown deletes $PARA_VOLUME, so a developer who exports PARA_VOLUME
  #     (e.g. the docs-recommended shared name para-home) must not have it leak in
  #     and get their real volume deleted by a `--cli` run;
  #   - the image keys are just as destructive one step over. The fixture's
  #     env declares them with `: "${X:=…}"`, which yields to the
  #     environment, so an exported PARA_IMAGE_NAME (say, a real project's alias)
  #     means a PARA_TEST_REBUILD=1 run PUBLISHES the Alpine fixture payload over
  #     that real alias. Without the rebuild it's merely confusing: workspaces
  #     launch from the wrong image and fail with no /usr/sbin/httpd.
  # sandbox_e2e sets its own run-unique values after this.
  unset PARA_VOLUME PARA_PROJECT_NAME PARA_PROJECT_DIR
  unset PARA_IMAGE_NAME PARA_IMAGE_BASE PARA_IMAGE_BOOTSTRAP
  # PARA_POOL is deliberately NOT in that list, so the run shares the real pools.
  # That is safe because isolation here is by NAME: everything the run creates is
  # run-unique, teardown is guarded to those names, and para has no pool-level
  # destructive operation. (para no longer switches or creates pools on your
  # behalf. `para doctor` reports a pool that would hurt, and leaves it to you.)
  # A non-default port so the run's Caddy can't collide with a real para Caddy on
  # :8443, and its own pidfile (under the temp XDG_STATE_HOME) governs only it.
  export PARA_HTTPS_PORT="${PARA_TEST_PORT:-9443}"
  # And its own Caddy admin endpoint. Caddy's default (localhost:2019) is shared
  # by every Caddy on the box via SO_REUSEPORT, so a `caddy reload` from this run
  # could otherwise land on the developer's real para Caddy, or theirs on ours.
  # This is why the e2e tier no longer has to refuse to start while one is up.
  export PARA_CADDY_ADMIN="localhost:$((PARA_HTTPS_PORT + 10000))"
  # No prompts, no pty, fully scripted.
  export PARA_NONINTERACTIVE=1
  # Pin the workspace user rather than inherit it. These are project keys with a
  # documented default, but a real user config (~/.config/para/config) could set
  # them, and then the fixture image and the assertions would disagree. Exporting
  # them makes the run deterministic AND gives the tests one place to read the
  # expected ids from, instead of a literal 1000 sprinkled around.
  export PARA_USER=app PARA_UID=1000 PARA_GID=1000
}

# e2e setup: base sandbox + a throwaway project identity + a free IP band + the
# Alpine image. PARA_PROJECT_DIR pins para at the hello fixture from any cwd.
sandbox_e2e() {
  sandbox_base
  export PARA_PROJECT_DIR="$FIXTURE_DIR"
  export PARA_PROJECT_NAME="paratest-$$"
  export PARA_VOLUME="para-home-$PARA_PROJECT_NAME"
  # The fixture's base image, built through para itself, so `para image build`
  # reads the fixture's env (PARA_PROJECT_DIR above) for the Alpine base,
  # the bash bootstrap, and the payload. Doing it this way means an e2e run also
  # exercises image build against a non-Void, Docker-free consumer, but only on
  # the run that actually builds. An existing alias is REUSED, because the
  # rebuild is by far the slow part, so in steady state most runs skip
  # image build entirely. Nothing detects that you edited the fixture's payload:
  # if you touched hooks/image-build, the env's base/bootstrap, or
  # cmd_image_build itself, rebuild explicitly with PARA_TEST_REBUILD=1.
  # --no-build skips even the existence check.
  # Hardcoded, not "${PARA_IMAGE_NAME:-…}": sandbox_base unset PARA_IMAGE_NAME precisely so
  # the caller's environment can't redirect the build, which leaves the fixture
  # env's own `: "${PARA_IMAGE_NAME:=alpine-minimal}"` as the single source of the
  # alias. Keep this string in step with that line.
  local img=alpine-minimal
  if [ "${PARA_TEST_NO_BUILD:-0}" != 1 ]; then
    if [ "${PARA_TEST_REBUILD:-0}" = 1 ] || ! incus image info "$img" >/dev/null 2>&1; then
      "$PARA" image build || return 1
    else
      echo "sandbox: reusing cached image '$img' (PARA_TEST_REBUILD=1 rebuilds)" >&2
    fi
  fi
}

# Register a workspace name so teardown removes it even if a test aborts midway.
sandbox_track() { SANDBOX_WORKSPACES+=("$1"); }

# Remove everything this run created: its workspaces, its shared volume, its
# Caddy, and the temp XDG tree. The Alpine image is left cached (rebuild is the
# slow part); `incus image delete alpine-minimal` drops it, or run with
# PARA_TEST_REBUILD=1 to rebuild it in place.
sandbox_teardown() {
  [ "${PARA_TEST_KEEP:-0}" = 1 ] && { echo "sandbox: --keep set, leaving workspaces + $SANDBOX_ROOT" >&2; return 0; }
  local ws
  for ws in "${SANDBOX_WORKSPACES[@]:-}"; do
    [ -n "$ws" ] || continue
    "$PARA" rm "$ws" >/dev/null 2>&1 || true
    # Backstop straight to incus: `para rm` refuses a workspace owned by another
    # project, and a run that died mid-launch may have left one unstamped, so
    # the line above is not guaranteed to have removed it. The name is
    # ct_name's `para-<ws>` on a run-unique <ws>, so this can only ever hit
    # something this run launched.
    incus delete -f "para-$ws" >/dev/null 2>&1 || true
  done
  # The shared volume para lazily created for this project. Sweep EVERY pool
  # rather than guessing: PARA_POOL is inherited from the developer's
  # environment, so a hardcoded default/para-dir pair leaked the volume on every
  # run for anyone using a custom pool.
  # The sweep is safe only because it stays GUARDED to our run-unique name pattern
  # (sandbox_e2e sets para-home-paratest-$$): teardown must NEVER delete a volume
  # it didn't create, even if PARA_VOLUME somehow carried in from the environment.
  case "${PARA_VOLUME:-}" in
    para-home-paratest-*)
      local p
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        incus storage volume delete "$p" "$PARA_VOLUME" >/dev/null 2>&1 || true
      done < <(incus storage list -f csv -c n 2>/dev/null)
      ;;
  esac
  # Kill the run's own Caddy by its sandboxed pidfile, which targets exactly
  # ours. (`para caddy stop` does the same thing, stopping by pidfile too, but
  # going direct keeps teardown independent of the CLI under test.)
  local pidf="${XDG_STATE_HOME:-}/para/caddy.pid" pid
  if [ -f "$pidf" ]; then
    pid="$(cat "$pidf" 2>/dev/null || true)"
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
  fi
  [ -n "$SANDBOX_ROOT" ] && rm -rf "$SANDBOX_ROOT"
  # project.sh's own bookkeeping file lives in $TMPDIR, not under
  # $SANDBOX_ROOT, so it needs removing explicitly.
  rm -f "${_SCRATCH_LIST:-}"
}
