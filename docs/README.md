# ParaSpace documentation

`para` runs any number of full, isolated copies of a project side by side. Each
workspace is an unprivileged [Incus](https://linuxcontainers.org/incus/) system
container with its own clone, its own Docker stack, a static bridge IP, and its
own `https://<name>.<domain>` URL, reachable from your workstation.

`para` is a **generic mechanism** — the Incus/Caddy/volume/lifecycle engine, the
way `docker compose` is generic. It bakes in nothing project-specific: each
project keeps its own setup in a `.paraspace/` dir at its repo root.

New here? [Get started](./getting-started.md) — install, prerequisites, and
your first workspace.

## Guides

- [Getting started](./getting-started.md) — install `para`, launch a
  workspace, scaffold your project.
- [Project setup](./project-setup.md) — adapt `para` to your own project with
  `para init` and a `.paraspace/` dir.
- [How it works](./how-it-works.md) — the problem this solves and the
  architecture that solves it: one host Caddy, one container per workspace,
  one shared volume per project.
- [Workspace URLs](./urls.md) — removing the `:8443` from URLs, using your own
  domain, and trusting the local CA in your browser.
- [Git authentication](./git-auth.md) — authorizing a machine's SSH key so
  workspaces can clone and push.

## Reference

- [Commands](./commands.md) — the full CLI surface, plus shell completion.
- [The Parafile](./parafile.md) — every key `para` reads from a project.
- [Hooks](./hooks.md) — the `provision`/`boot` contract and the environment
  `para` injects.
- [The image contract](./image.md) — what a base image must provide, and how
  `para image build` builds one.
- [Contract versioning](./versioning.md) — how the `para`↔project interface is
  versioned, and what counts as a breaking change.
- [Internals](./internals.md) — the finer mechanics: self-describing
  workspaces, machine-global names, project discovery, where state lives.

## Templates

Three runnable templates under
[`templates/`](https://github.com/paraspace-dev/paraspace/tree/main/templates)
share one shape and vary in weight:

- [`void-docker-gh`](https://github.com/paraspace-dev/paraspace/tree/main/templates/void-docker-gh)
  — the `para init` default: a
  small, complete Docker demo exercising the whole mechanism.
- [`void-minimal`](https://github.com/paraspace-dev/paraspace/tree/main/templates/void-minimal)
  — the barest box: installs and
  runs nothing, with comments marking where your stack goes.
- [`void-jchook`](https://github.com/paraspace-dev/paraspace/tree/main/templates/void-jchook)
  — a full personal dev environment
  (zsh, tmux, Neovim, Claude Code) on top of the same demo.

