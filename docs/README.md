# ParaSpace documentation

`para` runs any number of full, isolated copies of a project side by side on
your own machine. Each workspace is an unprivileged
[Incus](https://linuxcontainers.org/incus/) system container with its own
clone, its own stack, a static bridge IP, and its own
`https://<name>.<domain>` URL.

It is a **generic mechanism** — the Incus/Caddy/volume/lifecycle engine, the way
`docker compose` is generic. It bakes in nothing project-specific: each project
keeps its own setup in a `.paraspace/` directory at its repo root.

## Where to start

**I want to try it.**
[Why ParaSpace](./why.md) makes the case ·
[Getting started](./getting-started.md) installs it and launches your first
workspace · [How it works](./how-it-works.md) is the mental model.

**I want to run agents in parallel.**
[Running coding agents](./agents.md) — one agent per workspace, YOLO mode and
what it does and doesn't isolate, and the review loop.

**I want to add para to my repo.**
[Project setup](./project-setup.md) — `para init`, then the four files that
make a project para-enabled: the [Parafile](./parafile.md), the
[hooks](./hooks.md), the [image](./image.md), and any
[commands](./commands.md#project-commands) you want to add.

**Something is broken.**
[Troubleshooting](./troubleshooting.md) — `para doctor` and what its checks
mean.

## Reference

- [Commands](./commands.md) — the full CLI surface, project commands, and
  shell completion.
- [The Parafile](./parafile.md) — every key `para` reads from a project.
- [Hooks](./hooks.md) — the `provision`/`boot` contract and the environment
  `para` injects.
- [The image contract](./image.md) — what a base image must provide, and how
  `para image build` builds one.
- [Workspace URLs](./urls.md) — dropping the `:8443`, using your own domain,
  and trusting the local CA.
- [Git authentication](./git-auth.md) — authorizing a machine's key so
  workspaces can clone and push.
- [Contract versioning](./versioning.md) — how the `para`↔project interface is
  versioned, and what breaks on a bump.
- [Internals](./internals.md) — self-describing workspaces, machine-global
  names, project discovery, where state lives.
