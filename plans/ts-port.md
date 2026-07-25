# Porting `bin/para` to TypeScript

Status: **shelved pending a trigger**. Phase -1 (`plans/cut-and-harden.md`,
PR #11) lands first either way; where it overlaps this plan (the registry
rewrite, `config-dump`, the three behavior fixes, the `install` removal), its
versions are authoritative and the corresponding items here become
preserve-not-implement. Unshelve when **any one** of:

1. a committed roadmap item bash structurally can't serve (REST-over-socket
   incus client, plugin API, JSON output surface);
2. external contributors exist and bash friction shows up in real issues/PRs;
3. ≥2 **shipped** (not review-caught) bash-semantics bugs after Phase -1's
   registry rewrite and unit tier land.

Revised after three independent reviews; the Why section states the case at
its post-review strength. All `bin/para`/test line references and version
pins are **as of `main@50a8b8e`** — re-resolve at re-baseline; Phase -1 moves
code.

The contract does **not** change: `PARA_CONTRACT` stays 1,
hooks/templates/`image-build.sh`/`skel/` stay shell, and the behavioral test
suite (`test/run`) is the oracle the port must satisfy verb by verb.

## Why — the case at its measured strength

`bin/para` is 2,244 lines (1,289 code, 848 comments). The case for the port:

1. **The `set -e` invisible-context class** — load-bearing `|| true`s, the
   AND-OR exemption — is structurally eliminated by throw-by-default and is
   beyond shellcheck's reach; in bash it can only ever be mitigated.
2. **Top-level execution structure** — config load running before the
   helpers exist. (Phase -1 improves this in bash with `load_config()`;
   a real `main()` removes the class.)
3. **The `su -c` quoting boundary** — still handwritten in TS, but
   centralized behind one typed seam.
4. **Type-checked refactoring at scale**, which matters if — and only if —
   the tool is meant to grow substantially and take outside contributors.

That is a real but narrow case: it justifies porting **when growth demands
it**, not as an unconditional win — hence the triggers above. Two claims
earlier drafts leaned on were measured by review and are retracted:

- ~~"A large share of the comments warn about bash itself."~~ Classified:
  only ~100–150 comment lines (12–18%) are bash-mechanics warnings; the
  great majority are domain spec (incus alias globality, publish/swap
  ordering, su/pty/SIGWINCH, Caddy ambiguity, the vfs/idmap footguns) that
  ports verbatim and gains nothing from types.
- ~~"PR #9 spent most of its lines on bug classes a typed language makes
  unrepresentable."~~ Scored: ~1.5 of that PR's seven fixes were
  bash-the-language; the rest were policy and domain decisions a TS
  implementation would have needed identically.

## Goals

- **Contract-identical** (the contract as defined in docs/versioning.md).
  A consumer pinning `PARA_VERSION=1` notices nothing.
- **Behavior-identical** where documented; deliberate changes only via the
  change-control rule under "Behavior changes" below. **Error/warning text
  is frozen for the duration of the port** — the CLI tests assert on message
  substrings, and message drift is behavior drift.
- **Fast startup** (< ~50 ms bare `para` on Bun). Load-bearing, not vanity:
  dynamic shell completions call back into the binary on every Tab.
- **Distribution is npm-only** — `para install` is already gone (Phase -1
  A1); see Packaging.
- **Adding a verb is one declaration** — name, args, flags, completions,
  help, `needsProject` — in one file, with types inferred.

## Non-goals

- Porting hooks, templates, `image-build.sh`, or `skel/` — they run inside
  guests and *should* be shell. `bin/lint` keeps shellchecking them.
- Windows. (incus is Linux/macOS; `process.execve` is POSIX-only. Fine.)
- Plugins, config formats, new verbs. Port first, evolve after.
- **REST-over-socket incus access.** The port stays on the CLI subprocess
  seam: same argv the bash issued, validated by the same suite — and the test
  suite's backend fence is PATH-based (test/lib/project.sh), which a
  unix-socket client would silently bypass. API migration is a separate,
  later, incremental change.

## Toolchain decisions

