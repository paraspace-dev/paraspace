# The image contract

Your project has total control over the base image used to create workspaces.

## What the image must have

para's own mechanism needs very little:

- a **workspace user**, `$PARA_USER` with uid/gid `$PARA_UID`/`$PARA_GID`
  (`app` and `1000`/`1000` by default). para runs hooks and `para sh` as that
  user and chowns every pushed file to those ids;
- **bash**, because para invokes hooks and shells via `su -s /bin/bash`;
- **util-linux `su`**, if you run `para sh <ws> -c '<cmd>'` from a terminal.
  That path uses `su --pty`, and busybox's `su` has no `--pty` and fails
  loudly. A bare `para sh`, and `-c` with its output piped, use plain `su -`
  and work on a busybox image;
- **git**, if your hooks clone. para itself never runs git.

Everything else is your project's choice, and nothing here requires containers.
If your stack runs them, as `void-docker-gh`'s does, the image also needs
**docker**, that workspace user in the `docker` group, and nesting that resolves
to **overlayfs**. On a btrfs or ZFS pool it silently [falls back to the very slow
`vfs` driver](./troubleshooting.md#everything-inside-the-workspace-is-slow).

For full ergonomics also include a login shell like `zsh`, nicer dotfiles, and
whatever agent harness you use.

## Building with `para image build`

The command is base-agnostic plumbing:

1. launches a builder from **`$PARA_IMAGE_BASE`** with `security.nesting=true`;
2. runs **`$PARA_IMAGE_BOOTSTRAP`** in it via `sh -c`, if there is one;
3. pushes your whole **`.paraspace/`** to `/opt/.paraspace` in the builder, so
   `$PARA_HOOKS` and `$PARA_SKEL` name real paths in there. Your `.env` is the
   exception, so `$PARA_HOST_ENV` names a file the builder does not have;
4. runs **`hooks/image-build`** as root, with no tty and no stdin: yours first,
   then any mods under `.paraspace/mods/*/hooks/image-build`;
5. removes `/opt/.paraspace` and publishes the result as **`$PARA_IMAGE_NAME`**.
   A failed or interrupted build leaves the existing image untouched.

Nothing to build is an error, not a no-op. With no `hooks/image-build`
anywhere, `para image build` stops before it touches incus rather than
publishing a base image with nothing in it.

Two caveats:

- Images are **per-arch**, so build on the machine that runs them (arm64 on
  Apple Silicon).
- `-i` / `--from-current` layers onto the existing `$PARA_IMAGE_NAME` instead of
  a pristine base, and skips the bootstrap. A fast iterative rebuild while
  you're tuning the hook; it assumes your hook is idempotent, and you should do
  one clean build before relying on the result.

The templates'
[`hooks/image-build`](https://github.com/paraspace-dev/paraspace/blob/main/templates/void-docker-gh/.paraspace/hooks/image-build)
is the reference: a package list, a user, and Docker set up for nesting.

## Checking it with `para image status`

```
$ para image status
  image    myapp
  built    2026/07/21 14:02 UTC
  base     images:voidlinux
```

`base` is what this image was built **from**, stamped at build time, rather than
what `PARA_IMAGE_BASE` names today. After a `-i` build it is `$PARA_IMAGE_NAME`
itself, which is how you tell an incremental image from a clean one.

Rebuild when you've edited your `hooks/image-build`. Nothing checks for you, and
if you leave it too long you find out because the tool you added isn't in the
workspace.

`para image rm` deletes `$PARA_IMAGE_NAME`, to reclaim space or force a fully
clean next build. Workspaces already `up` are clones and keep running.
