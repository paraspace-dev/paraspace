# Plan: the hook runner — one hook name, many hooks

> **Working document.** Delete it once `docs/run-hook.md` carries the resolution
> rule and the runner's contract, and the [mods](./mods.md) migration is adopted.
> Paired with [`plans/mods.md`](./mods.md): this plan is the seam, that one is
> what it's for. Land this first.
>
> **Depends on [#18](https://github.com/paraspace-dev/paraspace/pull/18)**
> (`PARA_HOOKS`/`PARA_SKEL`).

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
developer's host and the other in the guest. It must be set as:

```sh
export -n LC_ALL 2>/dev/null; LC_ALL=C
```

A bare assignment does **not** make it shell-local: assigning to an
already-exported variable keeps the export attribute, so on any guest whose
`/etc/profile.d` exports `LC_ALL` — `su -` runs a login shell — every hook would
silently inherit `LC_ALL=C`, which is the regression this is meant to prevent.
Dev hosts export it more often than minimal guests do, so without `export -n`
the CLI tier would behave differently from what ships.

## Why a runner in the guest, not a loop on the host

para pushes its own script to `$PARA_RUN_HOOK`, and `run_hook` becomes:

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

The runner is injected as a **fourth `local` in `push_project`**, beside #18's
three, and reaches hooks through `para_env` like everything else. Three reasons,
and it has to happen in *this* PR because the spelling becomes contract the
moment a project hook contains it:

- In the guest `~/.paraspace` *is* the project's `.paraspace`; on the host they
  are different directories. A hardcoded `~/.paraspace/run-hook` makes the CLI
  tier's nested-point and recursion tests unwritable without contorting `$HOME`.
- The builder's copy lives somewhere else again ([mods.md](./mods.md#image-build)).
- #18 just established naming these by injected variables rather than by `$HOME`.

## What the runner must get right

Each of these is a way the obvious first draft breaks. A reference draft comes
in at ~50 lines, shellcheck-clean, and satisfies all of them simultaneously.

- **Bash shebang, and the bash 3.2 bar.** `ws_exec` already requires bash, and
  `bin/lint` selects files by a `bash` shebang — `#!/bin/sh` would ship
  unlinted. It is also a new shipped script that `test/run --cli` executes under
  macOS's bash 3.2, which CI (ubuntu-only) structurally cannot catch; #22 was
  exactly that class of bug.
- **`--mode 0755`, pushed after the recursive push**, so a project shipping its
  own `.paraspace/run-hook` can't shadow para's. `push_project` `die`s naming
  `libexec/run-hook` if it is missing from the package, rather than letting
  `incus file push` report an empty source path.
- **In `package.json`'s `files`.** `files` lists `bin/para`, *not* `bin/`, so a
  new top-level directory is invisible to npm. Miss it and every published para
  execs a file that was never packaged, on the first hook of every project. Add
  a CLI test asserting `npm pack --dry-run` covers everything `pkg_root`
  resolves against. Note `pkg_root` moves onto the `up` path for the first time,
  so a `bin/para` copied out of its package now fails at `push_project`.
- **The runner repairs the exec bit** on each candidate before running it
  (`[ -x "$f" ] || chmod +x "$f"`). This **deletes** `push_project`'s
  `chmod -R +x` and the `[ -d … ]` guard around it: one line, scoped to exactly
  the files being executed, covering mods, hand-written mods and the builder,
  with no glob inside an `incus exec` that has no shell — and without making
  `skel/` files executable or re-moding the `0600` `env`/`host.env`. A checkout
  with `core.fileMode=false`, a tarball, or a zip all lose the bit; today's
  chmod covers only `hooks/`, and a project with mods but no `hooks/` directory
  skips it entirely.
- **Root from its own path**, never from `$PARA_HOOKS` — which the runner
  itself re-points. A mod hook opening a nested point would otherwise enumerate
  `mods/<m>/mods/*` and silently skip every other owner.
- **`for dir in "$root"/mods/*/` with `[ -d "$dir" ] || continue`**, not
  `find | while read`. A piped loop hands the hook list to the hook as stdin,
  killing every prompt — and `provision` is documented to prompt. The `-d`
  guard is the unmatched-glob case.
- **stdin belongs to the hook.** One tty and one stdin feed the project's hook
  *and* every mod's; the runner reads neither. See
  [the builder](./mods.md#image-build) for where this bites hardest.
- **One `cd` per invocation**, to the documented place — `~/$PARA_CLONE_DIR` if
  it exists, else `$HOME`. Hooks are child processes, so a `cd` in one cannot
  leak to the next; per-hook re-`cd`ing buys nothing. The cost is real and worth
  naming: `GUEST_PRELUDE` already implements this rule, so it now lives in two
  files.
- **Says what it is running.** `run_hook`'s host-side `Running hook: X` goes
  away with the existence check, so the runner prints one line per candidate
  (`Running hook: <mod>/<H>`) and a `no 'X' hook — skipping` when there are no
  candidates at all. Without the latter, `docs/hooks.md`'s "an absent hook is a
  visible no-op" becomes false; without the former, `para up` goes silent
  between the volume chown and the hook's own first output. This is para's log
  vocabulary getting a second implementation — ~6 lines, deliberate, in exchange
  for two documented guarantees.
- **Errors name the file** and propagate its exit status.
- **A cycle guard** that doesn't bury its own diagnosis. The runner carries the
  active stack and dies naming it — `hook point 'provision' is already running
  (provision → post-clone → provision)` — using a **distinguished exit status**
  so enclosing runner frames propagate silently instead of stacking one
  `error: … failed` per level above the only useful line.
- **The stack variable is not a `PARA_*` name.** Call it `_para_hook_stack`.
  `para_env` forwards every `PARA_*` in scope, so a `PARA_HOOK_STACK` would need
  an entry on `push_project`'s unset line — and `GUEST_PRELUDE` re-sources
  `~/.paraspace/env` on every `ws_exec`, so a hook that re-sources it would
  clear the stack and re-open the fork bomb. A non-forwarded name needs neither
  the unset entry nor the caveat.

It is **runnable on the host against a fixture `.paraspace/`**, so all of the
above gets CLI-tier tests with no incus.

## The environment a hook sees

`PARA_HOOKS`/`PARA_SKEL` arrive from #18. The runner **re-points them at
whoever owns the hook it is about to run**, and adds the owner's identity:

```sh
PARA_HOOKS=$owner/hooks PARA_SKEL=$owner/skel \
PARA_MOD=$name PARA_MOD_DIR=$mod_dir "$hook"
```

so a mod's hook is written *identically* to a project's:

```sh
. "$PARA_HOOKS/helpers"                  # the mod's own helpers
cp "$PARA_SKEL/zshrc" ~/.zshrc           # the mod's own skel
```

**`PARA_MOD` and `PARA_MOD_DIR` are both empty for the project's own hooks** —
so `[ -n "$PARA_MOD" ]` is how a shared hook body asks "am I a mod?", and
`$PARA_MOD_DIR` is only ever a mod's directory. (An earlier draft set
`PARA_MOD_DIR` to the owner in all cases, which made it non-empty for the
project and gave the two variables different rules. Pick this one before it
reaches `docs/`.)

`.shellcheckrc`'s `source-path=SCRIPTDIR` already resolves `$PARA_HOOKS/helpers`
by basename, so a mod's `hooks/helpers` follows for free.

`PARA_MOD_DIR` earns its place only because **a mod's `commands/` run on the
host**, where `PARA_HOOKS`/`PARA_SKEL` are unset by design, so a mod command has
no other way to reach its own files. That means it is real only once
[mods.md](./mods.md#commands)'s resolver exports it per verb — the two land
together or the variable is justified by a capability nothing implements.

Two sharp edges, both of which need writing down:

- **`~/.paraspace/env` still holds the project's values**, and `GUEST_PRELUDE`
  re-sources it on every `ws_exec`. A hook that re-sources it mid-run silently
  rewinds `PARA_HOOKS`/`PARA_SKEL` to the project's — wrong file, no error.
  Don't re-source it; the runner already gave you the right values.
- **The context does not survive `su -` or `sudo`**, both of which reset the
  environment. A build hook that installs *as* another user needs the spelling
  `su - "$PARA_USER" -c 'PARA_SKEL=… …'`. This bites the migration directly.

`PARA_MOD` and `PARA_MOD_DIR` join `push_project`'s `unset` line: `para_env`
forwards every `PARA_*` in scope, so a stray `PARA_MOD=1` in a `Parafile` or the
ambient environment would poison every hook's view of itself. A mod command that
shells back into `"$PARA_BIN" up` is the realistic path for that.

## Contract

**Additive — `PARA_CONTRACT` stays 1.** A project with one `hooks/provision`,
no mods, and no `run-hook` lines resolves to exactly one file and behaves
identically.

Two things are nonetheless new claims on a tree the project ships verbatim, and
`docs/versioning.md` names the `~/.paraspace` layout as a contract surface, so
both get written down there:

- para now **executes** `.paraspace/mods/*/hooks/*`.
- `.paraspace/run-hook` joins `env` and `host.env` as a name para owns and
  overwrites.

Make the second fail loudly: **`require_project` refuses** a project that ships
its own `.paraspace/run-hook` (test `-e`, so a directory is caught too). Not
`push_project` — that runs after `incus launch`, the volume, and a 120s-capable
readiness wait, so the refusal would cost a container every time. In
`require_project` it fires before any backend call, which is also what lets the
CLI tier assert it with `assert_backend_untouched`.

`$PARA_RUN_HOOK` becomes **public API** the moment a project hook contains it —
its argument form and the env it sets are contract from then on, and changing
either is a bump. Say so in `docs/versioning.md`.

## A note on contract 1

`PARA_BASE_IMAGE` → `PARA_IMAGE_BASE` (merged in #21) changed a `Parafile` var
without bumping `PARA_CONTRACT`, which `docs/versioning.md` lists as a contract
surface. **This is deliberate**: paraspace has no consumers yet, so contract 1
is still soft and pre-adoption cleanups land inside it. Recorded here so it
isn't re-litigated. The question it defers is when contract 1 freezes — first
real consumer, or the 1.0 publish — and that decision wants a line in
`docs/versioning.md` when it's made.

## Test checklist

CLI tier — this is why the runner is a standalone script, and why
`$PARA_RUN_HOOK` matters: with it these are one-liners against a fixture.

- resolution: project before mods, mods in `LC_ALL=C` order, a mod with no `H`
  skipped, no `mods/` at all → unchanged behavior, `hooks/helpers` never
  executed, zero candidates prints the skip line, each candidate announced.
- a failing hook aborts the rest, its **path** is in the error, and its exit
  status propagates.
- a candidate with no exec bit runs anyway (the repair), including a mod in a
  project with no `hooks/` directory.
- `PARA_HOOKS`/`PARA_SKEL`/`PARA_MOD`/`PARA_MOD_DIR` re-pointed per hook, and
  both `PARA_MOD*` empty for the project's own; the documented cwd.
- a **nested** point from inside a mod hook resolves every owner (the
  `$PARA_HOOKS`-derived-root trap); a cycle dies naming it, once, not once per
  frame.
- a hook that reads stdin gets the caller's stdin, not the hook list.
- an ambient exported `LC_ALL` does not reach hooks as `C`.
- `require_project` refuses a project shipping `.paraspace/run-hook`, with the
  backend untouched.
- `npm pack --dry-run` covers `libexec/`.

e2e tier (run it — CI won't): a fixture mod that appends its name in `provision`
and in a named point the fixture project opens; assert both ran, in order, and
that `para up` is still idempotent. A prompting hook still gets the terminal
through the runner.

## Docs

Step 3 ships its own docs — CLAUDE.md makes that mandatory for a hook-semantic
change, and this plan can't be deleted until they exist. `docs/hooks.md` is 122
lines today and ~131 after #18; the resolution rule, `PARA_MOD*`, the run-hook
API, the guest-layout row, the don't-re-source note and the `su -` caveat push
it past the ~150 gate. So: a new **`docs/run-hook.md`** carrying the runner's
contract, `docs/hooks.md` gaining the resolution rule and a link, plus a
`.vitepress/config.mts` sidebar entry and a `docs/README.md` router line.

## Sequence

1. **`void-docker-gh`'s seeding fix**, alone — see
   [mods.md](./mods.md#the-first-pr-has-nothing-to-do-with-mods). No engine
   change, no #18, no mods, and it fixes a live bug.
2. #18 lands.
3. **This plan**: the runner, `PARA_RUN_HOOK`, `run_hook`, the unset line, the
   `require_project` refusal, `libexec/` in `files`, the docs and the tests.
   Mods do not exist yet — the runner resolves `mods/*/hooks/H` and finds
   nothing.
4. [mods.md](./mods.md) from there.

Step 3 is independently shippable and independently useful: the day it lands, a
project can split its own **guest** provisioning into named points. Build-time
points wait for step 4, because `cmd_image_build` never calls `push_project`, so
no runner reaches the builder until the image work.
