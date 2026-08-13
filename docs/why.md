# Why ParaSpace

Every coding task gets an entire, disposable copy of your project, with its own
services, and its own URL on your machine. Run several agents or pursue several
experiments at once, each in its own workspace, without them stepping on each
other.

## The problem

Two agents on one checkout contend for the same working tree, branch state,
database, and ports. Letting one agent run migrations, reseed the database, or
one agent reconfigure the running services can also disrupt every other task.

Worktrees give each task its own files but share everything else. Full clones
need their own services, ports, and env to actually run, so you end up
maintaining several copies of "how do I boot this thing" anyway. ParaSpace
makes that boot procedure the project's code, then stamps out as many running
copies as you want. [Prior art](./prior-art.md) covers the alternatives in
depth.

## One workspace = one container

It has its own clone and can run its own Docker services, including nested
containers, on its own bridge IP.

```sh
para up fix-auth
para sh fix-auth
```

The workspace is disposable. `para rm` deletes it; the project's shared
credentials survive on a per-project volume.

## Share project authentication

Run `gh auth login` in one workspace and use that authentication from other
workspaces for the same project, including workspaces created later or
restarted after a reboot.

The credentials live on a [shared volume](./internals.md#the-shared-home-volume)
attached to the project's workspaces. They remain on the container side of the
boundary.

## Reach each workspace at its usual ports

Each workspace receives its own bridge IP. Your application can keep using the
ports it already expects, while Caddy routes workspace hostnames to those
ports.

```text
https://my-feature.paraspace.dev     →  10.x.x.201:3000
https://db.my-feature.paraspace.dev  →  10.x.x.201:8081
```

Configure the routes in [the env file](./env.md). Caddy sends each workspace
hostname to its configured port, so your application does not need port offsets
or sandbox-specific proxy settings.

## Let the project define its environment

Keep your image construction, provisioning, and boot behavior in
`.paraspace/`. The repository defines the tools, services, and setup that every
workspace needs. See [Project setup](./project-setup.md) and
[Hooks](./hooks.md) for the available project configuration.

A project can also add its own `para` verbs as executables under
`.paraspace/layers/project/commands/<verb>`. See [Commands](./commands.md) for
how project commands work.

The `dotfiles` layer provides `para claude`. Add it to a project with:

```sh
para add dotfiles
```

The layer supplies that command rather than the `para` engine.

## Next

- [Install ParaSpace](./install.md) to set up your machine
- [How it works](./how-it-works.md) for the architecture
- [Running coding agents](./agents.md) for the workflow
- [Prior art](./prior-art.md) for the alternatives

[hn]: https://news.ycombinator.com/item?id=48892468
