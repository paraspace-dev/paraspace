# Choosing a base image and writing `image-build`

para owns no image. `PARA_IMAGE_BASE` is the Incus image the builder starts
from, `PARA_IMAGE_BOOTSTRAP` is one `sh -c` line run in it before your hook
(its only required job is leaving **bash** behind, plus refreshing the package
index if the base needs it), and `.paraspace/hooks/image-build` does the rest as
root with **no tty and no stdin** — a package manager that stops to ask will
hang the build, so pass the non-interactive flag every time.

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
| `images:fedora/41` | `dnf -y makecache` | `dnf install -y …` | fine; larger images |
| `images:archlinux` | `pacman -Sy --noconfirm` | `pacman -S --noconfirm …` | rolling; refresh keyring first if installs fail signature checks |

Aliases move over time — `incus image list images: <distro>` on the machine is
the check, and it takes a second.

## The contract, and how to prove you met it

para needs very little from an image, and everything else is your project's
choice. What it does need:

- the workspace user `$PARA_USER` at `$PARA_UID`/`$PARA_GID` (all three are in
  the hook's environment — create the user with **those** ids, or every file
  para pushes lands on a uid with no passwd entry and the shared volume becomes
  unwritable);
- **bash** (para runs hooks and shells through `su -s /bin/bash`);
- **util-linux `su`**, if anyone will run `para sh <ws> -c '<cmd>'` from a
  terminal — that path uses `su --pty`, which busybox's `su` does not have;
- **git**, if your hooks clone.

End `image-build` with a self-check rather than assuming. It costs four lines
and turns a mystery in three days' time into a failed build now:

```sh
echo "==> image contract"
command -v bash git >/dev/null || { echo "error: bash and git are required" >&2; exit 1; }
id -u "$PARA_USER" >/dev/null || { echo "error: $PARA_USER was not created" >&2; exit 1; }
su --pty --help >/dev/null 2>&1 || echo "warn: this su has no --pty; 'para sh -c' from a terminal will fail" >&2
```

Add `iproute2` (for `ss`, which the readiness helpers use), and — for ergonomics
— `tmux`, a login shell, and whatever agent CLI the team runs. para degrades
rather than breaks without those.

## Per-distro caveats that actually bite

**Alpine.** `useradd`/`groupadd`/`usermod` come from `shadow`, not busybox, and
`su --pty` comes from util-linux — on Alpine that's split into subpackages, so
install and then *verify* with the self-check above instead of trusting a
package name. Alpine is also musl: a project with prebuilt glibc binaries
(some Node native modules, many vendored wheels, Playwright browsers) will fail
in ways that look like the app's fault. Great for a small worker box, risky as a
default for an app stack.

**Void.** Installing new packages against freshly-synced repodata without a full
`-Syu` first is the classic partial-upgrade footgun — do the full upgrade, then
install. The Incus base also ships `/tmp` as non-world-writable, which breaks
any tool that makes `/tmp/<tool>` as a non-root user; `chmod 1777 /tmp`. Services
are runit: `ln -sf /etc/sv/<svc> /var/service/`.

**Debian/Ubuntu.** `DEBIAN_FRONTEND=noninteractive` on every `apt-get install`,
and prefer `apt-get` over `apt` in scripts. For Docker, the distro's `docker.io`
gets you an engine but compose v2 availability varies by release — adding
Docker's own apt repo (`docker-ce docker-ce-cli containerd.io
docker-buildx-plugin docker-compose-plugin`) is the predictable path.

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
curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh
printf 'eval "$(/usr/local/bin/mise activate bash)"\n' > /etc/profile.d/mise.sh
```

Two details that decide whether this works:

- **Put the shell wiring in `/etc/profile.d/`.** Hooks, `para sh` and project
  commands all run through login shells, so a `profile.d` file is how a tool
  installed at build time is on `PATH` everywhere afterwards. An `export` inside
  a hook reaches nothing.
- **Install as root, then let the workspace user use it.** If a version manager
  insists on living in `$HOME`, install it per workspace in `provision` instead
  and cache its downloads on `$PARA_SHARED` — but system-wide in the image is
  faster and simpler when the tool allows it.

## Things that belong in the image, not in provision

Anything identical in every workspace and expensive to repeat: compilers and
system libraries, browser binaries for e2e tests, `PARA_PREPULL_IMAGES`-style
container images, big model or dataset downloads that are read-only.

Anything that differs per workspace — the clone, credentials, `.env`, the
database — belongs in `provision`. The dividing question is never "is it big",
it's "does it vary".

## Iterating without waiting

`para image build` takes minutes; `para image build -i` layers onto the current
image and skips the bootstrap, which is the loop to use while tuning the hook.
It assumes your hook is idempotent (guard `useradd`, `groupadd`, and anything
that appends to a file). Do one clean build before declaring victory, and
remember images are **per-arch** — an arm64 Mac and an x86 CI box each build
their own.

Nothing tracks image drift: after editing `image-build`, someone has to rebuild,
and the symptom of forgetting is a tool that just isn't there. Say so in the
project's README when you hand off.
