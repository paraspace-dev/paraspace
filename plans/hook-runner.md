# Plan: the hook runner — one hook name, many hooks

> **Working document.** Delete it once `docs/hooks.md` carries the resolution
> rule and the process model. [`plans/mods.md`](./mods.md) is what it's for;
> [Landing order](#landing-order) sequences both.

## Goal

Let a hook name resolve to **more than one script**, so a project can compose
provisioning out of parts it didn't write — and let a project **open hook points
of its own** that para has never heard of.

```sh
# anywhere in a project's own hook
"$PARA_RUN_HOOK" clone:before
```

para runs `provision`, `boot` and `image-build`. Every other name in that
vocabulary belongs to projects and the people writing against them: a project
opens a point wherever its own ordering constraint is, and para never learns the
name. **No bundled template opens one in v1** —
[mods.md](./mods.md#shape) is why — so the fixture is the only consumer, which
is the honest state of a mechanism with one user.

## The runner

`libexec/run-hook`, pushed into the guest alongside the project's `.paraspace/`.
For hook `H` it runs the project's `hooks/H`, then each `mods/<m>/hooks/H`:

```sh
#!/usr/bin/env bash
# Run every owner's <hook>: the project's, then each mod's. See docs/hooks.md.
name="${1:?usage: run-hook <name>}"
root="$(cd "$(dirname "$0")" && pwd)"
stack="${PARA_HOOK_STACK:-}"
export PARA_RUN_HOOK="$root/run-hook"
ran=0

case " $stack " in
  *" $name "*) printf "\033[31merror:\033[0m hook cycle: %s\n" "$stack > $name" >&2; exit 1 ;;
esac
export PARA_HOOK_STACK="${stack:+$stack > }$name"

for owner in "$root" "$root"/mods/*; do
  hook="$owner/hooks/$name"
  [ -f "$hook" ] || continue
  printf '\033[36m==>\033[0m hook: %s\n' "${hook#"$root"/}" >&2
  PARA_HOOKS="$owner/hooks" PARA_SKEL="$owner/skel" bash "$hook"
  status=$?  # its own line, NOT `if ! …; then` — see below.
  if [ "$status" -ne 0 ]; then
    printf "\033[31merror:\033[0m hook failed (exit %s): %s\n" "$status" "${hook#"$root"/}" >&2
    if [ -n "$stack" ]; then printf '  stack: %s\n' "$PARA_HOOK_STACK" >&2; fi
    exit "$status"
  fi
  ran=1
done
if [ "$ran" -eq 0 ]; then
  printf "\033[36m==>\033[0m no '%s' hook\n" "$name" >&2
fi
```

That is the feature. What is deliberate in it:

- **A child process, not a sourced subshell.** `bash "$hook"` — the form
  `cmd_image_build` already uses in the builder. An earlier draft wrote
  `( set --; export PARA_HOOKS=…; . "$hook" )`, which is an emulation of this:
  the parens are there to un-share the shell that `.` shares. A process does it
  natively, and the scaffolding goes with it — `set --`, the `export`, a
  `source=/dev/null` directive, and a comment warning the next reader that
  `( … ) || …` disarms the hook's own `set -euo pipefail`, because bash ignores
  errexit inside a compound command on the left of a `||` ([POSIX][posix-e], so
  3.2 does it too). The file ends up with no shellcheck disable in it at all.
  Verified against `koalaman/shellcheck:v0.10.0` and `.shellcheckrc`.
- **The env crosses regardless.** `para_env` emits `export` lines and
  `GUEST_PRELUDE` sources them into the shell that execs the runner, so every
  `PARA_*` is in the runner's *process environment* before it starts and a child
  inherits all of it. Sourcing never carried the context; the `env` file did.
  The `VAR=… bash …` prefix is what re-points the two per owner.
- **`status=$?` on its own line.** The errexit hazard above is gone, but the
  reporting one isn't: written `if ! bash "$hook"; then status=$?`, `$?` is the
  status of the `!` — zero — so the runner announces `hook failed` and exits 0,
  and `run_hook`'s `|| die` never fires. **This is the line someone will later
  "simplify"**; the comment and [the test](#test-checklist) exist to stop them.
- **The runner sets no shell options at all** — no `set` line. Options don't
  cross into a child either way, so a hook gets exactly what its own file sets
  and `bash hooks/provision` still reproduces what para ran. What `set -e` would
  cost is the runner's own error path: it would exit at the failing hook without
  naming it. Its two possibly-unset variables carry their own defaults
  (`${1:?}`, `${PARA_HOOK_STACK:-}`), and it contains no pipe.
- **`PARA_HOOK_STACK` is the trace.** Each level appends the point it is about
  to run and exports it down, so the failing level can name the whole chain —
  `provision > clone:before > keys:setup`. Without it, a hook three points deep
  fails with a path and no answer to "how did para get here". Every level still
  reports as the failure unwinds, and that is not redundancy: the `stack:` line
  names the *points*, each level's own line names the *file and owner* that
  filled one. Only the deepest carries a complete stack, and it comes first.
- **The stack line is suppressed at the top level** (`[ -n "$stack" ]`), where
  it would only repeat the hook name already in the message. A `provision` that
  opens no point fails in exactly one line, the way it does today — the tracing
  is invisible until something actually nests.
- **The cycle guard is one `case`**, and it exists because the stack does. A
  point that invokes itself recursed until the container's limits bit; now it
  stops at depth two and prints the chain. Re-entrancy is what trips it, not
  repetition: calling one point twice in a row from one hook is two children
  with the same parent stack, which is fine and stays fine.
- **The root comes from its own path**, never from `$PARA_HOOKS` — which it
  re-points — so a nested point doesn't enumerate `mods/<m>/mods/*`.
- **It exports `PARA_RUN_HOOK` itself**, because in the guest `~/.paraspace` *is*
  the project's `.paraspace` while the builder's copy lives somewhere else.
- **A `for` over a glob, not a pipe**, so a hook that prompts still has the
  caller's stdin.
- **`ran`** keeps `docs/hooks.md`'s "an absent hook is a visible no-op" true once
  the host stops checking. **A note, not a `warn:`** — an unfilled point is the
  normal state, so a template that opens `clone:before` would otherwise warn on
  every `up` of every project that has no mod for it, forever. Where absence
  really is a bug, the check belongs where it can `die`:
  [image build](./mods.md#image-build) keeps its on the host.
- **The runner owns the announcing**, in para's own `==>`. The host
  used to `log "Running hook: $1"` before a call that might run zero scripts or
  four; only the runner knows which. The two `printf`s are the one place para's
  output style is spelled twice — cheaper than a `helpers` the engine owns, and
  the alternative is announcing the same event from both sides.

[posix-e]: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#set

One file per hook name per owner. No `H.d/`, no `NN-` prefixes, no priority
field, and **no promise about the order mods run in** — the glob's order is
whatever the filesystem and locale give.

> **Hooks are order-agnostic. Where order matters, fill a named point.**

That is about the *hook*, not the outcome. Two hooks that write one file still
collide, and para promises nothing about who wins —
[mods.md](./mods.md#what-a-mod-may-assume) makes that an authoring rule rather
than a mechanism.

### Naming a point

`<subject>` for the thing itself, `<subject>:before` and `<subject>:after` for
the moments around it — `clone:before`, not `pre-clone`, so a directory listing
sorts by subject first and moment second. The separator is a colon because
subjects already contain hyphens: `image-build-after` is ambiguous about where
the subject ends, `image-build:after` isn't. para's own three (`provision`,
`boot`, `image-build`) are subjects and don't change. The runner doesn't care —
this is a convention the reference templates set, and
[mods.md](./mods.md#why-the-vocabulary-is-the-product) is why that matters.

**A point a mod opens is named after the mod.** `dotfiles-jchook:after`, never
`dotfiles:after`. The project owns the bare namespace because there is one
project; there is no limit on mods, and two of them opening `dotfiles:after`
collide with no error and no promise about who runs first. Prefixing costs a
word and makes the collision impossible instead of undetected. Whether a mod
should open one at all is [an authoring rule](./mods.md#what-a-mod-may-assume),
not a mechanism.

On the host, `run_hook` loses its existence check *and* its `log` line — the
runner announces each hook it actually finds, and only it knows how many that
is:

```sh
run_hook() { # run_hook <hook> <name>
  ws_exec "$2" "exec ~/.paraspace/run-hook '$1'" || die "the '$1' hook failed (above)."
}
```

The name is quoted in the guest command. Every caller is a literal in `bin/para`
today, but named points make hook names a vocabulary projects write, and one
`$1` that reaches here unquoted is a word-split at best.

Enumerating on the host instead would work for `provision` and `boot`, and would
leave every named point hand-rolling its own glob in a project hook. One
implementation, reachable from both sides, is the argument.
[mods.md](./mods.md#image-build) is the second caller.

## A hook is a process

`bash "$hook"` — not `.`, and not by path. para is pure bash and the guest
already requires bash, so a hook's freedom to pick its own interpreter buys
nothing, and running it by name would make an exec bit load-bearing.

- **No exec bit anywhere in the hook path.** `push_project`'s `chmod -R +x` and
  its `[ -d … ]` guard are deleted, and `cmd_init` stops chmod'ing what it
  scaffolds into `hooks/`. A checkout with `core.fileMode=false`, a tarball or a
  zip stops breaking a workspace.
- **`exit` still means "this hook".** `helpers`' `die()` is `exit 1`; that ends
  the hook's process and the status reaches the runner, so one hook's `exit 0`
  can't cancel the rest.
- **`cd`, `set -o` and variable names don't leak — in either direction.** One
  hook's `cd` can't move the next, and a hook can't read the runner's `$owner`
  or `$ran` by accident, so neither side needs defensive namespacing. Every hook
  starts where `GUEST_PRELUDE` left the shell — `~/$PARA_CLONE_DIR` if it
  exists, else `$HOME` — which is unchanged.

Two consequences `docs/hooks.md` has to state:

- para **ignores the shebang**. Keep `#!/usr/bin/env bash` on hooks — `bin/lint`
  discovers files *by* shebang — or someone writes a Python hook that silently
  runs as bash.
- **A hook gets no arguments.** `$@` is empty by construction — the runner
  passes none and there is no caller's `$@` to inherit.

`$0` is the hook's own path, so `. "$(dirname "$0")/helpers"` resolves. It names
the same directory `$PARA_HOOKS` does, for every hook and every owner, so
`docs/hooks.md` still teaches one spelling — but nothing breaks for a hook
written against the old one, which is why the
[migration below](#para_contract-stays-1) is one edit rather than two.

The model is one sentence:

> **A hook reads its environment and writes to the filesystem. It never writes
> to its caller.**

It is true by construction rather than by convention, and it is one sentence for
both ways in: the runner's loop and a nested `"$PARA_RUN_HOOK"` are both a fresh
process, so "what can a hook see" has the same answer however it was reached.
There is deliberately no channel for writing back — what a hook wants a *later*
hook to see goes through a file, and
[mods.md](./mods.md#how-a-hook-reaches-a-later-hook) is the list of which one.
The case that wanted it — `$BROWSER`, so the base's `authorize_key` device flow
finds a browser — is solved in the image, because the base's `provision` runs
*before* any mod's and no hook point comes earlier: a mod's build hook writes
`/etc/profile.d/`, which the bash login shell para runs hooks in sources.

## The environment a hook sees

The runner re-points #18's two at whoever owns the hook, so a mod's hook is
written *identically* to a project's:

```sh
. "$PARA_HOOKS/helpers"                  # the mod's own helpers
cp "$PARA_SKEL/zshrc" ~/.zshrc           # the mod's own skel
```

**Two new variables, both set by the runner** rather than by `para_env`, so
neither appears in `~/.paraspace/env`: `PARA_RUN_HOOK` (the path a hook opens a
point with) and `PARA_HOOK_STACK` (the chain that reached this hook, for reading
— para rewrites it at every level). Both are additive, so the contract does not
move. No `PARA_MOD`, no `PARA_MOD_DIR` — a hook already knows where it lives via
`$PARA_HOOKS`. `.shellcheckrc`'s `source-path=SCRIPTDIR` resolves
`$PARA_HOOKS/helpers` by basename, so a mod's `hooks/helpers` follows for free.

Three sharp edges to document:

- **Only exported variables reach a nested point.** `"$PARA_RUN_HOOK"
  clone:before` is a new process, so a plain `repo_url=…` set three lines above
  it is unset inside the hooks it runs. Export what a point is meant to see —
  or, better, don't: the point is filling in behavior, not receiving arguments.
- **A hook that opens a point needs `set -e` to honor the failure.** The nested
  runner reports and exits non-zero, so the error and its stack are always on
  screen — but a hook without `set -e` carries on past the failed
  `"$PARA_RUN_HOOK" …` and can still exit 0, and then `para up` reports a ready
  workspace over a visible error. Templates ship `set -euo pipefail`; this is
  the rule for hooks written elsewhere, and the reason the trace is loud.
- **Don't re-source `~/.paraspace/env`.** It holds the *project's* values and
  `GUEST_PRELUDE` re-sources it on every `ws_exec`, so a hook that re-sources it
  mid-run rewinds `PARA_HOOKS`/`PARA_SKEL` — wrong file, no error.
- **The context does not survive `su -`/`sudo`**, which reset the environment. A
  build hook installing as another user needs `su - "$PARA_USER" -c 'PARA_SKEL=… …'`.

## Landing order

Four PRs, each shippable alone:

1. **Delete drift detection** — `image_src_sha`, `sha256_of` (no other caller
   once the stamp is gone), the `user.para.src_sha` stamp, and `image status`'s
   comparison. [Why](./mods.md#drift-detection-goes-away) it can't survive the
   builder consuming all of `.paraspace/`.
2. **`image-build.sh` → `hooks/image-build`**, with `push_paraspace` and
   `guest_env` — [mods.md](./mods.md#image-build). The builder starts consuming
   `.paraspace/` the way a workspace does. No runner yet, so it runs the hook by
   path.
3. **This plan** — the runner. `cmd_image_build`'s one line becomes `run-hook
   image-build`, and `push_project` loses its `chmod`.
4. **[mods.md](./mods.md)** — `mods/`, `para mod add`, `docs/mods.md`, and
   `void-jchook` deleted.

2 before 3 costs one rewritten line in `cmd_image_build`, and buys landing the
rename — [the largest blast radius in either plan](./mods.md#docs-impact) —
while it is the only thing in flight.

## Shipping it

The details worth writing down are all about packaging the runner, not about
running hooks:

- **`libexec/` in `package.json`'s `files`**, which lists `bin/para`, *not*
  `bin/`. Same class as the `templates` entry beside it — omit either and every
  published para reaches for a file that was never packaged — so one
  `npm pack --dry-run` test covers both.
- **Pushed by `push_paraspace`, not `push_project`** — the builder execs its
  copy too. `--mode 0755`, after the recursive push, so a project's own
  `.paraspace/run-hook` can't shadow para's. **No existence check**: `incus file
  push` already fails naming the path it couldn't find.
- **Bash shebang**, or `bin/lint` skips it. It also runs under macOS's bash 3.2
  in `test/run --cli`, which CI can't catch.
- `guest_env()` — the guest's corrected view of `para_env` — arrives with PR 2
  above and gains no caller here. **It takes the destination as an argument**:
  #18 hardcodes `PARA_HOOKS="$home/.paraspace/hooks"`, and the builder's copy
  lives at `/opt`, so a build hook doing `su - "$PARA_USER" -c 'cat
  $PARA_SKEL/…'` otherwise reads `/home/app/.paraspace/skel` — absent in the
  builder, and absent behind the `[ -f ]` guards those hooks already use, so a
  dotfiles mod seeds nothing and says nothing.

It is **runnable on the host against a fixture `.paraspace/`**, which is what
makes every test below a two-liner with no incus.

**Why a file and not a function in the generated `env`.** `env` is already
pushed per destination and sourced by both callers, so emitting a `para_hook()`
into it would delete this whole section. It loses the two things that matter:
`bin/lint` can't see a heredoc, and the CLI tier would have no way to reach the
real loop — leaving [the required test](#test-checklist) either testing a copy or
running only in e2e, which CI doesn't. `env` is also *data* — "para's context as
export lines," re-sourced on every `ws_exec` including every `para sh` — and
behavior in it is a category change that the next function would follow.

## Test checklist

CLI tier, against a fixture directory. **The first one is required** — it is the
whole reason the runner is shaped the way it is:

- **A hook whose *middle* command fails stops there, and the runner exits
  non-zero.** Both halves, and they guard different rewrites. The exit status is
  what an `if ! bash "$hook"; then status=$?` breaks — it reports 0. The absent
  tail line is what going back to `( . "$hook" )` breaks. Naming the middle is
  what catches the second: a hook that fails on its *last* line reports
  correctly under a sourced shape too, so a test written that way guards
  nothing.
- a hook sees no arguments (`$#` is 0), not the runner's `$1`.
- `$0` is the hook, so a hook doing `. "$(dirname "$0")/helpers"` works.
- resolution: project before mods, a mod with no `H` skipped, no `mods/` →
  unchanged, `hooks/helpers` never run as a hook, each hook announced.
- a failing hook aborts the rest, its path is in the error, and a
  `helpers`-style `die` (`exit 1`) is what fails it.
- no owner fills the name → `no 'X' hook` on stderr, exit 0.
- a hook with no exec bit runs; `PARA_HOOKS`/`PARA_SKEL` re-pointed per hook.
- a nested point from inside a mod hook resolves every owner, and
  `$PARA_RUN_HOOK` is set in the hook's environment for it to have been reached
  at all — the variable the whole named-point feature rests on.
- a non-directory under `mods/` (a stray file, a `README`) is skipped, not
  treated as an owner.
- **the trace**: a failure three points deep names every level, and the deepest
  line carries the full `stack:`. Assert the *flat* case too — a `provision`
  that opens no point still fails in one line with no `stack:` — or the tracing
  quietly becomes noise on the path everyone actually takes.
- **the cycle guard**: a point that invokes itself exits 1 naming the chain,
  rather than recursing. And its inverse, which is the one that matters: the
  same point invoked twice *in sequence* from one hook runs twice.
- a hook that reads stdin gets the caller's, not the hook list — the one that
  catches a future rewrite of the loop into a pipe.
- `npm pack --dry-run` covers `libexec/` — **its own assert**, next to separate
  ones for `templates/` and `mods/`. One combined test says "something is
  missing"; three say which, and `templates/` carries this exposure today with
  no test on it at all.

e2e (run it — CI won't): a fixture mod appending its name in `provision` and in
a named point the fixture opens; both ran, `up` still idempotent; a prompting
hook still gets the terminal. And **`image-build` through the runner in the
builder** — the `/opt` paths and the `su - "$PARA_USER"` step-down meet there,
which is the only place `guest_env`'s destination argument is load-bearing and
the only place a wrong answer is silent (a build hook reads an absent
`$PARA_SKEL` behind a `[ -f ]` guard, seeds nothing, and says nothing).

## `PARA_CONTRACT` stays 1

Dropping the exec bit changes hook semantics and
[mods.md](./mods.md#image-build) renames the image-build payload, so
[CLAUDE.md](../CLAUDE.md)'s rule would bump the contract. It doesn't,
deliberately, and this section is the record of that decision.

para has **one consumer** — the author's own project — and it migrates by hand.
Bumping is a promise to people who aren't there yet, and 1.0 shipping at contract
2 publishes a version number for a migration nobody made. 1 is what every
template pins and what 1.0 will ship.

The bill, paid by hand rather than by the engine: `paraspace@0.1.0` on npm
predates both changes, and a `.paraspace/` scaffolded from it needs **one** edit.

- **`image-build.sh` → `hooks/image-build`.** Nothing refuses the old name; the
  build just runs no hook, which is what the runner's `no 'X' hook` line is for.

The edit that isn't needed: `$(dirname "$0")/helpers` keeps resolving, because
`$0` is the hook. #18 moved every tracked hook, template comment and
`.shellcheckrc` reference to `$PARA_HOOKS` and that stays the taught spelling —
but a hook written against the old one does not break, which is one fewer thing
a pre-release migration has to catch by hand.

It goes in `docs/versioning.md` under a **pre-release** heading, not a new
contract's migration table — and its existing "hooks run by path — the shebang
decides, so keep it executable" row is now wrong and gets rewritten.

Contract 1 freezes at 1.0. After that, anything that breaks a `.paraspace/`
bumps it.

## Docs

`docs/hooks.md` gains the resolution rule, "a hook is a process" and its two
consequences, `PARA_RUN_HOOK`/`PARA_HOOK_STACK` and the four sharp edges — and
drops its "Everything here runs **by path**, so each file's own shebang decides
its interpreter" line in favor of them. It also wants **the trace read
end-to-end once**, on a worked nested failure: that is the page someone lands on
at the wrong moment, and a stack is only obvious to whoever designed it.
`docs/versioning.md` gains two rows besides the pre-release notes above: para now
runs `.paraspace/mods/*/hooks/*`, and `.paraspace/run-hook` joins `env` and
`host.env` as a name para owns.

## Deliberately not in v1

- **Refusing a project that ships `.paraspace/run-hook`.** para overwrites it.
- **Deterministic mod ordering**, and any `LC_ALL=C` to get it. Order is
  explicitly not a promise.
