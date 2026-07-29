# Choosing a base image and writing `image-build`

`image.md` and `parafile.md` define `PARA_IMAGE_BASE`, `PARA_IMAGE_BOOTSTRAP`
and what `para image build` does with them. This page is the part they leave to
you: *which* base, and what goes in the hook.

The one mechanical fact worth carrying here, because it decides how you write
every line: `image-build` runs as root with **no tty and no stdin**, so a
package manager that stops to ask will hang the build. Pass the non-interactive
flag every time.

## Picking the base

**Default to the distro the project already targets.** A `Dockerfile`'s `FROM`,
a CI runner image, or the team's servers are all better reasons than novelty.
Void is what the bundled templates use; it is not a requirement, and a Void
image is a poor fit for a team that has never used it.

| Base | `PARA_IMAGE_BOOTSTRAP` | Install line | Notes |
|---|---|---|---|
| `images:debian/13` | `apt-get update` | `DEBIAN_FRONTEND=noninteractive apt-get install -y …` | best default for most stacks: widest package coverage, systemd, util-linux `su` |
| `images:ubuntu/24.04` | `apt-get update` | same | same as Debian; pick it if the team's servers are Ubuntu |
| `images:alpine/3.21` | `apk add --no-cache bash` | `apk add --no-cache …` | tiny and fast, but read the Alpine caveats below before choosing it |
| `images:voidlinux` | `xbps-install -Syu xbps bash` | `xbps-install -Sy …` | what the templates ship; rolling, runit, see the partial-upgrade note |
| `images:fedora/43` | `dnf -y makecache` | `dnf install -y …` | fine; larger images |
| `images:archlinux` | `pacman -Syu --noconfirm` | `pacman -S --noconfirm …` | rolling; `-Sy` without the `u` is the partial-upgrade footgun, same as Void's |

Aliases move over time — `incus image list images: <distro>` on the machine is
the check, and it takes a second.

## Proving you met the contract

What an image must provide is `image.md`'s "What the image must have" — read it
there. What that page doesn't give you is a way to find out *before* the image
is in use, so end `image-build` by checking rather than assuming. It costs six
lines and turns a mystery in three days' time into a failed build now:

```sh
echo "==> image contract"
for c in bash git; do
  command -v "$c" >/dev/null || { echo "error: $c is required in the image" >&2; exit 1; }
done
id -u "$PARA_USER" >/dev/null || { echo "error: $PARA_USER was not created" >&2; exit 1; }
su --pty --help >/dev/null 2>&1 || echo "warn: this su has no --pty; 'para sh -c' from a terminal will fail" >&2
```

The loop is not style. `command -v bash git` returns success when **either**
name resolves, and bash is guaranteed present — so the one-line version can
only ever pass, including on an image with no git.

Add `iproute2` too — `ss` is what the readiness helpers in
`references/stacks.md` poll with, and without it every `boot` blames the app for
a missing package. `image.md` lists the ergonomic extras worth having.

## Per-distro caveats that actually bite

**Alpine.** `useradd`/`groupadd`/`usermod` come from `shadow`, and `su --pty`
comes from **`util-linux-login`** — plain `util-linux` leaves `/bin/su` as
busybox's, which has no `--pty`. Alpine is also musl: a project with prebuilt
glibc binaries
(some Node native modules, many vendored wheels, Playwright browsers) will fail
in ways that look like the app's fault. Great for a small worker box, risky as a
default for an app stack.

**Void.** Installing new packages against freshly-synced repodata without a full
`-Syu` first is the classic partial-upgrade footgun — do the full upgrade, then
install. The Incus base also ships `/tmp` as non-world-writable, which breaks
any tool that makes `/tmp/<tool>` as a non-root user; `chmod 1777 /tmp`. Services
are runit: `ln -sf /etc/sv/<svc> /var/service/`.

**Debian/Ubuntu.** `DEBIAN_FRONTEND=noninteractive` on every `apt-get install`,
and prefer `apt-get` over `apt` in scripts. For Docker, trixie's `docker.io` +
`docker-compose` (2.26.1) does give you a working `docker compose`; add Docker's
own apt repo only when you need a version the distro doesn't carry. Either way
the workspace user goes in the `docker` group, and the driver check that the
Void template does with runit is `systemctl enable --now docker` here:

```sh
usermod -aG docker "$PARA_USER"
systemctl enable --now docker
for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
case "$(docker info --format '{{.Driver}}')" in
  overlay|overlay2|overlayfs) ;;
  *) echo "error: docker driver is not overlay — use a dir/ext4 incus pool" >&2; exit 1 ;;
esac
```

**Anything with systemd** (Debian, Ubuntu, Fedora, Arch): services you `enable`
in `image-build` come up automatically in every workspace, which is usually what
you want. Don't try to `start` something in the builder that needs hardware or a
network the builder doesn't have.

## Language runtimes

Honor the version the repo pins (`.nvmrc`, `.tool-versions`, `mise.toml`,
`.python-version`) rather than taking whatever the distro packages. Install it
in `image-build`, system-wide, so every workspace shares it:

```sh
echo "==> mise + pinned runtimes"
export MISE_DATA_DIR=/usr/local/share/mise MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh
cat > /etc/profile.d/mise.sh <<'EOF'
export MISE_DATA_DIR=/usr/local/share/mise MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
eval "$(/usr/local/bin/mise activate bash)"
EOF
chmod -R a+rX /usr/local/share/mise
```

Three details decide whether this works, and the first is the one that bites:

- **`MISE_INSTALL_PATH` only moves the binary.** The runtimes it downloads still
  land in `$HOME/.local/share/mise`, and `image-build` runs as root — so without
  `MISE_DATA_DIR` the pinned Node ends up in `/root/.local/share/mise` at mode
  0700, where `$PARA_USER` can neither see it nor read it. The same shape
  applies to any version manager that defaults to `$HOME`: point its data
  directory somewhere system-wide, then make it world-readable.
- **Put the shell wiring in `/etc/profile.d/`.** Hooks, `para sh -c` and project
  commands all run through login shells, so a `profile.d` file is how a tool
  installed at build time is on `PATH` everywhere afterwards. An `export` inside
  a hook reaches nothing.
- **Check which shell your workspace user actually logs into.** `/etc/profile.d`
  is read by bash; the bundled `void-docker-gh` image gives `$PARA_USER` zsh,
  which mostly doesn't read it. Then hooks see the tool and the human's
  `para sh` doesn't — wire the same lines into that shell's rc too.

## Things that belong in the image, not in provision

Anything identical in every workspace and expensive to repeat: compilers and
system libraries, browser binaries for e2e tests, `PARA_PREPULL_IMAGES`-style
container images, big model or dataset downloads that are read-only.

Anything that differs per workspace — the clone, credentials, `.env`, the
database — belongs in `provision`. The dividing question is never "is it big",
it's "does it vary".

## Iterating without waiting

`para image build -i` is the loop to use while tuning the hook — `image.md`
covers what it does and what it assumes. The part that falls on you: write the
hook so a re-run is a no-op (guard `useradd`, `groupadd`, and anything that
appends to a file), or `-i` will happily stack duplicates into the image.

When you hand off, say in the project's README that editing `image-build` means
rebuilding. Nothing checks, and the symptom of forgetting is a tool that just
isn't there.
