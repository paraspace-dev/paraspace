# CLAUDE.md (ParaSpace)

Guidance for Claude Code working in this repo.

## What this is

ParaSpace ships the `para` tool, which gives you parallel dev workspaces. Each
workspace is an unprivileged Incus system container with its own clone, its own
stack, a bridge IP, and a `https://<name>.<domain>` URL. Nesting means a stack
of containers can run inside one, but no project has to have one. **It is a
standalone, self-contained, MIT-licensed npm package (`paraspace`)**, published
from a `v*` tag by `.github/workflows/publish.yml`.

The README is the funnel (what it is, pointers into the docs). `docs/` is the
authoritative spec, and it owns the `Parafile` schema (`docs/parafile.md`), the
hook and image contracts (`docs/hooks.md`, `docs/hook-points.md`,
`docs/image.md`), the vendoring model (`docs/mods.md`), the command surface
(`docs/commands.md`), the architecture (`docs/how-it-works.md`), and the case
para makes for itself (`docs/why.md`). Don't duplicate any of that here or in
commit messages; link to it.

## The generic-mechanism boundary

`para` is a **thin generic mechanism**, the incus/Caddy/volume/lifecycle engine,
much like `docker compose`. It bakes in **nothing** about *how* a workspace is
provisioned. The real provision and boot logic lives in a consumer's
`.paraspace/` dir (`Parafile` + `hooks/` + vendored `mods/`), which para runs
but never contains. The `mods/` and `templates/` this package ships are
*content* under that boundary, not engine, and `para mod add` only copies them.

## Contract version

The para↔project interface is versioned with `PARA_CONTRACT`, currently **1**.
That interface is the `.paraspace/` dir a project ships: its `Parafile`, its
`hooks/`, its `mods/` (vendored `hooks/`+`skel/`+`commands/` para also
resolves), and its `commands/` (host-side verbs that become `para <verb>`). A
**breaking** change to injected env, the hook names or semantics, the
`~/.paraspace` layout in the guest, or the `Parafile` vars must bump
`PARA_CONTRACT`; additive changes don't. A project pins the contract it targets
with the same var in its `Parafile`, and para refuses on mismatch.

That rule starts at 1.0. `PARA_CONTRACT` stays **1** for all of 0.x, breaks land
inside it, and there are **no consumers to migrate**, so don't write migration
notes, deprecation shims, renamed-to warnings, or "this used to be called X"
prose. Rename the thing, update every caller and page in the same change, and
leave nothing behind that names the old spelling. See
[`docs/versioning.md`](./docs/versioning.md).

## Code + conventions

- **Pure shell.** `bin/para` is one lean bash script (`set -euo pipefail`),
  organized as small helpers plus `cmd_*` handlers dispatched from `main()`.
  Expect terse helpers, `log/warn/die/need`, lowercase function names, and
  POSIX-ish code where practical. It is the minimal-engine rewrite that
  replaced a 2,244-line predecessor, and it is the reference for **House
  style** below. New code should read like it.
- **ShellCheck is the static gate**, run via `bin/lint` (or `npm run lint`), and
  CI runs the same on every push and PR. It lints the CLI, the runner, the
  templates' and `mods/`' hooks, and the `test/` scripts (discovered by
  shebang). Hook sources resolve via `.shellcheckrc` (`source-path`), so prefer
  that over per-file directives. **Run `bin/lint` before finishing any change
  here.**
- **Behavioral tests live in [`test/`](./test/README.md)** (`test/run`, or
  `npm test`), in two tiers. The CLI tier needs no incus and runs in CI. The
  e2e tier drives a real Incus workspace off a tiny Alpine fixture and asserts
  the incus, Caddy, hook, and volume contracts (`up` → hooks → boot readiness →
  Caddy → the app). It's Docker-free by design, so it does not cover the
  nested-Docker/compose boot path. Run `test/run --e2e` after changing the
  `up`/route/lifecycle mechanism; every run is sandboxed from your real
  workspaces. The e2e tier is **Linux-only** (native incus, or a Linux VM on
  macOS) and CI runs only the CLI tier, so run e2e locally and confirm it's
  green before merging or marking a PR ready. Tests are autodiscovered `test_*`
  functions run in name order, so write them **order-independent**. See
  [`test/README.md`](./test/README.md) for the full conventions (tier choice,
  `|| return 1`, `eventually`, per-workspace asserts).
- The `zsh` `skel/` is intentionally not linted (ShellCheck parses only sh/bash).
- `plans/` holds design notes for in-flight work; not shipped in the npm `files`.

## House style

The bar is that someone who knows bash but not para can read any function top to
bottom and be right about what it does. `bin/para` is the reference. The rules
below are not aesthetic preferences. Each one names a mess the rewrite cleaned
up.

- **Prefer the elegant tool.** Favor designs whose usefulness falls out of a few
  well-chosen primitives.
- **No bash gymnastics.** If a line needs a comment warning you about bash,
  write the line that doesn't need one. A reader should never need a manual for
  the *mechanism* of a line, only (occasionally) for the domain.
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
  costs lines *and* drifts from what the tool actually accepts. Surface its
  error instead.
- **One way to do each thing.** One door into a workspace (`ws_exec`), one
  env-forwarding rule (`para_env`), one place that knows about Caddy. A second
  spelling of an existing idea is a defect even when it works.
- **`if` beats `A && B || C`.** Clearer, and it isn't a conditional, since `C`
  runs when `B` fails too. It also avoids a `set -e` trap, because `[ -f x ] &&
  cmd` as the last line of a function returns 1 when the test fails, aborting
  the caller.
