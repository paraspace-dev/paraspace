#!/usr/bin/env bash
# sandbox.sh — isolate an e2e run from the developer's real para state.
#
# Sourced by test/run. para keeps its registry, Caddyfile, pidfile and machine
# config under XDG dirs, so pointing those at throwaway temp dirs (plus a distinct
# Caddy port) gives a run that can start its OWN Caddy, register its OWN workspaces
# and never touch — or be seen by — the real ones. What is NOT XDG-scoped is the
# incus bridge: container IPs are a machine-global resource, and para's IP
# bookkeeping lives in the (now-sandboxed, empty) registry — so a naive run would
# hand out .200 straight into a live workspace. sandbox_ip_band() fixes that by
# carving PARA_IP_LO/HI out of the addresses actually free on the bridge.

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
  # SAFETY-CRITICAL: teardown deletes $PARA_VOLUME, so a developer who exports
  # PARA_VOLUME (e.g. the docs-recommended shared name para-home) must not have it
  # leak in and get their real volume deleted by a `--cli` run. sandbox_e2e sets
  # its own run-unique values after this.
  unset PARA_VOLUME PARA_PROJECT PARA_PROJECT_DIR
  # A non-default port so the run's Caddy can't collide with a real para Caddy on
  # :8443, and its own pidfile (under the temp XDG_STATE_HOME) governs only it.
  export PARA_HTTPS_PORT="${PARA_TEST_PORT:-9443}"
  # No prompts, no pty — scripted.
  export PARA_NONINTERACTIVE=1
}

# The bridge's /24 prefix, e.g. "10.120.251". Mirrors bin/para's subnet_prefix.
sandbox_prefix() {
  local addr
  addr="$(incus network get "${PARA_BRIDGE:-incusbr0}" ipv4.address 2>/dev/null)" || return 1
  addr="${addr%/*}"; echo "${addr%.*}"
}

# Every last octet on the bridge subnet an allocation must avoid — across ALL
# instances, not just para's. Reads incus directly (our registry is empty), and
# unions TWO sources:
#   1. runtime IPs (`incus list -c 4`) — but that column is empty for STOPPED
#      instances, so on its own it misses a stopped workspace's reservation;
#   2. each instance's CONFIGURED static eth0 address — para pins IPs with
#      `-d eth0,ipv4.address=`, a device override that persists while stopped.
# Without (2) the picker would happily allocate over a stopped real workspace and
# collide the moment it starts.
sandbox_used_octets() {
  local prefix="$1" n
  {
    incus list -f csv -c 4 2>/dev/null
    while IFS= read -r n; do
      [ -n "$n" ] && incus config device get "$n" eth0 ipv4.address 2>/dev/null
    done < <(incus list -f csv -c n 2>/dev/null)
  } | grep -oE "${prefix//./\\.}\.[0-9]+" \
    | sed "s/^${prefix//./\\.}\.//" \
    | sort -un
}

# True when nothing is listening on Caddy's admin endpoint (127.0.0.1:2019). para
# does not sandbox that port (its Caddyfile sets no `admin` directive), and Caddy
# binds it with SO_REUSEPORT — so our sandbox Caddy and a real para Caddy would
# BOTH bind :2019, and para's admin calls (`caddy reload`/`caddy stop`) would be
# load-balanced across the two: an `up` in our run could reload — or a stop could
# kill — the developer's real Caddy. So we refuse to run e2e while another Caddy
# owns :2019, rather than risk cross-contaminating it. Uses bash /dev/tcp, no
# extra tools. (The typical culprit is a running `para` Caddy — `para stop` it.)
# Prefer `ss` (a definitive listener check on Linux, where the e2e tier runs); fall
# back to bash /dev/tcp. /dev/tcp fails OPEN (reports "free" if the connect can't be
# made), so `ss` is the safer primary when present.
sandbox_caddy_admin_free() {
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:2019 '
  else
    ! (exec 3<>/dev/tcp/127.0.0.1/2019) 2>/dev/null
  fi
}

