# Plan: mods — vendored, reusable `.paraspace/` components

> **Working document.** Delete it once `docs/mods.md` and `docs/conventions.md`
> exist, the migration is adopted, and `void-jchook` is gone. Paired with
> [`plans/hook-runner.md`](./hook-runner.md), which is the seam this is built on
> and lands first.

## Goal

Let a project vendor reusable pieces of provisioning — dotfiles, a language
runtime, a CI helper — instead of forking a whole template to get them.

```sh
para mod add https://github.com/jchook/paraspace-mod-dotfiles
para up feat-x
```

The near-term test case is `templates/void-jchook`: diffed against
`void-docker-gh` it forks `provision` (125 vs 88 lines), `boot`,
`image-build.sh`, `Parafile` and `README.md`, and every one of those diffs
exists to carry **dotfiles and the toolchain they need**. None of it is a
different *kind* of workspace, so an engine-level fix to the base has to be
hand-ported into the fork; it rots instead.

The longer-term one is bigger: **templates become composable**. `void-docker-gh`
decomposes into docker / gh-auth / ssh-key / dotfiles-base, a template
*references* those instead of copying them, and the duplication between
templates goes away the same way the duplication between `void-jchook` and its
base does. That is why `para mod` is v1 rather than a convenience bolted on
later — see [Templates that declare mods](#templates-that-declare-mods).

A template is a **starting point** — copy once, own it forever. A mod is a
**dependency** — copy it, update it, don't edit it.

## Shape

```
project/.paraspace/
  Parafile  image-build.sh  hooks/  commands/  skel/
  mods/
    dotfiles-jchook/
      README.md
      hooks/{helpers,seed-shared,pre-clone,packages}
      commands/{claude,run}
      skel/{nvim,tmux,claude,zshrc}
      contract  .mod-source
```

A mod is **a directory with the same shape as a `.paraspace/`**. That is the
whole idea, and it is why little has to be invented: `push_project` already
pushes `.paraspace/` verbatim, so a mod reaches the guest with no engine change,
`up` stays offline, the review-before-you-run trust model holds, and every mod
change lands in the project's own git history.

Hook names above are **this template's vocabulary, not para's** — see
[Conventions](#conventions-are-the-real-interface).

## `para mod` lives in `libexec/mod`

```
para mod add <git-url|path> [--as <name>]   vendor a mod into .paraspace/mods/
para mod ls [--names]                       what's vendored, and from where
para mod rm <name>                          delete it
para mod update [<name>]                    re-vendor from .mod-source
```

Written out in full against the real `bin/para`, this is **~220 lines** — larger
than any single row in [`plans/minimal-engine.md`](./minimal-engine.md)'s
~955-line budget table, whose biggest is 130. It is also, honestly, a small
package manager: fetch, strip, shape-check, replace, stamp, hash, state, refuse,
converge. That does not belong in a file whose thesis is glue over incus and
caddy.

So **`bin/para` keeps only what `up`, `doctor` and `image` need** — `mod_names`,
`tree_sha`, the command resolver, roughly 60 lines — and the ~160 lines of
vendoring live in `libexec/mod`, which `para mod` execs. `mod` becomes the first
verb with no incus dependency at all, and the hot file stays the size its own
plan budgets for. `libexec/` is already being added to `package.json` for the
runner.

`cmd_mod` calls **`require_project_dir`**, not `require_project`. This is not
style: `require_project` validates mod contracts (below), so a mod declaring a
future contract would make every command die — *including the `para mod update`
the error message names*, leaving `rm -rf` by hand as the only escape. A repair
verb has to survive the state it repairs.

**The name** is the spec's basename, minus `.git`, any `#ref`, and a leading
`paraspace-mod-` — the ecosystem naming convention, which would otherwise put
the prefix in every directory, every `$PARA_MOD` and the resolution order.
`--as` overrides, and warns when a directory of the *derived* name already
exists: two vendors of one repo under two names is a silent double-run of every
hook. It needs its own `validate_mod_name`; `validate_name` is the *workspace*
validator (31 chars, must start `a-z`, error message says "workspace").

**Vendoring is `rm -rf "$dest" && cp -R "$tmp/." "$dest"`** — no copy loop, no
parameterized `copy_tree`, and `cmd_init` untouched. `update` is the same
operation, which is *why* overlaying was rejected: a force-copy never removes a
file the author deleted upstream, so a hook renamed `provision` → `post-clone`
would leave both, the stale one running forever.

Load-bearing details:

- **Strip `.git`, `.gitignore` and `.gitattributes`.** `.git` or "the tree in
  git is the truth" is false and `push_project` ships the object store into
  every workspace. The other two because they apply to the vendored copy *inside
  the consumer's repo*: a dotfiles mod ignoring `lazy-lock.json` means
  `git add .paraspace/mods/x` silently omits it, the consumer commits an
  incomplete mod, and a teammate runs a different mod than the author shipped.
- **Check the shape** — refuse a fetch with none of `hooks/`, `commands/`,
  `skel/`, the way `para init` refuses a repo with no `.paraspace/`.
- **Validate the name before it reaches a path.** `para mod rm ''` is
  `rm -rf .paraspace/mods/`; `para mod rm ../hooks` takes the project's hooks.
- **A local path is copied, not cloned**, and absolutized at add time. Cloning
  would vendor the last commit while the author iterates uncommitted; absolute
  because para finds the project by walking *up*, so `update`'s cwd varies.
- **`need git`** plus a `doctor_host` check, and
  `git -c advice.detachedHead=false clone` — `--branch <tag>` otherwise dumps
  twelve lines of detached-HEAD advice into the middle of para's output.
  `--branch` takes a branch or tag, never a sha.
- **`mod add` prints the hook points the mod ships**, flagging any the project's
  tree never mentions. A mod filling a point nobody opens is a silent no-op, and
  it is the likeliest first-day report. Four lines.

`.mod-source` holds the spec verbatim (`#ref` included) so `update` is a
parse-free re-vendor, plus a tree hash so `ls` can print `modified` and `update`
can refuse without `--force`. The hash **excludes `.mod-source` itself** — it
lives inside the mod, so a whole-tree hash could never match and every mod would
report `modified` on arrival. It is `find -print0 | xargs sha256sum` batched,
**not** one fork per file: measured on a 365-file nvim config — this plan's own
motivating example — per-file is 2.5s against 0.011s, 230×, and it lands on
`mod ls`, `doctor`, `image status` and every `update`. `sha256sum`'s own output
*is* the `<sha>  <path>` list, sorted `LC_ALL=C` and hashed once more. It cannot
see symlinks or modes; say so.

A mod with no `.mod-source` is hand-written: bare `update` warns and skips. So
does a *modified* one — dying mid-list would re-vendor mod 1, abort on mod 2 and
never touch mod 3, a partial state from a converging verb. `update <name>`
converts that same warning into a `die`, so the diagnosis is written once.

**A mod declares the contract it targets** in `mods/<m>/contract` — first line, a
bare integer. That is a new name para owns inside someone else's directory, so
it needs a `docs/versioning.md` entry beside `run-hook`. Checked in
`require_project` and surfaced by `doctor`, not only at `add`/`update`: the case
that actually happens is *para* upgrading while the vendored mod sits still.

**`para mod` must be registered in four places** or it half-exists: `main`'s
dispatch, `usage`'s PROJECT block (CLAUDE.md requires `--help` and
`docs/commands.md` share one grouping), `is_engine_verb`, and `cmd_completions`
— which needs `add|ls|rm|update` at position 2 *and* vendored names at 3, or the
existing fallback offers **workspace** names for `para mod rm <TAB>`. That is
what `ls --names` is for, and it must land in the same commit as the completion
heredoc, which no test executes.

### What ships bundled

para's tarball ships **its own reference mods** — the components
`void-docker-gh` decomposes into — and no personal ones. The line is
maintenance, not principle: bundling para's own building blocks is what
`templates/` already is, while bundling someone's nvim config makes para the
vendor-of-record for a tree that changes weekly against an engine that doesn't.
`dotfiles-jchook` ships as its own repo, and `para mod update` picks up its
changes with no para release.

The repo also needs a mod under `test/fixtures/`, **committed** — see
[Tests](#test-checklist) for why it can't be vendored at test time — exercising
two hook points, a command, a skel file, a build hook and a `.mod-source`.
Without one, `bin/lint` never lints a mod hook and no test sees the documented
shape. (Confirmed: `bin/lint`'s shebang discovery picks it up, and
`.shellcheckrc` resolves its own `helpers`.)

## Commands

`mods/<m>/commands/<verb>` becomes `para <verb>`, run on the host like
`.paraspace/commands/`. Precedence, first match wins: **engine verb → project
command → mod command** (mods in `LC_ALL=C` order).

`project_commands` returns bare names and two callers rebuild the path from
`$PARA_PROJECT_DIR/.paraspace/commands/` — `run_project_command`, and
`command_summary` via `usage_project_commands`. For a mod verb both are wrong:
`--help` would `sed` a nonexistent file per mod verb, and `run_project_command`
would `die "unknown command"` for a verb `para commands` just listed. Replace it
with **one resolver emitting paths in precedence order**; the callers consume
paths, and `usage_project_commands`' header
`PROJECT COMMANDS (%s/.paraspace/commands)` stops being a lie. First-wins dedupe
is one `awk -F/ '!seen[$NF]++'`, and inverting it gives `doctor` the shadowed
list for free.

`run_project_command` exports `PARA_MOD`/`PARA_MOD_DIR` — **always, empty for a
project command** — which is the entire justification for `PARA_MOD_DIR`
existing.

**Commands are the one remaining exec-bit case.** Hooks are sourced now, but a
mod command is a host process: vendored from a mode-644 tree it fails with
`Permission denied`, exit 126, no para context. One line where commands are
executed, mirroring nothing else in the engine.

**`para commands` stays one bare name per line.** It is a scripting surface and
the shipped completion feeds it into `compgen -W`; a second column would offer
mod names as verbs. Source goes in `--help`, whose second column already belongs
to the `# summary:` line — so prefix it (`claude   [dotfiles] …`) and pick that
spelling before `docs/commands.md` is written.

## Image build

`.paraspace/` goes into the builder and the payload opens named points — the
same resolution rule as everywhere else, rather than a second list-and-loop kept
in step by prose.

- **The tree lands in `/opt/.paraspace`, pushed with `-r -p`.** Not
  `/root/.paraspace`: that is mode 0700, so `su - "$PARA_USER" -c 'cat
  $PARA_SKEL/…'` — this plan's own migration spelling — can't read it. `-p`
  because `/opt` may not exist on a minimal base. Verified in a real build, with
  nothing left in the published image.
- **Push the runner there too** and set `PARA_RUN_HOOK` in the generated env, or
  the migrated `image-build.sh`'s first named point is an unbound variable under
  `set -u` and `para image build` fails for every project on day one. The
  builder's value differs from the workspace's, which is the concrete reason the
  variable exists.
- **Stop piping the payload.** `cmd_image_build` pipes
  `{ para_env; cat "$payload"; }` into `bash -s`, so **the payload is stdin** —
  and the runner hands stdin to each hook. A build hook running `xbps-install`
  without `-y`, or any `read`, swallows the rest of `image-build.sh`: the docker
  enable, the daemon wait and the overlay-driver check never run, the pipeline
  exits 0, and `image_publish` publishes exactly the broken image that driver
  check exists to refuse. Silently. Run it by path instead:
  `incus exec … bash -c '. /opt/.paraspace/env; exec bash …/image-build.sh' &`
  + `wait "$!"`. The interrupt dance survives byte for byte.
  **But note the `&` means POSIX gives the async list `/dev/null` for stdin**, so
  a build hook gets EOF, not a terminal. The swallowing bug is fixed; "a hook can
  prompt" is `up`-only and the docs must say where.
- **`rm -rf` the builder's tree before pushing.** `incus file push -r` merges;
  `push_project` opens with exactly this `rm -rf` for exactly this reason.
  Without it, `para image build -i` — which relaunches from `$PARA_IMAGE` — runs
  mods you deleted, because they are still in the image.
- **Don't bake it into the published image.** `image_publish` snapshots the
  builder's whole rootfs.
- **Reuse `guest_env`** — the same corrections `push_project` makes, named once
  rather than enumerated so it can't drift. Raw `para_env` hands a build hook
  `PARA_BIN`, `PARA_PROJECT_DIR`, `PARA_CONFIG*` and `PARA_STATE_DIR` as *host*
  paths.

Inlining this pushes `cmd_image_build` to ~72 lines, so the builder body extracts
to `image_provision()` and `cmd_image_build` ends up *below* its current 55.

**`image_src_sha` covers the mods** via the same `tree_sha`. Hashing content
without names is not enough — deleting one hook and creating another with the
same bytes yields an identical hash for a different image. The open cost, measured:
hashing all of `.paraspace/` reports `drifted` after a comment appended to the
`Parafile`, or an edit to a guest-only `hooks/provision`. That is most commits,
and it can't be narrowed by rule — `PARA_PREPULL_IMAGES` genuinely *is* an image
input. Keep over-broad, because a spurious rebuild beats a stale image reported
current, but **`image status` must name the files that changed** or the signal
degrades to "something in the project changed". One line in `docs/image.md` for
the one-time cliff that flips every already-published image, including every
developer's cached fixture image.

## What a mod may assume

Only para's contract: `$PARA_*`, `$HOME`, `$PARA_SHARED`, and its own
`$PARA_HOOKS`/`$PARA_SKEL`/`$PARA_MOD_DIR`.

- **Not the project's `helpers`.** Template policy, not engine contract, and
  `$PARA_HOOKS/helpers` resolves to the mod's own anyway. (Promoting `helpers`
  into the engine would make para own log formatting.)
- **Never clobber** — but see [Conventions](#conventions-are-the-real-interface):
  never-clobber and append-a-fragment are different rules for different files,
  and which applies is a property of the file.
- **Not its position**, and not that another mod ran.
- **Not stdin past its own prompt**, and no stdin at all in the builder.
- **Not that it can write to its caller.** A hook reads its environment and
  writes to the filesystem — see
  [hook-runner.md](./hook-runner.md#hooks-are-sourced-in-a-subshell). Anything
  the rest of the workspace must see goes in the image (`/etc/profile.d`) or on
  the filesystem.
- **Not that its context survives `su -`/`sudo`.**
- **Not the `Parafile`.** Mods are never sourced on the host. A mod's knobs are
  ordinary `PARA_*`, defaulted in its own hook and documented in its README.
- **Not the distro.** Build hooks are package-manager-coupled; the README says
  which base it targets.

Two mods that both symlink `~/.zshrc` is a conflict para will not detect: **a
hook must be idempotent and must not clobber; where the outcome depends on
order, para promises nothing and you resolve it by hand.**

### Mods are not reversible

`para mod rm` deletes the directory. It does not touch what the mod wrote:
`$PARA_SHARED` files, symlinks in every existing workspace, the login shell it
`chsh`'d, packages baked into the image. Under first-writer-wins nothing
re-seeds them either, so a new workspace still links the removed mod's files.

So `mod rm` warns and names `$PARA_SHARED`, `docs/mods.md` carries the manual
path (`rm $shared/zshrc; para up`), and the e2e tier tests **removal**. The same
asymmetry bites on add: a mod added to an already-seeded volume gets its *new*
paths and skips what the base already wrote — the mod's editor with the base's
shell, half-applied and silent. The test asserts that this is what happens, not
that it is desirable.

## The first PR has nothing to do with mods

`void-docker-gh` seeds the shared volume inside a one-time `$shared/.seeded`
guard. Replacing that with per-destination guards converges, and is what lets
`seed-shared` exist at all.

**It is not a bug fix, and an earlier draft of this plan claimed it was.** The
sentinel does mean a file added to `skel/` later never reaches an existing
volume — but `void-docker-gh` and `void-minimal` each seed exactly one file, so
it needs a second one to bite; the only template where it occurs is
`void-jchook`, which already worked around it per-file; and templates are
copy-once, so no existing project would get the fix anyway. The honest claim is
**it fixes the shape users copy, and it unblocks the mod work.**

Traps, all verified:

- **`[ -e dest ] || cp` is not a drop-in for `[ -f src ] && cp`.** Under
  `set -euo pipefail` the `&&` form survives a missing source (the failing test
  isn't the list's last command) while the `||` form runs `cp` on a nonexistent
  file and aborts the hook. Guard **both**:
  `if [ -f "$skel/zshrc" ] && [ ! -e "$shared/zshrc" ]; then …`
- **Retire `.seeded`** rather than keeping it; with per-destination guards it is
  strictly less precise. It is never removed from already-upgraded volumes —
  migration code in a copy-once file lives forever, so don't write any.
- **`void-minimal` and `test/fixtures/hello` carry the same sentinel.**
  `void-jchook` carries it too and is being **deleted**, not converted.
- **The `stage "Seeding shared volume (one-time)"` line becomes a lie**, and an
  unconditional header prints on every `up`. Pick deliberately.
- **This PR must carry the first test of the seam.** `sandbox.sh` creates a
  run-unique volume and deletes it at teardown, so every e2e run seeds fresh and
  the sentinel and the guards are indistinguishable — both tiers pass unchanged
  on the converted tree, i.e. the change is invisible to CI. The test is
  `para sh <ws> -c 'rm /para/shared/marker'` → `para up` → assert it came back.
  Five lines, and the only thing that makes this PR observable.

## Migrating `void-jchook`

A naive additive port does not work: both templates ship a `skel/zshrc` and the
base seeds `$shared/zshrc` in its one-time guard, so a mod running after it can
only clobber or skip; and mods at the `provision` point run after the project's
*entire* provision, which `die`s on a failed clone — today `void-jchook` seeds
zsh/nvim/tmux *before* cloning, so an unauthorized key still leaves a usable box.

So `void-docker-gh` **gains two hook points**:

```sh
"$PARA_RUN_HOOK" seed-shared     # before its own seeding
…                                 # guarded, so a mod's file survives
"$PARA_RUN_HOOK" pre-clone        # everything that must precede the clone
clone || authorize_key
```

| Today | Becomes |
|---|---|
| the `skel/` tree (nvim, tmux, claude, zshrc, bin) | `mods/dotfiles-jchook/skel/` |
| seeding the shared volume | `hooks/seed-shared`, guarded both ways |
| symlinks, `chsh`, the managed Claude policy | `hooks/pre-clone` — **not** `provision`, which is after the clone and defeats the point |
| the `image-build.sh` diff (packages, Claude Code) | `hooks/packages` |
| `commands/{claude,run}` | `mods/dotfiles-jchook/commands/` |
| the `Parafile` and `boot` diffs | nothing — prose differences |
| the template itself | deleted; its README content moves to the mod's repo |

Everything else in that diff — `/tmp` perms, the docker group,
`PARA_PREPULL_IMAGES`, `known_hosts`, recording the clone dir — is already in
the base and moves nowhere.

Four wrinkles to settle rather than discover:

- **`$shared/gitconfig` needs an owner, and first-writer-wins is the wrong rule
  for it.** git has no include-*directory*, so composing means each mod appends
  its own `[include] path =` line — so the first mod to run *creates* the file,
  the base's guarded write skips, `[user]` is never written, and every workspace
  fails `git commit` with "Please tell me who you are". So the base **owns** it:
  identity written create-if-absent *before* `seed-shared`, and the
  include-emitting loop *after* it — mods write their fragments **in** that hook
  point, so a loop running before would pick them up only on the next `up`.
  Create-if-absent is essential rather than cosmetic: `git config --global`
  inside a workspace writes through the symlink, so a regenerate-every-up design
  would eat every alias and signing key the user ever set. Idempotence is
  `grep -qxF "path = $f"` — the `-x` is load-bearing, since `-qF` prefix-matches
  and a mod named `dot` would never be included when `dotfiles` exists. Iterate
  with `[ -f "$f" ] || continue`, never `cat gitconfig.d/*` (the unmatched-glob
  `pipefail` trap). A removed fragment leaves a stale include line forever; git
  ignores missing includes, so it is harmless but never collected.
- **A fragment must never write `[user]`.** git resolves includes at read time
  and `git config --global user.name` edits the existing section in place, so a
  fragment's `[user]` silently overrides both the base identity and the user's
  own later edit. Ordering cannot prevent it; it is a `docs/conventions.md` rule.
- **`$BROWSER` fits no hook point** — `void-jchook` exports it so the base's
  `authorize_key` device flow sees it, and a hook cannot write to its caller.
  The mod's `packages` build hook writes `/etc/profile.d/`, which `su -` sources
  before any hook runs.
- **`packages` runs late and its name says early.** It must follow the base's
  `useradd` (Claude Code installs *as* `$PARA_USER`) and the base's `-Syu` full
  upgrade, or it is Void's partial-upgrade footgun. The position is the
  contract; document it where the point is defined.
- **`ln -sfn` onto a real `~/.claude` nests inside it.** The trigger is a
  workspace where `claude` ran once and recreated it before the mod was added,
  not `image build -i`. The mod's hook does `[ -L ~/.claude ] || rm -rf ~/.claude`.

**Migration check** (a one-time manual equivalence, not a test):
`para init void-docker-gh && para mod add <url>` reproduces today's
`void-jchook`. The committed fixture mod is what the tiers actually run.

## Conventions are the real interface

para has no opinions, so every opinion lives somewhere else or mods don't
compose. Two mods coexist only because their authors independently assumed the
same hook point names, shared-volume layout and package manager. None of that is
enforceable and all of it is required.

**`docs/conventions.md`** is a compatibility target, not a style guide, and
opens by saying para enforces none of it. Two audiences: project authors ("open
these points if you want mods to work with you"), mod authors ("assume only
these"). The editorial test that keeps it from swallowing the contract docs: **if
para still works when you ignore it, it's a convention; if para breaks, it's
contract** and belongs in `versioning.md`/`run-hook.md`.

Contents: the hook point names (`seed-shared`, `pre-clone`, `post-clone`,
`packages`) *and where each sits*, with the reference template as their
executable definition; the `$PARA_SHARED` layout; the base image;
`paraspace-mod-*` repo naming; and the two that must be stated together or they
read as contradictory —

- **Never clobber** a file with a single owner (`zshrc`, `tmux.conf`).
- **Append a fragment** to a file with many (`gitconfig.d/<mod>`), where the
  base owns the file and mods only ever add — and never touch `[user]`.

Which rule applies is a property of the file, and the layout says which.

**Conventions are more expensive to change than contracts.** A `PARA_CONTRACT`
bump has a mechanism — para refuses and says so. Renaming `post-clone` has none;
mods just stop running.

## Templates that declare mods

`PARA_MODS` in the `Parafile` — the specs a project intends to have vendored —
and `para init` runs `mod add` for each. This is what makes templates
composable: `void-docker-gh` decomposes into reference mods and *references*
them, so the duplication between templates goes the way the duplication inside
`void-jchook` does.

`PARA_MODS` is a **manifest, not the source of truth for what runs** — the
directory is, the way `package.json` relates to `node_modules` — so a
declared-but-missing mod is a `doctor` warning, not a behavior change. And
**para never writes to a `Parafile`**; `config-set` was deleted in favor of
hand-editing. `init` gains `--no-mods` and prints each fetch, since it now
touches the network, and `cmd_init`'s `chmod` case needs the same widening the
copy loop did.

Sequence this **after** `dotfiles-jchook` proves the seams as a single external
consumer. Decomposing the default template is the second consumer, and it should
be informed rather than speculative.

## Settled: no ordering knob, and the name

An earlier draft gave hooks `H.d/*` fragments with `NN-` prefixes and had to pick
whether numbers were scoped or global. Scoped makes the number a lie across mods;
global makes every author guess against projects they've never seen. Named points
replace both. The resolution rule **is** the contract, so adding position
semantics later reorders existing hooks; adding named points never does.

`mod`, not `plugin` (implies an extension API para doesn't have), not `pod`
(para is a container tool; a workspace *is* a container), not `fragment` (long in
the CLI, connotes a broken-off piece). A mod **composes into** a `.paraspace/`;
it never modifies the engine.

## Docs impact

- new `docs/mods.md` and `docs/conventions.md` — both need a
  `.vitepress/config.mts` sidebar entry **and** a `docs/README.md` router line.
- `docs/commands.md` — mod commands, precedence, the `--help` source spelling,
  and the template→commands table.
- `docs/image.md` — the builder push, named build points, no stdin in the
  builder, and the one-time `drifted` cliff.
- `docs/versioning.md` — the reserved names (`run-hook`, `mods/<m>/contract`).
- `docs/project-setup.md` — a `mods/` row in "What's in `.paraspace/`".
- `docs/parafile.md` — `PARA_MODS`, and link "Your own vars" rather than
  re-deriving it.
- `docs/cookbook.md` — "Bring your dotfiles" and "Add a `para` verb" are the two
  recipes a mod supersedes.
- `docs/shared-auth.md` — one line on `$PARA_SHARED/gitconfig.d/`.
- `void-jchook` is named in `README.md` ("three runnable templates"),
  `docs/project-setup.md` ×2, `docs/commands.md`, `docs/agents.md`,
  `docs/shared-auth.md`, `CLAUDE.md` ×2 — plus **relative links from
  `templates/void-docker-gh/README.md` and `templates/void-minimal/README.md`**,
  which ship in the tarball and would 404, and a mention in `void-minimal`'s
  `skel/zshrc`. `docs/agents.md` is the sharpest: it teaches `para claude`, so it
  must say *mod*, not *template*.
- `plans/minimal-engine.md` — a budget-table row, honest that mods are the
  largest thing in the engine even after the `libexec/mod` split.
- `plans/init-from-git-url.md` is **stale**; this work *builds*
  `is_git_spec`/`git_clone_spec` and `para init <git-url>` adopts them later.

## Test checklist

The fixture mod is **committed**, not vendored at test time: `sandbox.sh` points
`PARA_PROJECT_DIR` at the tracked `test/fixtures/hello` and teardown doesn't
cover it, so a test running `mod add` there would dirty the working tree, make
`bin/lint` lint the vendored copy, and fail on the second run with "already
vendored".

CLI tier — most of this belongs here so CI runs it. `add`/`rm`/`update` drive a
**copied** project (`cp -R "$FIXTURE_DIR" "$(scratch)/hello"`), no incus needed:

- `add` from a local path and a URL → files land, `.git`/`.gitignore` stripped,
  shape check refuses a non-mod, name derived without the `paraspace-mod-`
  prefix, `--as` overrides and warns on a derived-name collision.
- `update` removes an upstream-deleted file; refuses a modified tree without
  `--force`; warns and skips hand-written and modified mods in a bare `update`
  rather than dying mid-list; a freshly added mod does **not** report `modified`.
- a mod declaring a future contract still lets `para mod update` run.
- `rm`/`add` refuse a name with a path in it; `cmd_mod` outside a project fails
  with para's own error.
- command precedence, `para commands` still one bare name per line,
  `PARA_MOD_DIR` exported to a mod's command, a mode-644 mod command still runs.
- `para mod` in all four registration sites, including `para mod rm <TAB>`.

e2e tier (run it — CI won't): the committed fixture mod through a full `up`;
**`mod add` onto an already-seeded volume** (assert the half-applied reality);
**`mod rm` then `up`** (assert the shared volume and symlinks survive);
`para image build` with a mod's build hook, then `image status` after editing it
→ rebuild needed, naming the changed file. Needs `PARA_TEST_REBUILD=1`, since the
fixture image is cached and this would otherwise pass vacuously.

## Deferred

- Any ordering syntax. Named points instead.
- Mod dependencies, or declaring which points a mod needs (`mod add`'s printout
  is the cheap interim).
- Fetch-at-`up` mods, or a lockfile. Vendoring is the model.
- Mod-contributed `Parafile` defaults — deliberately not a thing.
- `cmd_up` warning when a mod's build hooks postdate the image's stamped
  `src_sha`. "Added the mod, ran `up`, nvim isn't there" is the day-one report.
