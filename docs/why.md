# Why ParaSpace

Running several coding agents at once and not having to babysit them turn out
to be the same problem: an agent needs somewhere to work that is neither your
working copy nor your host.

## The problem

Point two agents at one checkout and they trip over each other: branches change
underneath, half-finished edits land in each other's context, and the mixed
diff has to be teased apart into separate PRs afterward. Give each agent a real
place to work and that whole class of problem goes away — but "a real place to
work" is harder to assemble than it sounds.

A worktree separates the files but not the running stack, and the agent still
runs as you. Port offsets deconflict the ports and nothing else. Devcontainers
get awkward spawned per branch. A VM per task reserves its RAM whether it's
busy or not. Cloud sandboxes bill by the second while your own machine idles.
[Prior art](./prior-art.md) covers each properly, including when you should
pick one over `para`.

## What you get

### It runs on your machine, in a real terminal

The common shape for "agents in a sandbox" is a browser tab: the agent's TUI in
an iframe, your app in another tab, a web terminal in a third, a proxy chain
behind all of it. That shape is part of what you pay for the isolation: TUIs
misbehave outside a real terminal, and live reload rarely survives the proxies.

para inverts it. The workspace is a container on your own box:

```sh
para sh my-feature        # a real pty in the clone
```

It comes with a `$TERM` the container has terminfo for, so tmux, Neovim and
Claude Code behave the way they do in any terminal — because they are in one.
Your dotfiles get there through a `skel/` directory your own hooks copy in.

So parallel work becomes a window-manager problem rather than a tab-management
one: one workspace per desktop, navigated with the keybindings you already have.

### An agent can't reach your host

You can turn off permission prompts because the blast radius stops at the
workspace. Inside one:

- it is an **unprivileged** container — root inside is an unprivileged uid
  outside;
- **nothing of your host is mounted.** para pushes your `.paraspace/` directory
  and, optionally, one `.env` — that's the whole surface. Your home directory,
  SSH keys and cloud credentials aren't there to be read;
- it's disposable: `para rm my-feature` and the whole thing is gone.

So [an agent uploading a home directory][hn] can't happen here — there is
nothing mounted to upload.

**What it doesn't isolate:** the workspace has ordinary outbound network
access, and it mounts the shared volume holding the git key you authorized. An
agent can reach the internet and push to the repositories that key allows. para
does no egress filtering — if you need it, that's an Incus network ACL, not a
para setting.

### Authenticate once per project

Run `gh auth login` in any workspace and every workspace of that project is
authenticated — including the one you create next week, and after a reboot.
Credentials live on a [volume](./internals.md#the-shared-home-volume) shared by
the project's workspaces — on the container side of the boundary, not a host
bind mount.

Re-authenticating each new sandbox is what makes people stop at two.

### Caddy sits at the doorway, not in your stack

Every workspace gets its own bridge IP, so your stack binds its **usual ports**
on it. Port 3000 is port 3000 in every workspace — no offsets, no override
files, no compose config that knows it's being sandboxed. Caddy's entire job is
to map one hostname to one address:

```
https://my-feature.paraspace.dev  →  10.x.x.201:3000
```

Nothing is remapped or path-rewritten, and there's no `X-Forwarded-Prefix` your
app has to learn about — which is why WebSockets and hot reload work without
anyone configuring them. Your Compose stack runs *inside* the workspace,
unchanged, on the ports it already uses. Routes are one line of your
[`Parafile`](./parafile.md).

### A thin engine your project takes over

`para` is simply a thin wrapper over `incus` and `caddy`: it makes a
container, gives it an IP, attaches a volume, points Caddy at it, and runs your
hooks. It knows nothing about your stack. The extension points are all files in
*your* repo:

| What | Where it lives |
|---|---|
| how the base image is built | `.paraspace/hooks/image-build` |
| how a workspace is provisioned | `.paraspace/hooks/provision` |
| how the stack boots, and when it's ready | `.paraspace/hooks/boot` |
| **new `para` verbs** | `.paraspace/commands/<verb>` |

`para claude ws1` is not a feature of para — it's a command you drop in
`.paraspace/commands/`, and no bundled template ships one.

```sh
#!/usr/bin/env bash
exec "$PARA_BIN" sh "$1" -c "exec claude --name $1"
```

So the answer to "can para do X for my project" is that your project can.

## What it isn't

- **A hosted service.** Workspaces run on your hardware, on Linux or macOS.
  There is no control plane and nothing to log into.
- **A boundary against hostile code.** It's a strong boundary against an agent
  doing something dumb or a dependency doing something rude — not a claim that
  container escape is impossible.
- **A git workflow.** Each workspace gets its own clone; branching, review and
  merge stay exactly what they were.

See [Prior art](./prior-art.md) for a comparison of alternatives.

## Next

[Getting started](./getting-started.md) to launch one ·
[How it works](./how-it-works.md) for the architecture ·
[Running coding agents](./agents.md) for the practice ·
[Prior art](./prior-art.md) for the alternatives.

[hn]: https://news.ycombinator.com/item?id=48892468
