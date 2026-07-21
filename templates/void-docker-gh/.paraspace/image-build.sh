#!/usr/bin/env bash
set -euo pipefail

# Guest provisioning for the void-docker-gh base image. Runs as root inside a fresh
# `images:voidlinux` (glibc) container — launched with security.nesting=true —
# invoked by `para image-build`. Installs the minimum a para workspace needs so
# `para up` only has to clone + `docker compose up`.
#
# This is yours — para owns no image. Add your toolchain (language runtime,
# package manager, CLIs) and make it as robust as you like; just keep the image
# contract (docker→overlayfs, a uid-1000 user in the docker group, bash + git).

# Workspace user to bake in. Passed by `para image-build`; defaults keep a
# standalone run working. useradd -m lands the home at /home/$PARA_USER.
PARA_USER="${PARA_USER:-app}"
PARA_UID="${PARA_UID:-1000}"
PARA_GID="${PARA_GID:-1000}"

echo "==> xbps sync + packages"

# Update xbps
xbps-install -Syu xbps >/dev/null 2>&1 || true
xbps-install -Syu -y

# Install what's missing (xbps is noisy about already-present named packages)
missing=()
pkgs="bash ca-certificates curl git zsh tmux sudo unzip docker
  docker-compose github-cli kitty-terminfo alacritty-terminfo ncurses-term"
for p in $pkgs; do
  xbps-query "$p" >/dev/null 2>&1 || missing+=("$p")
done
[ "${#missing[@]}" -eq 0 ] || xbps-install -Sy "${missing[@]}" >/dev/null

# Void incus ships with non-world-writeable /tmp
echo "==> writable /tmp"
chmod 1777 /tmp

# Create a user
echo "==> $PARA_USER user ($PARA_UID:$PARA_GID)"
getent group "$PARA_USER" >/dev/null 2>&1 || groupadd -g "$PARA_GID" "$PARA_USER"
id -u "$PARA_USER" >/dev/null 2>&1 \
  || useradd -m -u "$PARA_UID" -g "$PARA_GID" -s "$(command -v zsh)" "$PARA_USER"
usermod -aG docker "$PARA_USER"
echo "$PARA_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$PARA_USER-nopasswd"
chmod 0440 "/etc/sudoers.d/90-$PARA_USER-nopasswd"

# Docker service -- drop the modprobe exit as we are running inside a container
echo "==> enable docker (runit)"
sed -i 's/modprobe -q loop || exit 1/modprobe -q loop || true/' /etc/sv/docker/run
ln -sf /etc/sv/docker /var/service/

echo "==> waiting for docker daemon"
for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done

echo "==> docker storage driver:"
# para also verifies this host-side and refuses a non-overlay driver — nested
# Docker on a btrfs/zfs(<2.2) pool silently falls back to vfs (slow). A dir/ext4
# pool gives overlayfs.
docker info --format '{{.Driver}}'

# Pre-pull images into the base image so workspaces don't have to on first boot.
if [ -n "${PARA_PREPULL_IMAGES:-}" ]; then
  echo "==> Pre-pulling stack image(s) into the base image"
  for img in $PARA_PREPULL_IMAGES; do
    echo "  -> $img"
    docker pull -q "$img" || echo "warn: failed to pre-pull $img (workspaces will pull it on first boot)"
  done
fi

echo "==> provisioning complete"
