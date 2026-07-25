# Porting `bin/para` to TypeScript

Status: planned; revised after two independent reviews (adversarial fact-check
against `bin/para` + architecture/sequencing review). The contract does **not**
change: `PARA_CONTRACT` stays 1, hooks/templates/`image-build.sh`/`skel/` stay
shell, and the behavioral test suite (`test/run`) is the oracle the port must
satisfy verb by verb.

## Why (one paragraph)

`bin/para` is 2,244 lines: 848 comment lines against 1,289 of code, and a large
share of the comments are warnings about bash itself — `${a+set}` testing
element zero, `:=` firing on empty, unquoted expansion needing `set -f`, `%q`
capturing element 0 of arrays, SIGPIPE-under-pipefail, the `set -e` AND-OR
exemption. The Parafile-audit PR (#9) spent most of its 430 net lines on bug
classes a typed language makes unrepresentable (scalar/array confusion,
positional-registry field shifts, unset-vs-empty). We are pre-launch with zero
external consumers and a black-box test suite; this is the cheapest moment the
port will ever have.

## Goals

- **Contract-identical.** Same injected env, hook names/semantics, `~/.para`
  guest layout, Parafile keys. A consumer pinning `PARA_VERSION=1` notices
  nothing.
- **Behavior-identical** where documented; the only deliberate behavior changes
  are the sanctioned fixes listed below. **Error/warning text is frozen for the
  duration of the port** — the CLI tests assert on message substrings, and
  message drift is behavior drift.
- **Fast startup** (< ~50 ms bare `para` on Bun). Load-bearing, not vanity:
  dynamic shell completions call back into the binary on every Tab.
- **Distribution is npm-only**: `npm i -g paraspace` (already the documented
  funnel). `para install` is removed rather than ported — see Packaging.
- **Adding a verb is one declaration** — name, args, flags, completions, help,
  `needsProject` — in one file, with types inferred.

## Non-goals

- Porting hooks, templates, `image-build.sh`, or `skel/` — they run inside
  guests and *should* be shell. `bin/lint` keeps shellchecking them.
- Windows. (incus is Linux/macOS; `process.execve` is POSIX-only. Fine.)
- Plugins, config formats, new verbs, REST-over-socket. Port first, evolve
  after.

## Toolchain decisions

| Decision | Choice | Rationale |
|---|---|---|
| Language | TypeScript, `strict` + `noUncheckedIndexedAccess` | the point of the exercise |
| Runtime | **Bun** for dev/test and preferred runtime; artifact also runs on Node ≥ 24 | bun startup ≈ instant; npm consumers are guaranteed node, not bun |
| Entry shim | `bin/para` becomes a small sh shim (below) | picks the fast runtime when present; `PARA_RUNTIME=node\|bun` override for debugging and CI |
| CLI framework | `@cliffy/command` **1.2.1** (stable since 1.0.0, 2026-02; exact-version pinned), imported only by one adapter file | declarative, typed, dynamic completion resolvers; the adapter contains framework risk on principle |
| Bundler | `bun build --target=node --sourcemap=linked` → one ESM file + map, zero runtime deps | JSR/npm dep tree is dev-time only; users never see it |
| Unit tests | `bun test` for pure modules (routes, config, registry, quoting) | the tier bash couldn't have |
| Behavioral tests | `test/run` — with the two carve-outs noted in Testing | it drives `$PARA` as a black box |
| Lint | `tsc --noEmit`, typescript-eslint strict, `knip`; shellcheck stays for the shell that remains | `bin/lint` runs all of it |

The shim (note: `exec bun … || exec node …` does **not** work — a failed
`exec` terminates a non-interactive POSIX shell with 127):

```sh
#!/bin/sh
# resolves dist/para.js across the three layouts: git checkout, npm global,
# para-install staging (see Packaging)
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
    registry.ts       typed workspace records; LEGACY FLAT FORMAT until Phase 4
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
confined to one file. The `ls --names` / `init --names` plumbing
verbs stay — they are asserted by tests and are the completion feeders.

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
   `incus/guest.ts`, using POSIX single-quote escaping (`'` → `'\''`).
   (`run_hook`'s guest shell is always bash via `su … -s /bin/bash`, so
   `%q`'s `$'…'` spellings were not actually a live hazard there — but
   single-quote escaping is uniformly safe, including for any future
   non-bash guest path, and it is one rule instead of two.)

### The seven patterns

| bash today | examples | TS |
|---|---|---|
| `$(cmd 2>/dev/null \|\| true)` capture-with-shrug | `ct_meta`, `image get-property`, `ip_of`, `git config` | `tryRun` — `{ok, code, stdout, stderr}`, never throws |
| `cmd >/dev/null 2>&1` boolean | `instance_exists`, `caddy_running`, backend probes | `ok` |
| bare streaming command | `incus launch`, `incus file push`, hook execution | `passthrough` (child shares our stdio) |
| passthrough **with TTY, returning** | `run_hook` interactive path, `config-import` prompts | `passthrough` — distinct from exec-replace; do not "simplify" these into it |
| `exec incus … -t` TTY handoff | `cmd_sh`, `cmd_claude`, `cmd_run` (5 sites) | `execReplace` |
| `bash -s <` payload + background/`wait`/trap Ctrl-C dance | `cmd_image_build` | `passthrough` + `stdin: file(…)` + `AbortSignal` + `try/finally` (preserving the temp-alias/`published`-latch ordering exactly) |
| **daemonizer capture via temp file** | `start_caddy` (bin/para:877-884) | `run(…, {stdout: toFile})`. `caddy start` daemonizes `caddy run`, which inherits the pipe's write end and never closes it — a naive read-to-EOF capture **deadlocks**, in TS exactly as in `$(…)`. The temp-file redirect is the pattern; port it as a mode, with the original comment. |

Poll loops (`wait_ready`'s agent-up and DNS checks) become `poll(fn, {timeout,
interval})` over `ok()`; the ~120 s guest-readiness budget stays.

Traps → `try/finally` plus one top-level SIGINT/SIGTERM handler that runs
registered cleanups and exits `128+sig`.

### Sanctioned behavior fixes (the complete list; anything else found mid-port
### either stays bug-for-bug or is added here deliberately, with a
### versioning.md entry)

- `caddy_reload` (bin/para:902) swallows errors at the post-`gen_caddyfile`
  reload sites (`up`, `rm`, `reconcile`) — `start_caddy`'s own reload branch
  does not. The port runs `caddy validate --config … --adapter caddyfile`
  (verified: real subcommand, catches duplicate site addresses) and
  **surfaces** reload failures. Route validation in `core/routes.ts` stays —
  defense in depth.
- `route_host` lowercases the whole host (today only the sub is folded, so the
  cross-row duplicate guard is case-blind for name/domain).
- `cmd_web`'s dead `${wdomain:-$PARA_DOMAIN}` fallback goes away.

## `para sh` and exec-replacement

**`process.execve` exists in both Node (≥ 23) and Bun** (verified here: Node
25.2.1, Bun 1.3.14). True `execve(2)`: para's process is replaced by `incus
exec` — no wrapper, signals and TTY belong to incus, like bash's `exec`.
POSIX-only; throws with live worker threads (we have none); resolve the binary
path ourselves (small `which()` in `proc/`). **Fallback** for Node < 23:
`spawn` with `stdio: "inherit"`, forward SIGTERM/SIGHUP, exit with the child's
code or `128+signal`. Implemented once as `execReplace`, chosen at runtime.

The exact argv today — `-t`/`-T`, `su --pty` vs `su -`, the SIGWINCH rationale
— is preserved verbatim, comments included: they document incus/su semantics,
not bash.

The **strangler dispatch** uses the same primitive: verbs marked `legacy` in
the table `execReplace` into `bin/para-legacy`. One live implementation per
verb; **no hybrids** (TS arg-parsing shelling into legacy bodies is banned —
it doubles the drift surface the design exists to avoid). Rollback for any
ported verb is flipping its table entry back to `legacy` — a one-line PR.

## Parafile evaluation

The Parafile stays **sourced bash** (contract surface; the
`git remote get-url` derivation is a documented pattern). The port evaluates
it in a bash subprocess and reads back `env -0`. Review of `bin/para:28-290`
pinned four semantics the naive sketch missed; the eval must reproduce all of
them:

1. **The prelude is `set -euo pipefail`, plus `readonly PARA_CONTRACT=1`.**
   The Parafile runs under para's own strict mode today, and
   `docs/versioning.md` *documents* that reading a not-yet-defaulted key trips
   `set -u` — deliberate contract behavior. `readonly` preserves today's error
   when a Parafile tries to assign `PARA_CONTRACT`.
2. **Defaults are two-phase.** `PARA_CONTRACT`, `PARA_POOL`, `PARA_BRIDGE`,
   `PARA_HTTPS_PORT`, `PARA_WORKCOPY_HOST/PORT`, `PARA_IP_LO/HI`
   (bin/para:78-106) resolve **before** sourcing and are readable by the
   Parafile; `PARA_CLONE_DIR`, `PARA_USER/UID/GID`, `PARA_PROJECT`,
   `PARA_IMAGE`, `PARA_DOMAIN`, `PARA_VOLUME`, `PARA_HOST_ENV`,
   `PARA_CLONE_BRANCH` default **after** (bin/para:154-249). The eval env
   injects the pre-set; TS applies the post-set to the result.
3. **`PROJECT_ROOT` and the `PARAFILE` override are inputs.** The documented
   `PARA_ORIGIN` derivation reads `$PROJECT_ROOT` inside the Parafile; it must
   be present (unexported today, so injected explicitly, not inherited).
4. **User-config overlay applies when the env var is unset *or empty***
   (`[ -n "${!_k:-}" ]`, bin/para:64) — a naive `key in process.env` check
   flips this. Values are literal (no expansion), split on first `=`,
   non-`PARA_[A-Z_]*` lines silently dropped, denylist warnings on stderr.
   All owned by `core/config.ts`, unit-tested against the precedence table in
   `docs/parafile.md`.

`ROUTES_DECLARED` falls out of a `declare -p PARA_ROUTES` probe in the same
subprocess (unset / scalar / legacy-array, keeping the array migration error).

**Config load is unconditional inside a project, exactly as today** — `--help`
prints Parafile-resolved values, `ls` scopes by the Parafile's
`PARA_PROJECT`, and therefore **completions (fed by `ls --names`) also need
the eval**. The earlier claim that completions skip it was wrong. The ~5 ms
subprocess cost is the completion budget's floor; acceptable, measured (see
Performance).

### Hook environment: the blanket is the contract

`run_hook` forwards **every `PARA_*` in scope** (`${!PARA_@}`,
bin/para:994-999), and `docs/hooks.md` documents that openness — a user's own
`PARA_FOO` from Parafile *or user config* must reach hooks, and para internals
(`PARA_STATE_DIR`, `PARA_POOL`, `PARA_HTTPS_PORT`, …) ride along today. The
TS forwarder is therefore: **all `PARA_*` from the post-eval resolved map**
(documented or not) ∪ the computed per-workspace set
(`PARA_NAME/URL/SHARED/HOSTNAME/GIT_NAME/GIT_EMAIL`) ∪ `PARA_CONTRACT`. A
curated known-keys forwarder would be a contract break.

## Registry

The flat positional file (`name ip routes domain project`, `-` sentinels) is
host-internal state, **not contract** (verified: no template hook or doc-facing
contract reads it; `docs/internals.md` mentions the path and updates with the
change). It was PR #9's biggest bug source and should become one JSON file per
workspace — **but not until Phase 4.** Both reviews independently flagged the
original Phase 1 timing as the plan's worst flaw:

- The JSON directory would occupy the flat file's exact path
  (`$PARA_STATE_DIR/workspaces`), so every legacy verb breaks outright
  (`touch` on a dir "succeeds", appends and `mv` fail mid-`up` after `incus
  launch`, `ip_of`/`project_of` read empty, `gen_caddyfile` dies).
- Even at a fresh path, dual-format state means a legacy `up` regenerates the
  machine-wide Caddyfile from a flat file missing every JSON-only workspace
  and reloads it — **live routing loss for every other workspace**, silently
  (that reload swallows errors — see sanctioned fixes).
- Registry *readers* stay legacy into Phase 3 (`sh`/`claude`/`run`/`key` via
  `ip_of`/`require_ws`), so even "migrate with the Phase 2 writers" is too
  early.

Resolution: `core/registry.ts` is the **typed accessor from Phase 1, over the
legacy flat format** (a ~20-line parser, throwaway by design; sentinels
translated at the boundary: `routes: []` ↔ `-`). The format swap is a
**Phase 4 change**, after `bin/para-legacy` is retired: new path
`$PARA_STATE_DIR/workspaces.d/<name>.json`, one-way migration keeping the old
file as `workspaces.migrated` (the rollback artifact), atomic tmp+rename
writes. Two compatibility tails, both Phase 4 work items:

- The **container stamp** `user.para.routes` carries `-` in already-stamped
  containers; TS `reconcile` translates it forever.
- The CLI-tier fixtures `a_registry_row`/`forget_registry_row`
  (test/lib/project.sh:141-153) write the flat format directly and are updated
  in the same PR as the swap — the one place "the suite is unchanged" needed a
  carve-out. The e2e tier asserts registry state only through para commands
  and is format-agnostic.

`caddy/caddyfile.ts` takes `WorkspaceRecord[]` and returns text — pure,
unit-tested, including the cross-row duplicate-host guard.

## Compatibility policies (the dual-implementation window)

- **Frozen surfaces:** error/warning message text, exit codes (1 for user
  errors, `128+sig`), and stream discipline — `log/warn/die` → stderr; data
  (`ls --names`, `key`, `completions <shell>`, `config-dump`) → stdout.
  `cli/adapter.ts` overrides cliffy's error handler, exit codes, and help
  renderer: **`--help` is a config-introspection surface** (tests assert the
  resolved-config table, the absence of `para-dev`, and that user-config
  warnings appear on it), so help is hand-rendered from the verb table + the
  resolved config, not delegated to cliffy's formatter.
- **Golden config cross-check:** before Phase 1, a hidden `para config-dump`
  (sorted `KEY=VALUE` of every resolved `PARA_*` + `ROUTES_DECLARED` +
  `PROJECT_ROOT`) is added to the **bash** script (tiny PR), then implemented
  in TS, and CI diffs the two across a fixture matrix: env
  set/empty/unset × user config present/absent × Parafile variants
  (denylist warnings on stderr included). This pins the subtle cases — the
  unset-or-empty overlay, slug derivation (`tr` char class + edge-hyphen
  trim), `PARA_IMAGE`/`PARA_VOLUME` derivation — where silent drift would make
  workspaces "disappear" from `ls` with nothing erroring. The verb survives
  Phase 4 as a support tool.

## Why TypeScript and not Go (considered and decided)

Go was seriously considered: incus is Go and ships the client library its own
CLI uses (`github.com/lxc/incus/client`), which would turn the ~45 incus
subprocess call sites into typed API calls; `syscall.Exec` is first-class; a
static binary makes install and completion startup trivially perfect. Decision:
**TypeScript**, because —

- **The incus REST API is not Go-exclusive.** The daemon speaks versioned REST
  over a unix socket; Node/Bun reach it natively (undici `socketPath`, Bun
  `fetch` unix option). para uses ~15 endpoints; typing them by hand is small.
  The Go library is pre-written types, not privileged access.
- **Interactive exec is sidestepped in both languages.** The API path means
  websockets + raw-mode PTY + resize forwarding — the incus CLI already got
  that right, and `execReplace` into it keeps it. A Go port would sensibly do
  the same, so Go's API advantage shrinks to non-interactive calls.
- **Porting on the identical CLI seam is the safety rail.** Same argv the bash
  issued, validated by the same suite. Language *and* seam at once doubles
  drift surface. Corollary, either language: **stay on the CLI seam for the
  port**; REST-over-socket is a separate, later, incremental change — which
  also matters because the test suite's backend *fence* is PATH-based
  (test/lib/project.sh): a unix-socket client would bypass the sandbox.
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

The authoritative verb inventory is `main()`'s dispatch table
(bin/para:2211-2242) — every row gets a phase assignment in the Phase 0 PR
(the draft below covers the known surface; earlier drafts listed a nonexistent
`auth` verb and omitted `start`/`stop` entirely — the table, not prose, is the
checklist). Every phase PR carries its docs updates in the same change
(CLAUDE.md rule), and versioning.md Decisions entries land **when the change
lands**, not at the end.

**Phase 0 — scaffold + packaging.** Toolchain; `proc/run.ts`; `ui.ts`; verb
table + adapter with every verb marked `legacy` (dispatch = `execReplace` into
`bin/para-legacy`) except `install`, marked **removed** (see Packaging — this
replaces what was previously a Phase 0 rework of `cmd_install`); the shim;
eslint fences; `config-dump` in bash; CI matrix + performance baselines
(below).
*Gate:* full suite green under **both** forced runtimes; manual TTY checklist:
interactive `sh`, `claude` under resize, Ctrl-C mid-`image build` (temp alias
cleaned), a hook prompt flow. Plus a new e2e test pinning dispatcher
transparency: `para sh ws -c 'exit 42'` → 42; child killed by signal →
`128+sig`.

**Phase 1 — config + read-only verbs.** `core/config.ts`, `core/parafile.ts`,
`core/routes.ts`, `core/registry.ts` **(legacy format)**, `config-dump` in TS
+ CI diff; port `ls`, `web`, `config-set`, `init`, help, completions.
*Gate:* CLI tier + config-dump matrix green; completion round-trip beats the
performance budget under node.

**Phase 2 — lifecycle.** `up`, `down`, `rm`, `start`, `stop`, `reconcile`,
`caddy/*`, `incus/ready.ts`, `run_hook`. The `up` ordering (ownership → routes
→ domain → backend → uid-drift → launch/converge) ports check-for-check.
*Gate:* `test/run --e2e` per verb on Linux; a macOS/colima manual pass for
`start`/`ensure_backend`; docs: internals/how-it-works state sections +
versioning.md entries for the sanctioned fixes. **This is the schedule risk:
`cmd_up` sits on `ensure_backend`/`ensure_pool`/`ensure_idmap`/
`ensure_volume`/`alloc_ip` — the most environment-sensitive code in the tool
(zfs/btrfs/colima branches), covered only by e2e. Budget 2–3 weeks, not
days.**

**Phase 3 — sessions + image.** `sh`, `run`, `claude`, `key`,
`config-import`, `config-sync`, `image build/status/rm` + the deprecated
`image-build` alias (its warning text is test-asserted).
*Gate:* `PARA_TEST_REBUILD=1 test/run --e2e` (the steady-state suite skips
image builds — without this flag a ported `cmd_image_build` ships untested);
one full `templates/void-docker-gh` run end-to-end on Linux (the suite is
Docker-free by design); the TTY manual checklist again.

**Phase 4 — retire + registry swap.** Delete `bin/para-legacy`; registry
format swap (`workspaces.d/`, migration, stamp `-` translation, test-fixture
update — all one PR); `bin/lint` scope shrinks to the remaining shell; final
docs pass; versioning.md port entry (non-breaking: implementation change,
contract intact).

Phases 1 and 3-minus-image-build are the "days" work; Phase 0's packaging and
Phase 2 are the honest cost centers.

## Packaging & distribution (Phase 0 unless noted)

- **`para install` is removed, not ported.** Its rationale — a zero-toolchain
  copy-one-file install from a checkout — dies with the port: the ported para
  requires node/bun, so everyone who can run it has npm, and the README/
  getting-started funnel is already `npm i -g paraspace`. Audiences:
  npm global install (primary; updates via `npm update -g`, dissolving the
  stale-installed-copies problem); `bunx paraspace` for taste-tests only
  (completions and state want a stable bin); `bun link`/`npm link` or the
  checkout's own `bin/para` for contributors; `npm i -D paraspace` + `npx
  para` for project-pinned versions. In Phase 0 the verb table marks `install`
  **removed** (not `legacy`): it prints the npm instruction and exits 1. Same
  PR: drop its `docs/commands.md` row and add a versioning.md Decisions entry
  (command surface is not `PARA_CONTRACT`; pre-launch, zero consumers). The
  XDG template-staging machinery goes with it — npm ships `templates/` inside
  the package where `pkg_root` already resolves them, and the shim now covers
  exactly **two** layouts: git checkout and npm global.
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
Budget: completion round-trip < 50 ms bun / < 120 ms node (includes the
~5 ms Parafile eval, which completions cannot skip — see above). If node
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

- **cliffy** — stable since 1.0.0 (2026-02; 1.2.1 current, actively
  released), so the former RC concern is resolved. Residual risk is ordinary
  single-maintainer/JSR-distribution risk, handled by exact-pin + bundling +
  the adapter; fallback candidate remains Bloomberg `stricli`.
- **`process.execve` maturity** — experimental-flagged in Node; the spawn
  fallback is behaviorally equivalent and mandatory anyway (Node < 23).
- **Phase 2 is the deep end** — environment-sensitive backend code with
  e2e-only coverage; the per-verb e2e gate and the macOS manual pass are the
  mitigations, and the estimate says weeks on purpose.
- **Parafiles doing exotic bash** — the eval subprocess gives them today's
  semantics (strict mode included); anything reading para *internals* beyond
  the documented env may break, which the contract explicitly permits.
- **Interactive/TTY behavior has no automated tier** — hence the dispatcher
  e2e test (exit status, signal) plus the recurring manual checklist as named
  phase-exit criteria.
