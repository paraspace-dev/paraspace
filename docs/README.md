# ParaSpace documentation

`para` runs any number of full, isolated copies of a project side by side. Each
workspace is an unprivileged [Incus](https://linuxcontainers.org/incus/) system
container with its own clone, its own Docker stack, a static bridge IP, and its
own `https://<name>.<domain>` URL, reachable from your workstation.

para is a **generic mechanism** — the Incus/Caddy/volume/lifecycle engine, the
way `docker compose` is generic. It bakes in nothing project-specific: each
project keeps its own setup in a `.paraspace/` dir at its repo root.

New here? Start with the [README](../README.md) — install and quick start live
there.

## Guides

- [How it works](./how-it-works.md) — the moving parts: the host Caddy, the
  shared home volume, self-describing workspaces, and where state lives.
- [Project setup](./project-setup.md) — adapt para to your own project with
  `para init` and a `.paraspace/` dir.
- [Workspace URLs](./urls.md) — removing the `:8443` from URLs, using your own
  domain, and trusting the local CA in your browser.
- [Git authentication](./git-auth.md) — authorizing a machine's SSH key so
  workspaces can clone and push.

## Reference

- [Commands](./commands.md) — the full CLI surface, plus shell completion.
- [The Parafile](./parafile.md) — every key para reads from a project.
- [Hooks](./hooks.md) — the `provision`/`boot` contract and the environment
  para injects.
- [The image contract](./image.md) — what a base image must provide, and how
  `para image-build` builds one.
- [Contract versioning](./versioning.md) — how the para↔project interface is
  versioned, and what counts as a breaking change.

## Templates

Three runnable templates under [`templates/`](../templates) share one shape and
vary in weight:

- [`void-docker-gh`](../templates/void-docker-gh) — the `para init` default: a
  small, complete Docker demo exercising the whole mechanism.
- [`void-minimal`](../templates/void-minimal) — the barest box: installs and
  runs nothing, with comments marking where your stack goes.
- [`void-jchook`](../templates/void-jchook) — a full personal dev environment
  (zsh, tmux, Neovim, Claude Code) on top of the same demo.

