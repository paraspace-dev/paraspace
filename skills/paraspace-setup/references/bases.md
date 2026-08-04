# Choosing a base image and writing `image-build`

`image.md` and `parafile.md` define `PARA_IMAGE_BASE`, `PARA_IMAGE_BOOTSTRAP`
and what `para image build` does with them. This page is the part they leave to
you: *which* base, and what goes in the hook. (Bare filenames like those two are
pages of the **installed** para's `docs/`, at the path `scripts/para-probe`
printed, or <https://paraspace.dev/docs/>.)

One mechanical fact decides how you write every line. `image-build` runs as root
with **no tty and no stdin**, so a package manager that stops to ask will hang
the build. Pass the non-interactive flag every time.

## Picking the base

**Default to the distro the project already targets.** A `Dockerfile`'s `FROM`,
a CI runner image, or the team's servers are all better reasons than novelty.
Void is what the bundled templates use, it is not a requirement, and a Void
image is a poor fit for a team that has never used it.

Aliases move over time, so confirm the one you pick before you build on it.
`incus image list images: <distro>` takes a second, and the failure it saves you
is minutes into a build.

| Base | `PARA_IMAGE_BOOTSTRAP` |
|---|---|
| `images:debian/13` | `apt-get update` |
| `images:ubuntu/24.04` | `apt-get update` |
| `images:alpine/3.21` | `apk add --no-cache bash` |
| `images:voidlinux` | `xbps-install -Syu xbps bash` |
| `images:fedora/43` | `dnf -y makecache` |
| `images:archlinux` | `pacman -Syu --noconfirm` |

The bootstrap is one `sh -c` line, and leaving **bash** in the builder is the
only thing para asks of it.

**Packaging is your job, not this page's.** Which package carries a binary, what
a distro splits in two, and what `--no-install-recommends` drops all drift
faster than any page can track, and a confident sentence here would be wrong for
somebody within a release. Check it in the builder rather than trusting a
recollection, yours or this file's. That is what the contract check below is
for.

## Proving you met the contract

What an image must provide is `image.md`'s "What the image must have", so read
it there. What that page doesn't give you is a way to find out *before* the
image is in use, so end `image-build` by checking rather than assuming. It costs
six lines and turns a mystery in three days' time into a failed build now:

```sh
echo "==> image contract"
for c in bash git; do
  command -v "$c" >/dev/null || { echo "error: $c is required in the image" >&2; exit 1; }
done
id -u "$PARA_USER" >/dev/null || { echo "error: $PARA_USER was not created" >&2; exit 1; }
su --pty --help >/dev/null 2>&1 || echo "warn: this su has no --pty; 'para sh -c' from a terminal will fail" >&2
```

The loop matters. `command -v bash git` returns success when **either** name
resolves, and bash is guaranteed present, so the one-line version can only ever
pass, including on an image with no git.

**Put every binary the hooks will call in that loop**, not just the two the
contract names. `ss` is what the readiness helpers in `references/stacks.md`
poll with, so a base without it makes every `boot` blame the app for a missing
package. On a Docker stack, `docker` belongs there too: a distro can ship the
daemon and the client as separate packages, so an install line that reads
correctly still leaves you a daemon and no client. Rather than remember which
distros do that, let the loop catch it. `image.md` lists the ergonomic extras
worth having.

## Caveats that touch para's own contract

These are here because they break *para*, not because they are distro facts you
couldn't look up.

**Alpine.** `su --pty` comes from **`util-linux-login`**, since plain
`util-linux` leaves `/bin/su` as busybox's, which has no `--pty`, and that is
the `su` an interactive `para sh` needs. `useradd`/`groupadd`/`usermod` come
from `shadow`. Alpine is also musl, so a project with prebuilt glibc binaries
(some Node native modules, many vendored wheels, Playwright browsers) fails in
ways that look like the app's fault.

**Void.** The Incus base ships `/tmp` non-world-writable, which breaks any tool
that makes `/tmp/<tool>` as a non-root user; `chmod 1777 /tmp`. Services are
runit: `ln -sf /etc/sv/<svc> /var/service/`.

**Anything with systemd.** Services you `enable` in `image-build` come up in
every workspace, which is usually what you want. Don't `start` something in the
builder that needs hardware or a network the builder doesn't have.

**Docker in the image**, whatever the distro calls the packages. The workspace
user joins the `docker` group, the daemon is enabled the way this init system
does it, and the storage driver gets checked, because a btrfs or ZFS incus pool
silently gives you `vfs`:

```sh
usermod -aG docker "$PARA_USER"
# then enable the daemon the way this init system does, and wait for it:
for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
case "$(docker info --format '{{.Driver}}')" in
  overlay|overlay2|overlayfs) ;;
  *) echo "error: docker driver is not overlay; use a dir/ext4 incus pool" >&2; exit 1 ;;
esac
```

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
  land in `$HOME/.local/share/mise`, and `image-build` runs as root, so without
  `MISE_DATA_DIR` the pinned Node ends up in `/root/.local/share/mise` at mode
  0700, where `$PARA_USER` can neither see it nor read it. The same shape
  applies to any version manager that defaults to `$HOME`. Point its data
  directory somewhere system-wide, then make it world-readable.
- **Put the shell wiring in `/etc/profile.d/`.** `provision`, `boot` and
  `para sh -c` get a login shell, so that file is how a build-time tool is on
  `PATH` afterwards; an `export` inside a hook reaches nothing. Two things it
  doesn't reach: `image-build` itself is not a login shell, so a mod's
  `image-build` running after yours needs the absolute path rather than the
  wiring yours just wrote, and a `para <verb>` project command runs on the
  *host* under its own shebang, so it never sees the image at all.
- **Check which shell your workspace user actually logs into.** `/etc/profile.d`
  is read by bash, and the bundled `void-docker-gh` image gives `$PARA_USER`
  zsh, which mostly doesn't read it. Then hooks see the tool and the human's
  `para sh` doesn't, so wire the same lines into that shell's rc too.

## Things that belong in the image, not in provision

Anything identical in every workspace and expensive to repeat: compilers and
system libraries, browser binaries for e2e tests, `PARA_PREPULL_IMAGES`-style
container images, big model or dataset downloads that are read-only.

Anything that differs per workspace belongs in `provision` instead, which covers
the clone, credentials, `.env` and the database. The dividing question is
whether it varies, not whether it's big.

## Iterating without waiting

`para image build -i` is the loop to use while tuning the hook, and `image.md`
covers what it does and what it assumes. The part that falls on you is writing
the hook so a re-run is a no-op (guard `useradd`, `groupadd`, and anything that
appends to a file), or `-i` will happily stack duplicates into the image.

When you hand off, say in the project's README that editing `image-build` means
rebuilding. Nothing checks, and the symptom of forgetting is a tool that just
isn't there.
