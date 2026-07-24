#!/usr/bin/env bash
set -euo pipefail

# Guest provisioning for the void-jchook base image. Runs as root INSIDE a fresh
# $PARA_BASE_IMAGE container — `images:voidlinux` (glibc) per the Parafile,
# launched with security.nesting=true and bootstrapped with $PARA_IMAGE_BOOTSTRAP —
# invoked by `para image build`. Installs everything the carried dotfiles need so
# `para up` only has to clone + `docker compose up`: Docker + compose (runit
# service enabled), git, and the full interactive environment the skel/ dotfiles
# assume — zsh, tmux, Neovim + its toolchain, and Claude Code.
#
# Void, not Ubuntu, on purpose: xbps ships current docker/compose, gh, neovim
# (0.12.x, matching the config's API needs), node, tree-sitter, and fd/bat/rg/fzf
# as ordinary packages — one `xbps-install` replaces the old per-tool
# apt-repo/GitHub-release/npm dance. Only Claude Code comes from its upstream
# installer. The GLIBC variant (`images:voidlinux`, not `.../musl`) is deliberate:
# the Claude Code binary is prebuilt against glibc.
#
# This is yours — para owns no image. Add language runtimes / your own tools; keep
# the image contract (docker→overlayfs, a $PARA_USER/$PARA_UID user in the docker
# group, bash + git). Not meant to be run on a host — it mutates system packages
# and services.

# Workspace user to bake in. Passed by `para image build`; defaults keep a
# standalone run working. $HOME_DIR is where useradd -m lands the home.
PARA_USER="${PARA_USER:-app}"
PARA_UID="${PARA_UID:-1000}"
PARA_GID="${PARA_GID:-1000}"
HOME_DIR="/home/$PARA_USER"

echo "==> xbps sync + packages"
# Update xbps itself first (rolling release — a stale xbps can refuse to proceed),
# then full-upgrade: installing new packages against freshly-synced repodata
# WITHOUT a full -Syu is Void's classic partial-upgrade footgun (a new package
# pulls a lib newer than a held-back one and shlib resolution breaks).
# Package notes:
#   docker + docker-compose : compose lands as the `docker compose` cli-plugin.
#   just, github-cli, neovim, nodejs, tree-sitter-cli : plain packages here (no
#     GitHub-release/apt-repo/npm dance). tree-sitter-cli is what nvim-treesitter's
#     `main` branch shells out to (the bare `tree-sitter` package is only the lib).
#   base-devel : C toolchain for treesitter parser compiles + LuaSnip's jsregexp.
#   ripgrep/fd/bat/fzf : fzf-lua's shell-outs (Void ships fd/bat under their
#     upstream names, so no shim symlinks needed).
#   lsd/tree : back the ls/tree aliases in skel/zshrc.
#   kitty-terminfo/alacritty-terminfo/ncurses-term : correct TERM handling for
#     `para sh` from non-baseline terminals.
xbps-install -Syu xbps >/dev/null 2>&1 || true
xbps-install -Syu -y >/dev/null
# Install only what's missing — xbps errors (non-fatally, but noisily) on an
# explicitly-named already-present package, and a few here always are (bash from
# the Parafile's PARA_IMAGE_BOOTSTRAP; ca-certificates/sudo from the Void base image).
pkgs="bash ca-certificates curl git zsh tmux sudo unzip xz
      docker docker-compose just github-cli neovim nodejs tree-sitter-cli
      base-devel ripgrep fd bat fzf lsd tree kitty-terminfo alacritty-terminfo ncurses-term"
missing=()
for p in $pkgs; do xbps-query "$p" >/dev/null 2>&1 || missing+=("$p"); done
[ "${#missing[@]}" -eq 0 ] || xbps-install -Sy "${missing[@]}" >/dev/null

# The linuxcontainers Void base image ships /tmp as 0755 root:root (a normal Void
# install is 1777). Without the sticky world-writable bit, $PARA_USER
# can't create /tmp/<tool> dirs — `para claude` dies with EACCES, and other tools
# fail the same way. /tmp is on the rootfs, so this persists across restarts.
echo "==> writable /tmp (sticky 1777)"
chmod 1777 /tmp

