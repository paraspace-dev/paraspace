# Plan: the hook runner — one hook name, many hooks

> **Working document.** Delete it once `docs/hooks.md` carries the resolution
> rule and the sourcing model, and the [mods](./mods.md) migration is adopted.
> Lands first; `plans/mods.md` is what it's for.

## Goal

Let a hook name resolve to **more than one script**, so a project can compose
provisioning out of parts it didn't write — and let a project **open hook points
of its own** that para has never heard of.

```sh
# .paraspace/hooks/provision, once the clone is in place
"$PARA_RUN_HOOK" post-clone
```

para runs `provision` and `boot`. Every other name in that vocabulary belongs to
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

That is about the *hook*, not the outcome. Two hooks that write one file still
collide, and para promises nothing about who wins —
[mods.md](./mods.md#what-a-mod-may-assume) makes not-colliding an authoring rule
rather than a mechanism.

Sorting is `LC_ALL=C` so a run is reproducible across machines. In the runner
that has to be `export -n LC_ALL 2>/dev/null; LC_ALL=C` — assigning to an
already-exported variable keeps the export attribute, so on a guest whose
`/etc/profile.d` exports `LC_ALL` (and `su -` is a login shell) every hook would
inherit `C`, which is the regression the rule exists to prevent.

## Hooks are sourced in a subshell

```sh
( . "$hook" )
```

Not `exec`'d by path. This reverses the minimal-engine rewrite's move to
run-by-path and gives up a hook's freedom to choose its interpreter. para is
pure bash and the guest already requires bash, so it is worth taking now, while
contract 1 is soft and there are no consumers.

- **No exec bit anywhere in the hook path.** `push_project`'s `chmod -R +x` and
  its `[ -d … ]` guard are deleted. A checkout with `core.fileMode=false`, a
  tarball or a zip stops breaking a workspace.
- **The hook reads the runner's environment.** A subshell inherits non-exported
  variables, so re-pointing `PARA_HOOKS`/`PARA_SKEL` is plain assignment — no
  `export`, no quoting.
- **`exit` still means "this hook".** `helpers`' `die()` is `exit 1`; inside
  `( … )` that ends the subshell and the status reaches the runner. Identical to
  today, so `die` needs no rewrite and one hook's `exit 0` can't cancel the rest.
- **`cd`, `set -o` and variable names don't leak**, so the runner needs no
  defensive namespacing.

The model is one sentence:

> **A hook reads its environment and writes to the filesystem. It never writes
> to its caller.**

There is deliberately no channel for writing back. The one case that wanted it —
`$BROWSER` for `gh auth login` — is solved in the image: the mod's build hook
writes `/etc/profile.d/`, which `su -` sources before any hook runs.

The shebang becomes decorative. Keep `#!/usr/bin/env bash` on hooks — `bin/lint`
discovers files *by* shebang — and say in the docs that para ignores it, or
someone writes a Python hook that silently runs as bash.

## The runner

para pushes its own script to `$PARA_RUN_HOOK`, and `run_hook` becomes three
lines:

```sh
run_hook() { # run_hook <hook> <name>
  ws_exec "$2" "exec \"\$PARA_RUN_HOOK\" $1" || die "the '$1' hook failed (above)."
}
```

Enumerating on the host instead would work for `provision` and `boot`, and would
leave every named point hand-rolling its own glob-and-sort in a project hook.
One implementation, reachable from both sides, is the argument.

It is generic mechanism, not a boundary violation: no ports, no repo URLs, no
compose knowledge. para already writes `~/.paraspace/env` and splices in
`GUEST_PRELUDE`.

**`PARA_RUN_HOOK` is a fourth `local` in `push_project`**, beside #18's three.
In the guest `~/.paraspace` *is* the project's `.paraspace`; on the host they
differ, so a literal path makes the CLI-tier tests unwritable — and the builder's
copy lives somewhere else again. **The runner exports it itself**, from its own
resolved path, or a hook opening a nested point dies on `unbound variable`.

What the runner must get right — each is a way the obvious draft breaks:

- **Bash shebang**, or `bin/lint` skips it. It also runs under macOS's bash 3.2
  in `test/run --cli`, which CI can't catch.
- **`--mode 0755`, pushed after the recursive push**, so a project's own
  `.paraspace/run-hook` can't shadow para's. `push_project` `die`s naming
  `libexec/run-hook` if it's missing from the package.
- **`libexec` in `package.json`'s `files`**, which lists `bin/para`, *not*
  `bin/`. Miss it and every published para execs a file that was never packaged.
  A CLI test should assert `npm pack --dry-run` covers what `pkg_root` resolves.
- **Root from its own path**, never from `$PARA_HOOKS` — which it re-points. A
  nested point would otherwise enumerate `mods/<m>/mods/*`.
- **`for dir in "$root"/mods/*/` with `[ -d … ] || continue`**, not
  `find | while read`: a piped loop feeds the hook list to the hook as stdin and
  kills every prompt, and `provision` is documented to prompt.
- **One `cd`** to the documented place — `~/$PARA_CLONE_DIR` if it exists, else
  `$HOME`. The subshell keeps it from leaking.
- **Announce each candidate**, and print `no 'X' hook — skipping` when there are
  none. `run_hook`'s host-side line goes away with the existence check, and
  `docs/hooks.md` promises an absent hook is a visible no-op.
- **Errors name the file** and propagate its exit status.

It is **runnable on the host against a fixture `.paraspace/`**, which is what
makes every one of those a two-line CLI test with no incus.

## The environment a hook sees

The runner re-points #18's two at whoever owns the hook:

```sh
( PARA_HOOKS=$owner/hooks PARA_SKEL=$owner/skel; . "$hook" )
```

so a mod's hook is written *identically* to a project's:

```sh
. "$PARA_HOOKS/helpers"                  # the mod's own helpers
cp "$PARA_SKEL/zshrc" ~/.zshrc           # the mod's own skel
```

**`PARA_RUN_HOOK` is the only new variable.** No `PARA_MOD`, no
`PARA_MOD_DIR` — a hook already knows where it lives via `$PARA_HOOKS`, and
nothing in v1 needs the name. `.shellcheckrc`'s `source-path=SCRIPTDIR` resolves
`$PARA_HOOKS/helpers` by basename, so a mod's `hooks/helpers` follows for free.

Two sharp edges to document:

- **Don't re-source `~/.paraspace/env`.** It holds the *project's* values and
  `GUEST_PRELUDE` re-sources it on every `ws_exec`, so a hook that re-sources it
  mid-run rewinds `PARA_HOOKS`/`PARA_SKEL` — wrong file, no error.
- **The context does not survive `su -`/`sudo`**, which reset the environment. A
  build hook installing as another user needs `su - "$PARA_USER" -c 'PARA_SKEL=… …'`.

Extract `guest_env()` here, with one caller — it is the guest's corrected view of
`para_env`, and [mods.md](./mods.md#image-build) needs a second caller. Adding
the fourth `local` now and extracting later means editing `push_project` twice.

## Contract

**The resolution rule is additive** — a project with one `hooks/provision`, no
mods and no `run-hook` lines resolves to one file and behaves identically.
**Sourcing is not**: it changes hook semantics. Contract 1 is deliberately soft
pre-adoption (`PARA_BASE_IMAGE` → `PARA_IMAGE_BASE` landed inside it in #21), so
both land at 1 with a `docs/versioning.md` row. The open question that wants
answering there eventually: when contract 1 freezes — first real consumer, or
1.0.

Two new claims on a tree the project ships verbatim, both named in
`docs/versioning.md`: para now runs `.paraspace/mods/*/hooks/*`, and
`.paraspace/run-hook` joins `env` and `host.env` as a name para owns.

## Test checklist

CLI tier, against a fixture directory, no incus:

- resolution: project before mods, `LC_ALL=C` order, a mod with no `H` skipped,
  no `mods/` → unchanged, `hooks/helpers` never sourced, zero candidates prints
  the skip line, each candidate announced.
- a failing hook aborts the rest, its path is in the error, its status
  propagates — including a `helpers`-style `die` (`exit 1`).
- a hook with no exec bit runs; a hook's `cd`, `set -o` and stray variables
  don't reach the next.
- `PARA_HOOKS`/`PARA_SKEL` re-pointed per hook; the documented cwd.
- a nested point from inside a mod hook resolves every owner.
- a hook that reads stdin gets the caller's, not the hook list.
- an ambient exported `LC_ALL` doesn't reach hooks as `C`.
- `npm pack --dry-run` covers `libexec/`.

e2e (run it — CI won't): a fixture mod appending its name in `provision` and in
a named point the fixture opens; both ran, in order, `up` still idempotent; a
prompting hook still gets the terminal.

## Docs

`docs/hooks.md` gains the resolution rule, the sourcing model, `PARA_RUN_HOOK`
and the two sharp edges; `docs/versioning.md` gains the sourcing row and the
reserved name. The page is ~131 lines after #18 and the gate is ~150, so if it
doesn't fit, the runner's contract splits to `docs/run-hook.md` with a sidebar
entry and a `docs/README.md` router line.

## Sequence

1. **`void-docker-gh`'s seeding fix**, alone — see
   [mods.md](./mods.md#the-first-pr-has-nothing-to-do-with-mods).
2. **This plan.** Mods don't exist yet; the runner resolves `mods/*/hooks/H` and
   finds nothing. Independently useful the day it lands: a project can split its
   own guest provisioning into named points.
3. [mods.md](./mods.md).

## Deliberately not in v1

- **A cycle guard.** A hook point that invokes itself recurses until the
  container's limits bite. You have to author that on purpose.
- **Refusing a project that ships `.paraspace/run-hook`.** para overwrites it;
  nobody has that file.
- **Build-time points.** `cmd_image_build` never calls `push_project`, so no
  runner reaches the builder until [mods.md](./mods.md#image-build).
