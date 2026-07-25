# The docs rewrite: make the case, then get out of the way

Status: **approved, in progress** — decisions taken below. Companion to
[`minimal-engine.md`](./minimal-engine.md) — its step 3 ("docs pass"), scoped up
from "update the stale bits" to the same kind of rewrite the engine got.
Contract 2 **has shipped**: `bin/para` is the 1,079-line rewrite, the templates
are migrated, `.paraspace/commands/` exists. The docs are the last thing left
describing contract 1.

## The goal

The docs have the engine's old problem. `bin/para` read like a compliance
document; `docs/parafile.md` reads like the same document with the code
removed — 308 lines, of which ~120 explain *why the validation is written the
way it is* for validation contract 2 deletes. `docs/versioning.md` is 135 lines
of pre-launch decision log: a changelog for a contract version that no longer
exists, published as a spec.

Meanwhile the one thing a reader arrives wanting — *why would I run this
instead of a worktree, a devcontainer, or a cloud sandbox?* — is four bullets
under `## The problem` on a page called "How it works," and the page never gets
around to answering them. The lander carries the argument the docs don't.

The target is the same as the engine's: **habitability.** Four rules.

1. **Write for the reader's job, not the code's shape.** A page exists to get
   someone unstuck. If a paragraph's grammatical subject is `para`, try
   rewriting it with the reader as the subject and see if it survives.
2. **Document behavior, not the reasoning that produced it.** Rationale for a
   design decision belongs in `plans/`. A reference page says what the key
   does, what it defaults to, and what breaks if you get it wrong.
3. **One home per fact.** Routes are currently explained in four places
   (`parafile`, `hooks`, `versioning`, `urls`) and they disagree. Every fact
   gets one page; everywhere else links to it.
4. **Say what it costs.** Where para is worse than the alternative, say so on
   the page where it bites, not in a "Limitations" ghetto nobody reads.

Structural gates, the equivalent of "no function over 30 lines": **no page over
150 lines**, and **every `##` names a task or a thing, never a mechanism.**
A page that wants to explain why the code is written that way is a `plans/`
entry with a one-line pointer.

## The missing page: the case for para

This is the substance of the rewrite. Everything else is cleanup.

The problem statement we have is good and mostly survives. What's missing is
the turn: after "here's why the alternatives fall short," the page goes
straight to an ASCII diagram. The reader is never told what they *get*.

### `## The problem` — sharpen, don't rewrite

Two agents in one working copy trip over each other. Current escapes, re-cut so
each one names the specific thing it fails to solve:

| Escape | What it fixes | What it leaves |
|---|---|---|
| A worktree per agent | tracked files | no `.gitignore`d state (`.env`, data), stacks still collide on ports and DBs — and the agent still runs **as you, on your host** |
| Port offsets + override files | the port collisions | the same host, the same keys, the same filesystem; and a growing pile of per-agent config |
| A devcontainer per branch | the toolchain | "the moment you start spawning them per branch — which is exactly what you want for parallel agent work — things get painful" ([perevillega]) |
| A VM per workspace | isolation, cleanly | fixed RAM and CPU per VM; a laptop affords two or three |
| Cloud sandboxes / hosted dev envs | isolation, elastically | a metered bill while your machine idles — **and the interface is the price** (see below) |

The tell is [mikemcquaid]'s setup: worktrees *plus* a separate macOS sandbox
*plus* an orchestrator, assembled by hand. Worktrees are the checkout half. The
sandbox is the other half. Nothing ships both.

### `## What you get instead` — the five claims

Five sections, in this order (impact first). Each is a claim the alternatives
can't make, and each maps to a card on the lander.

**1. It's your machine, and it's a real terminal.**

The dominant shape for "agents in a sandbox" is a browser tab: the agent's TUI
in an iframe on the left, the app in another tab, a web terminal in a third,
everything behind a proxy chain. That shape is what you pay for the isolation,
and it's expensive in ways that don't show up on the pricing page — the TUI
scrolls a thousand lines of empty space, selecting an option means switching
input modes, and Vite HMR doesn't survive the proxies.

para inverts it. The workspace is a container on your own box, so:

