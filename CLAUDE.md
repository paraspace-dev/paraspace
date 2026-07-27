# CLAUDE.md — paraspace

Guidance for Claude Code working in this repo.

## What this is

ParaSpace is the `para` tool: parallel dev workspaces, each an unprivileged
Incus system container with its own clone, Docker stack, bridge IP, and
`https://<name>.<domain>` URL. **It is a standalone, self-contained,
MIT-licensed npm package (`paraspace`)**, published from a `v*` tag by
`.github/workflows/publish.yml`.

The README is the funnel (install, quick start, pointers); `docs/` is the
authoritative spec — the `Parafile` schema (`docs/parafile.md`), the hook +
image contracts (`docs/hooks.md`, `docs/image.md`), the command surface
(`docs/commands.md`), the architecture (`docs/how-it-works.md`), and the case
para makes for itself (`docs/why.md`). Don't duplicate any of that here or in
commit messages; link to it.

## The generic-mechanism boundary

para is a **thin generic mechanism** — the incus/Caddy/volume/lifecycle engine,
like `docker compose`. It bakes in **nothing** about *how* a workspace is
provisioned: the real provision and boot logic lives in a consumer's
`.paraspace/` dir (`Parafile` + `hooks/`), which para runs but never contains.

## Contract version

The para↔project interface is versioned (`PARA_CONTRACT`, currently **1**) — the
`.paraspace/` dir a project ships: its `Parafile`, its `hooks/`, and its
`commands/` (host-side verbs that become `para <verb>`). A **breaking** change to
injected env, the hook names/semantics, the `~/.paraspace` layout in the guest,
or the `Parafile` vars must bump `PARA_CONTRACT`; additive changes don't.
A project pins the contract it targets with the same var in its `Parafile`, and
para refuses on mismatch. If you change the
seam, decide breaking-vs-additive deliberately and update both the constant and
[`docs/versioning.md`](./docs/versioning.md).

## Code + conventions

- **Pure shell.** `bin/para` is one relatively lean bash script (`set -euo
  pipefail`), organized as small helpers + `cmd_*` handlers dispatched from
  `main()`: terse helpers, `log/warn/die/need`, lowercase function names,
  POSIX-ish where practical. It is the minimal-engine rewrite
  ([`plans/minimal-engine.md`](./plans/minimal-engine.md)) that replaced a
  2,244-line predecessor; it is the reference for **House style**, below, and
  new code should read like it.
- **ShellCheck is the static gate**, run via `bin/lint` (or `npm run lint`) — CI
  runs the same on every push/PR. It lints the CLI plus the templates' hooks
  and the `test/` scripts (discovered by shebang). Hook sources
  resolve via `.shellcheckrc` (`source-path`), so prefer that over per-file
  directives. **Run `bin/lint` before finishing any change here** — it's the
  static gate.
- **Behavioral tests live in [`test/`](./test/README.md)** (`test/run`, or
  `npm test`): a CLI tier (no incus, runs in CI) and an e2e tier that drives a
  real Incus workspace off a tiny Alpine fixture and asserts the incus/Caddy/hook/
  volume seams (`up` → hooks → boot readiness → Caddy → the app). It's Docker-free
  by design, so it does not cover the nested-Docker/compose boot path. Run
  `test/run --e2e` after changing the `up`/route/lifecycle mechanism; every run is
  sandboxed from your real workspaces. The e2e tier is **Linux-only** (native
  incus, or a Linux VM on macOS) and **not run in CI** — only the CLI tier is — so
  run it locally and confirm it's green before merging or marking a PR ready.
  Tests are autodiscovered `test_*` functions run in name order, so write them
  **order-independent**; see [`test/README.md`](./test/README.md) for the full
  conventions (tier choice, `|| return 1`, `eventually`, per-workspace asserts).
- The `zsh` `skel/` is intentionally not linted (ShellCheck parses only sh/bash).
- `plans/` holds design notes for in-flight work; not shipped in the npm `files`.

## House style: code a human wrote on purpose

The bar is that someone who knows bash but not para can read any function top to
bottom and be right about what it does. `bin/para` is the reference. The rules
below are not aesthetic preferences — each one is a mess the rewrite cleaned up.

- **Prefer the elegant tool.** Favor designs whose usefulness falls out of a few
  well-chosen primitives.
- **No bash gymnastics.** If a line needs a comment warning you about bash,
  write the line that doesn't need one. A reader should never need a manual for
  the *mechanism* of a line — only, occasionally, for the domain.
- **Comments are domain spec, not bash tutorials.** Three lines is the ceiling,
  and they say *why*, not *what*. Anything longer belongs in `docs/` with a
  one-line pointer. (The predecessor explained single expressions in
  twenty-line comments; that is the smell this rule exists for.)
- **Change the shape instead of adding a guard.** Most defensive checks exist
  because some structure is fragile. Deleting the registry deleted every "an
  empty field would shift the parse" guard with it; moving the guest's context
  into a file it reads itself deleted the argument-injection guard and the regex
  behind it. Before writing a check, ask what shape makes it unnecessary.
