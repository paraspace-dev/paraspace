# Prior art

Isolated-workspace-per-task is a crowded idea. This page is where `para` sits
among the alternatives, and — more usefully — which of them you should pick
instead.

> This is a categorisation, not a feature audit. The space moves fast and these
> tools change; check current docs before deciding on the strength of a row.

## The approaches

### A worktree per task

`git worktree` gives each task its own checkout sharing one object database.

Free, instant, and the right answer when your work is *only* editing files. It
doesn't carry `.gitignore`d state, so each worktree needs its `.env` and its
data recreated; running stacks still collide on ports and databases; and
whatever runs there runs as you, on your host, with your keys in reach.

The tell is that people who use worktrees for agent work end up stacking
something else on top — [Mike McQuaid's setup][mikemcquaid] is worktrees plus a
macOS sandbox plus an orchestrator.

### Port offsets and compose overrides

Deconflict the ports and you can run two stacks at once. It works, and it costs
you a growing pile of per-task configuration that every contributor has to
understand — plus it solves nothing about isolation.

### A devcontainer per branch

[Dev Containers](https://containers.dev/) give you a reproducible toolchain per
repo, and every major editor speaks the format. Reach for one if a consistent
toolchain is the problem you actually have.

Spawning them per branch — which is exactly what parallel agent work needs — is
[where they get awkward][perevillega]: the spec is built around one container
per repo, not N live at once, and Docker's shared-kernel isolation is weaker
than it looks when the point is to let something untrusted run wild.

### A VM per task

Lima, Multipass, Vagrant, or plain QEMU. The strongest isolation on this page,
and genuinely the right call if you're running something you actively distrust.
The cost is that each VM reserves its RAM and CPU whether or not it's busy, so
a laptop affords two or three.

### Cloud development environments

[Coder](https://coder.com/) (self-hosted, Terraform-defined workspaces) and
[Gitpod](https://www.gitpod.io/) / [GitHub
Codespaces](https://github.com/features/codespaces) (hosted). Built for teams:
central policy, provisioned identically for everyone, reachable from a
Chromebook.

If you need governance across an organisation, use one of these — `para` has no
control plane and no notion of a team. What you pay is a bill that runs while
your own machine idles, and an interface mediated by a browser or a remote-IDE
tunnel.

### Agent sandbox services

[Daytona](https://www.daytona.io/), [E2B](https://e2b.dev/),
[Modal](https://modal.com/), [Northflank](https://northflank.com/) and
[Docker's `sbx`](https://www.docker.com/) target the newer shape: ephemeral
sandboxes an agent drives through an SDK, sold per second.

The right tool when the *agent* is the product — when code runs on behalf of
your users and has to be someone else's liability. Overkill when the agent is
just you, working on your own repo, on hardware you already own.

## Where para sits

| | Runs on | Isolation | Interface | URL per workspace | Recurring cost |
|---|---|---|---|---|---|
| Worktrees | your machine | none | native | no | none |
| Devcontainer per branch | your machine | OCI container | editor-attached | manual | none |
| VM per task | your machine | full VM | native | manual | none |
| Cloud dev environments | vendor or your servers | container or VM | browser / remote IDE | yes | per hour |
| Agent sandbox services | vendor cloud | container or microVM | SDK / API | varies | per second |
| **para** | your machine | unprivileged system container | **native terminal** | **yes, automatic** | none |

The row that isn't in the table is the one that motivated `para`: a **system**
container is a middle point most of these skip. It behaves like a VM — its own
init, its own network stack, nested Docker works — without reserving fixed
memory, so a dozen at once is unremarkable on a laptop. See
[How it works](./how-it-works.md).

## Closest in spirit

Two personal setups arrived at nearly the same design independently, and both
are worth reading:

- **[sandbox-claude][perevillega]** — Incus system containers, per-container
  deploy keys, network egress filtering, tmux for parallelism. The nearest
  neighbour to `para`, and it does egress filtering, which `para` doesn't.
- **[Sandvault + Superset][mikemcquaid]** — the macOS answer: an unprivileged
  user account per agent, over git worktrees, with an orchestrator on top.

## When not to use para

- **You need a browser to reach it.** para deliberately has no web UI. If
  you're working from an iPad, use a cloud dev environment.
- **You need team governance.** No control plane, no roles, no audit log.
- **You're running genuinely hostile code.** An unprivileged container is a
  strong boundary against mistakes, not a claim that escape is impossible. Use
  a VM or a vendor's microVM sandbox.
- **You're not on Linux or macOS.** Incus needs a Linux kernel; macOS gets one
  via Colima.
- **Your laptop is already full.** Workspaces are cheap, not free — each one
  runs your whole stack.

[perevillega]: https://perevillega.com/posts/2026-03-03-ai-sandbox-coding-agents/
[mikemcquaid]: https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/
