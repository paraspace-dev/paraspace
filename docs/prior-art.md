# Prior art

Isolated-workspace-per-task is a crowded idea, and it got more crowded during
2026. This page is where ParaSpace sits among the alternatives, and, more
usefully, which of them you should pick instead.

> Descriptions here come from each project's own docs at the time of writing.
> This is a categorisation, not a feature audit. The space moves fast, so check
> current docs before deciding on the strength of a row.

## The general approaches

### A worktree per task

`git worktree` gives each task its own checkout sharing one object database.
**[par](https://github.com/coplane/par)** is this approach made ergonomic, with
a worktree plus a persistent tmux session per task, and a `.par.yaml` that
copies the gitignored files into each new one. No relation to ParaSpace, despite
the name.

Free, instant, and the right answer when your work is *only* editing files. It
doesn't carry `.gitignore`d state, so each worktree needs its `.env` and its
data recreated; running stacks still collide on ports and databases; and
whatever runs there runs as you, on your host, with your keys in reach.

### Port offsets and compose overrides

Deconflict the ports and you can run two stacks at once. It works, at the cost
of a growing pile of per-task configuration that every contributor has to
understand, and it solves nothing about isolation.

### A devcontainer per branch

[Dev Containers](https://containers.dev/) give you a reproducible toolchain per
repo, and every major editor speaks the format. Reach for one if a consistent
toolchain is the problem you actually have.

Spawning them per branch, which is what parallel agent work needs, is
[where they get awkward][perevillega], because the spec is built around one
container per repo rather than N live at once.

### A VM per task

Lima, Multipass, Vagrant, or plain QEMU. The strongest isolation on this page,
and genuinely the right call if you're running something you actively distrust.
The cost is that each VM reserves its RAM and CPU whether or not it's busy, so
a laptop affords two or three.

### Cloud development environments

[Coder](https://coder.com/) (self-hosted, Terraform-defined workspaces) and
[Gitpod](https://www.gitpod.io/) / [GitHub
Codespaces](https://github.com/features/codespaces) (hosted). Built for teams,
with central policy, identical provisioning for everyone, and access from a
Chromebook.

If you need governance across an organisation, use one of these, because
ParaSpace has no control plane and no notion of a team. What you pay is a bill
that runs while your own machine idles, and an interface mediated by a browser
or a remote-IDE tunnel.

### Agent sandbox services

[Daytona](https://www.daytona.io/), [E2B](https://e2b.dev/),
[Modal](https://modal.com/), [Northflank](https://northflank.com/) and
[Docker's `sbx`](https://www.docker.com/) target the newer shape of ephemeral
sandboxes an agent drives through an SDK, sold per second.

The right tool when the *agent* is the product, when code runs on behalf of
your users and has to be someone else's liability. Overkill when the agent is
just you, working on your own repo, on hardware you already own.

## Tools that combine checkout and runtime isolation

This is ParaSpace's actual peer group, local tools that give each task both its
own files and its own place to run them.

- **[Container Use](https://github.com/dagger/container-use)** (Dagger) calls
  itself "containerized environments for coding agents". A fresh container per
  agent on its own git branch, driven as an MCP server plus a CLI, with terminal
  attach into any environment. Agent-driven by design, and built on application
  containers rather than system containers.
- **[Sculptor](https://github.com/imbue-ai/sculptor)** (Imbue) gives you
  isolated worktrees with a Docker container backend, a workspace terminal,
  multi-agent management and diff/PR review. A desktop application rather than a
  terminal-first substrate; its own docs call it an experimental research
  preview.
- **[Agent of Empires](https://github.com/agent-of-empires/agent-of-empires)**
  runs parallel agents in git worktrees with per-agent Docker, Podman or Apple
  Container sandboxing, shared authentication volumes, project hooks, custom
  launchers, and TUI and web dashboards. The closest in feature surface to the
  list below.
- **[Code on Incus](https://github.com/mensfeld/code-on-incus)** is the closest
  technically, an Incus **system** container per agent with root, systemd and
  Docker, and host credentials kept out unless explicitly mounted. It mounts
  your project directory from the host rather than cloning inside, publishes
  services to `localhost:<port>` rather than routing hostnames, and is oriented
  around agent security (it ships active threat detection, which ParaSpace does
  not).
- **[Coasts](https://github.com/jsx-tool/coasts)** gives you worktree-aware
  local environments, each with an isolated runtime and its own Docker daemon,
  letting an existing Compose stack run unchanged. It normally shares the
  worktree filesystem from the host and expects the agent to run on the host, so
  it isolates the *application* runtime more than it isolates the agent.

Two personal setups arrived at similar designs and are worth reading:
**[sandbox-claude][perevillega]** (Incus system containers, per-container deploy
keys, and network egress filtering, which ParaSpace doesn't do) and
**[Sandvault + Superset][mikemcquaid]** (an unprivileged macOS user account per
agent, over git worktrees, with an orchestrator on top).

## Where ParaSpace sits

✅ yes · ⚠️ partial, or with caveats · ❌ no · ❓ not documented

| | Isolation unit | Workspace files | Nests unprivileged | Interface | Per-workspace URL |
|---|---|---|---|---|---|
| par | none (host processes) | worktree | n/a (host Docker) | CLI + tmux | ❌ |
| Container Use | app container | branch per env | ❓ | MCP + CLI | ❌ |
| Sculptor | container backend | worktree | ❓ | desktop app | ⚠️ in-app |
| Agent of Empires | Docker / Podman / Apple Container | worktree | ❓ | TUI + web | ⚠️ in-app |
| Code on Incus | system container | host bind mount | ✅ | CLI | ⚠️ `localhost:<port>` |
| Coasts | runtime + own Docker daemon | host worktree | ❓ own daemon per env | CLI | ⚠️ per-env ports |
| **ParaSpace** | system container | clone inside | ✅ | native terminal | ✅ stable hostname |

"Nests unprivileged" means route 3 below, a nested daemon that costs neither the
host socket nor `--privileged`. Plenty of these run containers inside a
workspace; that column is about what it costs you.

The emoji columns are the ones with a real yes/no. The rest describe *how*, and
the "how" is usually what decides it.

### On nested containers

Running containers *inside* the isolated workspace is the thing most of these
have to solve, and how they solve it matters more than whether they do. There
are three routes:

1. **Mount the host's Docker socket.** Easy, and it hands whatever is in the
   container control of the *host* daemon, which can start a privileged
   container mounting `/`. Convenient for a devcontainer you trust; not a
   boundary you'd let an agent run wild behind.
2. **A privileged container running its own daemon.** Real nesting, but
   `--privileged` gives up most of what the container was doing for you.
3. **A runtime built for nesting.** Sysbox (which Daytona uses), a VM, or an
   **unprivileged system container**, the Incus route ParaSpace and Code on
   Incus take.

`para up` launches each workspace with `security.nesting=true` on an
unprivileged container, with no host socket, no `--privileged`, and a real
Docker daemon inside. The workspace's root is an unprivileged uid on your host,
so what the nested containers ask for stops mattering. Even a `docker run
--privileged` in there is still bounded by the workspace's user namespace.

The workspace also owns its network namespace and a bridge IP, so the nested
daemon's bridge and every port it binds stay inside the workspace. Nothing is
published to the host and nothing is remapped, which is why a Compose file
written for your laptop boots unchanged, and why the storage-driver question in
[Troubleshooting](./troubleshooting.md#everything-inside-the-workspace-is-slow)
exists at all, since nesting is doing real work.

## What's actually distinct

No single row above is unique to ParaSpace. The combination is unusual:

- local and terminal-first, with no bundled agent UI;
- a complete clone **inside** an unprivileged system container;
- no project or home-directory bind mount from the host;
- nested Docker and Compose work unchanged, without a host socket or
  `--privileged`;
- ordinary port numbers (3000 is 3000 in every workspace);
- automatic per-workspace hostname routing through Caddy;
- persistent, project-scoped shared credentials;
- provisioning, boot and new `para` verbs all owned by files in your repo;
- no prescribed git workflow.

If what you want is an agent harness with a UI and a review flow, several of
the tools above will suit you better. ParaSpace is the isolated machine, and
leaves the workflow to you.

## When not to use ParaSpace

- **You need a browser to reach it.** ParaSpace deliberately has no web UI. If
  you're working from an iPad, use a cloud dev environment.
- **You need team governance.** No control plane, no roles, no audit log.
- **You want the agent workflow bundled.** Review UI, diff view and PR
  orchestration are what Sculptor and Agent of Empires ship; ParaSpace doesn't.
- **You're running genuinely hostile code.** An unprivileged container is a
  strong boundary against mistakes, not a claim that escape is impossible. Use
  a VM or a vendor's microVM sandbox.
- **You're not on Linux or macOS.** Incus needs a Linux kernel; macOS gets one
  via Colima.
- **Your laptop is already full.** Workspaces are cheap but not free, because
  each one runs your whole stack.

[perevillega]: https://perevillega.com/posts/2026-03-03-ai-sandbox-coding-agents/
[mikemcquaid]: https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/
