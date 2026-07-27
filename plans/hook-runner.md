# Plan: the hook runner — one hook name, many hooks

> **Working document.** Delete it once `docs/hooks.md` carries the resolution
> rule and the sourcing model. [`plans/mods.md`](./mods.md) is what it's for;
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
export PARA_RUN_HOOK="$root/run-hook"
ran=0

for owner in "$root" "$root"/mods/*; do
  hook="$owner/hooks/$name"
  [ -f "$hook" ] || continue
  printf 'hook: %s\n' "${hook#"$root"/}" >&2
  # A plain command, NOT `( … ) || …` — see below.
  # shellcheck source=/dev/null  # the hook is chosen at runtime
  ( set --; export PARA_HOOKS="$owner/hooks" PARA_SKEL="$owner/skel"; . "$hook" )
  status=$?
  if [ "$status" -ne 0 ]; then
    printf 'hook failed: %s\n' "$hook" >&2
    exit "$status"
  fi
  ran=1
done
[ "$ran" -eq 1 ] || printf "no '%s' hook\n" "$name" >&2
```

That is the feature. What is deliberate in it:

- **The subshell is a plain command.** Written the obvious way — `( … ) ||
  { …; exit 1; }`, or `if ( … ); then` — bash ignores errexit for *everything*
  inside a compound command on the left of a `||`, and that includes the hook's
  own `set -euo pipefail`. A `provision` whose `git clone` fails then runs to the
  end, its last command decides the status, and `para up` reports a ready
  workspace. Verified on bash 5.3; it is [POSIX-specified][posix-e], so 3.2 does
  it too. **This is the one line in the runner someone will later "simplify"** —
  the comment and [the test](#test-checklist) exist to stop them.
- **The runner sets no shell options at all** — no `set` line — so a sourced hook
  gets exactly what its own file sets and `bash hooks/provision` still reproduces
  what para ran. A draft that opened `set -uo pipefail` quietly imposed both on
  every hook: a third-party hook reading `"$OPTIONAL"` died on `unbound
  variable`, and `false | true` returned 1. Same class of bug as the one above,
  through the friendlier-looking door. The runner needs neither: its only unset
  variable is `$1`, already `${1:?}`, and it contains no pipe.
- **`export`, and the `source=/dev/null` directive.** Without the export, a
  hook's own subprocesses see the *project's* paths on a host fixture but the
  *mod's* in the guest, where `~/.paraspace/env` exported both already — the CLI
  tier and the guest would disagree. Without the directive `bin/lint` fails:
  SC2034 ×2 and SC1090, three warnings in twenty lines, well past the house
  budget. Both verified against `koalaman/shellcheck:v0.10.0` and `.shellcheckrc`.
- **`set --` clears the positionals**, or a sourced hook sees the runner's `$1` —
  the hook name. Hooks take no arguments; everything they need is a `PARA_*`.
- **The root comes from its own path**, never from `$PARA_HOOKS` — which it
  re-points — so a nested point doesn't enumerate `mods/<m>/mods/*`.
- **It exports `PARA_RUN_HOOK` itself**, because in the guest `~/.paraspace` *is*
  the project's `.paraspace` while the builder's copy lives somewhere else.
- **A `for` over a glob, not a pipe**, so a hook that prompts still has the
  caller's stdin.
- **`ran`** keeps `docs/hooks.md`'s "an absent hook is a visible no-op" true once
  the host stops checking — which [image build](./mods.md#image-build) needs more
  than `provision` does.

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

On the host, `run_hook` loses its existence check and gains nothing:

```sh
run_hook() { # run_hook <hook> <name>
  log "Running hook: $1"
  ws_exec "$2" "exec ~/.paraspace/run-hook $1" || die "the '$1' hook failed (above)."
}
```

Enumerating on the host instead would work for `provision` and `boot`, and would
leave every named point hand-rolling its own glob in a project hook. One
implementation, reachable from both sides, is the argument.
[mods.md](./mods.md#image-build) is the second caller.

## Hooks are sourced in a subshell

`( . "$hook" )`, not run by path. para is pure bash and the guest already
requires bash, so a hook's freedom to pick its own interpreter buys nothing.

- **No exec bit anywhere in the hook path.** `push_project`'s `chmod -R +x` and
  its `[ -d … ]` guard are deleted, and `cmd_init` stops chmod'ing what it
  scaffolds into `hooks/`. A checkout with `core.fileMode=false`, a tarball or a
  zip stops breaking a workspace.
- **`exit` still means "this hook".** `helpers`' `die()` is `exit 1`; inside
  `( … )` that ends the subshell and the status reaches the runner, so one
  hook's `exit 0` can't cancel the rest.
- **`cd`, `set -o` and variable names don't leak**, so the runner needs no
  defensive namespacing and one hook's `cd` can't move the next. Every hook
  starts where `GUEST_PRELUDE` left the shell — `~/$PARA_CLONE_DIR` if it
  exists, else `$HOME` — which is unchanged.

Three consequences `docs/hooks.md` has to state:

- para **ignores the shebang**. Keep `#!/usr/bin/env bash` on hooks — `bin/lint`
  discovers files *by* shebang — or someone writes a Python hook that silently
  runs as bash.
- **`$0` is the runner, not the hook**, so `. "$(dirname "$0")/helpers"` resolves
  to `~/.paraspace/helpers` and the hook dies. #18 already moved every tracked
  hook, the templates' comments and `.shellcheckrc` to `$PARA_HOOKS`, so nothing
  in the repo changes — this is the rule for hooks written elsewhere, and the
  one hand-migration [below](#para_contract-stays-1) names.
- **A hook gets no arguments.** `$@` is empty by construction.

The model is one sentence:

> **A hook reads its environment and writes to the filesystem. It never writes
> to its caller.**

There is deliberately no channel for writing back. The one case that wanted it —
`$BROWSER` for `gh auth login` — is solved in the image: a mod's build hook
writes `/etc/profile.d/`, which `su -` sources before any hook runs.

## The environment a hook sees

The runner re-points #18's two at whoever owns the hook, so a mod's hook is
written *identically* to a project's:

```sh
. "$PARA_HOOKS/helpers"                  # the mod's own helpers
cp "$PARA_SKEL/zshrc" ~/.zshrc           # the mod's own skel
```

**`PARA_RUN_HOOK` is the only new variable.** No `PARA_MOD`, no `PARA_MOD_DIR` —
a hook already knows where it lives via `$PARA_HOOKS`. `.shellcheckrc`'s
`source-path=SCRIPTDIR` resolves `$PARA_HOOKS/helpers` by basename, so a mod's
`hooks/helpers` follows for free.

Two sharp edges to document:

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

- **A hook whose *middle* command fails stops there.** Assert both that the tail
  line's side effect is absent *and* that the runner exits non-zero. Naming the
  middle is the point: a hook that fails on its *last* line reports correctly
  under the broken shape too, so a test written that way passes either way and
  guards nothing.
- a hook sees no arguments (`$#` is 0), not the runner's `$1`.
- resolution: project before mods, a mod with no `H` skipped, no `mods/` →
  unchanged, `hooks/helpers` never sourced, each hook announced.
- a failing hook aborts the rest, its path is in the error, and a
  `helpers`-style `die` (`exit 1`) is what fails it.
- no owner fills the name → `no 'X' hook` on stderr, exit 0.
- a hook with no exec bit runs; `PARA_HOOKS`/`PARA_SKEL` re-pointed per hook.
- a nested point from inside a mod hook resolves every owner.
- a hook that reads stdin gets the caller's, not the hook list — the one that
  catches a future rewrite of the loop into a pipe.
- `npm pack --dry-run` covers `libexec/` — and `templates/`, which carries the
  same exposure today with no test on it.

e2e (run it — CI won't): a fixture mod appending its name in `provision` and in
a named point the fixture opens; both ran, `up` still idempotent; a prompting
hook still gets the terminal.

## `PARA_CONTRACT` stays 1

Sourcing changes hook semantics and [mods.md](./mods.md#image-build) renames the
image-build payload, so [CLAUDE.md](../CLAUDE.md)'s rule would bump the contract.
It doesn't, deliberately, and this section is the record of that decision.

para has **one consumer** — the author's own project — and it migrates by hand.
Bumping is a promise to people who aren't there yet, and 1.0 shipping at contract
2 publishes a version number for a migration nobody made. 1 is what every
template pins and what 1.0 will ship.

The bill, paid by hand rather than by the engine: `paraspace@0.1.0` on npm
predates both changes, so a `.paraspace/` scaffolded from it needs two edits.

- **`image-build.sh` → `hooks/image-build`.** Nothing refuses the old name; the
  build just runs no hook, which is what the runner's `no 'X' hook` line is for.
- **`$(dirname "$0")/helpers` → `$PARA_HOOKS/helpers`.** #18 already moved every
  tracked hook, template comment and `.shellcheckrc` reference, so this is only
  for hooks scaffolded before it.

Both go in `docs/versioning.md` under a **pre-release** heading, not a new
contract's migration table — and its existing "hooks run by path — the shebang
decides, so keep it executable" row is now wrong and gets rewritten.

Contract 1 freezes at 1.0. After that, anything that breaks a `.paraspace/`
bumps it.

## Docs

`docs/hooks.md` gains the resolution rule, the sourcing model and its three
consequences, `PARA_RUN_HOOK` and the two sharp edges — and drops its "Everything
here runs **by path**, so each file's own shebang decides its interpreter" line
in favor of them. `docs/versioning.md`
gains two rows besides the pre-release notes above: para now runs
`.paraspace/mods/*/hooks/*`, and `.paraspace/run-hook` joins `env` and
`host.env` as a name para owns.

## Deliberately not in v1

- **A cycle guard.** A hook point that invokes itself recurses until the
  container's limits bite. You have to author that on purpose.
- **Refusing a project that ships `.paraspace/run-hook`.** para overwrites it.
- **Deterministic mod ordering**, and any `LC_ALL=C` to get it. Order is
  explicitly not a promise.
