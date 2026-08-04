# ParaSpace documentation

`para` runs any number of full, isolated copies of a project side by side on
your own machine. Each workspace is an unprivileged system container with its
own clone, its own stack, a static bridge IP, and its own
`https://<name>.<domain>` URL.

[Incus](https://linuxcontainers.org/incus/) runs the containers.
[Caddy](https://caddyserver.com/) runs on your host and points each workspace's
hostname at its bridge IP. Everything about how your project gets set up inside
a workspace lives in a `.paraspace/` directory at your repo root.

## Where to start

**I want to try it.** [Why ParaSpace](./why.md) makes the case ·
[Install ParaSpace](./install.md) prepares your machine · [Use a ParaSpace
project](./using-a-project.md) launches your first workspace in a repo that
already has `.paraspace/` · [How it works](./how-it-works.md) is the mental
model · [Prior art](./prior-art.md) compares the alternatives, including when
to pick something else.

**I want to run agents in parallel.** [Running coding agents](./agents.md)
covers one agent per workspace, running an agent with permissions wide open,
what that does and doesn't isolate, and the review loop.

**I want to add para to my repo.** [Add ParaSpace to a
project](./project-setup.md) starts at `para init`, then walks the pieces that
make a project para-enabled: the [Parafile](./parafile.md), the
[hooks](./hooks.md), the [image](./image.md), and any
[commands](./commands.md#project-commands) you want to add.
[Mods](./mods.md) are how you vendor a ready-made piece of that instead of
writing it. The [Cookbook](./cookbook.md) has recipes for the common ones. Or
have the [Claude Code plugin](./claude-plugin.md) do it from what your repo
already says about itself.

**Something is broken.** [Troubleshooting](./troubleshooting.md) starts at
`para doctor` and explains what its checks mean.

## Reference

- [Commands](./commands.md) covers the full CLI surface, project commands, and
  shell completion.
- [The Parafile](./parafile.md) lists every key `para` reads from a project.
- [Hooks](./hooks.md) defines the `provision`/`boot`/`image-build` contract and
  the environment `para` injects.
- [Hook points](./hook-points.md) shows how to run a hook point of your own,
  and how one name resolves to more than one script.
- [Mods](./mods.md) covers vendoring a reusable piece of `.paraspace/` with
  `para mod add`, and writing one that plays well with others.
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
