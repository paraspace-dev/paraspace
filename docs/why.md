# Why ParaSpace

Running `n` coding agents on your project in parallel and not having to babysit
them turn out to be the same problem. An agent needs somewhere to work that is
neither your working copy nor your host.

## The problem

You can naively point two agents at one project directory, but they will trip
over each other. Branches change underneath, changes conflict or pollute the
other's context, and the mixed diff has to be teased apart into separate PRs
afterward. Forget about having one agent reconfigure the underlying stack.

If you give each agent a real place to work, that whole class of problem goes
away, but a real place to work is harder to assemble than it sounds.

A worktree separates the files but not the running stack. Port offsets
deconflict the ports, but it gets confusing, runs on your host, and requires
parameterizing your stack's configuration. Devcontainers can work, but lack the
surrounding lifecycle management, and tie you to the Docker runtime /
configuration language. A VM per task reserves its RAM whether it's busy or
not. Cloud sandboxes bill by the second while your own machine idles. Coder has
you using a clunky web-based agent harness and complicates routing.
[Prior art](./prior-art.md) covers each properly, including when you should
pick one over `para`.

## The solution

ParaSpace answers all of it with one choice. A workspace is an unprivileged
system container on your own machine, and everything below follows from that.

### Reserve nothing

A workspace is a container, not a virtual machine. It shares your kernel and
doesn't need to reserve large chunks of resources up front. At idle, it costs
almost nothing. When busy, it borrows from the same pool as everything else.
That is what makes a dozen ParaSpace workspaces running at once possible even
on modest hardware. On macOS the Linux VM underneath reserves once for the
whole machine, not once per workspace.
[How it works](./how-it-works.md#macos-adds-one-layer) covers that layer.

It is a *system* container, so it can hold containers of its own. A Docker
stack can boot inside it on its own Docker daemon, with no host socket and no
`--privileged`. Your one kernel serves every layer.
[Prior art](./prior-art.md#on-nested-containers) has the mechanics.

### It runs on your machine, in a real terminal

Most "agents in a sandbox" products put the agent's TUI in an iframe, your app
in a second tab and a web terminal in a third, with a proxy chain behind all of
them. You pay for that isolation in the browser, where TUIs misbehave outside a
real terminal and live reload rarely survives the proxies.

A ParaSpace workspace is a container on your own box, so you reach it the
ordinary way:

```sh
para sh my-feature   # a real pty in the clone
```

It comes with a `$TERM` the container has terminfo for, so tmux, Neovim and
Claude Code behave the way they do in any terminal, because they are in one.
Your dotfiles get there through a `skel/` directory your own hooks copy in.

So parallel work becomes a window-manager problem rather than a tab-management
one. Put one workspace per desktop and switch between them with the keybindings
you already have.

### An agent can't reach your host

You can turn off permission prompts because the blast radius stops at the
workspace. Inside one:

- it is an **unprivileged** container,
- **nothing of your host is mounted.** para pushes your `.paraspace/` directory
  and, optionally, one `.env`. That is the whole surface, and your home
  directory, SSH keys and cloud credentials aren't there to be read;
- it's disposable: `para rm my-feature` and the whole thing is gone.

So [an agent uploading a home directory][hn] can't happen here, because there
is nothing mounted to upload.

> [!NOTE]
> Workspaces have ordinary outbound network access. If you need network egress
> rules, that can be achieved with Incus ACLs.

### Authenticate once per project

Run `gh auth login` in any workspace and every workspace of that project is
authenticated, including the one you create next week, and after a reboot.
Credentials live on a [volume](./internals.md#the-shared-home-volume) shared by
the project's workspaces, on the container side of the boundary, not a host
bind mount.

### Automatic subdomain routing

Every workspace gets its own bridge IP, so your stack binds its **usual ports**
on it. Port 3000 is port 3000 in every workspace, with no offsets, no override
files, and nothing in your stack's config that knows it's being sandboxed.
Caddy runs on your host and its entire job is to map workspace subdomains to
each port you want to access, e.g.:

```
https://my-feature.paraspace.dev     →  10.x.x.201:3000
https://db.my-feature.paraspace.dev  →  10.x.x.201:8081
```

Nothing is remapped or path-rewritten, and there's no `X-Forwarded-Prefix` your
app has to learn about, which is why WebSockets and hot reload work without
anyone configuring them. Your stack runs *inside* the workspace, unchanged, on
the ports it already uses, whether that's a single process or a dozen
containers. Routes are one line of your [`Parafile`](./parafile.md).

### A thin engine your project takes over

`para` is simply a thin wrapper over `incus` and `caddy`. It makes a
container, gives it an IP, attaches a volume, points Caddy at it, and runs your
hooks. It knows nothing about your stack. The extension points are all files in
*your* repo:

| What | Where it lives |
|---|---|
| how the base image is built | `.paraspace/hooks/image-build` |
| how a workspace is provisioned | `.paraspace/hooks/provision` |
| how the stack boots, and when it's ready | `.paraspace/hooks/boot` |
| **new `para` verbs** | `.paraspace/commands/<verb>` |

`para claude ws1` is not a feature of para. It's a command you drop in
`.paraspace/commands/`, and no bundled template ships one.

```sh
#!/usr/bin/env bash
exec "$PARA_BIN" sh "$1" -c "exec claude --name $1"
```

So whatever you need para to do for your project, your project is where you add
it.

## What it isn't

- **A hosted service.** Workspaces run on your hardware, on Linux or macOS.
  There is no control plane and nothing to log into.
- **A boundary against hostile code.** It's a strong boundary against an agent
  doing something dumb or a dependency doing something rude, but not a claim
  that container escape is impossible.
- **A git workflow.** Each workspace gets its own clone; branching, review and
  merge stay exactly what they were.

See [Prior art](./prior-art.md) for a comparison of alternatives.

## Next

[Getting started](./getting-started.md) to launch one ·
[How it works](./how-it-works.md) for the architecture ·
[Running coding agents](./agents.md) for the practice ·
[Prior art](./prior-art.md) for the alternatives.

[hn]: https://news.ycombinator.com/item?id=48892468