- **Avoid clever quoting.** No `'…'"$var"'…'` sandwiches. Pass context out of
  band (a file, the environment) and append only what genuinely has to cross the
  boundary; guest scripts stay fully single-quoted. Related: `<<-EOF` strips
  *every* leading tab, so it flattens anything that wants indentation. Use a
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

## Docs style

This style applies to:

- all markdown files in the repository,
- all code comments,
- all code output intended for human users.

`README.md` and `docs/` are a published spec, not internal notes. **If you
change a command, flag, `Parafile` var, hook semantic, or the image contract,
update the relevant page in the same change.** Drift between `bin/para` and the
docs is a bug.

### Do not write AI slop

Write for human readers.

- M-dashes are banned.
- Colons are mostly banned except in rare cases, e.g. "Related: ...".
- Cut filler phrases. Remove throat-clearing openers ("Here's the thing:"),
  emphasis crutches ("Let that sink in."), business jargon ("navigate the
  landscape"), and meta-commentary ("In this section, we'll explore...").
- Avoid binary contrasts ("Not X. Y."), negative listings ("Not a X. Not a Y. A
  Z."), dramatic fragmentation ("Speed. That's it. That's the tradeoff."),
  self-posed rhetorical questions ("The result? Devastating."), and
  anaphora/tricolon abuse. Prefer active constructions with named actors. "The
  complaint becomes a fix" is wrong. "The team fixed it" is right.
- Do not stack short punchy fragments for manufactured emphasis. Do not write
  listicles disguised as prose ("The first wall... The second wall...").

Banned words:

- barrel
- seam
- load-bearing
- quietly
- delve

### Quality bar

The bar is that someone who has never read the source can do the thing the page
is about. These rules are the prose version of **House style** above, and each
one was a mess that a full rewrite had to clean up.

- **Write for the reader's job, not the code's shape.** If a paragraph's
  grammatical subject is `para`, try rewriting it with the reader as the
  subject and see if it survives. "Let me tell you what the code does" is the
  smell; "here is how you get unstuck" is the target.
- **Behavior, not the reasoning that produced it.** A reference entry says what
  a thing does, what it defaults to, who reads it, and what breaks if you get
  it wrong. Why it was *designed* that way goes in `plans/`, and the page does
  not link to it. (`parafile.md` spent forty lines justifying route validation
  the engine no longer performs; that is what this rule is for.)
- **A doc links to other docs.** `plans/` is a working note that gets deleted,
  and it ships in neither the tarball nor the site, so a link to one is a dead
  link for every reader who isn't in the repo. If a page needs something a plan
  says, the page says it.
- **One home per fact**, and everywhere else links to it. `PARA_ROUTES` was
  explained on four pages and they disagreed. Invariants and gotchas count as
  facts: don't re-explain one (machine-global workspace names, say) on every
  page where it happens to bite. Any of them may get fixed, and the fix should
  not mean hunting through twelve pages that each re-derive the old behavior.
- **Say what it costs**, on the page where it bites, not in a "Limitations"
  section nobody reads. `para ls` needs incus reachable; an interactive
  `para sh` needs util-linux `su`; images are per-arch; the first
  `para image build` takes minutes.
- **Never document template or mod policy as engine behavior.** The
  generic-mechanism boundary applies to prose. `para claude` is a file the
  `dotfiles` mod ships (no bundled *template* does), not something the
  engine knows about, and every page that shows it says so. Blurring it teaches
  people to file engine bugs about their own hooks.
- **Show the command.** A page earns its keep with the line the reader can
  paste. Prose that surrounds no command is usually rationale in disguise.
- **Don't restate defaults.** A doc (or a Parafile) that repeats a default is a
  copy that goes stale.
- **`para --help` and `docs/commands.md` share one grouping** (WORKSPACES /
  HOST / PROJECT) so the two can't silently diverge.
- **Page gates:** no page over ~150 lines, and every `##` names a task or a
  thing, never a mechanism. A page over the gate is two pages, or one page plus
  a `plans/` entry.

### The three surfaces

Each piece of information lives in one place. If another doc references it,
link to the doc that owns that information.

- **root `README.md`** is the npm/GitHub funnel. What it is and pointers into
  the docs; it duplicates no doc content.
- **`index.md`** is the VitePress lander (hero + feature cards).
- **`docs/README.md`** routes into the reading paths and does not summarize
  them.

The site is [VitePress](https://vitepress.dev) (`.vitepress/config.mts`) served
from the repo root. `index.md` is the lander, `docs/` is served as-is at
`/docs/`, and `docs/README.md` is rewritten to `/docs/` so it stays the index on
GitHub and npm too. Keep pages plain GitHub-flavored markdown that reads
correctly in all three places. The only generator-specific syntax in use is the
lander's frontmatter and GitHub-style alert blockquotes. **A new page also needs
a `sidebar` entry** in the config.

`public/logo.svg` is the mark, the poster's two lenses flattened to read at tab
size. It serves as both the navbar logo and the favicon. Editing it means
rerunning `bin/site-icons`, which renders the PNGs that Safari and iOS need,
and committing what that writes.

**Both the mark and the poster split their circles at 0.62 diameters**, so the
overlap is the same shape at 16px and at 540px. The number came from measuring
Mastercard's artwork, and it lands within a rounding of 1/φ (0.618), which is
about as good a reason as a ratio gets. Moving it means moving `--dx` in
`Poster.vue` and the centres in `public/logo.svg` together, or the diagram
starts saying two different things about how much two workspaces share.
