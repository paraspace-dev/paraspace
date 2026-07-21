# The image contract

para owns **no** base image — you build your own. `para up` launches whatever
`PARA_IMAGE` names, so the image is where your toolchain, package installs, and
pre-pulled Docker images get baked in once instead of on every `up`.

## What the image must have

For para's mechanism to work, the image must have:

- **docker**, with nesting resolving to **overlayfs** — para runs your stack in
  nested Docker on a `dir`/ext4 pool, not vfs;
- a **uid-1000 user in the `docker` group** — para runs everything as it;
- **bash** and **git**.

For full ergonomics also include `tmux` (`para run`), a login shell like `zsh`
(`para sh`), and `claude`/`nvim`/`gh` — para degrades rather than breaks
without them.

## Building with `para image-build`

`para image-build` runs your project's `.paraspace/image-build.sh` inside a fresh
Void Linux container, pre-pulls the stack's external images so workspaces boot
without network pulls, verifies the Docker storage driver resolved to
overlay(fs) rather than vfs, and publishes the result as `$PARA_IMAGE`.

- Images are **per-arch** — build on the machine that runs them (arm64 on
  Apple Silicon).
- `-i` / `--from-current` layers onto the existing image instead of pristine
  Void — a fast iterative rebuild while you tune `image-build.sh`.
- `-q` / `-v` force or keep the Incus progress bars (auto-quiet when not a
  tty).

The templates' [`image-build.sh`](../templates/void-docker-gh/.paraspace/image-build.sh)
scripts are the reference: a package list, a user, and Docker set up for
nesting.
