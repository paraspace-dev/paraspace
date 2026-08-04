# Why ParaSpace

Running parallel coding agent tasks on a project *and* not having to babysit
them are the same problem: each agent needs somewhere to work that is neither
your working copy nor your host.

## The problem

Point two agents at the same project directory and they will interfere with
each other. Branches change underneath them, edits conflict or contaminate
context, and the resulting mixed diff must be separated into individual PRs
afterward. Letting one agent reconfigure the underlying stack is even riskier.

Giving each agent a real place to work eliminates that entire class of
problems. Assembling that place is harder than it sounds.

- A worktree separates files, but not the running stack.
- Port offsets avoid collisions, but quickly become confusing, still run on
  your host, and require parameterizing the stack.
- Devcontainers can work, but lack the surrounding lifecycle management and tie
  you to Docker's runtime and configuration model.
- A VM per task reserves RAM whether it is busy or not.
- Cloud sandboxes bill by the second while your own machine sits idle.
- Coder complicates routing and pushes you toward a web-based agent harness.

[Prior art](./prior-art.md) covers each option in detail, including when you
should choose one instead of ParaSpace.

## The solution

ParaSpace starts from one choice, that a workspace is an unprivileged system
container on your own machine.

Everything else follows from that.

### Reserve nothing

A workspace is a container, not a virtual machine. It shares your kernel and
does not reserve a large block of resources up front. At idle, it costs almost
nothing. Under load, it draws from the same resource pool as everything else.

That is what makes it practical to run a dozen ParaSpace workspaces at once,
even on modest hardware. On macOS, the underlying Linux VM is reserved once for
the machine, not once per workspace. [How it
works](./how-it-works.md#macos-adds-one-layer) explains that layer.

Because it is a _system_ container, a workspace can also run containers of its
own. A Docker stack boots inside it on an independent Docker daemon, without
mounting the host socket or using `--privileged`. One kernel serves every
layer.

[Prior art](./prior-art.md#on-nested-containers) covers the mechanics.

### It runs on your machine, in a real terminal

Many "agent in a sandbox" products put the agent TUI in an iframe, the
application in another tab, and a web terminal in a third, with a proxy chain
behind all of them. You pay for the isolation in browser friction. TUIs
misbehave outside a real terminal, and live reload often breaks across the
proxies.

A ParaSpace workspace is a container on your own machine, so you enter it
normally:

```sh
para sh my-feature   # a real PTY in the clone
```

The workspace has a `$TERM` with matching terminfo, so tmux, Neovim, and Claude
Code behave as they do in any other terminal, because they are in one. Your
dotfiles arrive through a `skel/` directory copied by your own hooks.

Parallel work becomes a window-manager problem instead of a tab-management
problem. Put one workspace on each desktop and switch between them with the
keybindings you already use.

### An agent cannot reach your host

You can disable permission prompts because the blast radius ends at the
workspace.

Inside each workspace:

- it runs as an **unprivileged** container;
- **nothing from your host is mounted**. `para` pushes only your `.paraspace/`
  directory and, optionally, one `.env` file;
- your home directory, SSH keys, and cloud credentials are not available to
  read;
- the workspace is disposable: `para rm my-feature` removes the whole
  environment.

That means [an agent uploading a home directory][hn] cannot happen here. There
is no mounted home directory to upload.

> [!NOTE]
> Workspaces have ordinary outbound network access. Incus ACLs can be used
> when you need egress restrictions.

### Authenticate once per project

Run `gh auth login` in any workspace and every workspace for that project
becomes authenticated, including workspaces created later and workspaces
restarted after a reboot.

Credentials live on a [shared volume](./internals.md#the-shared-home-volume)
attached to the project's workspaces. They remain on the container side of the
boundary rather than entering through a host bind mount.

### Automatic subdomain routing

Every workspace receives its own bridge IP, so each stack can bind its **usual
ports**.

Port 3000 remains port 3000 in every workspace. There are no offsets, override
files, or sandbox-specific settings in your application configuration.

Caddy runs on the host and maps workspace subdomains to the ports you expose:

```text
https://my-feature.paraspace.dev     →  10.x.x.201:3000
https://db.my-feature.paraspace.dev  →  10.x.x.201:8081
```

Nothing is port-remapped or path-rewritten. There is no `X-Forwarded-Prefix`
for the application to understand. WebSockets and hot reload work without
application-specific proxy configuration.

Your stack runs unchanged inside the workspace, on the ports it already uses,
whether it consists of one process or a dozen containers. Each route is one
line in your [`Parafile`](./parafile.md).

### A thin engine your project takes over

`para` is a thin wrapper around `incus` and `caddy`. It creates a container,
assigns an IP, attaches a volume, configures Caddy, and runs your hooks.

It knows nothing about your stack.

Every extension point lives in _your_ repository:

| What                                       | Where it lives                 |
| ------------------------------------------ | ------------------------------ |
| How the base image is built                | `.paraspace/hooks/image-build` |
| How a workspace is provisioned             | `.paraspace/hooks/provision`   |
| How the stack starts and reports readiness | `.paraspace/hooks/boot`        |
| **New `para` verbs**                       | `.paraspace/commands/<verb>`   |

`para claude ws1` is not a built-in ParaSpace feature. It is a project command
you add under `.paraspace/commands/`. For example:

```sh
#!/usr/bin/env bash
exec "$PARA_BIN" sh "$1" -c "exec claude --name $1"
```

When your project needs `para` to do something new, you add that behavior to
the project itself.

## What it is not

- **A hosted service.** Workspaces run on your hardware, on Linux or macOS.
  There is no control plane and nothing to log into.
- **A security boundary for hostile code.** It is a strong boundary against an
  agent making a mistake or a dependency behaving badly, but it does not claim
  that container escape is impossible.
- **A Git workflow.** Each workspace receives its own clone. Branching, review,
  and merge remain unchanged.

See [Prior art](./prior-art.md) for a comparison with the alternatives.

## Next

[Install ParaSpace](./install.md) to set up your machine · [How it
works](./how-it-works.md) for the architecture · [Running coding
agents](./agents.md) for the workflow · [Prior art](./prior-art.md) for the
alternatives

[hn]: https://news.ycombinator.com/item?id=48892468
