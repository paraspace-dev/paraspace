# Why ParaSpace

Every coding task gets an entire, disposable copy of your project, with its own
services and its own URL on your machine. Run several agents or pursue several
experiments at once, each in its own workspace, without them stepping on each
other.

## The problem

Two agents on one checkout contend for the same working tree, branch state,
database, and ports. One of them runs a migration, reseeds the database, or
reconfigures a service, and every other task breaks under it.

Worktrees give each task its own files but share everything else. Full clones
need their own services, ports, and env before they will run, so you end up
maintaining several copies of "how do I boot this thing" anyway. Write that
boot procedure once, as code in the repo, and para stamps out as many running
copies as you want. [Prior art](./prior-art.md) covers the alternatives in
depth.

## One workspace = one container

Each workspace holds its own clone and runs its own services, nested Docker
containers included, on its own bridge IP.

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
that only this project's workspaces mount. Your host never mounts it, and no
workspace can reach the keys in your own home directory.

## Reach each workspace at its usual ports

Each workspace gets its own bridge IP, so your application keeps the ports it
already expects and Caddy sends each workspace hostname to the right one.

```text
https://my-feature.paraspace.dev     →  10.x.x.201:3000
https://db.my-feature.paraspace.dev  →  10.x.x.201:8081
```

Configure the routes in [the env file](./env.md). Your application needs no port
offsets and no sandbox-specific proxy settings.

## Let the project define its environment

Keep your image construction, provisioning, and boot behavior in `.paraspace/`,
so the repository decides what tools, services, and setup every workspace gets.
See [Project setup](./project-setup.md) and [Hooks](./hooks.md) for what a
project can configure.

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