- `para sh` is a **real pty** — `su --pty` in the container, SIGWINCH
  forwarded, your `$TERM` passed through. tmux, Neovim and Claude Code behave
  the way they do in any terminal, because they're in one.
- your dotfiles are a `skel/` dir your own hooks copy in, so a fresh workspace
  feels like your box from the first prompt;
- one workspace per window-manager desktop is a real workflow — you organize
  parallel work with the WM you already use, not with a tab bar.

The services are cleanly exposed local URLs, not iframes. Nothing is embedded
in anything.

**2. The sandbox is the point: YOLO mode, safely.**

The reason to skip permission prompts is that the blast radius is small enough
not to care. In a para workspace it is:

- an **unprivileged** Incus container — root inside is nobody outside;
- **no host filesystem mounted.** para pushes your `.paraspace/` dir and,
  optionally, one `.env` you name. That's it. Your home dir, your SSH keys,
  your `~/.aws` — not mounted, not reachable, not something the agent has to be
  trusted about;
- disposable: `para rm` and it's gone.

The failure mode people actually worry about — [an agent uploading a home
directory][hn] — isn't mitigated here, it's unreachable. That's the difference
between a policy and a boundary.

**Say the cost, on this page:** the workspace has outbound network, and it has
the project's shared volume, which holds the git key you authorized. An agent
in a workspace can reach the internet and can push to the repos that key
allows. para does not do egress filtering. If you need that, it's an Incus
network ACL, not a para feature.

Frame it with [harness engineering][fowler]: *Agent = Model + Harness.* para is
not the guides or the sensors — it's the **place the harness runs**: a
reproducible workspace with the real stack booted, cheap enough to throw away,
isolated enough to let the agent run unattended inside it.

**3. Authenticate once per project, not once per workspace.**

Run `gh auth login` in any workspace and every workspace of that project is
authenticated — the one you create next week included, and after a reboot. The
credentials live on an Incus custom volume attached to each workspace at
`/para/shared`, not a host bind mount: inside the virtualized filesystem, on
the pool's native driver, so it's fast and it's on the container side of the
boundary.

This is the difference between "N sandboxes" and "a project that has
workspaces." Per-workspace auth is what makes people stop at two.

**4. Caddy sits at the doorway, not inside your stack.**

Every workspace gets its own bridge IP. Your stack binds its **usual ports** on
it — 3000 is 3000 in every workspace, no offsets, no overrides, no compose file
that knows it's being sandboxed. Caddy's entire job is
`https://<name>.<domain>` → that IP:port.

Nothing is remapped, nothing is path-rewritten, no `X-Forwarded-Prefix` your
app has to learn about. Which is why WebSockets and HMR work without anyone
configuring them, and why most stacks boot unchanged on the first try. The URLs
are readable and guessable: `https://fix-login.myapp.dev`.

**5. A thin engine your project takes over.**

~950 lines of bash over `incus` and `caddy`. It knows how to make a container,
give it an IP, attach a volume, point Caddy at it, and run your hooks. It knows
nothing about your stack, and it has no plan to learn.

What that buys you concretely is that the extension points are *files in your
repo*, not options in ours:

| What | Where it lives |
|---|---|
| how the base image is built | `.paraspace/image-build.sh` |
| how a workspace is provisioned | `.paraspace/hooks/provision` |
| how the stack boots + when it's ready | `.paraspace/hooks/boot` |
| **new `para` verbs** | `.paraspace/commands/<verb>` |

That last row is the one to lead with. `para claude ws1` is not a feature of
para — it's three lines a template ships:

```sh
#!/usr/bin/env bash
# summary: claude in the workspace clone
exec "$PARA_BIN" sh "$1" -c "exec claude --name $1"
```

The engine will not grow a `--with-postgres` flag, because the answer to
"can para do X for my project" is that your project can.

[perevillega]: https://perevillega.com/posts/2026-03-03-ai-sandbox-coding-agents/
[mikemcquaid]: https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/
[fowler]: https://martinfowler.com/articles/harness-engineering.html
[hn]: https://news.ycombinator.com/item?id=48892468

## Information architecture

