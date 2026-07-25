#!/usr/bin/env bash
set -euo pipefail

# Guest provisioning for the e2e fixture's base image. Runs as root inside a
# fresh $PARA_BASE_IMAGE container — `images:alpine/edge` per the Parafile,
# bootstrapped with `apk add --no-cache bash` (Alpine ships no bash, and para
# runs this payload with `bash -s`) — invoked by `para image build`.
#
# Deliberately NOT Void and NOT Docker: this is the second consumer that proves
# `para image build` is generic. It's also what keeps the e2e tier cheap — the
# published image is ~5.5 MB and boots in a second, where a Docker-capable box
# is minutes and gigabytes.
#
# What it installs is only what para's contract needs, plus the one thing the
# fixture's app needs:
#   bash            — para runs hooks and `para sh` via `su -s /bin/bash`
#   sudo            — the contract's passwordless-sudo-for-$PARA_USER
#   busybox-extras  — /usr/sbin/httpd, the "app" hooks/boot starts on :8080
#
# Idempotent (guarded user create, `apk add` is a no-op when present), so
# `para image-build -i` works here too.

PARA_USER="${PARA_USER:-app}"
PARA_UID="${PARA_UID:-1000}"
PARA_GID="${PARA_GID:-1000}"

echo "==> packages"
apk add --no-cache bash busybox-extras sudo >/dev/null

echo "==> $PARA_USER user ($PARA_UID:$PARA_GID) + passwordless sudo"
# Alpine's busybox adduser/addgroup, not shadow's useradd. -D: no password.
getent group "$PARA_USER" >/dev/null 2>&1 || addgroup -g "$PARA_GID" "$PARA_USER"
id -u "$PARA_USER" >/dev/null 2>&1 \
  || adduser -D -u "$PARA_UID" -G "$PARA_USER" -s /bin/bash "$PARA_USER"
echo "$PARA_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$PARA_USER-nopasswd"
chmod 0440 "/etc/sudoers.d/90-$PARA_USER-nopasswd"

# No pre-pull step: PARA_PREPULL_IMAGES is always empty here (the fixture has no
# compose file), and there's no Docker in this image to pull into.

echo "==> provisioning complete"
