# Plan: mods — vendored, reusable `.paraspace/` components

> **Working document.** Delete it once `docs/mods.md` and
> `docs/conventions.md` exist, the migration is adopted, and `void-jchook` is
> gone. Paired with [`plans/hook-runner.md`](./hook-runner.md), which is the
> seam this is built on and lands first.

## Goal

Let a project vendor reusable pieces of provisioning — dotfiles, a language
runtime, a CI helper — instead of forking a whole template to get them.

```sh
para mod add https://github.com/jchook/paraspace-mod-dotfiles
para up feat-x
```

The test case is `templates/void-jchook`. Diffed against `void-docker-gh`, it
forks `provision` (125 vs 88 lines), `boot`, `image-build.sh`, `Parafile` and
`README.md` — and every one of those diffs exists to carry **dotfiles and the
toolchain they need**. None of it is a different *kind* of workspace, so an
engine-level fix to the base has to be hand-ported into the fork; it rots
instead.

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
      .mod-source
```

A mod is **a directory with the same shape as a `.paraspace/`**. That is the
whole idea, and it is why little has to be invented: `push_project` already
pushes `.paraspace/` verbatim, so a mod reaches the guest with no engine change,
`up` stays offline, the review-before-you-run trust model holds, and every mod
change lands in the project's own git history.

Hook names above are **this template's vocabulary, not para's** — see
[Conventions](#conventions-are-the-real-interface).

`para mod add` is a convenience, not a requirement: a mod is just a directory,
so a project can write one by hand and a fixture can ship one inline.

## `para mod`

```
para mod add <git-url|path> [--as <name>]   vendor a mod into .paraspace/mods/
para mod ls                                 what's vendored, and from where
para mod rm <name>                          delete it
para mod update [<name>]                    re-vendor from .mod-source
```

**The name** is the basename of the spec, minus `.git` and any `#ref`, with
`--as` to override. It needs its own `validate_mod_name` — `validate_name` is
the *workspace* validator (31 chars, must start `a-z`, and an error message that
says "workspace"), so a repo called `Dotfiles` would be refused for the wrong
reason. `add` refuses an existing directory unless it came from `update`.

**Vendoring is `rm -rf "$dest" && cp -R "$tmp/." "$dest"`.** No copy loop, no
parameterized `copy_tree`, no chmod predicate: exec bits come from the clone,
and `cmd_init` is untouched. `update` is the same operation — which is *why*
overlaying was rejected, since a force-copy never removes a file the author
deleted upstream and a hook renamed `provision` → `post-clone` would leave both,
the stale one running forever. Split `mod_vendor <spec> <dir>` (clone → strip
`.git` → shape check → replace → stamp) from `cmd_mod_add` (parse, validate,
report) so neither blows the ~30-line gate.

Load-bearing details:

- **Strip the mod's `.git`.** Otherwise "the tree in git is the truth" is false
  in the consumer's repo, and `push_project` ships the object store into every
  workspace on every `up`.
- **Check the shape.** `para init` refuses a repo with no `.paraspace/`; a mod's
  repo root *is* the mod, so refuse a clone with none of `hooks/`, `commands/`,
  `skel/`. Without it, `para mod add <any repo>` vendors an arbitrary tree that
  para then makes executable and pushes into every workspace.
- **Validate the name before it reaches a path.** `para mod rm ''` is
  `rm -rf .paraspace/mods/`; `para mod rm ../hooks` takes the project's hooks.
  `add` and `update` need the same guard on the write side.
- **`.mod-source` stores the original spec verbatim**, `#ref` included, so
  `update` is a parse-free re-vendor. It also records a tree hash at vendor
  time, so `ls` can print `modified` and `update` can refuse without `--force`
  rather than silently eating local edits. A hand-written mod has no
  `.mod-source`: bare `update` warns and skips it, never dies.
- **A mod may declare the contract it targets**, checked at `add`/`update` —
  not at `up`, which would make mods executable on the host. Without it, a mod
  written against a later contract fails confusingly, or its hook silently never
  runs.

**`para mod` must be registered in four places** or it half-exists: `main`'s
dispatch, `usage`'s PROJECT block (CLAUDE.md requires `--help` and
`docs/commands.md` share one grouping), `is_engine_verb` (or a project command
named `mod` is silently shadowed with no `doctor` warning), and
`cmd_completions`' verb list plus a `mod)` case arm.

### No bundled mods, one in-repo reference

