# The image contract

`para` owns **no** base image — you build your own. `para up` launches whatever
`PARA_IMAGE` names, so the image is where your toolchain, package installs and
pre-pulled containers get baked in once instead of on every `up`.

## What the image must have

para's own mechanism needs very little:

- a **workspace user** — `$PARA_USER` with uid/gid `$PARA_UID`/`$PARA_GID`
  (`app` and `1000`/`1000` by default). para runs hooks and `para sh` as that
  user and chowns every pushed file to those ids, so the user your
  `hooks/image-build` creates **must** match. It gets all three in its
  environment;
- **bash** — para invokes hooks and shells via `su -s /bin/bash`;
- **util-linux `su`**, if you run `para sh <ws> -c '<cmd>'` from a terminal —
  that path uses `su --pty` so SIGWINCH reaches the child. busybox's `su` has no
  `--pty` and fails loudly. A bare `para sh`, and `-c` with its output piped or
  redirected, both use plain `su -` and work on a busybox image;
- **git**, if your hooks clone. para itself never runs git.

Everything else is your project's choice. If your stack is Docker Compose — as
the bundled templates' is — the image also needs **docker**, that workspace user
in the `docker` group, and nesting that resolves to **overlayfs** — on a btrfs
or ZFS pool it silently [falls back to the very slow `vfs`
driver](./troubleshooting.md#everything-inside-the-workspace-is-slow). para
doesn't check that; the templates' `hooks/image-build` does.

For full ergonomics also include `tmux`, a login shell like `zsh`, and whatever
agent CLI you use — para degrades rather than breaks without them.

## Building with `para image build`

The command is base-agnostic plumbing:

1. launches a builder from **`$PARA_IMAGE_BASE`** with `security.nesting=true`;
2. runs **`$PARA_IMAGE_BOOTSTRAP`** in it via `sh -c`, if set;
3. pushes your whole **`.paraspace/`** to `/opt/.paraspace` in the builder, near
   enough to the way `para up` pushes it to `~/.paraspace` that `$PARA_HOOKS`
   and `$PARA_SKEL` name real paths in there — your `.env` is the exception, so
   `$PARA_HOST_ENV` names a file the builder does not have;
4. runs **`hooks/image-build`** as root, with no tty and no stdin — yours, then
   any a mod vendored under `.paraspace/mods/`;
5. removes `/opt/.paraspace` and publishes the result as **`$PARA_IMAGE`**. A
   failed or interrupted build leaves the existing image untouched.

Your project's tree is a build *input*, so step 5 takes it back out before the
snapshot — a workspace should find its `.paraspace/` at `~`, pushed fresh by
`para up`, and nowhere else.

Both keys live in the [Parafile](./parafile.md), which is also where the
per-distro bootstrap examples are.

Nothing to build is an error, not a no-op: with no `hooks/image-build` anywhere,
`para image build` stops before it touches incus rather than publishing a base
image with nothing in it.

Two caveats:

- Images are **per-arch** — build on the machine that runs them (arm64 on
  Apple Silicon).
- `-i` / `--from-current` layers onto the existing `$PARA_IMAGE` instead of a
  pristine base, and skips the bootstrap. A fast iterative rebuild while you're
  tuning the hook; it assumes your hook is idempotent, and you should do
  one clean build before relying on the result.

The templates'
[`hooks/image-build`](https://github.com/paraspace-dev/paraspace/blob/main/templates/void-docker-gh/.paraspace/hooks/image-build)
is the reference: a package list, a user, and Docker set up for nesting.

## Checking it — `para image status`

```
$ para image status
  image    myapp
  built    2026/07/21 14:02 UTC
  base     images:voidlinux
```

`base` is what this image was built **from**, stamped at build time — not what
`PARA_IMAGE_BASE` names today. After a `-i` build it is `$PARA_IMAGE` itself,
which is how you tell an incremental image from a clean one.

Rebuild when you've edited your `hooks/image-build` — nothing checks for you,
and if you leave it too long you find out because the tool you added isn't in
the workspace.

`para image rm` deletes `$PARA_IMAGE` — to reclaim space or force a fully clean
next build. Workspaces already `up` are clones and keep running.
