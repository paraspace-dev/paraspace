# The image contract

para owns **no** base image — you build your own. `para up` launches whatever
`PARA_IMAGE` names, so the image is where your toolchain, package installs, and
pre-pulled Docker images get baked in once instead of on every `up`.

## What the image must have

para's own mechanism needs very little of the image:

- a **workspace user** — `$PARA_USER` with uid/gid `$PARA_UID`/`$PARA_GID`
  (`app` and `1000`/`1000` by default). para runs hooks, `para sh`, and
  `para run` as it, and every file it pushes is chowned to those ids, so the
  user your `image-build.sh` creates **must** match them (it gets all three in
  its environment — see below). Override them in the
  [Parafile](./parafile.md#para_user--para_uid--para_gid) if `1000` is taken in
  your base image;
- **bash** — para invokes hooks and shells via `su -s /bin/bash`;
- **git**, if your hooks clone (the bundled templates' do; para itself never
  runs git).

Everything else is your project's choice. If your stack is Docker Compose —
as the bundled templates' is — then the image also needs **docker** with
nesting resolving to **overlayfs** (a `dir`/ext4 Incus pool; btrfs/zfs<2.2
silently falls back to the slow vfs driver) and that workspace user in the
`docker` group. para doesn't know or check that; the templates'
`image-build.sh` verifies it for you, because the payload that installs Docker
is what should refuse to publish a half-broken image.

For full ergonomics also include `tmux` (`para run`), a login shell like `zsh`
(`para sh`), and `claude`/`nvim`/`gh` — para degrades rather than breaks
without them.

## Building with `para image-build`

`para image-build` is base-agnostic plumbing. It:

1. launches a builder from **`$PARA_BASE_IMAGE`** (any Incus image —
   `images:debian/13`, `images:voidlinux`, `images:alpine/edge`, …) with
   `security.nesting=true`;
2. runs **`$PARA_IMAGE_BOOTSTRAP`** in it via `sh -c`, if set;
3. runs your project's **`.paraspace/image-build.sh`** in it via `bash -s`, as
   root, with `$PARA_USER`/`$PARA_UID`/`$PARA_GID` and `$PARA_PREPULL_IMAGES`
   (the stack's external image tags, scraped from your `docker-compose.yml` /
   `Dockerfile`) in the environment;
4. publishes the result as **`$PARA_IMAGE`**.

The bootstrap step exists because step 3 needs bash and step 2 is the only one
guaranteed to run (`sh` is in every base image). Use it to install bash and/or
refresh the package index — `xbps-install -Syu xbps bash` on Void,
`apk add --no-cache bash` on Alpine, `apt-get update` on Debian. A base that
already ships what your payload needs doesn't need it at all; leave it unset.

Both keys live in the [Parafile](./parafile.md). `PARA_BASE_IMAGE` has **no
default** — the distro is entirely the project's call, so para asks rather than
picks, and a para update can never swap the ground your image is built on.

- Images are **per-arch** — build on the machine that runs them (arm64 on
  Apple Silicon).
- `-i` / `--from-current` layers onto the existing `$PARA_IMAGE` instead of a
  pristine base (and skips the bootstrap) — a fast iterative rebuild while you
  tune `image-build.sh`. It assumes your payload is idempotent.
- `-q` / `-v` force or keep the Incus progress bars (auto-quiet when not a
  tty).

The templates' [`image-build.sh`](https://github.com/paraspace-dev/paraspace/blob/main/templates/void-docker-gh/.paraspace/image-build.sh)
scripts are the reference: a package list, a user, and Docker set up for
nesting.