echo "==> $PARA_USER user ($PARA_UID:$PARA_GID) + docker group + passwordless sudo"
# The Void base ships only root; para expects $PARA_USER at $PARA_UID/$PARA_GID.
# Create the group + user with a zsh login shell so skel/zshrc applies, add it to
# the docker group so `docker` needs no sudo, and grant passwordless sudo (dev
# container — in-place `sudo xbps-install` tweaks stay one step). Guarded so a
# `--from-current` re-run is a no-op; usermod/sudoers are idempotent.
getent group "$PARA_USER" >/dev/null 2>&1 || groupadd -g "$PARA_GID" "$PARA_USER"
id -u "$PARA_USER" >/dev/null 2>&1 \
  || useradd -m -u "$PARA_UID" -g "$PARA_GID" -s "$(command -v zsh)" "$PARA_USER"
usermod -aG docker "$PARA_USER"
echo "$PARA_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$PARA_USER-nopasswd"
chmod 0440 "/etc/sudoers.d/90-$PARA_USER-nopasswd"

echo "==> enable docker (runit)"
# runit, not systemd. The packaged run script hard-fails on `modprobe -q loop ||
# exit 1`, but an unprivileged nested container can't load kernel modules — so the
# service would exit the instant runsvdir starts it, even though dockerd runs fine
# on overlayfs (the loop module is only for the long-dead devicemapper-loop driver
# we don't use). Soften that one line, then enable the service.
sed -i 's/modprobe -q loop || exit 1/modprobe -q loop || true/' /etc/sv/docker/run
ln -sf /etc/sv/docker /var/service/

echo "==> Claude Code (as $PARA_USER)"
# Native install: binary lands in ~/.local/share/claude + launcher ~/.local/bin/claude
# (~/.local/bin is on PATH via skel/zshrc). The installer also seeds ~/.claude, but
# the provision hook symlinks ~/.claude to the shared volume — and `ln -sfn` onto an
# existing real dir nests inside it instead of replacing it. So drop ~/.claude here;
# the binary is in ~/.local and auth/config come from the shared volume at runtime.
if [ ! -x "$HOME_DIR/.local/bin/claude" ]; then
  su - "$PARA_USER" -c 'curl --connect-timeout 20 --max-time 300 --retry 5 --retry-delay 2 --retry-connrefused -fsSL https://claude.ai/install.sh | bash' >/dev/null
  rm -rf "$HOME_DIR/.claude" "$HOME_DIR/.claude.json"
else
  echo "  (claude already installed — skipping)"
fi
# Expose the launcher on the system PATH (like the xbps tools): a non-interactive
# `su - -c` login shell never sources ~/.zshrc where ~/.local/bin is added, so
# without this `para claude` can't find it. The launcher self-updates in place, so
# link the launcher itself, not a pinned version dir.
ln -sf "$HOME_DIR/.local/bin/claude" /usr/local/bin/claude

# NOTE: the nvim *config* and its plugins/parsers/LSP servers are NOT baked into
# the image. They live on the shared volume — the provision hook seeds the config
# from skel/nvim and symlinks ~/.config/nvim + ~/.local/share/nvim into it — so a
# config edit is instantly live in every workspace and plugins/LSPs install once
# (on first `nvim` launch), not on every image build. The image carries only the
# toolchain above (nvim, node, tree-sitter, fd/rg/bat/fzf).
#
# Add a language runtime here if your project needs one, e.g. Bun:
#   su - "$PARA_USER" -c 'curl -fsSL https://bun.sh/install | bash'

echo "==> waiting for docker daemon"
for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done

# Nested Docker on a btrfs/zfs(<2.2) pool silently falls back to the vfs storage
# driver, which is punishingly slow — a dir/ext4 pool gives overlayfs. para does
# NOT check this (it knows nothing about Docker): an image that needs Docker is
# the one that has to refuse to publish itself half-broken.
echo "==> docker storage driver"
driver="$(docker info --format '{{.Driver}}' 2>/dev/null || true)"
case "$driver" in
  overlay|overlayfs|overlay2) echo "  $driver ✓" ;;
  *) echo "error: docker driver is '$driver', not overlay(fs) — nested Docker would be slow. Use a dir/ext4 incus pool." >&2; exit 1 ;;
esac

# Pre-pull the stack's images so `para up` boots without hitting the network in
# every workspace. The tag list arrives via PARA_PREPULL_IMAGES (set by `para
# image-build`, extracted host-side from the compose file). A failed pull is
# non-fatal — that workspace just pulls it on first boot.
if [ -n "${PARA_PREPULL_IMAGES:-}" ]; then
  echo "==> Pre-pulling stack image(s) into the base image"
  for img in $PARA_PREPULL_IMAGES; do
    echo "  -> $img"
    docker pull -q "$img" || echo "warn: failed to pre-pull $img (workspaces will pull it on first boot)"
  done
fi

echo "==> provisioning complete"
