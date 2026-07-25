# The minimal engine: a total rewrite of `bin/para`

Status: planned. This **supersedes** `plans/cut-and-harden.md` (PR #11),
`plans/ts-port.md` (PR #10), and `plans/go-rewrite.md` — all three were
answers to "how do we live with these 2,244 lines"; this plan's answer is
that most of them should not exist in the engine at all. Decisions, made:
**bash**, rewritten minimal; **`PARA_CONTRACT` 2**, redesigned freely
(pre-launch: madi, the templates, and the fixtures migrate in the same
pass — the "bank the breakage now" argument from go-rewrite.md, finally
banked); **open verb dispatch to host-side template hooks** as the one new
primitive that does most of the halving.

## The thesis

para's one rule is that the engine is a generic mechanism holding zero
project policy. The current `bin/para` violates it in both directions: it
carries policy (claude/tmux sessions, a pubkey path, one template's skel
layout, compose parsing, install plumbing), and it lacks the primitive that
would let templates carry that policy themselves. The rewrite fixes the
architecture, and the line count follows: **target ≤ 1,100 lines** (from
2,244), achieved by subtraction and by a clean rewrite — not by compressing
prose. The maintainer's habitability complaint is answered structurally: a
small engine that does one thing is readable in any language, which is why
the language question, so hard at 2,244 lines, dissolved at 1,100 — bash,
written fresh, no compat baggage, no policy, no apologies.

## The one new primitive: open verb dispatch

```
para <verb> [args…]
  known engine verb        -> engine
  .paraspace/hooks/host/<verb> exists -> exec it, HOST-side, with the full
                              resolved PARA_* env injected (same blanket
                              forwarding as guest hooks)
  otherwise                -> unknown command error
```

Like `git-<foo>`: a template ships a file, and `para <foo>` exists — no
engine change, no PR to paraspace. Host hooks run on the host with the
user's tty (interactive flows work naturally), receive every resolved
`PARA_*`, and **compose by calling back into para** (`para ls --names`,
`para sh <ws> -c …`, `incus` directly if they choose). Workspace resolution
is the hook's business — para passes args through verbatim. ~15 lines of
dispatch replaces ~250 lines of engine verbs, and it is the extension
mechanism this tool always implied.

Engine verbs shadow hooks (the engine namespace wins; a template cannot
silently replace `para up`). `para --help` lists discovered host verbs in
their own section, sourced from the files' `# summary:` first-comment line.

## What the engine keeps (mechanism only)

| Verb | Why it's mechanism |
|---|---|
| `up` / `down` / `rm` / `start` / `stop` | incus lifecycle, IP allocation, volume attach, registry, hooks, Caddy |
| `ls` (+ `--names`) | registry reader; completion feeder |
| `sh` | the TTY door into a workspace (`exec incus … su -`); everything else builds on it |
| `reconcile` | registry ↔ container-stamp repair |
| `image build` / `status` / `rm` | the publish/swap choreography and provenance stamps are engine-grade |
| `init` (+ `--list`/`--names`) | how a consumer gets a template; pure file copy |
| `config-set` | the user-config write path + denylist |
| `completions <shell>` | generated from the verb table + discovered host verbs |
| `--help` / `--version` | resolved-config introspection stays |

Internals that carry over **as spec** (the domain knowledge is the valuable
part of the old file; it is rewritten around, not discarded): the backend
preflight (colima, dir-pool/vfs footgun, idmap/OpenZFS), `wait_ready`'s
agent+DNS budget, `gen_caddyfile` with the cross-row duplicate-host guard,
the image publish/swap with temp alias + `published` latch, `su`-vs-`exec`
initgroups and `su --pty` SIGWINCH semantics (now documented once, at `sh`),
the `${!PARA_@}` blanket hook-env forwarder, ownership stamps.

## What offloads to templates (host hooks, shipped per template)

| Was | Becomes |
|---|---|
| `cmd_claude`, `cmd_run` (claude/tmux session policy) | `hooks/host/claude`, `hooks/host/run` in `void-jchook` (and any template that wants them) |
| `cmd_key` (hardcoded `/para/shared/ssh/…` path) | `hooks/host/key` in templates whose provision hook creates that key |
| `cmd_config_sync` (one template's skel layout + statusline chmod) | `hooks/host/config-sync` owned by the template whose skel it is |
| `cmd_config_import` | `hooks/host/config-import` (it was `incus file push` sugar) |
| `cmd_web` (xdg-open an URL) | `hooks/host/web`, or nothing — `para ls` prints the URL |
| `stack_images` (compose/Dockerfile parsing) | the template's Parafile derives `PARA_IMAGE_PREPULL` itself (sourced bash — it can); engine pre-pulls whatever the key lists, or nothing |
| `cmd_install` + XDG staging | gone; npm is the funnel |
| `image-build` alias | gone |

Because the hooks own their own paths, the `PARA_PUBKEY`/`PARA_RUN` keys the
cut-and-harden plan invented are unnecessary — offloading beats
parameterizing.

## Contract 2

Breaking (the reason this is v2):

- **Host hooks + open dispatch** exist; `hooks/` splits into `hooks/host/`
  and the guest hooks (`provision`, `boot` — names and semantics unchanged).
- Verbs removed from the engine (table above): consumers that called them
  get them back from their template's hooks.
- Anything else found mid-rewrite that contract 1 got wrong gets fixed
  deliberately and logged in versioning.md — this is the one window where
  that is free.

Kept from contract 1 (proven good): the Parafile as sourced bash with the
same core keys and `:=` precedence; the blanket `PARA_*` env forwarding into
hooks (now host hooks too); the guest `~/.para` layout; `PARA_VERSION`
pinning — a v1 project gets the clear refusal, and the migration is
documented in versioning.md (for madi and the templates it is: move files
into `hooks/host/`, set `PARA_VERSION=2`).

## Clean-room properties (day one, not retrofits)

The rewrite starts from an empty file and steals proven fragments
deliberately. Baked in from the first commit:

- **Registry is KEY=VALUE per workspace** (`workspaces.d/<name>`): no
  positional fields, no `-` sentinels, no whitespace guards — the entire
  PR #9 bug class is unrepresentable.
- **No top-level execution**: `main()` calls `load_config()`; helpers exist
  before anything runs; a **source guard** makes every pure helper
  unit-testable, and a `test/unit/` tier ships with the rewrite.
- The three known bug fixes are just how it's written: `caddy validate`
  before reload with surfaced failures; `route_host` lowercases the whole
  host; no dead fallbacks.
- shellcheck with the optional checks
  (`check-set-e-suppressed,check-extra-masked-returns,add-default-case`) +
  `shfmt` in `bin/lint` from the start — the new file is written under the
  rules, not graded against them later.
- Comments are **domain spec only**. Bash-mechanics commentary is treated as
  a smell: if a line needs a bash warning, write the line that doesn't.

## Line budget (the honesty check on "half or more")

| Section | est. lines |
|---|---|
| config load + validation + denylist | ~200 |
| backend preflight (incus/colima/pool/idmap/volume) | ~200 |
| caddy (start/validate/reload/generate) | ~100 |
| registry (KEY=VALUE) | ~40 |
| lifecycle verbs (up/down/rm/start/stop/ls/reconcile) | ~250 |
| image (build/status/rm) | ~150 |
| `sh` | ~40 |
| `init` | ~80 |
| dispatch + open-verb fallback + help + completions | ~80 |
| misc helpers (log/die/validate/poll) | ~60 |
| **total** | **~1,100** |

Domain comments are inside those numbers. If it lands at 1,200 it still
succeeded; if a section balloons past its budget, that's the review signal
that policy is creeping back in.

## Migration (one branch, staged, suite-green at the end)

1. **Write the engine** against the e2e fixture first: new `bin/para`
   developed as `bin/para2` beside the old one; the `hello` fixture gains a
   `hooks/host/` verb so dispatch is exercised from day one. The e2e tier
   (which drives mostly kept verbs — up/sh/ls/routes/volume) is adapted as
   the rewrite proceeds; the CLI tier is rewritten against the new surface;
   the unit tier is new.
2. **Migrate the bundled templates**: each gains its `hooks/host/` files
   (the offload table above), drops what it no longer needs, sets
   `PARA_VERSION=2`.
3. **Docs pass**: parafile.md, hooks.md (host hooks are new contract
   surface), commands.md (smaller), how-it-works, versioning.md's contract-2
   entry with the v1→v2 migration guide. CLAUDE.md's line-count references
   update.
4. **Migrate madi** (the repo-root `.paraspace/`) in the same change that
   swaps `bin/para2` → `bin/para` and deletes the old script. Git history
   keeps the 2,244-line original; nothing of it survives in the tree.

Gates throughout: `bin/lint` (new rules), CLI + unit tiers in CI, full e2e
locally including one `PARA_TEST_REBUILD=1` run and a real
`void-docker-gh` boot before the swap.

## What happens to the other plans

- `cut-and-harden.md` (PR #11): superseded — its A-cuts become offloads
  (better: templates keep the features), its B-hardening items are
  clean-room properties above. Close or repurpose the PR.
- `ts-port.md` (PR #10): stays shelved; its triggers still apply *to the
  1,100-line engine*, where a port would be a fraction of the analyzed
  cost — but the habitability motivation that drove it is answered here
  first. Its subprocess-pattern catalog and Parafile-eval analysis remain
  the reference if a port ever fires.
- `go-rewrite.md`: already superseded; its "bank the breakage" argument is
  realized by contract 2, its completion insight by the dispatch design.

## Risks

- **Contract 2 is a real break** — mitigated by owning every consumer
  (madi, templates, fixtures) and shipping the migration guide in the same
  PR set. `PARA_VERSION=1` projects fail loudly, as designed.
- **A rewrite can drop invisible behavior** — mitigated by treating the old
  file's domain comments as the checklist (they are the spec of the
  invisible behavior), and by the e2e suite surviving mostly intact.
- **Policy creep back into the engine** — the line budget per section is
  the tripwire; the open dispatch removes the excuse ("just one more verb").
- **Host hooks are new attack/confusion surface** — engine verbs shadow
  hooks; discovered verbs are listed in help so nothing runs invisibly;
  hooks run with the user's own privileges, same as any script in a repo
  they cloned (documented in hooks.md).
