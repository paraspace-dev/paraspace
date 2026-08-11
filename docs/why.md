# Why ParaSpace

ParaSpace gives every coding task its own isolated copy of your project, its own
stack, and its own URL on your machine. Run several agents or pursue several
changes at once without sharing a checkout, application state, or application
ports.

## The problem

Agents pointed at the same project directory interfere with each other.
Branches change underneath them, edits conflict or contaminate context, and the
resulting mixed diff must be separated into individual PRs afterward. Letting
one agent reconfigure the running stack can also disrupt every other task.

A worktree separates files but leaves the runtime shared. You need separate
files and a separate place to run the stack. [Prior art](./prior-art.md) covers
other ways to provide that isolation, including when one of them fits better.

## Run each task in its own workspace

Each workspace runs as an unprivileged Incus system container on your machine.
It has its own clone and can run its own Docker stack, including nested
containers on an independent Docker daemon.

Workspaces share the machine's available CPU and memory. An idle workspace uses
little, while a busy workspace draws from the same pool as your other work.
macOS runs one underlying Linux VM for the machine rather than one per
workspace. [How it works](./how-it-works.md#macos-adds-one-layer) explains that
layer.

Enter a workspace from your usual terminal:

```sh
para sh my-feature
```

The command opens a PTY in that workspace's clone. tmux, Neovim, and Claude
Code have the terminal support they expect, so you can keep using the terminal
tools and workflows you use locally.

## Keep host files out of the workspace

Nothing from the host is mounted into a workspace. `para` pushes the project's
`.paraspace/` directory, a small generated environment file, and, when present,
the project's root `.env` file. Your home directory, SSH keys, and cloud
credentials are not readable from inside the workspace.

A workspace's root user maps to an unprivileged host UID through a user
namespace. Even `docker run --privileged` inside its nested Docker daemon stays
within that namespace.

This prevents incidents such as [an agent uploading a user's home
directory][hn] when that directory was never available to the agent. It does
not make container escape impossible. Workspaces share the host kernel and have
ordinary outbound network access. Incus ACLs can restrict egress when needed.

You may choose to relax agent permission prompts for trusted work after
considering those limits. Use a VM or another stronger isolation boundary for
code you actively distrust.

## Share project authentication

Run `gh auth login` in one workspace and use that authentication from other
workspaces for the same project, including workspaces created later or
restarted after a reboot.

The credentials live on a [shared volume](./internals.md#the-shared-home-volume)
attached to the project's workspaces. They remain on the container side of the
boundary.

## Reach each stack at its usual ports

Each workspace receives its own bridge IP. Your application can keep using the
ports it already expects, while Caddy routes workspace hostnames to those
ports.

```text
https://my-feature.paraspace.dev     →  10.x.x.201:3000
https://db.my-feature.paraspace.dev  →  10.x.x.201:8081
```

Configure the routes in your [`Parafile`](./parafile.md). Caddy sends each
workspace hostname to its configured port, so your application does not need
port offsets or sandbox-specific proxy settings.

## Let the project define its environment

Keep your image construction, provisioning, and boot behavior in
`.paraspace/`. The repository defines the tools, services, and setup that every
workspace needs. See [Project setup](./project-setup.md) and
[Hooks](./hooks.md) for the available project configuration.

A project can also add its own `para` verbs as executables under
`.paraspace/commands/<verb>`. See [Commands](./commands.md) for how project
commands work.

The `dotfiles` mod provides `para claude`. Add it to a project with:

```sh
para mod add dotfiles
```

The mod supplies that command rather than the `para` engine.

## Next

- [Install ParaSpace](./install.md) to set up your machine
- [How it works](./how-it-works.md) for the architecture
- [Running coding agents](./agents.md) for the workflow
- [Prior art](./prior-art.md) for the alternatives

[hn]: https://news.ycombinator.com/item?id=48892468