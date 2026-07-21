#!/usr/bin/env bash
set -euo pipefail
# ============================================================================
# build-image.sh — build the tiny Alpine base image the para e2e suite runs on.
#
# `para image-build` is deliberately NOT used: it hardwires a Void base, a
# bash/xbps bootstrap, and a mandatory docker-overlay check (bin/para), so it
# can't produce a docker-free ~15 MB Alpine box. This does the equivalent job
# with plain incus — launch Alpine, add just what para's contract needs (bash for
# the hooks + `su -s /bin/bash`, busybox httpd for the fixture, an app:1000 user
# with passwordless sudo), and publish it under $PARA_IMAGE.
#
# Idempotent: a second run is a no-op unless --force (rebuild from scratch).
#   Usage: build-image.sh [--force]
# ============================================================================

ALIAS="${PARA_IMAGE:-alpine-minimal}"
BASE="${PARA_BASE_IMAGE:-images:alpine/edge}"
BUILDER="${ALIAS}-builder"
PARA_USER="${PARA_USER:-app}"
PARA_UID="${PARA_UID:-1000}"
PARA_GID="${PARA_GID:-1000}"

force=0
[ "${1:-}" = "--force" ] && force=1

log() { printf '\033[36m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v incus >/dev/null 2>&1 || die "incus not found on PATH"

if incus image info "$ALIAS" >/dev/null 2>&1 && [ "$force" -eq 0 ]; then
  log "Image '$ALIAS' already exists — skipping (pass --force to rebuild)."
  exit 0
fi

# A stranded builder from a previous aborted run must not block us.
incus delete -f "$BUILDER" >/dev/null 2>&1 || true
# Tear the builder (and any half-published temp alias) down on any exit.
cleanup() {
  incus image delete "${ALIAS}-new" >/dev/null 2>&1 || true
  incus delete -f "$BUILDER" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'die "interrupted"' INT TERM

log "Launching Alpine builder ($BASE)…"
incus launch "$BASE" "$BUILDER" >/dev/null

# `incus exec` enters a container's namespace directly (no VM agent), so it's
# usable as soon as init is up — but apk needs the default route. Wait for it.
log "Waiting for guest network…"
ok=0
for _ in $(seq 1 60); do
  if incus exec "$BUILDER" -- sh -c 'ip route 2>/dev/null | grep -q default'; then ok=1; break; fi
  sleep 0.5
done
[ "$ok" -eq 1 ] || die "builder never got a default route (guest networking?)"

log "Installing bash + busybox httpd + sudo…"
# bash: para runs hooks and `para sh` via `su -s /bin/bash` (bin/para).
# busybox-extras: provides /usr/sbin/httpd for the fixture's boot hook.
# sudo: the image contract's passwordless-sudo-for-the-user expectation.
incus exec "$BUILDER" -- sh -c '
  set -e
  apk update >/dev/null
  apk add --no-cache bash busybox-extras sudo >/dev/null
'

log "Creating $PARA_USER user ($PARA_UID:$PARA_GID) + passwordless sudo…"
# The $VARs below are GUEST env (passed via --env) and must expand in the guest,
# not here — single quotes are deliberate.
# shellcheck disable=SC2016
incus exec "$BUILDER" \
  --env "PARA_USER=$PARA_USER" --env "PARA_UID=$PARA_UID" --env "PARA_GID=$PARA_GID" \
  -- sh -c '
  set -e
  getent group "$PARA_USER"  >/dev/null 2>&1 || addgroup -g "$PARA_GID" "$PARA_USER"
  id -u "$PARA_USER"         >/dev/null 2>&1 || adduser -D -u "$PARA_UID" -G "$PARA_USER" -s /bin/bash "$PARA_USER"
  echo "$PARA_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$PARA_USER-nopasswd"
  chmod 0440 "/etc/sudoers.d/90-$PARA_USER-nopasswd"
'

log "Publishing image as '$ALIAS'…"
# Force-stop + publish from a fresh snapshot: same reasons as para image-build —
# a hard stop is init-agnostic and a snapshot can't race the settling rootfs.
incus stop -f "$BUILDER"
incus snapshot create "$BUILDER" publish
# Publish to a temp alias then swap, so a publish failure never leaves us imageless.
incus publish "$BUILDER/publish" --reuse --alias "${ALIAS}-new" >/dev/null
incus image delete "$ALIAS" >/dev/null 2>&1 || true
incus image alias rename "${ALIAS}-new" "$ALIAS"
incus delete -f "$BUILDER"
trap - EXIT INT TERM

log "Base image '$ALIAS' ready."
