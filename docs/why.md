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

| The usual escape | What it fixes | What it leaves |
|---|---|---|
| A worktree per agent | the tracked files | no `.gitignore`d state, so every worktree needs its `.env` and data recreated; the running stacks still collide on ports and databases; and the agent still runs **as you, on your host** |
| Port offsets and override files | the port collisions | the same host, the same keys, the same filesystem — plus a growing pile of per-agent config to keep straight |
| A devcontainer per branch | the toolchain | spawning them per branch, [which is exactly what you want for parallel agent work][perevillega], is where they get painful |
| A VM per workspace | isolation, cleanly | fixed RAM and CPU reserved per VM; a laptop affords two or three |
| Cloud sandboxes and hosted dev environments | isolation, elastically | a metered bill while your own machine idles — and the interface is part of the price (below) |

The tell is that people who do this seriously end up stacking them —
[Mike McQuaid's 2026 setup][mikemcquaid] is worktrees *plus* a macOS sandbox
*plus* an orchestrator, assembled by hand. Worktrees are the checkout half of
the problem; the sandbox is the other half. Almost nothing ships both.

`para` ships both. Each workspace is an unprivileged [Incus] **system**
container — isolated like a VM, with no fixed reservation, and containers still
run *inside* it, so a Docker stack boots unchanged.

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

That's `su --pty` inside the container, with SIGWINCH forwarded and a `$TERM`
the container has terminfo for — so tmux, Neovim and Claude Code behave the way
they do in any terminal, because they are in one. Your dotfiles get there
through a `skel/` directory your own hooks copy in.

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
anyone configuring them, and why most stacks boot unchanged on the first
attempt. Routes are one line of your [`Parafile`](./parafile.md#para_routes).

### A thin engine your project takes over

`para` is about a thousand lines of bash over `incus` and `caddy`: it makes a
container, gives it an IP, attaches a volume, points Caddy at it, and runs your
hooks. It knows nothing about your stack. The extension points are all files in
*your* repo:

| What | Where it lives |
|---|---|
| how the base image is built | `.paraspace/image-build.sh` |
| how a workspace is provisioned | `.paraspace/hooks/provision` |
| how the stack boots, and when it's ready | `.paraspace/hooks/boot` |
| **new `para` verbs** | `.paraspace/commands/<verb>` |

That last row matters most. `para claude ws1` is not a feature of para — it's a
file a template ships:

```sh
#!/usr/bin/env bash
exec "$PARA_BIN" sh "$1" -c "exec claude --name $1"
```

So the answer to "can para do X for my project" is that your project can.

## What it isn't

- **A hosted service.** Workspaces run on your hardware — no control plane,
  nothing to log into, and Linux or macOS only (macOS runs Incus in a Colima
  VM). Base images are per-arch: build on the machine that runs them.
- **A boundary against hostile code.** It's a strong boundary against an agent
  doing something dumb or a dependency doing something rude — not a claim that
  container escape is impossible.
- **A git workflow.** Each workspace gets its own clone; branching, review and
  merge stay exactly what they were.

## Next

[Getting started](./getting-started.md) to launch one ·
[How it works](./how-it-works.md) for the architecture ·
[Running coding agents](./agents.md) for the practice.

[Incus]: https://linuxcontainers.org/incus/
[perevillega]: https://perevillega.com/posts/2026-03-03-ai-sandbox-coding-agents/
[mikemcquaid]: https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/
[hn]: https://news.ycombinator.com/item?id=48892468
