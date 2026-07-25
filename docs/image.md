# The image contract

`para` owns **no** base image — you build your own. `para up` launches whatever
`PARA_IMAGE` names, so the image is where your toolchain, package installs and
pre-pulled containers get baked in once instead of on every `up`.

## What the image must have

para's own mechanism needs very little:

- a **workspace user** — `$PARA_USER` with uid/gid `$PARA_UID`/`$PARA_GID`
  (`app` and `1000`/`1000` by default). para runs hooks and `para sh` as that
  user and chowns every pushed file to those ids, so the user your
  `image-build.sh` creates **must** match. It gets all three in its
  environment;
- **bash** — para invokes hooks and shells via `su -s /bin/bash`;
- **util-linux `su`** for interactive shells. `para sh` uses `su --pty` so
  SIGWINCH reaches the child; busybox's `su` has no `--pty`, so on a plain
  Alpine image an interactive `para sh` fails loudly. Non-interactive
  `para sh -c …` is unaffected;
- **git**, if your hooks clone. para itself never runs git.

Everything else is your project's choice. If your stack is Docker Compose — as
the bundled templates' is — the image also needs **docker**, that workspace user
in the `docker` group, and nesting that resolves to **overlayfs** (a `dir`/ext4
Incus pool; btrfs and ZFS < 2.2 silently fall back to the very slow `vfs`
driver). para doesn't know or check that; the templates' `image-build.sh`
verifies it, because the payload that installs Docker is what should refuse to
publish a half-broken image.

For full ergonomics also include `tmux`, a login shell like `zsh`, and whatever
agent CLI you use — para degrades rather than breaks without them.

## Building with `para image build`

The command is base-agnostic plumbing:

1. launches a builder from **`$PARA_BASE_IMAGE`** with `security.nesting=true`;
2. runs **`$PARA_IMAGE_BOOTSTRAP`** in it via `sh -c`, if set;
3. pipes your **`.paraspace/image-build.sh`** into it as root under `bash -s`,
   with every `PARA_*` exported ahead of it;
4. publishes the result as **`$PARA_IMAGE`**, stamping `user.para.src_sha` so
   the image can tell you later whether its source has changed.

The bootstrap step exists because step 3 needs bash and step 2 is the only one
guaranteed to run — `sh` is in every base image. Use it to install bash and
refresh the package index; a base that already has what your payload needs
doesn't need it at all.

Both keys live in the [Parafile](./parafile.md#para_base_image-and-para_image_bootstrap).
`PARA_BASE_IMAGE` has **no default**: the distro is entirely the project's call,
so a para update can never swap the ground your image is built on.

Two things worth knowing:

- Images are **per-arch** — build on the machine that runs them (arm64 on
  Apple Silicon).
- `-i` / `--from-current` layers onto the existing `$PARA_IMAGE` instead of a
  pristine base, and skips the bootstrap. A fast iterative rebuild while you're
  tuning the payload; it assumes your payload is idempotent, and you should do
  one clean build before relying on the result.

The templates'
[`image-build.sh`](https://github.com/paraspace-dev/paraspace/blob/main/templates/void-docker-gh/.paraspace/image-build.sh)
is the reference: a package list, a user, and Docker set up for nesting.

## Checking it — `para image status`

An image outlasts the source that built it, so:

```
$ para image status
  image    myapp
  built    2026/07/21 14:02 UTC
  base     images:voidlinux
  source   drifted — the image inputs changed since this build
```

`source` compares a hash stamped at build time against the current
**reproducibility surface**: the `image-build.sh` payload, `$PARA_IMAGE_BOOTSTRAP`
and `$PARA_BASE_IMAGE`. If any of those changed, a rebuild would produce
something different and status says `drifted`. An image built before provenance
stamping, or by a plain `incus` action, reports `unknown`.

`para image rm` deletes `$PARA_IMAGE` — to reclaim space or force a fully clean
next build. Workspaces already `up` are clones and keep running.

## If a build is interrupted

`para image build` publishes to a temporary alias and swaps it in only once the
new image exists, so an interrupted or failed build never leaves you with no
image. Ctrl-C tears the builder down and leaves `$PARA_IMAGE` as it was.
