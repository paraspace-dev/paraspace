# What is ParaSpace?

ParaSpace ships the `para` cli tool, which gives every task its own full,
isolated copy of a project, so several coding agents can work at once without
stepping on each other's branch, database, or half-finished edits.

Each workspace is a local unprivileged system container with its own clone, its
own running services, a static bridge IP, and its own `https://<name>.<domain>`
URL.

[Incus](https://linuxcontainers.org/incus/) runs the containers.
[Caddy](https://caddyserver.com/) runs on your host and points each workspace's
hostname at its bridge IP. Everything about how your project gets set up inside
a workspace lives in a `.paraspace/` directory at your repo root.

## Where to start

**I want to try it.**

- [Install ParaSpace](./install.md) to prepare your machine
- [Use a ParaSpace project](./using-a-project.md) on repos that already have
  `.paraspace/`
- [Running coding agents](./agents.md) in parallel
- [Why ParaSpace](./why.md) explains the approach
- [How it works](./how-it-works.md) and the mental model

**I want to add ParaSpace to my repo.**

- [Add ParaSpace to a project](./project-setup.md) starts at `para init`, then
  walks the pieces that make a project para-enabled, the
  [env file](./env.md), the [layers](./layers.md), the [hooks](./hooks.md), the
  [image](./image.md), and any [commands](./commands.md#project-commands) you
  want to add
- [Layers](./layers.md) are how you add a ready-made piece of that instead of
  writing it
- [The Cookbook](./cookbook.md) has recipes for the common ones
- [Prior art](./prior-art.md) compares the alternatives, including when to pick
  something else

**Something is broken.** [Troubleshooting](./troubleshooting.md) starts at
`para doctor` and explains what its checks mean.

## Reference

- [Commands](./commands.md) covers the full CLI surface, project commands, and
  shell completion.
- [The env file](./env.md) lists every key `para` reads from a project's
  `.paraspace/env`.
- [Hooks](./hooks.md) defines the `provision`/`boot`/`image-build` contract and
  the environment `para` injects.
- [Hook points](./hook-points.md) shows how to run a hook point of your own,
  and how one name resolves to more than one script.
- [Layers](./layers.md) covers the layer shape, the stack file, `para add`, and
  customizing a packaged layer.
- [Publishing plugins](./plugins.md) is for authors who want to ship layers as
  an npm package (`paraspace-plugin-*`).
- [The image contract](./image.md) says what a base image must provide, and how
  `para image build` builds one.
- [Workspace URLs](./urls.md) covers dropping the `:8443`, using your own
  domain, and trusting the local CA.
- [Shared authentication](./shared-auth.md) is how you sign in once per project
  (the VCS key, `gh`, agent sessions, API tokens).
- [Contract versioning](./versioning.md) explains how the `para`↔project
  interface is versioned, and what breaks on a bump.
- [Internals](./internals.md) covers self-describing workspaces, the shared
  volume, machine-global names, and where state lives.
