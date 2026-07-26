# Plan: the hook runner — one hook name, many hooks

> **Working document.** Delete it once `docs/run-hook.md` carries the resolution
> rule and the runner's contract, and the [mods](./mods.md) migration is adopted.
> Paired with [`plans/mods.md`](./mods.md): this plan is the seam, that one is
> what it's for. Land this first. (#18 — `PARA_HOOKS`/`PARA_SKEL` — is merged;
> this builds directly on it.)

## Goal

Let a hook name resolve to **more than one script**, so a project can compose
provisioning out of parts it didn't write — and let a project **open hook points
of its own** that para has never heard of.

```sh
# .paraspace/hooks/provision, once the clone is in place
"$PARA_RUN_HOOK" post-clone
```

para runs `provision` and `boot`. Everything else in that vocabulary belongs to
projects and the people writing against them.

## The rule

For hook `H`, para runs the project's, then one per mod:

```
hooks/H                    # the project's own
mods/<m>/hooks/H           # each mod's, mods in LC_ALL=C directory order
```

One file per hook name per owner. No `H.d/`, no `NN-` prefixes, no priority
field:

> **Hooks are order-agnostic. Where order matters, fill a named point.**

Order-agnostic is a statement about the *hook*, not about outcomes. Two hooks
that write the same file still collide; para promises nothing about who wins,
and [mods.md](./mods.md#what-a-mod-may-assume) makes not-colliding an authoring
rule rather than a mechanism.

Sorting is `LC_ALL=C` so a run is reproducible across machines — a plain glob
collates by the ambient locale, and `Zsh` and `dotfiles` sort one way on a
developer's host and the other in the guest. In the runner it must be

```sh
export -n LC_ALL 2>/dev/null; LC_ALL=C
```

A bare assignment does **not** make it shell-local: assigning to an
already-exported variable keeps the export attribute, so on any guest whose
`/etc/profile.d` exports `LC_ALL` — `su -` runs a login shell — every hook would
silently inherit `LC_ALL=C`, which is the regression this is meant to prevent.
(On the host `bin/para` uses the `LC_ALL=C sort` command-prefix form instead, so
nothing leaks into `incus`, `caddy` or project commands.)

## Hooks are sourced in a subshell

```sh
( . "$hook" )
```

Not `exec`'d by path. This reverses the minimal-engine rewrite's move to
run-by-path — `docs/versioning.md`'s migration table records it — and trades
away a hook's freedom to pick its own interpreter. para is pure bash and the
guest already requires bash, so the trade is worth making now, while contract 1
is soft and there are no consumers.

What it buys:

- **No exec bit anywhere in the hook path.** `push_project`'s `chmod -R +x` and
  its `[ -d … ]` guard are deleted outright, and mods, hand-written mods and
  the builder all stop needing one. A checkout with `core.fileMode=false`, a
  tarball, or a zip no longer break a workspace. (Mod **commands** still run as
  host processes and do still need the bit — see
  [mods.md](./mods.md#commands).)
- **The hook reads the runner's environment directly.** A subshell inherits
  non-exported variables, so re-pointing `PARA_HOOKS`/`PARA_SKEL`/`PARA_MOD*`
  is plain assignment with no `export` prefix and no quoting.

What the subshell keeps that direct sourcing would have broken:

- **`exit` still means "this hook".** `helpers`' `die()` is `exit 1`; inside
  `( … )` that ends the subshell and the status reaches the runner, which
  aborts. Identical to today — no `return`-not-`exit` rule, no rewriting `die`,
  and no footgun where one hook's `exit 0` silently cancels every later mod.
- **`cd`, `set -o` and variable names don't leak**, so the runner needs no
  defensive namespacing and one `cd` per invocation is enough.

And the rule that makes the model small enough to state in a sentence:

> **A hook reads its environment and writes to the filesystem. It never writes
> to its caller.**

There is deliberately no channel for a hook to contribute a variable back. The
one case that wanted it — `$BROWSER` for `gh auth login`'s device flow — is mod
policy with an image-level answer: the mod's build hook writes
`/etc/profile.d/`, `su -` sources it, and every hook has it before any of this
runs.

The shebang becomes decorative. Keep `#!/usr/bin/env bash` on hooks — `bin/lint`
discovers files *by* shebang, and editors want it — and say plainly in the docs
that para ignores it, or someone writes `#!/usr/bin/env python3` and it silently
runs as bash.

## Why a runner in the guest, not a loop on the host

para pushes its own script to `$PARA_RUN_HOOK`, and `run_hook` becomes three
lines:

```sh
run_hook() { # run_hook <hook> <name>
  ws_exec "$2" "exec \"\$PARA_RUN_HOOK\" $1" || die "the '$1' hook failed (above)."
}
```

Host-side enumeration — one `ws_exec` per candidate — would work for
`provision` and `boot`, and would leave every *named* point hand-rolling its own
glob-and-sort inside a project hook. One implementation, reachable from both
sides, is the whole argument.

It is legitimately generic mechanism, not a boundary violation: it contains no
ports, no repo URLs, no compose knowledge. para already authors guest-side
artifacts — `GUEST_PRELUDE` is a script it splices in, `~/.paraspace/env` a file
it writes.

### `PARA_RUN_HOOK`, not a literal path

Injected as a **fourth `local` in `push_project`**, beside #18's three. Three
reasons, and it has to happen in *this* PR because the spelling becomes contract
the moment a project hook contains it:

- In the guest `~/.paraspace` *is* the project's `.paraspace`; on the host they
  are different directories. A hardcoded `~/.paraspace/run-hook` makes the CLI
  tier's nested-point and recursion tests unwritable without contorting `$HOME`.
- The builder's copy lives somewhere else again ([mods.md](./mods.md#image-build)).
- #18 established naming these by injected variables rather than by `$HOME`.

**The runner exports `PARA_RUN_HOOK` itself**, from its own resolved path. A
hook that opens a nested point otherwise dies with `unbound variable` under
`set -u` unless it re-sources `~/.paraspace/env` — which this plan tells hooks
not to do. One line, and it is what makes the CLI-tier tests one-liners.

## What the runner must get right

Each of these is a way the obvious first draft breaks. A reference
implementation is ~80 lines, shellcheck-clean, and satisfies all of them.

- **Bash shebang, and the bash 3.2 bar.** `bin/lint` selects files by a `bash`
  shebang, so `#!/bin/sh` would ship unlinted. It is also a new shipped script
  that `test/run --cli` executes under macOS's bash 3.2, which CI (ubuntu-only)
  structurally cannot catch; #22 was exactly that class of bug.
- **`--mode 0755`, pushed after the recursive push**, so a project shipping its
  own `.paraspace/run-hook` can't shadow para's. `push_project` `die`s naming
  `libexec/run-hook` if it is missing from the package rather than letting
  `incus file push` report an empty source path.
- **In `package.json`'s `files`.** It lists `bin/para`, *not* `bin/`, so a new
  top-level directory is invisible to npm. Miss it and every published para
  execs a file that was never packaged, on the first hook of every project. Add
  a CLI test asserting `npm pack --dry-run` covers everything `pkg_root`
  resolves against. `pkg_root` moves onto the `up` path **and** the
  `image build` path for the first time, so a `bin/para` copied out of its
  package now fails there.
- **Root from its own path**, never from `$PARA_HOOKS` — which the runner itself
  re-points. A mod hook opening a nested point would otherwise enumerate
  `mods/<m>/mods/*` and silently skip every other owner.
- **`for dir in "$root"/mods/*/` with `[ -d "$dir" ] || continue`**, not
  `find | while read`. A piped loop hands the hook list to the hook as stdin,
  killing every prompt — and `provision` is documented to prompt. The `-d` guard
  is the unmatched-glob case.
- **stdin belongs to the hook.** One tty and one stdin feed the project's hook
  *and* every mod's; the runner reads neither. In the builder there is no tty at
  all ([mods.md](./mods.md#image-build)), so that promise is `up`-only.
- **One `cd` per invocation**, to the documented place — `~/$PARA_CLONE_DIR` if
  it exists, else `$HOME`. The subshell keeps it from leaking. The cost is worth
  naming: `GUEST_PRELUDE` already implements this rule, so it now lives in two
  files.
- **Says what it is running.** `run_hook`'s host-side `Running hook: X` goes
  away with the existence check, so the runner prints one line per candidate and
  a `no 'X' hook — skipping` when there are none. Without the latter,
  `docs/hooks.md`'s "an absent hook is a visible no-op" becomes false; without
  the former, `para up` goes silent between the volume chown and the hook's own
  first output.
- **Errors name the file** and propagate its exit status.
- **A cycle guard** that doesn't bury its own diagnosis: the active stack in
  `_para_hook_stack`, dying with `hook point 'provision' is already running
  (provision → post-clone → provision)`, using a **distinguished exit status**
  so enclosing frames propagate silently instead of stacking one
  `error: … failed` per level above the only useful line. The name is
  deliberately not `PARA_*`: `para_env` forwards every `PARA_*` in scope, so
  that spelling would need an `unset` entry *and* would be cleared by any hook
  that re-sourced `env`.

It is **runnable on the host against a fixture `.paraspace/`**, so all of the
above gets CLI-tier tests with no incus. With `PARA_RUN_HOOK` self-exported,
each is a two-line test.

## The environment a hook sees

The runner **re-points #18's two at whoever owns the hook**, and adds the
owner's identity:

```sh
( PARA_HOOKS=$owner/hooks PARA_SKEL=$owner/skel \
  PARA_MOD=$name PARA_MOD_DIR=$mod_dir; . "$hook" )
```

so a mod's hook is written *identically* to a project's:

```sh
. "$PARA_HOOKS/helpers"                  # the mod's own helpers
cp "$PARA_SKEL/zshrc" ~/.zshrc           # the mod's own skel
```

**`PARA_MOD` and `PARA_MOD_DIR` are always set, and empty for the project's own
hooks** — so `[ -n "$PARA_MOD" ]` is how a shared hook body asks "am I a mod?"
without tripping `set -u`. Set-only-when-a-mod would break exactly that idiom.

`.shellcheckrc`'s `source-path=SCRIPTDIR` already resolves `$PARA_HOOKS/helpers`
by basename, so a mod's `hooks/helpers` follows for free.

`PARA_MOD_DIR` earns its place because **a mod's `commands/` run on the host**,
where `PARA_HOOKS`/`PARA_SKEL` are unset by design, so a mod command has no
other way to reach its own files. It lands with
[mods.md](./mods.md#commands)'s resolver, which is what exports it there.

Two sharp edges to write down:

- **Don't re-source `~/.paraspace/env`.** It holds the *project's*
  `PARA_HOOKS`/`PARA_SKEL`, and `GUEST_PRELUDE` re-sources it on every
  `ws_exec`; a hook that re-sources it mid-run silently rewinds them. The runner
  already gave you the right values.
- **The context does not survive `su -` or `sudo`**, both of which reset the
  environment. A build hook that installs *as* another user needs
  `su - "$PARA_USER" -c 'PARA_SKEL=… …'`.

`PARA_MOD` and `PARA_MOD_DIR` join `push_project`'s `unset` line **in this PR**,
before mods exist — otherwise a runner-only release forwards a stray ambient
`PARA_MOD` into every hook, and the per-hook assignment hides it only for hooks
the runner runs, not for `para sh`.

Extract `guest_env()` here too, with one caller. It is the "guest's corrected
view of `para_env`" that [mods.md](./mods.md#image-build) needs a second caller
for; adding the fourth `local` now and extracting later means rewriting
`push_project` twice.

## Contract

**Additive — `PARA_CONTRACT` stays 1** for the resolution rule: a project with
one `hooks/provision`, no mods, and no `run-hook` lines resolves to exactly one
file and behaves identically. Sourcing instead of executing is *not* additive —
it changes hook semantics — but contract 1 is deliberately soft pre-adoption
(see [below](#a-note-on-contract-1)), so it lands inside it with a
`docs/versioning.md` row.

Three new claims on a tree the project ships verbatim, all of which
`docs/versioning.md` names as contract surface:

- para now **executes** `.paraspace/mods/*/hooks/*`.
- `.paraspace/run-hook` joins `env` and `host.env` as a name para owns.
- `$PARA_RUN_HOOK`'s argument form and the env it sets are public API the moment
  a project hook contains it.

Make the second fail loudly: **`require_project` refuses** a project shipping
its own `.paraspace/run-hook` (test `-e`, so a directory is caught too). Not
`push_project` — that runs after `incus launch`, the volume and a 120s-capable
readiness wait, so the refusal would cost a container every time. In
`require_project` it fires before any backend call, which is also what lets the
CLI tier assert it with `assert_backend_untouched`.

## A note on contract 1

`PARA_BASE_IMAGE` → `PARA_IMAGE_BASE` (merged in #21) changed a `Parafile` var
without bumping `PARA_CONTRACT`. **This is deliberate**: paraspace has no
consumers yet, so contract 1 is soft and pre-adoption cleanups land inside it.
Recorded so it isn't re-litigated. The open question is when contract 1 freezes
— first real consumer, or the 1.0 publish — and that answer wants a line in
`docs/versioning.md` when it's made.

## Test checklist

CLI tier, all against a fixture directory with no incus:

- resolution: project before mods, mods in `LC_ALL=C` order, a mod with no `H`
  skipped, no `mods/` at all → unchanged behavior, `hooks/helpers` never
  sourced, zero candidates prints the skip line, each candidate announced.
- a failing hook aborts the rest, its **path** is in the error, and its exit
  status propagates — including a hook whose `helpers`-style `die` is `exit 1`.
- a hook with no exec bit runs (that is the point of sourcing), and a hook's
  `cd`, `set -o` and stray variables do not reach the next hook.
- `PARA_HOOKS`/`PARA_SKEL`/`PARA_MOD`/`PARA_MOD_DIR` re-pointed per hook, both
  `PARA_MOD*` set-and-empty for the project's own; the documented cwd.
- a **nested** point from inside a mod hook resolves every owner; a cycle dies
  naming it, once, not once per frame; an ambient `_para_hook_stack` doesn't
  trip it.
- a hook that reads stdin gets the caller's stdin, not the hook list.
- an ambient exported `LC_ALL` does not reach hooks as `C`.
- `require_project` refuses a project shipping `.paraspace/run-hook`, backend
  untouched.
- `npm pack --dry-run` covers `libexec/`.

e2e tier (run it — CI won't): a fixture mod that appends its name in `provision`
and in a named point the fixture project opens; assert both ran, in order, and
`para up` still idempotent. A prompting hook still gets the terminal.

## Docs

This PR ships its own docs — CLAUDE.md makes that mandatory for a hook-semantic
change, and this plan can't be deleted until they exist. `docs/hooks.md` is ~131
lines after #18; the resolution rule, the sourcing model, `PARA_MOD*`, the
run-hook API, the guest-layout row, the don't-re-source note and the `su -`
caveat push it past the ~150 gate. So: a new **`docs/run-hook.md`** carrying the
runner's contract, `docs/hooks.md` gaining the resolution rule, the sourcing
change and a link, plus a `.vitepress/config.mts` sidebar entry and a
`docs/README.md` router line. `docs/versioning.md` gets the sourcing row.

## Sequence

1. **`void-docker-gh`'s seeding fix**, alone — see
   [mods.md](./mods.md#the-first-pr-has-nothing-to-do-with-mods). No engine
   change, no runner.
2. **This plan**: the runner, `PARA_RUN_HOOK`, `run_hook`, `guest_env`, the
   `unset` line, the `require_project` refusal, `libexec/` in `files`, the docs
   and the tests. Mods do not exist yet — the runner resolves `mods/*/hooks/H`
   and finds nothing.
3. [mods.md](./mods.md) from there.

Step 2 is independently shippable and independently useful: the day it lands, a
project can split its own **guest** provisioning into named points. Build-time
points wait, because `cmd_image_build` never calls `push_project`, so no runner
reaches the builder until the image work.
