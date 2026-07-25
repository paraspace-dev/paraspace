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
in the `docker` group, and nesting that resolves to **overlayfs** — on a btrfs
or ZFS pool it [falls back to the very slow `vfs`
driver](./troubleshooting.md#everything-inside-the-workspace-is-slow), silently.
para doesn't check that; the templates' `image-build.sh` does.

For full ergonomics also include `tmux`, a login shell like `zsh`, and whatever
agent CLI you use — para degrades rather than breaks without them.

## Building with `para image build`

The command is base-agnostic plumbing:

1. launches a builder from **`$PARA_BASE_IMAGE`** with `security.nesting=true`;
2. runs **`$PARA_IMAGE_BOOTSTRAP`** in it via `sh -c`, if set;
3. pipes your **`.paraspace/image-build.sh`** into it as root under `bash -s`,
   with every `PARA_*` exported ahead of it;
4. publishes the result as **`$PARA_IMAGE`**, stamping `user.para.src_sha` so
   the image can tell you later whether its source has changed. A failed or
   interrupted build leaves the existing image untouched.

Both keys live in the
[Parafile](./parafile.md#para_base_image-and-para_image_bootstrap), which is
also where the per-distro bootstrap examples are.

Two caveats:

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

`drifted` means the `image-build.sh` payload, `$PARA_IMAGE_BOOTSTRAP` or
`$PARA_BASE_IMAGE` changed since the build, so rebuilding would give you
something different. `unknown` means the image predates provenance stamping, or
was built by a plain `incus` action.

`para image rm` deletes `$PARA_IMAGE` — to reclaim space or force a fully clean
next build. Workspaces already `up` are clones and keep running.
