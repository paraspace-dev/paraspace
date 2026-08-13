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
3. pushes the composed layer stack to `/opt/.paraspace` in the builder, with
   each layer at `/opt/.paraspace/stack/<layer name>`, the same layout a
   workspace gets at `~/.paraspace`;
4. runs `hooks/image-build` from every layer that defines it, in stack order,
   as root, with no tty and no stdin;
5. removes `/opt/.paraspace` and publishes the result as **`$PARA_IMAGE_NAME`**.

Two caveats:

- Images are **per-arch**, so build on the machine that runs them (arm64 on
  Apple Silicon).
- `-i` / `--from-current` layers onto the existing `$PARA_IMAGE_NAME` instead of
  a pristine base, and skips the bootstrap. A fast iterative rebuild while
  you're tuning the hook; it assumes your hook is idempotent, and you should do
  one clean build before relying on the result.

The bundled base layer's
[`hooks/image-build`](https://github.com/paraspace-dev/paraspace/blob/main/layers/base/void/hooks/image-build)
is the reference: Void packages, a workspace user, and the zsh extension paths
bundled layers use. Docker lives in its own layer.

## Checking it with `para image status`

```
$ para image status
  image    myapp
  built    2026/07/21 14:02 UTC
  base     images:voidlinux
```

`base` is what this image was built **from**, stamped at build time.

Rebuild when you've edited your `hooks/image-build`.

`para image rm` deletes `$PARA_IMAGE_NAME`, to reclaim space or force a
fully clean next build. Workspaces already `up` are clones and keep running.
