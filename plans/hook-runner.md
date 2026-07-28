# Plan: the hook runner — one hook name, many hooks

> **Working document.** Delete it once `docs/hooks.md` carries the resolution
> rule and the process model. [`plans/mods.md`](./mods.md) is what it's for;
> [Landing order](#landing-order) sequences both.

## Goal

A hook name resolves to **more than one script**, and a project can open hook
points para has never heard of:

```sh
"$PARA_RUN_HOOK" clone:before    # anywhere in a project's own hook
```

para keeps `provision`, `boot`, `image-build`; every other name belongs to
projects. **No bundled template opens one in v1** ([why](./mods.md#shape)), so
the test fixture is the only consumer.

## The runner

`libexec/run-hook`, pushed into the guest beside the project's `.paraspace/`.
For hook `H`: the project's `hooks/H`, then each `mods/<m>/hooks/H`.

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

- **`bash "$hook"`, not `( . "$hook" )`.** The subshell draft needed `set --`,
  an `export` and a `source=/dev/null`, and left the hook one refactor from
  silent success: bash disables errexit everywhere inside a compound command on
  the left of a `||`, *including the hook's own `set -euo pipefail`*
  ([POSIX][posix-e], so 3.2 too). A process needs none of it and gets `$0`
  right. No shellcheck disable left in the file.
- **`status=$?` on its own line.** `if ! bash "$hook"; then status=$?` captures
  the status of the `!` — zero — so the runner prints `hook failed` and exits 0,
  and `run_hook`'s `|| die` never fires. **The line someone will "simplify"**;
  [the test](#test-checklist) is the guard.
- **No `set` line.** `set -e` would exit at the failing hook before naming it.
- **`PARA_HOOK_STACK` is the trace.** Each level appends and exports down, so
  the failing level names the chain. Every level reports as it unwinds, which is
  not redundancy — `stack:` names the points, each level's own line names the
  file. Suppressed at the top, so a flat `provision` still fails in one line.
- **The cycle guard trips on re-entrancy, not repetition** — one point invoked
  twice in a row is two children with the same parent stack.
- **`root` from `$0`, never `$PARA_HOOKS`**, which it re-points; otherwise a
  nested point enumerates `mods/<m>/mods/*`.
- **A `for` over a glob, not a pipe**, so a prompting hook keeps stdin.
- **Absence is a note, not a `warn:`.** An unfilled point is the normal state;
  warning would fire on every `up` of every project without a mod for it. Where
  absence is a bug, [image build](./mods.md#image-build) checks on the host and
  dies.

[posix-e]: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#set

One file per hook name per owner — no `H.d/`, no `NN-` prefixes, no priority
field, and **no order promise** across mods.

> **Hooks are order-agnostic. Where order matters, fill a named point.**

That is about the hook, not the outcome: two hooks writing one file still
collide, which [mods.md](./mods.md#what-a-mod-may-assume) makes an authoring
rule rather than a mechanism.

### Naming a point

`<subject>`, `<subject>:before`, `<subject>:after`. A colon because subjects
already contain hyphens — `image-build-after` is ambiguous about where the
subject ends — and it sorts by subject first. **A point a mod opens is prefixed
with the mod's name**; the project owns the bare namespace because there is only
one project. Whether a mod *should* open one is
[an authoring rule](./mods.md#a-mod-may-open-a-point).

On the host, `run_hook` loses its existence check and its `log` line — only the
runner knows whether a name resolved to zero scripts or four:

```sh
run_hook() { # run_hook <hook> <name>
  ws_exec "$2" "exec ~/.paraspace/run-hook '$1'" || die "the '$1' hook failed (above)."
}
```

Enumerating on the host instead would work for `provision` and `boot` and leave
every named point hand-rolling a glob in a project hook. One implementation,
reachable from both sides; [mods.md](./mods.md#image-build) is the second caller.

## A hook is a process

- **No exec bit anywhere in the hook path.** `push_project`'s `chmod -R +x` and
  its `[ -d … ]` guard go, and `cmd_init` stops chmod'ing `hooks/`. A checkout
  with `core.fileMode=false`, a tarball or a zip stops breaking a workspace.
- **`exit` still means "this hook"** — `helpers`' `die` ends that process, so
  one hook's `exit 0` can't cancel the rest.
- **Nothing leaks either way.** One hook's `cd` can't move the next, and a hook
  can't read the runner's `$owner` or `$ran`.
- **para ignores the shebang.** Keep `#!/usr/bin/env bash` anyway — `bin/lint`
  discovers *by* shebang.
- **No arguments.** `$@` is empty by construction.
- **`$0` is the hook**, so `$(dirname "$0")/helpers` resolves. `$PARA_HOOKS`
  stays the taught spelling; the old one just doesn't break.

> **A hook reads its environment and writes to the filesystem. It never writes
> to its caller.**

True by construction, and the same answer either way in — the loop and a nested
`"$PARA_RUN_HOOK"` are both fresh processes.
[mods.md](./mods.md#how-a-hook-reaches-a-later-hook) lists the file channels.

## The environment a hook sees

The runner re-points #18's pair at whoever owns the hook, so a mod's hook is
written identically to a project's — `$PARA_HOOKS/helpers`, `$PARA_SKEL/zshrc`.

**Two new variables, set by the runner rather than `para_env`**, so neither
lands in `~/.paraspace/env`: `PARA_RUN_HOOK`, and `PARA_HOOK_STACK` (read-only
in practice — para rewrites it at every level). Both additive. No `PARA_MOD`:
`$PARA_HOOKS` already says where a hook lives, and `.shellcheckrc`'s
`source-path=SCRIPTDIR` resolves a mod's own `helpers` for free.

Sharp edges for `docs/hooks.md`:

- **Only exported variables reach a nested point.** A point fills in behavior;
  it does not take arguments.
- **A hook opening a point needs `set -e` to honor the failure** — without it
  the hook sails past a non-zero `"$PARA_RUN_HOOK"` and can still exit 0, and
  `para up` reports a ready workspace over a visible error.
- **Don't re-source `~/.paraspace/env`** — it holds the project's values, so it
  rewinds `PARA_HOOKS`/`PARA_SKEL`. Wrong file, no error.
- **The context doesn't survive `su -`/`sudo`.** A build hook stepping down
  needs `su - "$PARA_USER" -c 'PARA_SKEL=… …'`.

## Landing order

Four PRs, each shippable alone:

1. **Delete drift detection** — `image_src_sha`, `sha256_of`, the
   `user.para.src_sha` stamp, `image status`'s comparison.
   [Why](./mods.md#drift-detection-goes-away) it can't survive the builder
   consuming all of `.paraspace/`.
2. **`image-build.sh` → `hooks/image-build`**, with `push_paraspace` and
   `guest_env` — [mods.md](./mods.md#image-build). No runner yet, so the builder
   runs the hook by path.
3. **This plan.** `cmd_image_build`'s line becomes `run-hook image-build`, and
   `push_project` loses its `chmod`.
4. **[mods.md](./mods.md)** — `mods/`, `para mod add`, `docs/mods.md`, and
   `void-jchook` deleted.

2 before 3 costs one rewritten line and buys landing the rename —
[the largest blast radius in either plan](./mods.md#docs-impact) — while it is
the only thing in flight.

## Shipping it

- **`libexec/` in `package.json`'s `files`**, which lists `bin/para`, not
  `bin/`. Same exposure as the `templates` entry beside it.
- **Pushed by `push_paraspace`, not `push_project`** — the builder execs its
  copy too. `--mode 0755`, after the recursive push, so a project's own
  `.paraspace/run-hook` can't shadow para's. No existence check: `incus file
  push` already fails naming the path.
- **Bash shebang**, or `bin/lint` skips it. It also runs under bash 3.2 in
  `test/run --cli`, which CI can't catch.
- `guest_env()` arrives with PR 2 and gains no caller here. **It takes the
  destination as an argument** — the builder's copy lives at `/opt`, and #18's
  hardcoded `$home` path otherwise has a build hook read an absent `$PARA_SKEL`
  behind the `[ -f ]` guards those hooks already use: seeds nothing, says
  nothing.

It is **runnable on the host against a fixture `.paraspace/`**, which is what
makes the tests below need no incus.

**Why a file, not a `para_hook()` emitted into `env`.** `bin/lint` can't see a
heredoc, and the CLI tier would have no way to reach the real loop — leaving
[the required test](#test-checklist) either testing a copy or running only in
e2e. `env` is also data, and behavior in it is a category change the next
function would follow.

## Test checklist

CLI tier, against a fixture directory. **The first is required.**

- **A hook whose *middle* command fails stops there, and the runner exits
  non-zero.** The two halves guard different rewrites: the status is what
  `if ! bash "$hook"` breaks, the absent tail line is what `( . "$hook" )` does.
- a hook sees no arguments (`$#` is 0), not the runner's `$1`.
- `$0` is the hook, so `$(dirname "$0")/helpers` works.
- resolution: project before mods, a mod with no `H` skipped, no `mods/` →
  unchanged, `hooks/helpers` never run as a hook, each hook announced.
- a failing hook aborts the rest, its path is in the error, and a
  `helpers`-style `die` is what fails it.
- no owner fills the name → the note on stderr, exit 0.
- a hook with no exec bit runs; `PARA_HOOKS`/`PARA_SKEL` re-pointed per hook.
- a nested point resolves every owner, with `$PARA_RUN_HOOK` in the environment.
- a stray file under `mods/` is skipped, not treated as an owner.
- **the trace**: three points deep names every level, deepest first with the
  full `stack:`; the flat case still fails in one line with no `stack:`, or
  tracing becomes noise on the path everyone takes.
- **the cycle guard**: a self-invoking point exits 1 naming the chain; the same
  point invoked twice *in sequence* still runs twice.
- a hook reading stdin gets the caller's, not the hook list — catches a rewrite
  of the loop into a pipe.
- `npm pack --dry-run` covers `libexec/`, its own assert next to `templates/`
  and `mods/`.

e2e (run it — CI won't): a fixture mod appending its name in `provision` and in
a point the fixture opens; both ran, `up` still idempotent; a prompting hook
still gets the terminal. And **`image-build` through the runner in the builder**
— the only place `guest_env`'s destination argument is load-bearing, and the
only place a wrong answer is silent.

## `PARA_CONTRACT` stays 1

Dropping the exec bit changes hook semantics and
[mods.md](./mods.md#image-build) renames the image-build payload, so
[CLAUDE.md](../CLAUDE.md)'s rule would bump the contract. It doesn't: para has
one consumer, migrating by hand, and 1.0 shipping at contract 2 publishes a
version number for a migration nobody made.

The bill is **one edit** to a `.paraspace/` scaffolded from `paraspace@0.1.0`:
`image-build.sh` → `hooks/image-build`. Nothing refuses the old name; the build
just runs no hook, which is what the host check is for.
`$(dirname "$0")/helpers` needs no edit — `$0` is the hook.

It goes in `docs/versioning.md` under a **pre-release** heading, not a new
contract's migration table; its existing "hooks run by path — the shebang
decides, so keep it executable" row is now wrong and gets rewritten. Contract 1
freezes at 1.0.

## Docs

`docs/hooks.md` gains the resolution rule, "a hook is a process" and its
consequences, `PARA_RUN_HOOK`/`PARA_HOOK_STACK`, the sharp edges, and one worked
nested failure read end-to-end — and drops its "Everything here runs **by
path**" line. `docs/versioning.md` gains two rows besides the pre-release notes:
para runs `.paraspace/mods/*/hooks/*`, and `.paraspace/run-hook` joins `env` and
`host.env` as a name para owns.

## Deliberately not in v1

- **Refusing a project that ships `.paraspace/run-hook`.** para overwrites it.
- **Deterministic mod ordering**, and any `LC_ALL=C` to get it.