Today's split is Guides / Reference, but "Getting started," "Project setup" and
"How it works" are three different jobs filed together, and there is no page
for the thing the tagline promises (running agents) or the thing the engine
gained (`para doctor`).

Proposed — grouped by **what you're doing**, and the sidebar order is a reading
order:

| Group | Page | Job | now | after |
|---|---|---|--:|--:|
| Start here | `README.md` (Overview) | route the reader to one of three paths | 57 | 45 |
| | `why.md` **new** | the problem and the case | — | 120 |
| | `getting-started.md` | install → first workspace | 58 | 65 |
| | `how-it-works.md` | the architecture, one diagram | 89 | 60 |
| Guides | `agents.md` **new** | running coding agents in workspaces | — | 110 |
| | `project-setup.md` | adding para to a repo | 68 | 70 |
| | `urls.md` | domain, port, certificate trust | 65 | 60 |
| | `git-auth.md` | authorizing the machine key | 29 | 30 |
| | `troubleshooting.md` **new** | `para doctor` and the known failures | — | 110 |
| Reference | `commands.md` | engine verbs + project commands | 93 | 120 |
| | `parafile.md` | every key para reads | 308 | 140 |
| | `hooks.md` | provision/boot + injected env | 77 | 85 |
| | `image.md` | what an image must provide | 114 | 95 |
| | `versioning.md` | the contract rules + v1→v2 | 135 | 45 |
| | `internals.md` | the finer mechanics | 73 | 50 |
| | **total** | | **1166** | **~1205** |

Flat on line count, which is the point: the three new pages are ~340 lines of
net-new value, so the existing thirteen shrink by roughly a quarter. Same trade
the engine made.

Three overlapping "what is this" texts also need one owner each, because they
currently duplicate the install block and quick start verbatim:

- **root `README.md`** — the npm/GitHub funnel. What it is, install, one quick
  start, links to the site. Trim 99 → ~70.