| Decision | Choice | Rationale |
|---|---|---|
| Language | TypeScript, `strict` + `noUncheckedIndexedAccess` | the point of the exercise |
| Runtime | **Bun** for dev/test and preferred runtime; artifact also runs on Node ≥ 24 | bun startup ≈ instant; npm consumers are guaranteed node, not bun |
| Entry shim | `bin/para` becomes a small sh shim (below) | picks the fast runtime when present; `PARA_RUNTIME=node\|bun` override for debugging and CI |
| CLI framework | `@cliffy/command`, exact-version pinned (1.2.1 at time of writing) | declarative, typed, dynamic completion resolvers; confined to `cli/adapter.ts` (see Module layout) |
| Bundler | `bun build --target=node --sourcemap=linked` → one ESM file + map, zero runtime deps | JSR/npm dep tree is dev-time only; users never see it |
| Unit tests | `bun test` for pure modules (routes, config, registry, quoting) | first-class unit tier (bash gets a narrower one via Phase -1's source guard; this one needs no sourcing tricks) |
| Behavioral tests | `test/run`, with two carve-outs: registry fixtures (see Registry) and the image-build rebuild flag (see Phase 3) | it drives `$PARA` as a black box |
| Lint | `tsc --noEmit`, typescript-eslint strict, `knip`; shellcheck stays for the shell that remains | `bin/lint` runs all of it |

The shim (note: `exec bun … || exec node …` does **not** work — a failed
`exec` terminates a non-interactive POSIX shell with 127):

```sh
#!/bin/sh
# resolves dist/para.js across the two layouts: git checkout, npm global
if [ "${PARA_RUNTIME:-}" != node ] && command -v bun >/dev/null 2>&1; then
  exec bun "$dist" "$@"
fi
exec node --enable-source-maps "$dist" "$@"
```

## Module layout

```
src/
  main.ts             entry: build program from the verb table, dispatch
  verbs/              one file per verb: declaration + handler
    table.ts          the verb registry (data-driven: verb -> ts | legacy)
  cli/
    adapter.ts        Verb[] -> cliffy Command tree — the ONLY file importing
                      cliffy; overrides cliffy's error handler, exit codes, and
                      help renderer (help is a config-introspection surface —
                      see Compatibility)
    completions.ts    resolvers: workspace names, template names, config keys
  core/
    config.ts         precedence env > user config > Parafile > default; denylist
    parafile.ts       Parafile evaluation via a bash subprocess (see below)
    routes.ts         parse/canonicalize/validate PARA_ROUTES (pure)
    registry.ts       typed workspace records over Phase -1's format
    project.ts        PROJECT_ROOT discovery, require_project, contract handshake
    paths.ts          XDG config/state paths
  incus/
    client.ts         typed incus operations (launch, exec, file push, image, …)
    guest.ts          guest shell-string construction — the one quoting boundary
    ready.ts          wait_ready polling (agent up, DNS resolves)
  caddy/
    caddyfile.ts      Caddyfile generation (pure: records in, text out)
    lifecycle.ts      start / validate / reload
  proc/
    run.ts            the subprocess layer (below)
  ui.ts               log/warn/die; stream discipline; exit-code policy
```

The **verb table is para's own type**, not cliffy's; `cli/adapter.ts` folds it
into cliffy (~50 lines + the overrides above). Help text, completions, and
dispatch derive from the table, so a framework swap, if ever needed, is
confined to one file. The `ls --names` / `init --names` plumbing verbs stay —
they are asserted by tests and are the completion feeders.

## The subprocess layer (`proc/run.ts`) — the glue

para *is* a subprocess orchestrator: ~45 `incus` call sites, ~10 `caddy`, plus
`git`, `hostname`, `open`/`xdg-open`, `colima`, and small POSIX utilities.
(para never invokes `gh` itself — hooks do, in the guest.) The call sites
reduce to **seven** patterns; the layer supports these and nothing else.

### Principles

1. **Argv arrays only, ever.** No `sh -c` on the host, no string-concatenated
   commands. Enforced by eslint (`no-restricted-imports` on
   `child_process`/`Bun.spawn` outside `proc/`), landing in the Phase 0 PR,
   not retrofitted.
2. **Non-zero throws by default** — the `set -e` we actually want: opting
   *out* is explicit and local (`try*` variants) instead of an invisible
   property of the calling context.
3. **Guest shell strings are irreducible but centralized** in
   `incus/guest.ts`, using POSIX single-quote escaping (`'` → `'\''`) —
   uniformly safe for any guest shell, one rule instead of two.

### The seven patterns

| bash today | examples | TS |
|---|---|---|
| `$(cmd 2>/dev/null \|\| true)` capture-with-shrug | `ct_meta`, `image get-property`, `ip_of`, `git config` | `tryRun` — `{ok, code, stdout, stderr}`, never throws |
| `cmd >/dev/null 2>&1` boolean | `instance_exists`, `caddy_running`, backend probes | `ok` |
| bare streaming command | `incus launch`, `incus file push`, hook execution | `passthrough` (child shares our stdio) |
| passthrough **with TTY, returning** | `run_hook` interactive path, `config-import` prompts | `passthrough` — distinct from exec-replace; do not "simplify" these into it |
| `exec incus … -t` TTY handoff | `cmd_sh`, `cmd_claude`, `cmd_run` (5 sites) | `execReplace` |
| `bash -s <` payload + background/`wait`/trap Ctrl-C dance | `cmd_image_build` | `passthrough` + `stdin: file(…)` + `AbortSignal` + `try/finally` (preserving the temp-alias/`published`-latch ordering exactly) |
| daemonizer capture via temp file | `start_caddy` | `run(…, {stdout: toFile})` — a naive read-to-EOF capture deadlocks identically in TS; `start_caddy`'s comment is the spec, ported verbatim |

Poll loops (`wait_ready`'s agent-up and DNS checks) become `poll(fn, {timeout,
interval})` over `ok()`; the ~120 s guest-readiness budget stays.

Traps → `try/finally` plus one top-level SIGINT/SIGTERM handler that runs
registered cleanups and exits `128+sig`.

### Behavior changes

The change-control rule: anything found mid-port either stays bug-for-bug or
is added here deliberately, with a versioning.md entry. The three previously
listed fixes (surfaced caddy reload failures via `caddy validate`, full-host
lowercasing in `route_host`, `cmd_web`'s dead domain fallback) land in bash
as Phase -1 B5 — the port **preserves** them; they are regression surface
here, not new behavior. Route validation in `core/routes.ts` stays as defense
in depth behind the validate call.

## `para sh` and exec-replacement

**`process.execve` exists in Node (≥ 23) and Bun.** True `execve(2)`: para's
process is replaced by `incus exec` — no wrapper, signals and TTY belong to
incus, like bash's `exec`. POSIX-only; throws with live worker threads (we
have none); resolve the binary path ourselves (small `which()` in `proc/`).
**Fallback** when `execve` is unavailable or throws (it is still
experimental-flagged in Node): `spawn` with `stdio: "inherit"`, forward
SIGTERM/SIGHUP, exit with the child's code or `128+signal`. Implemented once
as `execReplace`, chosen at runtime.

The exact argv today — `-t`/`-T`, `su --pty` vs `su -`, the SIGWINCH rationale
— is preserved verbatim, comments included: they document incus/su semantics,
not bash. (The strangler dispatch reuses this primitive — see Migration.)

## Parafile evaluation

The Parafile stays **sourced bash** (contract surface; the
`git remote get-url` derivation is a documented pattern). The port evaluates
it in a bash subprocess and reads back `env -0`. Review of the config-load
block (bin/para:28-290) pinned four semantics the eval must reproduce:

1. **The prelude is `set -euo pipefail`, plus `readonly PARA_CONTRACT=1`.**
   The Parafile runs under para's own strict mode today, and
   `docs/versioning.md` *documents* that reading a not-yet-defaulted key trips
   `set -u` — deliberate contract behavior. `readonly` preserves today's error
   when a Parafile tries to assign `PARA_CONTRACT`.
2. **Defaults are two-phase.** The keys defaulted at bin/para:78-106 resolve
   **before** sourcing and are readable by the Parafile; those at
   bin/para:154-249 default **after**. The eval env injects the pre-set; TS
   applies the post-set to the result. (Don't enumerate the keys here — the
   two blocks are the authority, and Phase -1 adds keys.)
3. **`PROJECT_ROOT` and the `PARAFILE` override are inputs.** The documented
   `PARA_ORIGIN` derivation reads `$PROJECT_ROOT` inside the Parafile; it must
   be present (unexported today, so injected explicitly, not inherited).
4. **User-config overlay applies when the env var is unset *or empty***
   (the `[ -n "${!_k:-}" ]` test) — a naive `key in process.env` check flips
   this. Values are literal (no expansion), split on first `=`,
   non-`PARA_[A-Z_]*` lines silently dropped, denylist warnings on stderr.
   All owned by `core/config.ts`, unit-tested against the precedence table in
   docs/parafile.md.

`ROUTES_DECLARED` falls out of a `declare -p PARA_ROUTES` probe in the same
subprocess (unset / scalar / legacy-array, keeping the array migration error).

**Config load is unconditional inside a project, exactly as today** — `--help`
prints Parafile-resolved values, `ls` scopes by the Parafile's
`PARA_PROJECT`, and therefore completions (fed by `ls --names`) also need the
eval. Its cost is budgeted in Performance.

### Hook environment: the blanket is the contract

`run_hook` forwards **every `PARA_*` in scope** (`${!PARA_@}`), and
docs/hooks.md documents that openness — a user's own `PARA_FOO` from Parafile
*or user config* must reach hooks, and para internals ride along today. The
TS forwarder is therefore: **all `PARA_*` from the post-eval resolved map**
(documented or not) ∪ the computed per-workspace set (the documented table in
docs/hooks.md#the-environment-para-injects) ∪ `PARA_CONTRACT`. A curated
known-keys forwarder would be a contract break.

## Registry

Phase -1 B1 (`plans/cut-and-harden.md`) owns the registry rewrite: KEY=VALUE
per workspace under `workspaces.d/`, the one-way migration, sentinel removal,
container-stamp `-` translation, and the CLI-tier fixture updates
(`a_registry_row`/`forget_registry_row` — the one place "the suite is
unchanged" needs a carve-out; the e2e tier asserts through para commands and
is format-agnostic). `core/registry.ts` is a typed accessor over that format
from Phase 1.

One constraint stands regardless of format: **no state-format change may land
while `bin/para-legacy` still reads or writes that state.** Registry readers
stay legacy into Phase 3 (`sh`/`claude`/`run` resolve IPs), and a legacy `up`
regenerating the machine-wide Caddyfile from state it can't fully read means
silent live routing loss for every other workspace. Any post-port format
change (e.g. JSON) is a Phase 4+ decision.

`caddy/caddyfile.ts` takes `WorkspaceRecord[]` and returns text — pure,
unit-tested, including the cross-row duplicate-host guard.

## Compatibility policies (the dual-implementation window)

- **Frozen surfaces:** error/warning message text, exit codes (1 for user
  errors, `128+sig`), and stream discipline — `log/warn/die` → stderr; data
  (`ls --names`, `key`, `completions <shell>`, `config-dump`) → stdout.
  **`--help` is a config-introspection surface** (tests assert the
  resolved-config table, the absence of `para-dev`, and that user-config
  warnings appear on it), so help is hand-rendered from the verb table + the
  resolved config — one of the adapter's cliffy overrides.
- **Golden config-dump cross-check:** Phase -1 B4 ships `para config-dump`
  and the golden precedence-matrix tests in bash. Before Phase 1: implement
  the same verb in TS; CI diffs the two implementations across B4's matrix
  for the duration of the strangler. The verb survives Phase 4 as a support
  tool.

## Why TypeScript and not Go (considered and decided)

This section supersedes `plans/go-rewrite.md`, an earlier plan arguing the
opposite conclusion from premises that predate PR #9 (~1,400 lines, madi as
sole consumer, contract breakage still free). Go's real advantages — the
first-party incus client library, `syscall.Exec`, a static binary — were
weighed. Decision: **TypeScript**, because —

- **The incus REST API is not Go-exclusive.** The daemon speaks versioned REST
  over a unix socket; Node/Bun reach it natively (undici `socketPath`, Bun
  `fetch` unix option). para uses ~15 endpoints; typing them by hand is small.
  The Go library is pre-written types, not privileged access.
- **Interactive exec is sidestepped in both languages.** The API path means
  websockets + raw-mode PTY + resize forwarding — the incus CLI already got
  that right, and `execReplace` into it keeps it. A Go port would sensibly do
  the same, so Go's API advantage shrinks to non-interactive calls.
- **Porting on the identical CLI seam is the safety rail** (see Non-goals) —
  language *and* seam at once doubles drift surface, in either language.
- **Distribution is solved for TS** (npm + bundled file + shim) and is real
  infra for Go (per-platform binaries, goreleaser, npm wrapper packages).
- **Toolchain surface**: the repo is shell + one more language forever; TS
  keeps that language aligned with the packaging ecosystem, and Bun is one
  binary for runtime/test/bundle.

Escape hatch, recorded: the verb table, `proc/` boundary, and black-box suite
are language-agnostic, so a future Go rewrite would inherit this port's
acceptance suite. cobra's `ValidArgsFunction` completions are cliffy's equal,
so the framework is not a lock-in either.

## Migration: four phases, suite-green at every step

**Strangler policy.** Verbs marked `legacy` in the table `execReplace` into
`bin/para-legacy`: one live implementation per verb; **no hybrids** (TS
arg-parsing shelling into legacy bodies is banned — it doubles the drift
surface the design exists to avoid). Rollback for any ported verb is flipping
its table entry back to `legacy` — a one-line PR.

The authoritative verb inventory is `main()`'s dispatch table
(bin/para:2211-2242) — every row gets a phase assignment in the Phase 0 PR;
the table, not this prose, is the checklist, and the Phase 2/3 sets below
**re-baseline against Phase -1's A-series outcomes** (verbs removed, cut, or
redefined there are not ported). Every phase PR carries its docs updates in
the same change (CLAUDE.md rule), and versioning.md Decisions entries land
**when the change lands**, not at the end.

**Phase 0 — scaffold.** Toolchain; `proc/run.ts`; `ui.ts`; verb table +
adapter with every verb marked `legacy`; the shim; eslint fences; CI matrix +
performance baselines (below).
*Gate:* full suite green under **both** forced runtimes; manual TTY checklist:
interactive `sh`, `claude` under resize, Ctrl-C mid-`image build` (temp alias
cleaned), a hook prompt flow. Plus a new e2e test pinning dispatcher
transparency: `para sh ws -c 'exit 42'` → 42; child killed by signal →
`128+sig`.

**Phase 1 — config + read-only verbs.** `core/config.ts`, `core/parafile.ts`,
`core/routes.ts`, `core/registry.ts` (over Phase -1's format), `config-dump`
in TS + the CI diff; port `ls`, `web`, `config-set`, `init`, help,
completions.
*Gate:* CLI tier + config-dump matrix green; completion round-trip beats the
performance budget under node.

**Phase 2 — lifecycle.** `up`, `down`, `rm`, `start`, `stop`, `reconcile`,
`caddy/*`, `incus/ready.ts`, `run_hook`. The `up` ordering (ownership → routes
→ domain → backend → uid-drift → launch/converge) ports check-for-check.
*Gate:* `test/run --e2e` per verb on Linux; a macOS/colima manual pass for
`start`/`ensure_backend`; docs state sections updated. **This is the schedule
risk: `cmd_up` sits on `ensure_backend`/`ensure_pool`/`ensure_idmap`/
`ensure_volume`/`alloc_ip` — the most environment-sensitive code in the tool
(zfs/btrfs/colima branches), covered only by e2e. Budget 2–3 weeks, not
days.**

**Phase 3 — sessions + image.** `sh`, the surviving session verb(s) per
Phase -1 A6, `key` per A5, `config-import`, `config-sync` (as genericized by
A4), `image build/status/rm`.
*Gate:* `PARA_TEST_REBUILD=1 test/run --e2e` (the steady-state suite skips
image builds — without this flag a ported `cmd_image_build` ships untested);
one full `templates/void-docker-gh` run end-to-end on Linux (the suite is
Docker-free by design); the TTY manual checklist again.

**Phase 4 — retire.** Delete `bin/para-legacy`; `bin/lint` scope shrinks to
the remaining shell; final docs pass; versioning.md port entry (non-breaking:
implementation change, contract intact).

Phases 1 and 3-minus-image-build are the "days" work; Phase 2 is the honest
cost center.

## Packaging & distribution (Phase 0 unless noted)

- **`para install` is already removed** (Phase -1 A1, with its docs row and
  versioning.md entry). The shim covers exactly two layouts: git checkout and
  npm global. npm global install is the funnel; `npm link`/`npx` cover
  contributors and project-pinning.
- **package.json:** `files` += `dist/`, `bin/para-legacy` (an npm install
  without it strands every unported verb); `bin` → the shim;
  `prepublishOnly`: build + a smoke `node dist/para.js --help` (never ship a
  stale or bun-only `dist/`); `engines: {node: ">=24"}`. Phase 4: drop
  `bin/para-legacy` from `files`.
- **Sourcemaps:** ship `dist/para.js.map`; the shim's node branch passes
  `--enable-source-maps` — a user-reported stack trace must not be
  line 1, column 480000 of a bundle.
- **Dependency policy:** zero runtime `dependencies`; everything bundled is
  exact-pinned and reviewed. Bundling cliffy (MIT) requires a third-party
  license notice in the published package.

## CI & dev workflow

- `.github/workflows`: (1) `bin/lint` (shellcheck + tsc + eslint + knip);
  (2) `bun test` unit tier; (3) build `dist/`, then `test/run` CLI tier
  **twice: `PARA_RUNTIME=node` and bun** — a bun-preferring shim on a
  bun-equipped runner would otherwise never exercise the code path npm users
  actually run (spawn implementation, execve fallback, node cold start);
  (4) the config-dump diff matrix (Phases 1–3).
- **Dev loop:** from a git checkout the shim prefers `src/main.ts` under bun
  (bun runs TS directly); the bundle is a release artifact. This avoids
  `test/run` silently exercising a stale `dist/` during development; CI is
  what tests the built artifact.

## Performance protocol

Baseline **now** (Phase 0), not "measure later": a committed `hyperfine`
script benchmarking bash `para` (bare), `para ls --names`, and the completion
round-trip; then the same for TS under bun and under node at each phase gate.
Budget: completion round-trip < 50 ms bun / < 120 ms node — which includes
the ~5 ms bash-subprocess Parafile eval that completions cannot skip. If node
cold-start threatens the budget, verb handlers become lazy `import()`s (the
table is cheap); decided by measurement, not prose.

## Code-cleanliness conventions

- **No shell strings on the host.** Argv arrays; eslint-enforced from the
  first PR.
- **One quoting boundary** (`incus/guest.ts`); one subprocess boundary
  (`proc/`); one cliffy import (`cli/adapter.ts`); one exit path (`ui.die` →
  typed `UserError`, printed `para: …`, exit 1; `ProcError` carries the
  failing argv).
- **Pure core** (`routes.ts`, `caddyfile.ts`, config precedence, registry
  serialization): no I/O, unit-tested directly.
- **Comment policy:** domain comments (incus alias globality, su/SIGWINCH,
  Caddy ambiguous-site semantics, publish/swap ordering, the caddy-start
  daemonizer capture) port **verbatim** — they're the spec, and their
  preservation is a review-checklist item. Bash-mechanics comments are deleted
  without replacement; the type system and `proc/` API are their replacement.

## Risks / open questions

- **cliffy** — ordinary single-maintainer/JSR-distribution risk, handled by
  exact-pin + bundling + the adapter; fallback candidate: Bloomberg
  `stricli`. Re-verify the completions API against current docs in the
  Phase 0 spike.
- **`process.execve`** — experimental-flagged in Node; the spawn fallback
  (see `para sh`) covers it.
- **Phase 2 is the deep end** — environment-sensitive backend code with
  e2e-only coverage; the per-verb e2e gate and the macOS manual pass are the
  mitigations, and the estimate says weeks on purpose.
- **Parafiles doing exotic bash** — the eval subprocess gives them today's
  semantics (strict mode included); anything reading para *internals* beyond
  the documented env may break, which the contract explicitly permits.
- **Interactive/TTY behavior has no automated tier** — hence the dispatcher
  e2e test (exit status, signal) plus the recurring manual checklist as named
  phase-exit criteria.
