# Plan: the hook runner — one hook name, many hooks

> **Working document.** Delete it once `docs/hooks.md` carries the resolution
> rule and the runner's contract, and the [mods](./mods.md) migration is adopted.
> Paired with [`plans/mods.md`](./mods.md), which is the consumer: this plan is
> the seam, that one is what it's for. Land this first.
>
> **Depends on [#18](https://github.com/paraspace-dev/paraspace/pull/18)**
> (`PARA_HOOKS`/`PARA_SKEL`). See [Before this lands](#before-this-lands) for a
> contract problem inherited from that branch.

## Goal

Let a hook name resolve to **more than one script**, so a project can compose
provisioning out of parts it didn't write — and let a project **open hook points
of its own** that para has never heard of.

```sh
# .paraspace/hooks/provision, once the clone is in place
~/.paraspace/run-hook post-clone
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

`LC_ALL=C` is load-bearing rather than decorative: a plain glob collates by the
ambient locale, so `Zsh` and `dotfiles` sort one way on the host and the other
in the guest. Set it **unexported** — `export`ing it would silently change every
hook's own sorting and every tool's messages.

## Why a runner in the guest, not a loop on the host

para pushes its own script to `~/.paraspace/run-hook`, and `run_hook` becomes:

```sh
run_hook() { # run_hook <hook> <name>
  ws_exec "$2" "exec ~/.paraspace/run-hook $1" || die "the '$1' hook failed (above)."
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

## What the runner must get right

Each of these is a way the obvious first draft breaks.

- **Bash shebang.** `ws_exec` already requires bash (`su … -s /bin/bash`), and
  `bin/lint` selects files by a `bash` shebang — `#!/bin/sh` would ship
  unlinted.
- **`--mode 0755`, pushed after the recursive push.** `incus file push -`
  defaults to `0600`, which execs as 126. Pushing it last means a project that
  ships its own `.paraspace/run-hook` can't shadow para's — and that name is now
  reserved (below).
- **In `package.json`'s `files`.** It lives at `libexec/run-hook`; `files` lists
  `bin/para`, *not* `bin/`, so a new top-level directory is invisible to npm.
  Miss it and every published para execs a file that was never packaged, on the
  first hook of every project. Add a CLI test asserting `npm pack --dry-run`
  covers everything `pkg_root` resolves against — there is no such test today,
  which is exactly why this is invisible.
- **Root from its own path**, never from `$PARA_HOOKS` — which the runner
  itself re-points. A mod hook opening a nested point would otherwise enumerate
  `mods/<m>/mods/*` and silently skip every other owner.
- **`for dir in "$root"/mods/*/` with `[ -d "$dir" ] || continue`**, not
  `find | while read`. A piped loop hands the hook list to the hook as stdin,
  killing every prompt — and `provision` is documented to prompt. The `-d`
  guard is the unmatched-glob case: no `mods/` at all leaves the literal
  pattern and runs the body once.
- **stdin belongs to the hook.** One tty and one stdin feed the project's hook
  *and* every mod's; the runner reads neither. See
  [the builder](./mods.md#image-build) for where this bites hardest.
- **The documented cwd, per hook** — `~/$PARA_CLONE_DIR` if it exists, else
  `$HOME`. `GUEST_PRELUDE` sets it once today; with named points, a hook that
  has already `cd`'d would otherwise hand its cwd to every mod filling that
  point.
- **Zero candidates still says so.** `docs/hooks.md` promises "an absent hook is
  a visible no-op", and the host's `No 'X' hook — skipping` line goes away with
  the existence check. The runner prints it instead. This is the one place para's
  log vocabulary gets a second implementation; it is three lines and it keeps a
  documented guarantee.
- **Errors name the file.** With N candidates, `the 'provision' hook failed` no
  longer says which. The runner prints the failing path and propagates its exit
  status.
- **A recursion guard.** The runner carries the active stack in
  `PARA_HOOK_STACK` and dies naming it: `hook point 'provision' is already
  running (provision → post-clone → provision)`. A guard rather than a shape,
  deliberately: a hook is arbitrary code and can always call the runner, and
  what it prevents is a fork bomb inside a nesting-enabled container during
  `para up`.

It is **runnable on the host against a fixture `.paraspace/`**, so all of the
above gets CLI-tier tests with no incus.

## The environment a hook sees

`PARA_HOOKS`/`PARA_SKEL` arrive from #18. The runner **re-points them at
whoever owns the hook it is about to run**, and adds the owner's identity:

```sh
PARA_HOOKS=$owner/hooks PARA_SKEL=$owner/skel \
PARA_MOD=$name PARA_MOD_DIR=$owner "$hook"
```

so a mod's hook is written *identically* to a project's:

```sh
. "$PARA_HOOKS/helpers"                  # the mod's own helpers
cp "$PARA_SKEL/zshrc" ~/.zshrc           # the mod's own skel
```

`PARA_MOD` and `PARA_MOD_DIR` are empty for the project's own hooks.
`.shellcheckrc`'s `source-path=SCRIPTDIR` already resolves
`$PARA_HOOKS/helpers` by basename, so a mod's `hooks/helpers` follows for free.

`PARA_MOD_DIR` is not redundant with the re-pointed spelling, for one reason:
**a mod's `commands/` run on the host**, where `PARA_HOOKS`/`PARA_SKEL` are
unset by design, so a mod command has no other way to reach its own files. (An
earlier draft also justified it as the reliable spelling under a re-sourced
`~/.paraspace/env`. That was wrong in the case it named — `PARA_MOD_DIR` is not
in `env` either, so under `para sh` it is unset and `$PARA_MOD_DIR/hooks/x`
expands to `/hooks/x`. The re-sourcing hazard is real; the fix is the note
below, not this variable.)

Three sharp edges, all of which need writing down:

- **`~/.paraspace/env` still holds the project's values**, and `GUEST_PRELUDE`
  re-sources it on every `ws_exec`. A hook that re-sources it mid-run silently
  rewinds `PARA_HOOKS`/`PARA_SKEL` to the project's — wrong file, no error.
  Don't re-source it; the runner already gave you the right values.
- **The context does not survive `su -` or `sudo`**, both of which reset the
  environment. A build hook that installs *as* another user needs the spelling
  `su - "$PARA_USER" -c 'PARA_SKEL=… …'`. This bites the migration directly.
- **`PARA_MOD`, `PARA_MOD_DIR` and `PARA_HOOK_STACK` join `push_project`'s
  `unset` line.** `para_env` forwards every `PARA_*` in scope, so a stray
  `PARA_MOD=1` in a `Parafile` or the ambient environment would poison every
  hook's view of itself, and an inherited `PARA_HOOK_STACK` would trip the
  recursion guard on the first hook. A mod command that shells back into
  `"$PARA_BIN" up` is the realistic path for that.

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

Make both fail loudly rather than silently: `push_project` refuses a project
that ships its own `.paraspace/run-hook`, naming it. Collision probability is
near zero; a clear error is what makes "additive" defensible.

`~/.paraspace/run-hook` also becomes **public API** the moment a project hook
contains it — its argument form and the env it sets are contract from then on,
and changing either is a bump. Say so in `docs/versioning.md`.

## Before this lands

`docs/versioning.md` lists "the `Parafile` keys" as contract-covered, and the
branch this depends on renames `PARA_BASE_IMAGE` → `PARA_IMAGE_BASE` while
leaving `PARA_CONTRACT` at 1. Any project whose `Parafile` sets the old
spelling — which is what both shipped templates wrote — passes `para doctor`'s
contract check and then dies in `para image build` naming a key it has never
seen. That is the silent break across a shared para that the contract exists to
prevent.

Resolve it in #18/#21, not here: either bump to contract 2 with a migration row,
or ship `: "${PARA_IMAGE_BASE:=${PARA_BASE_IMAGE:-}}"` plus a `doctor` warning.
This plan should not assert contract-1 for the union until it is settled.

## Test checklist

CLI tier — this is why the runner is a standalone script:

- resolution: project before mods, mods in `LC_ALL=C` order, a mod with no `H`
  skipped, no `mods/` at all → unchanged behavior, `hooks/helpers` never
  executed, zero candidates prints the skip line.
- a failing hook aborts the rest and its **path** is in the error.
- `PARA_HOOKS`/`PARA_SKEL`/`PARA_MOD`/`PARA_MOD_DIR` re-pointed per hook; the
  documented cwd per hook.
- a **nested** point called from inside a mod hook still resolves every owner
  (the `$PARA_HOOKS`-derived-root trap); a recursive one dies naming the cycle;
  an inherited `PARA_HOOK_STACK` from the environment does not.
- a hook that reads stdin gets the caller's stdin, not the hook list.
- `npm pack --dry-run` covers `libexec/`.

e2e tier (run it — CI won't): a fixture mod that appends its name in `provision`
and in a named point the fixture project opens; assert both ran, in order, and
that `para up` is still idempotent. A prompting hook still gets the terminal
through the runner.

## Sequence

1. **`void-docker-gh`'s seeding fix**, alone — see
   [mods.md](./mods.md#the-first-pr-has-nothing-to-do-with-mods). No engine
   change, no #18, no mods, and it fixes a live bug.
2. #18 lands (with the contract question above resolved).
3. **This plan**: the runner, `run_hook`, the unset line, the reserved-name
   refusal, `libexec/` in `files`, and the tests. Mods do not exist yet — the
   runner resolves `mods/*/hooks/H` and finds nothing.
4. [mods.md](./mods.md) from there.

Step 3 is independently shippable and independently useful: a project can split
its own provisioning into named points the day it lands.