- **`index.md`** — the lander. Six cards, install, quick start.
- **`docs/README.md`** — a router, not a summary. Three named paths ("use a
  repo that has para" / "add para to my repo" / "run agents in parallel"),
  three links each.

## Page by page

**`index.md` (lander).** The cards are close; two carry generic claims where a
specific one is available.

- *A subdomain per workspace* → lead with the doorway point (claim 4). "Caddy
  sits at the doorway, not in your stack. Your app binds its usual ports on the
  workspace's own IP — nothing remapped, nothing rewritten, so WebSockets and
  HMR just work." This differentiator is currently absent from the entire site.
- *Bring your own stack* → say the extensibility out loud (claim 5): "…and
  `.paraspace/commands/` adds your own `para` verbs."
- *A real terminal* → add the WM line; it's the thing terminal users recognize.
- *Made for agents* → currently overlaps *Real isolation*. Make it the fleet:
  N agents, N URLs, one `para ls`.
- Hero alt action: **"Why ParaSpace" → `/docs/why`**, not GitHub (`socialLinks`
  already has GitHub).

**`docs/README.md`.** Becomes the router described above. Drop the templates
section — it duplicates `project-setup.md`.

**`getting-started.md`.** The user-facing shape is right; it needs contract-2
truth and one addition. `para web ws1` is a project command now (say so, in
half a sentence — it's the first place a reader meets the idea). Add the
one-liner that makes the rest of the docs unnecessary on a bad day: *"anything
odd on a fresh machine — run `para doctor`."*

**`why.md` (new).** As drafted above.

**`how-it-works.md`.** Loses `## The problem` to `why.md` and becomes purely
architectural: the diagram, the four bullets (one host Caddy, one container per
workspace, one shared volume per project, hooks do the provisioning), macOS,
"Nothing else runs on the host." ~60 lines, and it finally matches its title.

**`agents.md` (new).** The page the tagline promises. Not the argument — the
practice:

- one workspace per agent; name it after the task, since the name is the URL;
- turning the permission prompts off, and precisely what the blast radius is
  (repeat the boundary here — it's the page where someone acts on it);
- **what is not isolated**: outbound network, and the shared volume's git key;
- driving it — `.paraspace/commands/claude`, `para sh`, a tmux command;
- reviewing — the workspace URL, `para sh <ws> -c 'git diff'`, pushing from
  inside the workspace, and why the diff never mixes with another agent's;
- teardown — `para rm`, and `para ls --all` to find what you forgot.

**`project-setup.md`.** Structurally fine. Contract-2 updates: `~/.para` →
`~/.paraspace`, the `.paraspace/` table gains a `commands/` row, `image-build.sh`
loses "pre-pulled images" (that's `PARA_PREPULL` in the project's own Parafile
now, which the engine never sees — and it's a good one-line illustration of the
boundary), mention `PARA_READY_HOST` where the clone is discussed.

**`commands.md`.** Regroup to mirror `para --help` (WORKSPACES / HOST /
PROJECT) so the two never drift, then a `## Project commands` section — what
they are, how discovery and shadowing work, the summary-comment convention, and
what the templates ship — `key` and `web` in `void-docker-gh`, plus `claude`
and `run` in `void-jchook`, none in `void-minimal` — framed as *examples you
can delete*, not features. That spread is itself the best illustration
available: the same engine, three different verb sets. Keep the `-c`
pty/TTY note — it's real, hard-won knowledge — but at ~12 lines, not 25; the
full table of terminal semantics belongs in `internals.md`.

**`parafile.md`, 308 → 140.** The biggest single win, and almost all of it is
deletion contract 2 already earned:

- the ~40-line `PARA_ROUTES` validation list → *"para doesn't validate routes;
  `caddy validate` does, before every reload, and names the site it rejected."*
- `## Precedence`, both subsections → one paragraph: two sourced bash files,
  user config then Parafile then engine defaults, environment over all of it.
  The per-project-key denylist is gone from the engine; it survives as one
  sentence — *"a project-shaped key in your user config applies to every
  project on the box; `para doctor` warns."*
- the `PARA_USER`/`UID`/`GID` guarantee essay (~20 lines) → 3 lines. The
  build-time uid stamp and the `up`-time drift refusal it describes no longer
  exist.
- each key gets the same four-line shape: what it is, default, who reads it,
  what breaks. New key: `PARA_READY_HOST`.

**`hooks.md`.** `~/.para` → `~/.paraspace` throughout; `PARA_ROUTES` is
space-separated, so the example becomes `for r in $PARA_ROUTES` and the
`parse_routes`/`route_ports` helper references go with the helpers themselves.
Document the guest layout as one table (`hooks/`, `skel/`, `env`, `host.env`)
— it's the clearest thing to have gained a single name. Add `PARA_READY_HOST`
to the injected-env table.

**`image.md`.** Drop `PARA_PREPULL_IMAGES` from the build environment, drop the
`user.para.uid`/`user`/`contract`/`incremental` stamps and the `up`-time
refusal built on them, drop `-q`/`-v`. Add the requirement the rewrite
surfaced: **`su --pty` is util-linux, so a busybox `su` (plain Alpine) fails an
interactive `para sh`.** That belongs in "What the image must have," stated as
a requirement rather than discovered as a bug.

**`urls.md`.** `para config-set PARA_HTTPS_PORT 443` → `$EDITOR "$(para config
path)"`; `para start` → `para caddy start`; the `setcap` line is now what
`para doctor` prints, so lead with doctor and keep the command as the fix.

**`git-auth.md`.** Nearly correct already. `para key` is a project command now.

**`troubleshooting.md` (new).** `para doctor` is the spine: run it first, then
a section per class of failure with what doctor says and what to do —
cgroup-v1 under `/sys/fs/cgroup`, `cap_net_bind_service`, idmapped mounts,
OpenZFS < 2.2, a btrfs/zfs pool silently demoting nested Docker to vfs (the
slowest failure para has), the wildcard not resolving to 127.0.0.1, no image
built, `Permission denied (publickey)`, browser cert distrust, and a workspace
that's `up` but 502s (a boot hook that returned before its service was
listening). This is the ~200 lines of hard-won host knowledge the engine
evicted from the hot path — it must land somewhere or the rewrite loses it.

**`internals.md`.** Delete the registry and `para reconcile` sections outright
and replace with the one-liner that made them unnecessary: *incus is the
database — each container stamps its own project, routes and domain, and
`incus list` queries them as columns.* Update the state table (no `workspaces`
file), drop the `config-set` paragraph, add project-command discovery, and
adopt the terminal-semantics table from the engine plan — it's exactly what
this page is for.

**`versioning.md`, 135 → 45.** Keep: what's covered, the breaking-vs-additive
rule, `PARA_VERSION` pinning and the refusal. Replace the decision log — 100
lines of "why `PARA_CONTRACT` stayed at 1," for a version that no longer exists
— with a **v1 → v2 migration table** a reader can act on. Recommend deleting
the log rather than archiving it: it's pre-launch history with zero external
consumers, and git has it.

## Contract-2 truth checklist

Every stale fact, so the pass can be graded instead of eyeballed. Grep for the
left column.

| Stale | Now |
|---|---|
| `para start` / `para stop` | `para caddy start\|stop\|status` |
| `para config-set KEY VALUE` | `$EDITOR "$(para config path)"`, seeded by `para config init` |
| `para reconcile` | deleted — incus is the database |
| `para run` / `claude` / `web` / `key` / `config-sync` | project commands the template ships |
| `para install`, `para image-build` | deleted |
| `para exec` | never existed; now dies with a pointer to `para sh -c` |
| the registry at `$XDG_STATE_HOME/para/workspaces` | deleted |
| `~/.para` in the guest | `~/.paraspace` |
| `PARA_ROUTES` canonical form is comma-separated | space-separated |
| `parse_routes` / `route_ports` helpers | `for r in $PARA_ROUTES` |
| para validates routes / domain | `caddy validate` does, before every reload |
| per-project keys refused from user config | allowed; `para doctor` advises |
| `PARA_PREPULL_IMAGES` injected into `image-build.sh` | gone; a project's own `PARA_PREPULL`, invisible to the engine |
| image stamps `user.para.uid`/`user`/`contract`/`incremental` | only `user.para.src_sha` |
| `para up` refuses on uid drift | doctor's job |
| `para image build -q` / `-v` | auto-quiet when stderr isn't a tty |
| `--help` reports resolved config | `para doctor` does |
| host preflight inside `up` | `para doctor` |
| — | **new:** `para doctor`, `para commands`, `.paraspace/commands/`, `PARA_READY_HOST`, `~/.paraspace/env` |

## Decisions taken

1. **`why.md` is its own page**, not a `## Why para` h2 on `how-it-works.md`.
   The reader evaluating para and the reader implementing it are different
   people with different questions, and the lander needs a link target for the
   argument — "How it works" doesn't promise one, so nobody evaluating clicks
   it. The one-page alternative also lands at ~180 lines, over the gate.
2. **Project commands are a section of `commands.md`**, not their own page.
   One page keeps "everything `para` can be told to do" in one place (rule 3).
   It is the more prominent idea, but prominence is the lander's job and
   `why.md`'s, not the sidebar's.
3. **The contract-1 decision log is deleted**, not archived. ~100 lines
   explaining why `PARA_CONTRACT` stayed at 1, for a version that no longer
   exists, with zero external consumers who lived through it. Git has it.
4. **Order by value, not by dependency.** `why.md`, `agents.md`,
   `how-it-works.md`, the lander and `docs/README.md` are argument rather than
   contract, so they go first and carry most of the value. The reference pages
   follow, graded against the shipped engine with the truth checklist below.

## Risks

- **A "why" page rots into marketing.** Mitigated by rule 4: every claim in it
  is followed by its cost, on the same page. A section that can't name a cost
  is probably not a real differentiator.
- **The competitive framing dates fast.** The escapes table names categories
  (worktrees, devcontainers, cloud sandboxes), not products, and the three
  outbound links are dated posts — replaceable without touching the argument.
- **Losing the host knowledge.** ~200 lines of preflight left the engine for
  `doctor`; if `troubleshooting.md` isn't written in the same pass, that
  knowledge exists only as terse strings in one bash function. Write it from
  `cmd_doctor` as the checklist, the way the engine was written from the old
  file's comments.
- **`parafile.md` re-inflating.** Every key that grows past four lines is
  either a real design flaw in the key or a rationale that belongs here in
  `plans/`. The 150-line page gate is the tripwire.
