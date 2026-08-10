# The image contract

Your project has total control over the base image used to create workspaces.

## What the image must have

para's own mechanism needs very little:

- a **workspace user**, `$PARA_USER` with uid/gid `$PARA_UID`/`$PARA_GID`
  (`app` and `1000`/`1000` by default). para runs hooks and `para sh` as that
  user and chowns every pushed file to those ids;
- **bash**, because para invokes hooks and shells via `su -s /bin/bash`;
- **util-linux `su`**, if you run `para sh <ws> -c '<cmd>'` from a terminal.

Everything else is your project's choice.

For full ergonomics also include a login shell like `zsh`, nicer dotfiles, and
whatever agent harness you use.

## Building with `para image build`

The command is base-agnostic plumbing:

1. launches a builder from **`$PARA_IMAGE_BASE`** with `security.nesting=true`;
2. runs **`$PARA_IMAGE_BOOTSTRAP`** in it via `sh -c`, if there is one;
3. pushes your whole **`.paraspace/`** to `/opt/.paraspace` in the builder;
4. runs **`hooks/image-build`** as root, with no tty and no stdin: yours first,
   then any mods under `.paraspace/mods/*/hooks/image-build`;
5. removes `/opt/.paraspace` and publishes the result as **`$PARA_IMAGE`**.

Two caveats:

- Images are **per-arch**, so build on the machine that runs them (arm64 on
  Apple Silicon).
- `-i` / `--from-current` layers onto the existing `$PARA_IMAGE` instead of a
  pristine base, and skips the bootstrap. A fast iterative rebuild while you're
  tuning the hook; it assumes your hook is idempotent, and you should do
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

`base` is what this image was built **from**, stamped at build time.

Rebuild when you've edited your `hooks/image-build`.

`para image rm` deletes `$PARA_IMAGE`, to reclaim space or force a fully clean
next build. Workspaces already `up` are clones and keep running.