- **Let the tool do its job.** `caddy validate` validates routes; incus rejects
  bad names with a clear message. Re-implementing a downstream tool's checks
  costs lines *and* drifts from what the tool actually accepts — surface its
  error instead.
- **One way to do each thing.** One door into a workspace (`ws_exec`), one
  env-forwarding rule (`para_env`), one place that knows about Caddy. A second
  spelling of an existing idea is a defect even when it works.
- **`if` beats `A && B || C`.** Clearer, and it isn't a conditional: `C` runs
  when `B` fails too. It also avoids a `set -e` trap — `[ -f x ] && cmd` as the
  last line of a function returns 1 when the test fails, aborting the caller.
- **Avoid clever quoting.** No `'…'"$var"'…'` sandwiches. Pass context out of
  band (a file, the environment) and append only what genuinely has to cross the
  boundary; guest scripts stay fully single-quoted. Related: `<<-EOF` strips
  *every* leading tab, so it flattens anything that wants indentation — use a
  column-0 `<<EOF` for static blocks and `printf` inside loops.
- **Arrays are a last resort**; expanding an empty one trips `set -u` on macOS's
  bash 3.2. Two explicit branches beat one array-built argv.
- **Functions fit on a screen** (~30 lines) and do one thing. Nothing executes
  at the top level except `main "$@"`.
- **Budget your shellcheck disables.** Each carries a half-line reason on the
  same line. More than a handful in a file means the code is fighting the
  linter, and the code is what should change.
- **Errors point somewhere.** A `die` names the fix, the command that diagnoses
  it (`para doctor`), or the doc. And verbs converge: `up`, `down` and `rm` warn
  and succeed when the world is already in the state you asked for.

## Docs style: written for a reader, not a reviewer

`README.md` and `docs/` are a published spec, not internal notes. **If you
change a command, flag, `Parafile` var, hook semantic, or the image contract,
update the relevant page in the same change** — drift between `bin/para` and
the docs is a bug. See [`plans/docs-rewrite.md`](./plans/docs-rewrite.md) for
the in-flight rewrite and the page-by-page targets.

The bar is that someone who has never read the source can do the thing the page
is about. These rules are the prose version of **House style** above, and each
one was a mess that a full rewrite had to clean up.

- **Write for the reader's job, not the code's shape.** If a paragraph's
  grammatical subject is `para`, try rewriting it with the reader as the
  subject and see if it survives. "Let me tell you what the code does" is the
  smell; "here is how you get unstuck" is the target.
- **Behavior, not the reasoning that produced it.** A reference entry says what
  a thing does, what it defaults to, who reads it, and what breaks if you get
  it wrong. Why it was *designed* that way goes in `plans/`, with a link if it
  earns one. (`parafile.md` spent forty lines justifying route validation the
  engine no longer performs — that is what this rule is for.)
- **One home per fact**, and everywhere else links to it. `PARA_ROUTES` was
  explained on four pages and they disagreed. Invariants and gotchas count as
  facts: don't re-explain one (machine-global workspace names, say) on every
  page where it happens to bite. Any of them may get fixed, and the fix should
  not mean hunting through twelve pages that each re-derive the old behavior.
- **Say what it costs**, on the page where it bites, not in a "Limitations"
  section nobody reads. `para ls` needs incus reachable; an interactive
  `para sh` needs util-linux `su`; images are per-arch; the first
  `para image build` takes minutes.
- **Never document template policy as engine behavior.** The generic-mechanism
  boundary applies to prose: `para claude` is a file a template ships
  (`void-jchook`, not the `void-docker-gh` default), and every page that shows
  it says so. Blurring it teaches people to file engine bugs about their own
  hooks.
- **Show the command.** A page earns its keep with the line the reader can
  paste. Prose that surrounds no command is usually rationale in disguise.
- **Don't restate defaults.** A doc — or a Parafile — that repeats a default is
  a copy that goes stale.
- **`para --help` and `docs/commands.md` share one grouping** (WORKSPACES /
  HOST / PROJECT) so the two can't silently diverge.
- **Page gates:** no page over ~150 lines, and every `##` names a task or a
  thing, never a mechanism. A page over the gate is two pages, or one page plus
  a `plans/` entry.

### The three surfaces

One owner each — don't triple-write the install block, fix it where it's owned
and link:

- **root `README.md`** — the npm/GitHub funnel: what it is, install, one quick
  start, pointers.
- **`index.md`** — the VitePress lander (hero + feature cards).
- **`docs/README.md`** — the router into the reading paths, not a summary of
  them.

The site is [VitePress](https://vitepress.dev) (`.vitepress/config.mts`) served
from the repo root: `index.md` is the lander, `docs/` is served as-is at
`/docs/`, and `docs/README.md` is rewritten to `/docs/` so it stays the index on
GitHub and npm too. Keep pages plain GitHub-flavored markdown that reads
correctly in all three places — the only generator-specific syntax in use is
the lander's frontmatter and GitHub-style alert blockquotes. **A new page also
needs a `sidebar` entry** in the config.
