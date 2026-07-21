# CLAUDE.md — paraspace

Guidance for Claude Code working in `packages/paraspace/`. Rules here refine the
repo root `CLAUDE.md` for this subtree.

## What this is

ParaSpace is the
`para` tool: parallel dev workspaces, each an unprivileged Incus system
container with its own clone, Docker stack, bridge IP, and
`https://<name>.<domain>` URL. **It is a standalone, self-contained,
MIT-licensed npm package (`paraspace`)** that happens to live in this
monorepo — its own `package.json`, `LICENSE`, and `.github/workflows/lint.yml`.
It knows nothing about madi. Treat this directory as an independent open-source
project vendored here, not as part of the madi app.

**Read [`README.md`](./README.md) and [`docs/`](./docs/README.md) first.** The
README is the funnel (install, quick start, pointers); `docs/` is the
authoritative spec — the `Parafile` schema (`docs/parafile.md`), the hook +
image contracts (`docs/hooks.md`, `docs/image.md`), the command surface
(`docs/commands.md`), and the design rationale (`docs/how-it-works.md`). Don't
duplicate any of that here or in commit messages; link to it.

## The generic-mechanism boundary (the one rule that matters)

para is a **generic mechanism** — the incus/Caddy/volume/lifecycle engine, like
`docker compose`. It bakes in **nothing** about *how* a workspace is provisioned.
Everything project-specific lives in a consumer's `.paraspace/` dir (`Parafile` +
`hooks/`), which para runs but never contains. When working here:

- **Never leak madi (or any project) specifics into `bin/para`.** No madi ports,
  repo URLs, `.env` keys, compose knowledge, or refinance/domain concepts. If
  something is project policy, it belongs in a `.paraspace/hooks/` script, exposed
  to para only through the versioned contract (`PARA_*` env, hook names, the
  `Parafile` keys). The templates under `templates/` are the reference consumers
  (`void-docker-gh` is the `para init` default; `void-minimal`/`void-jchook` are
  siblings) — keep them minimal and runnable.
- madi is a *consumer*: its policy is at the repo-root `/.paraspace/` (docs in
  `/.paraspace/README.md`), and root `bin/para` symlinks into `bin/para` here.
  Changes to the tool must not silently break madi's hooks — see the contract.

## Contract version

The para↔project interface is versioned (`PARA_CONTRACT`, currently **1**). A
**breaking** change to injected env, the hook names/semantics, the `~/.para`
layout, or the `Parafile` keys must bump `PARA_CONTRACT`; additive changes don't.
A consumer pins `PARA_VERSION` and para refuses on mismatch. If you change the
seam, decide breaking-vs-additive deliberately and update both the constant and
[`docs/versioning.md`](./docs/versioning.md).

## Code + conventions

- **Pure shell.** `bin/para` is one ~1400-line bash script (`set -euo pipefail`),
  organized as small helpers + `cmd_*` handlers dispatched from `main()`. Match
  the surrounding style: terse helpers, `log/warn/die/need`, lowercase function
  names, POSIX-ish where practical.
- **ShellCheck is the static gate**, run via `bin/lint` (or `npm run lint`) — CI
  runs the same on every push/PR. It lints the CLI plus the templates' hooks,
  `image-build.sh`, and the `test/` scripts (discovered by shebang). Hook sources
  resolve via `.shellcheckrc` (`source-path`), so prefer that over per-file
  directives. **Run `bin/lint` before finishing any change here** — it's the
  static gate.
- **Behavioral tests live in [`test/`](./test/README.md)** (`test/run`, or
  `npm test`): a CLI tier (no incus, runs in CI) and an e2e tier that drives a
  real Incus workspace off a tiny Alpine fixture and asserts the whole path
  (`up` → hooks → boot readiness → Caddy → the app). Run `test/run --e2e` after
  changing the `up`/route/lifecycle mechanism; every run is sandboxed from your
  real workspaces.
- The `zsh` `skel/` is intentionally not linted (ShellCheck parses only sh/bash).
- `plans/` holds design notes for in-flight work; not shipped in the npm `files`.

## When editing, keep these honest

The README and `docs/` are a published spec, not internal notes — if you change
a command, flag, `Parafile` key, hook semantic, or the image contract, update
the relevant `docs/` page (and `README.md` / `templates/` if they show it) in
the same change. Drift between `bin/para` and the docs is a bug. The docs are
plain GitHub-flavored markdown, kept portable for a future VitePress site —
no generator-specific syntax.