# Carve a free, contiguous window of <count> static IPs out of [200,249] and
# export PARA_IP_LO/HI so para's alloc_ip hands out only addresses that are
# genuinely free on the bridge right now. Fails loudly if the band is saturated
# (better than colliding at launch with an opaque incus error).
sandbox_ip_band() {
  local count="${1:-4}" prefix used n k free
  prefix="$(sandbox_prefix)" || { echo "sandbox: cannot read bridge ipv4.address" >&2; return 1; }
  used="$(sandbox_used_octets "$prefix")"
  for n in $(seq 200 $((250 - count))); do
    free=1
    for k in $(seq "$n" $((n + count - 1))); do
      grep -qxF "$k" <<<"$used" && { free=0; break; }
    done
    if [ "$free" -eq 1 ]; then
      export PARA_IP_LO="$n" PARA_IP_HI="$((n + count - 1))"
      return 0
    fi
  done
  echo "sandbox: no free window of $count IPs in $prefix.200-249 (bridge saturated)" >&2
  return 1
}

# e2e setup: base sandbox + a throwaway project identity + a free IP band + the
# Alpine image. PARA_PROJECT_DIR pins para at the hello fixture from any cwd.
sandbox_e2e() {
  sandbox_base
  export PARA_PROJECT_DIR="$FIXTURE_DIR"
  export PARA_PROJECT="paratest-$$"
  export PARA_VOLUME="para-home-$PARA_PROJECT"
  # para's Caddy admin port (:2019) is NOT sandboxable from here — bail early and
  # clearly rather than risk our admin calls crossing into another live Caddy.
  sandbox_caddy_admin_free || {
    echo "sandbox: something is listening on Caddy's admin port :2019 (likely a running" >&2
    echo "         para Caddy). The e2e tier can't safely share it — run 'para stop'" >&2
    echo "         first, or free :2019, then re-run. (See test/README.md.)" >&2
    return 1
  }
  sandbox_ip_band 4 || return 1
  if [ "${PARA_TEST_NO_BUILD:-0}" != 1 ]; then
    PARA_IMAGE="${PARA_IMAGE:-alpine-minimal}" bash "$FIXTURE_DIR/build-image.sh"
  fi
}

# Register a workspace name so teardown removes it even if a test aborts midway.
sandbox_track() { SANDBOX_WORKSPACES+=("$1"); }

# Remove everything this run created: its workspaces, its shared volume, its
# Caddy, and the temp XDG tree. The Alpine image is left cached (rebuild is the
# slow part); pass --clean-image to build-image.sh yourself to drop it.
sandbox_teardown() {
  [ "${PARA_TEST_KEEP:-0}" = 1 ] && { echo "sandbox: --keep set, leaving workspaces + $SANDBOX_ROOT" >&2; return 0; }
  local ws
  for ws in "${SANDBOX_WORKSPACES[@]:-}"; do
    [ -n "$ws" ] || continue
    "$PARA" rm "$ws" >/dev/null 2>&1 || true
  done
  # The shared volume para lazily created for this project. It lands on whichever
  # pool para settled on — para-dir (the nested-Docker default) or, if that switch
  # didn't fire, default — so try both. GUARDED to our run-unique name pattern
  # (sandbox_e2e sets para-home-paratest-$$): teardown must NEVER delete a volume
  # it didn't create, even if PARA_VOLUME somehow carried in from the environment.
  case "${PARA_VOLUME:-}" in
    para-home-paratest-*)
      local p
      for p in para-dir default; do
        incus storage volume delete "$p" "$PARA_VOLUME" >/dev/null 2>&1 || true
      done
      ;;
  esac
  # Kill the run's own Caddy directly by its sandboxed pidfile — NOT via `para
  # stop`. `para stop` stops Caddy through the admin API on :2019, which Caddy
  # binds with SO_REUSEPORT: with any other caddy alive that admin stop is
  # ambiguous and can miss our instance (leaking it) or even hit the developer's
  # real para Caddy. The pidfile pid targets exactly ours. The preflight
  # guarantees ours is the only para Caddy on :2019 during the run.
  local pidf="${XDG_STATE_HOME:-}/para/caddy.pid" pid
  if [ -f "$pidf" ]; then
    pid="$(cat "$pidf" 2>/dev/null || true)"
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
  fi
  [ -n "$SANDBOX_ROOT" ] && rm -rf "$SANDBOX_ROOT"
}