para's tarball ships no mods. The reason is not "copy-once vs dependency" —
that collapses, since mods are vendored too and para's obligation also ends at
the copy. The reasons are **registry risk** (a bundled list plus an `update`
verb makes para's tarball the index) and **release cadence**: dotfiles change
weekly, para doesn't, and coupling the two means either your nvim tweaks wait
for a para release or para releases carry nvim tweaks. `dotfiles-jchook` ships
as its own repo, and `para mod update` picks up its changes with no para release
at all.

But the repo needs **one reference mod in-tree**, under `test/fixtures/`, or
nothing here is ever exercised: `bin/lint` would never lint a mod hook, no test
would see the documented shape, and the acceptance test below can't run in CI or
be sandboxed. It exercises two hook points, a command, a skel file, a build hook
and a `.mod-source`. It is also why `para mod add` takes a **local path**.

(So the `helpers` copy a mod must ship lives in the *mod author's* repo and is
their problem — `test_template_helpers_do_not_drift` globs `templates/*` and
can't reach it.)

## Commands

`mods/<m>/commands/<verb>` becomes `para <verb>`, run on the host like
`.paraspace/commands/`. Precedence, first match wins: **engine verb → project
command → mod command** (mods in `LC_ALL=C` order).

This needs a refactor the surface hides. `project_commands` returns bare names,
and three callers rebuild the path from `$PARA_PROJECT_DIR/.paraspace/commands/`:
`run_project_command`, `command_summary` via `usage_project_commands`, and
`doctor_project`. For a mod verb every one is wrong — `--help` would `sed` a
nonexistent file per mod verb (stderr noise inside `--help`), and
`run_project_command` would `die "unknown command"` for a verb `para commands`
just listed. Replace it with **one resolver emitting paths in precedence
order**; the three callers consume paths, and `usage_project_commands`' header
`PROJECT COMMANDS (%s/.paraspace/commands)` stops being a lie.

**`para commands` stays one bare name per line**, deduped first-wins. It is a
scripting surface and the shipped completion feeds it straight into
`compgen -W`; a second column would offer mod names as verbs. Source belongs in
`--help`'s second column. `doctor` already warns when a project command shadows
an engine verb — extend it to two mods shipping one verb, and have it list the
vendored mods and their `.mod-source`, since "read the hooks you run" is the
trust model and `doctor` is where para says what it will execute.

## Image build

Most of the `void-jchook` diff is packages, so a mod that ships dotfiles has to
reach the image. `.paraspace/` goes into the builder and the payload opens named
points — the same resolution rule as everywhere else, rather than a second
list-and-loop kept in step by prose.

Five things the naive version gets wrong:

- **Stop piping the payload.** `cmd_image_build` pipes
  `{ para_env; cat "$payload"; }` into `bash -s`, so **the payload is stdin** —
  and the runner deliberately hands stdin to each hook. A build hook that runs
  `xbps-install` without `-y`, or any `read`, swallows the rest of
  `image-build.sh`: the docker enable, the daemon wait and the overlay-driver
  check never run, the pipeline exits 0, and `image_publish` publishes exactly
  the broken image that driver check exists to refuse. Silently. Since the tree
  is now *in* the builder, run it by path instead — push a generated
  `/root/.paraspace/env`, then `incus exec … bash -c '. …/env; exec bash
  …/image-build.sh' &` + `wait "$!"`. The interrupt dance survives byte for
  byte, and payload and hooks each get a clean stdin.
- **`rm -rf` the builder's tree before pushing.** `incus file push -r` merges;
  it never deletes. `push_project` opens with exactly this `rm -rf` for exactly
  this reason. Without it, `para image build -i` — which relaunches from
  `$PARA_IMAGE` — runs mods you deleted, because they're still in the image.
- **Don't bake `.paraspace/` into the published image.** `image_publish`
  snapshots the builder's whole rootfs. `rm -rf /root/.paraspace` before it, or
  every published image carries project source and a pinned copy of para's
  runner.
- **`chmod -R +x` the builder tree too**, for the reason `push_project` already
  does it: a checkout, a tarball or a push can all lose the bit, and a build
  hook without it fails the build with 126.
- **Correct the builder's env like the guest's.** `cmd_image_build` pipes raw
  `para_env`, so `PARA_BIN`, `PARA_PROJECT_DIR`, `PARA_CONFIG*`,
  `PARA_STATE_DIR` reach a build hook as *host* paths — the exact set
  `push_project` unsets. A mod hook that works at `packages` would die at
  `provision`.

**`image_src_sha` must cover the mods**, and hashing content alone is not
enough: `cat`ting a file list drops the names, so deleting one hook and creating
another with the same bytes yields an identical hash for a genuinely different
image. Hash **path then content**, over an `LC_ALL=C`-sorted list, and hash the
whole of `.paraspace/` rather than trying to enumerate what the builder can
reach — build hooks now see `$PARA_SKEL`, so the project's `skel/` is an image
input too. Over-broad is the right failure direction: a spurious rebuild beats a
stale image reported as current. One `image_inputs()` helper, and it must not
break the *no-mods* case — an unmatched glob handed to `cat` exits non-zero, and
`pipefail` turns that into "the image inputs could not be hashed" for the
majority of projects.

Three spellings of one path (`~/.paraspace/run-hook`, `/root/.paraspace/…`,
`$PARA_HOOKS`-relative) is one too many, right after #18 established naming
these by injected variables. Inject one — a `PARA_RUN_HOOK` — used by `bin/para`,
the templates and the docs. The hardcoded `/root` also assumes the base image's
root home.

## What a mod may assume

Only para's contract: `$PARA_*`, `$HOME`, `$PARA_SHARED`, and its own
`$PARA_HOOKS`/`$PARA_SKEL`/`$PARA_MOD_DIR`.

- **Not the project's `helpers`.** Template policy, not engine contract, and
  `$PARA_HOOKS/helpers` resolves to the mod's own anyway — so a mod ships one.
  (Promoting `helpers` into the engine would make para own log formatting.)
- **Never clobber.** Every seeder guards the destination *and* its source.
  **First writer wins.** This is what makes `mod add` safe against a volume
  that's been live for months with hand-edited files.
- **Not its position**, and not that another mod ran.
- **Not stdin past its own prompt.** One stdin feeds every hook in a point.
- **Not that its context survives `su -`/`sudo`.** Both reset the environment;
  see [hook-runner.md](./hook-runner.md#the-environment-a-hook-sees).
- **Not the `Parafile`.** Mods are never sourced on the host. A mod's knobs are
  ordinary `PARA_*`, defaulted in its own hook and documented in its README.
- **Not the distro.** Build hooks are package-manager-coupled; the README says
  which base it targets.

Two mods that both symlink `~/.zshrc` is a conflict para will not detect. That
is the honest headline: **a hook must be idempotent and must not clobber; where
the outcome depends on order, para promises nothing and you resolve it by hand.**

### Mods are not reversible

`para mod rm` deletes the directory. It does not touch what the mod wrote:
`$PARA_SHARED` files, symlinks in every existing workspace, the login shell it
`chsh`'d, packages baked into the image. And under first-writer-wins nothing
re-seeds them, so a new workspace of the same project still links the removed
mod's files.

The "copy it, update it" framing promises a reversibility the mechanism can't
deliver, so say so: `mod rm` warns and names `$PARA_SHARED`, `docs/mods.md`
carries the manual path (`rm $shared/zshrc; para up` to re-seed), and the e2e
tier tests **removal**, not just addition.

The same asymmetry bites on add: a mod added to an already-seeded volume gets
its *new* paths (nvim, tmux) and skips the ones the base already wrote (zshrc) —
so you get the mod's editor and the base's shell. Half-applied, silently. The
reseed story is the answer, and the e2e test must assert the half-applied state
is what actually happens rather than asserting it is correct.

## The first PR has nothing to do with mods

`void-docker-gh` seeds the shared volume inside a one-time `$shared/.seeded`
guard. That has a live bug today: **a file added to `skel/` after the first `up`
never reaches an existing shared volume.** Replacing the sentinel with per-file
guards fixes it, converges, and removes the migration's hardest blocker — with
no engine change, no #18 and no mods.

Two traps in that edit:

- **`[ -e dest ] || cp` is not a drop-in for `[ -f src ] && cp`.** Under
  `set -euo pipefail` they differ: with the source missing, the `&&` form's
  failing test isn't the last command of the list and survives, while the `||`
  form runs `cp` on a nonexistent file and aborts the hook. A project that
  deleted `skel/zshrc` works today and would stop. Guard **both**:
  `if [ -f "$skel/zshrc" ] && [ ! -e "$shared/zshrc" ]; then …`
- **Retire `.seeded` rather than keeping it.** With per-destination guards it is
  strictly less precise, and keeping it breaks the gitconfig fix below on every
  pre-existing volume.

## Migrating `void-jchook`

A naive additive port does not work, for two reasons:

1. Both templates ship a `skel/zshrc`, and the base seeds `$shared/zshrc` and
   `gitconfig` in its one-time guard. A mod running after it can only clobber
   your edited file or skip.
2. Mods at the `provision` point run after the project's *entire* provision —
   which `die`s on a failed clone. Today `void-jchook` seeds zsh/nvim/tmux
   *before* cloning, so an unauthorized key still leaves a usable box; as a
   plain mod you'd get a workspace with none of your tools and no way out.

So `void-docker-gh` **gains two hook points** — it is not untouched, and this
plan should never have claimed it would be:

```sh
~/.paraspace/run-hook seed-shared     # before its own seeding
…                                     # guarded, so a mod's file survives
~/.paraspace/run-hook pre-clone       # everything that must precede the clone
clone || authorize_key
```

| Today | Becomes |
|---|---|
| the `skel/` tree (nvim, tmux, claude, zshrc, bin) | `mods/dotfiles-jchook/skel/` |
| seeding the shared volume | `hooks/seed-shared`, guarded both ways |
| symlinks, `chsh`, the managed Claude policy | `hooks/pre-clone` — **not** `provision`, which is after the clone and defeats the point |
| the `image-build.sh` diff (packages, Claude Code, /tmp) | `hooks/packages` |
| `commands/{claude,run}` | `mods/dotfiles-jchook/commands/` |
| the `Parafile` and `boot` diffs | nothing — they were prose differences |
| the template itself | deleted; its README content moves to the mod's repo |

Two wrinkles to settle rather than discover:

- **The gitconfig is written whole by both**, and jchook's adds an `[alias]`
  block its zsh aliases need. The fix is an `[include]` in the base's gitconfig
  plus an included file from the mod — but written **idempotently outside** the
  seed guard (`grep -q '^\[include\]' … || printf … >>`), or a volume seeded
  before the change never gets the include line and the aliases fail with
  `git: 'graph' is not a git command`.
- **`ln -sfn` onto a real `~/.claude` nests inside it.** The trigger isn't
  `image build -i` (that path is already guarded); it's a *workspace* where
  `claude` ran once and recreated `~/.claude` before the mod was added. The
  mod's hook does `[ -L ~/.claude ] || rm -rf ~/.claude` first.

**Migration check** (a one-time manual equivalence, not a test):
`para init void-docker-gh && para mod add <url>` reproduces today's
`void-jchook`. The in-repo fixture mod is what the test tiers actually run.

## Conventions are the real interface

para has no opinions, which means every opinion lives somewhere else or mods
don't compose. Two mods coexist only because their authors independently assumed
the same hook point names, shared-volume layout and package manager. None of
that is enforceable and all of it is required.

So: **`docs/conventions.md`**, a compatibility target rather than a style guide,
opening with the fact that para enforces none of it. Two audiences, one page —
project authors ("open these points if you want mods to work with you"), mod
authors ("assume only these"). The editorial test that keeps it from swallowing
the contract docs: **if para still works when you ignore it, it's a convention;
if para breaks, it's contract** and belongs in `versioning.md`/`hooks.md`.

Contents: the hook point names (`seed-shared`, `pre-clone`, `post-clone`,
`packages`), with the reference template as their executable definition; the
`$PARA_SHARED` layout; the base image; `paraspace-mod-*` repo naming; never
clobber; and the one to lead with — **compose, don't collide**: shared config
should be include-based (`zshrc.d/`, git `[include]`) so two mods add fragments
instead of fighting over a file. Without that, last-writer-wins is the entire
ecosystem.

Worth stating plainly: **conventions are more expensive to change than
contracts.** A `PARA_CONTRACT` bump has a mechanism — para refuses and says so.
Renaming `post-clone` has none; mods just stop running.

## Next: templates that declare mods

`PARA_MODS` in the `Parafile` — a space-separated list of specs the project
intends to have vendored — and `para init` runs `mod add` for each. A template
author then *references* a mod instead of copying it in, which is the dedupe
this whole plan is chasing, and `para mod update` keeps it current
independently of the template.

Two constraints: `PARA_MODS` is a **manifest, not the source of truth for what
runs** — the directory is, the way `package.json` relates to `node_modules` — so
a declared-but-missing mod is a `doctor` warning, not a behavior change. And
**para never writes to a `Parafile`**; `para config-set` was deleted in favor of
hand-editing, and resurrecting it here would be a step backward. `init` gains
`--no-mods` and prints each fetch, since it would now touch the network.

Separate PR, after the core lands.

## Settled: no ordering knob, and the name

An earlier draft gave hooks `H.d/*` fragments with `NN-` prefixes and had to
pick whether numbers were scoped or global. Scoped makes the number a lie across
mods; global makes every author guess against projects they've never seen, and
two mods that both chose `50-` are a coin flip. Named points replace both. The
resolution rule **is** the contract, so adding position semantics later reorders
existing hooks and bumps `PARA_CONTRACT`; adding named points never does.

`mod`, not `plugin` (implies an extension API para doesn't have — it never loads
one), not `pod` (para is a container tool; a workspace *is* a container, so
"pod" reads as a running thing), not `fragment` (long in the CLI, connotes a
broken-off piece). A mod **composes into** a `.paraspace/`; it never modifies
the engine.

## Docs impact

Same change, or it's drift:

- new `docs/mods.md` and `docs/conventions.md` — both need a
  `.vitepress/config.mts` sidebar entry **and** a line in `docs/README.md`, the
  router.
- `docs/hooks.md` — resolution, `run-hook` as public API, `PARA_MOD*`, the
  guest-layout table, #18's re-pointing reword. At 122 of ~150 lines, so
  authoring detail lives in `mods.md` and links back.
- `docs/commands.md` — mod commands, precedence, and the template→commands table.
- `docs/image.md` — the builder push and named build points.
- `docs/versioning.md` — the reserved names, and why executing a new path is
  still additive.
- `docs/parafile.md` — link "Your own keys" rather than re-deriving it.
- `docs/cookbook.md` — "Bring your dotfiles" and "Add a `para` verb" are the two
  recipes a mod supersedes.
- `void-jchook` is named in: `README.md` (including "three runnable templates"),
  `docs/project-setup.md` ×2, `docs/commands.md`, `docs/agents.md`,
  `docs/shared-auth.md`, `CLAUDE.md` ×2 — plus **relative links from
  `templates/void-docker-gh/README.md` and `templates/void-minimal/README.md`**,
  which ship in the tarball and would 404, and a mention in
  `void-minimal`'s `skel/zshrc`. `docs/agents.md` is the sharpest: it teaches
  `para claude`, so it must now say *mod*, not *template*.
- `plans/minimal-engine.md` says there is no third hook class. This supersedes
  that; add a row to its line-budget table, which is the repo's own stated gate
  for policy creeping back into the engine.
- `plans/init-from-git-url.md` is **stale** (it references `templates_dir`,
  `examples/`, and a `PARA_IMAGE` personalization step `cmd_init` no longer
  has). This work *builds* `is_git_spec`/`git_clone_spec`; `para init <git-url>`
  adopts them later. Use two explicit `git clone` branches rather than
  `${ref:+--branch "$ref"}`.

## Test checklist

CLI tier: `mod add` from a local path and a URL → files land, exec bits
preserved, `.git` stripped, shape check refuses a non-mod; `update` removes an
upstream-deleted file and refuses a modified tree without `--force`; `rm`/`add`
refuse a name with a path in it; `ls` shows source and `modified`; command
precedence (mod verb resolves, project verb wins, engine verb beats both) and
`para commands` still one bare name per line; `para mod` present in all four
registration sites.

e2e tier (run it — CI won't): the fixture mod through a full `up` — two points,
a command, a skel file; **`mod add` onto an already-seeded volume** (assert what
actually happens, including the half-applied case); **`mod rm` followed by
`up`** (assert the shared volume and symlinks survive, because that is the
documented behavior); `para image build` with a mod's build hook, then `image
status` after editing it → rebuild needed, which needs `PARA_TEST_REBUILD=1`
since the fixture image is cached and this would otherwise pass vacuously.

## Deferred

- Any ordering syntax. Named points instead.
- Mod dependencies, or declaring which points a mod needs. (Cheap interim: `mod
  add` prints the points the mod ships and flags any the project never mentions
  — a mod filling a point nobody opens is a silent no-op.)
- Fetch-at-`up` mods, or a lockfile. Vendoring is the model.
- Mod-contributed `Parafile` defaults — deliberately not a thing.
- `cmd_up` warning when a mod's build hooks postdate the image's stamped
  `src_sha`. "Added the mod, ran `up`, nvim isn't there" is the day-one report;
  the cheap version is a hint at the end of `mod add`.
