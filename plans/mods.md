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
so a project can write one by hand and a fixture can ship one committed.

## `para mod`

```
para mod add <git-url|path> [--as <name>]   vendor a mod into .paraspace/mods/
para mod ls [--names]                       what's vendored, and from where
para mod rm <name>                          delete it
para mod update [<name>]                    re-vendor from .mod-source
```

`cmd_mod` calls **`require_project`** first, like `run_project_command` does.
Outside a project `PARA_PROJECT_DIR` is empty, so every path becomes
`/.paraspace/mods/<name>`: `add` would fail with a raw `cp` error instead of
para's own, and `rm` would report success on a no-op.

**The name** is the spec's basename, minus `.git`, any `#ref`, and a leading
`paraspace-mod-` — the ecosystem naming convention, which would otherwise put
the prefix in every directory, every `$PARA_MOD`, and the resolution order.
`--as` overrides. It needs its own `validate_mod_name`: `validate_name` is the
*workspace* validator (31 chars, must start `a-z`, and an error message that
says "workspace"), so a repo called `Dotfiles` would be refused for the wrong
reason.

**Vendoring is `rm -rf "$dest" && cp -R "$tmp/." "$dest"`.** No copy loop, no
parameterized `copy_tree`, no chmod predicate — and `cmd_init` is untouched.
`update` is the same operation, which is *why* overlaying was rejected: a
force-copy never removes a file the author deleted upstream, so a hook renamed
`provision` → `post-clone` would leave both, the stale one running forever.
Split `mod_vendor <spec> <dir>` (fetch → strip → shape check → replace → stamp)
from `cmd_mod_add` (parse, validate, report) so neither blows the ~30-line gate.

Load-bearing details:

- **Strip `.git`, `.gitignore` and `.gitattributes`.** `.git` because otherwise
  "the tree in git is the truth" is false and `push_project` ships the object
  store into every workspace. The other two because they then apply to the
  vendored copy *inside the consumer's repo*: a dotfiles mod ignoring
  `lazy-lock.json` or `*.local` means `git add .paraspace/mods/x` silently omits
  those files, the consumer commits an incomplete mod, and a teammate's
  `para up` runs a different mod than the author shipped.
- **Check the shape.** `para init` refuses a repo with no `.paraspace/`; a mod's
  repo root *is* the mod, so refuse a fetch with none of `hooks/`, `commands/`,
  `skel/`. Without it, `para mod add <any repo>` vendors an arbitrary tree that
  para pushes into every workspace and executes.
- **Validate the name before it reaches a path.** `para mod rm ''` is
  `rm -rf .paraspace/mods/`; `para mod rm ../hooks` takes the project's hooks.
- **A local path is copied, not cloned**, and resolved to absolute at add time.
  Cloning would vendor the last commit while the author is iterating
  uncommitted — "added my mod, ran `up`, my change isn't there". Absolute
  because para finds the project by walking *up*, so `update`'s cwd genuinely
  varies. That is the one exception to storing the spec verbatim.
- **`need git`**, and a `doctor_host` check: `mod add` makes git a host
  prerequisite, where para's only current use is a guarded read. `#ref` takes a
  branch or tag, not a commit sha — `git clone --branch` can't do shas.

`.mod-source` stores the spec verbatim (`#ref` included) so `update` is a
parse-free re-vendor, plus a tree hash so `ls` can print `modified` and `update`
can refuse without `--force` rather than silently eating local edits. Two things
that hash must get right: it **excludes `.mod-source` itself**, or the recorded
value can never match and every mod reports `modified` the moment it's added;
and it is `sha256_of` per file, then `sha256_of` over the `LC_ALL=C`-sorted
`<sha>  <path>` list — hashing concatenated content alone loses renames, and
concatenating paths with content is ambiguous. Worth stating what it can't see:
`find -type f` misses symlinks and modes.

A mod with no `.mod-source` is hand-written: bare `update` warns and skips it.
So is a modified one — dying mid-list would re-vendor mod 1, abort on mod 2 and
never touch mod 3, which is a partial state from a converging verb.

**A mod may declare the contract it targets**, in a named file with a stated
format. Check it in `require_project` and surface it in `doctor_project` — not
only at `add`/`update`, because the case that actually happens is *para*
upgrading while the vendored mod sits still, which add-time checking never sees.
(An earlier draft justified add-time-only by "reading it at `up` would make mods
executable on the host". That was a category error: reading a declaration isn't
executing it, and para already sources the `Parafile` on the host.)

**`para mod` must be registered in four places** or it half-exists: `main`'s
dispatch, `usage`'s PROJECT block (CLAUDE.md requires `--help` and
`docs/commands.md` share one grouping), `is_engine_verb` (or a project command
named `mod` is silently shadowed with no `doctor` warning), and
`cmd_completions` — which needs `add|ls|rm|update` at position 2 *and* vendored
names at 3, or the existing fallback offers **workspace** names for
`para mod rm <TAB>`. That is what `ls --names` is for.

### No bundled mods, one in-repo reference

para's tarball ships no mods. The reason is not "copy-once vs dependency" —
that collapses, since mods are vendored too and para's obligation also ends at
the copy. The reasons are **registry risk** (a bundled list plus an `update`
verb makes para's tarball the index) and **release cadence**: dotfiles change
weekly, para doesn't, and coupling them means either your nvim tweaks wait for a
para release or para releases carry nvim tweaks. `dotfiles-jchook` ships as its
own repo, and `para mod update` picks up its changes with no para release at all.

But the repo needs **one reference mod in-tree**, or nothing here is ever
exercised: `bin/lint` would never lint a mod hook and no test would see the
documented shape. It goes at `test/fixtures/hello/.paraspace/mods/<m>/`,
**committed** — see [Tests](#test-checklist) for why it can't be vendored at
test time — exercising two hook points, a command, a skel file, a build hook and
a `.mod-source`. (Confirmed: `bin/lint`'s shebang discovery picks it up, and
`.shellcheckrc`'s `source-path=SCRIPTDIR` resolves its own `helpers`.)

So the `helpers` copy a mod must ship lives in the *mod author's* repo and is
their problem — `test_template_helpers_do_not_drift` globs `templates/*` and
can't reach it.

## Commands

`mods/<m>/commands/<verb>` becomes `para <verb>`, run on the host like
`.paraspace/commands/`. Precedence, first match wins: **engine verb → project
command → mod command** (mods in `LC_ALL=C` order).

This needs a refactor the surface hides. `project_commands` returns bare names,
and two callers rebuild the path from `$PARA_PROJECT_DIR/.paraspace/commands/`:
`run_project_command`, and `command_summary` via `usage_project_commands`. For a
mod verb both are wrong — `--help` would `sed` a nonexistent file per mod verb
(stderr noise inside `--help`), and `run_project_command` would
`die "unknown command"` for a verb `para commands` just listed. Replace it with
**one resolver emitting paths in precedence order**; the callers consume paths,
and `usage_project_commands`' header `PROJECT COMMANDS (%s/.paraspace/commands)`
stops being a lie. `run_project_command` exports `PARA_MOD`/`PARA_MOD_DIR` when
the verb resolved to a mod — that export is the entire justification for
`PARA_MOD_DIR` existing, so it lands with the resolver or not at all.

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

- **Push the runner into the builder too**, `--mode 0755`, and set
  `PARA_RUN_HOOK` in the generated env. Without both, the migrated
  `image-build.sh`'s first named point is an unbound variable under `set -u` and
  `para image build` fails for every project on day one. The builder's value
  differs from the workspace's, which is the concrete reason the variable exists
  rather than a literal path.
- **Stop piping the payload.** `cmd_image_build` pipes
  `{ para_env; cat "$payload"; }` into `bash -s`, so **the payload is stdin** —
  and the runner deliberately hands stdin to each hook. A build hook that runs
  `xbps-install` without `-y`, or any `read`, swallows the rest of
  `image-build.sh`: the docker enable, the daemon wait and the overlay-driver
  check never run, the pipeline exits 0, and `image_publish` publishes exactly
  the broken image that driver check exists to refuse. Silently. Since the tree
  is now *in* the builder, run it by path: push a generated env, then
  `incus exec … bash -c '. …/env; exec bash …/image-build.sh' &` + `wait "$!"`.
  The interrupt dance survives byte for byte, and payload and hooks each get a
  clean stdin.
- **`rm -rf` the builder's tree before pushing.** `incus file push -r` merges;
  it never deletes. `push_project` opens with exactly this `rm -rf` for exactly
  this reason. Without it, `para image build -i` — which relaunches from
  `$PARA_IMAGE` — runs mods you deleted, because they're still in the image.
- **Don't bake `.paraspace/` into the published image.** `image_publish`
  snapshots the builder's whole rootfs, so `rm -rf` the tree before it or every
  published image carries project source and a pinned copy of para's runner.
- **Correct the builder's env the way `push_project` corrects the guest's** —
  the same set, named once rather than enumerated here so it can't drift. Raw
  `para_env` hands a build hook `PARA_BIN`, `PARA_PROJECT_DIR`, `PARA_CONFIG*`
  and `PARA_STATE_DIR` as *host* paths, so a mod hook that works at `packages`
  would die at `provision`.

Exec bits need no work here: the runner repairs them, which is why that moved
into the runner in the first place.

**`image_src_sha` must cover the mods**, and hashing content alone is not
enough: deleting one hook and creating another with the same bytes yields an
identical hash for a genuinely different image. Reuse the mod tree hash — per
file, then over the sorted `<sha>  <path>` list — across the whole of
`.paraspace/` rather than enumerating what the builder can reach, since build
hooks now see `$PARA_SKEL` and the project's `skel/` is an image input too.
Over-broad is the right failure direction: a spurious rebuild beats a stale
image reported as current. It must not break the *no-mods* case — an unmatched
glob handed to `cat` exits non-zero and `pipefail` turns that into "the image
inputs could not be hashed" for the majority of projects. And it flips every
already-published image to `drifted` once, including every developer's cached
fixture image: one line in `docs/image.md` beats the support question.

## What a mod may assume

Only para's contract: `$PARA_*`, `$HOME`, `$PARA_SHARED`, and its own
`$PARA_HOOKS`/`$PARA_SKEL`/`$PARA_MOD_DIR`.

- **Not the project's `helpers`.** Template policy, not engine contract, and
  `$PARA_HOOKS/helpers` resolves to the mod's own anyway — so a mod ships one.
  (Promoting `helpers` into the engine would make para own log formatting.)
- **Never clobber** — but see [Conventions](#conventions-are-the-real-interface):
  never-clobber and append-a-fragment are different rules for different files,
  and which one applies is a property of the file, not of mods in general.
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
reseed story is the answer, and the e2e test asserts that this is what happens,
not that it is desirable.

## The first PR has nothing to do with mods

`void-docker-gh` seeds the shared volume inside a one-time `$shared/.seeded`
guard. That has a live bug today: **a file added to `skel/` after the first `up`
never reaches an existing shared volume.** Replacing the sentinel with per-file
guards fixes it, converges, and removes the migration's hardest blocker — with
no engine change, no #18 and no mods.

Three traps in that edit:

- **`[ -e dest ] || cp` is not a drop-in for `[ -f src ] && cp`.** Under
  `set -euo pipefail` they differ: with the source missing, the `&&` form's
  failing test isn't the last command of the list and survives, while the `||`
  form runs `cp` on a nonexistent file and aborts the hook. A project that
  deleted `skel/zshrc` works today and would stop. Guard **both**:
  `if [ -f "$skel/zshrc" ] && [ ! -e "$shared/zshrc" ]; then …`
- **Retire `.seeded` rather than keeping it.** With per-destination guards it is
  strictly less precise, and keeping it breaks the gitconfig fix below on every
  pre-existing volume.
- **`void-minimal` and `test/fixtures/hello` carry the same sentinel.** The
  fixture is what the e2e tier actually runs, and `void-minimal` is the file
  readers are pointed at to copy the seeding block from. Convert all three.

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
| the `Parafile` and `boot` diffs | nothing — they were prose differences |
| the template itself | deleted; its README content moves to the mod's repo |

Everything else in that diff — `/tmp` perms, the docker group,
`PARA_PREPULL_IMAGES`, `known_hosts`, recording the clone dir — is already in
the base and moves nowhere.

Four wrinkles to settle rather than discover:

- **`$shared/gitconfig` needs an owner, and first-writer-wins is the wrong rule
  for it.** git has no include-*directory*, so composing means each mod appends
  its own `[include] path =` line — which means the first mod to run *creates*
  the file, the base's guarded write then skips, and `[user] name/email` is
  never written. Every workspace fails `git commit` with "Please tell me who you
  are". So: **the base owns `$shared/gitconfig`**, writes it idempotently
  *before* `seed-shared`, mods write only `$shared/gitconfig.d/<mod>`, and the
  base emits one include line per file it finds there.
- **`$BROWSER` fits no hook point.** `void-jchook` exports it so the base's
  `authorize_key` device flow sees it — and a `pre-clone` hook is a separate
  process that cannot export into its caller. The interactive path is already
  covered by the mod's own zshrc; the non-interactive one isn't. Cleanest fix
  inside the boundary: the mod's `packages` build hook writes
  `/etc/profile.d/`.
- **`packages` runs late, and its name suggests early.** It must come after the
  base's `useradd` (Claude Code installs *as* `$PARA_USER`) and after the base's
  `-Syu` full upgrade, or it is Void's partial-upgrade footgun that the base's
  own comment warns about. The position is the contract; document it where the
  point is defined.
- **`ln -sfn` onto a real `~/.claude` nests inside it.** The trigger isn't
  `image build -i` (already guarded); it's a *workspace* where `claude` ran once
  and recreated `~/.claude` before the mod was added. The mod's hook does
  `[ -L ~/.claude ] || rm -rf ~/.claude` first.

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
if para breaks, it's contract** and belongs in `versioning.md`/`run-hook.md`.

Contents: the hook point names (`seed-shared`, `pre-clone`, `post-clone`,
`packages`) *and where each sits*, with the reference template as their
executable definition; the `$PARA_SHARED` layout; the base image;
`paraspace-mod-*` repo naming; and the two that have to be stated together or
they read as contradictory —

- **Never clobber** a file with a single owner (`zshrc`, `tmux.conf`).
- **Append a fragment** to a file with many (`gitconfig.d/<mod>`,
  `zshrc.d/<mod>`), where the owner is the base and mods only ever add.

Which rule applies is a property of the file, and the layout says which. Without
that distinction the gitconfig failure above is the whole ecosystem's default.

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
`cmd_init`'s `chmod` case has the same `.paraspace/hooks/*` blind spot the copy
loop had, so it needs widening when this lands.

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
- `docs/commands.md` — mod commands, precedence, and the template→commands table.
- `docs/image.md` — the builder push, named build points, and the one-time
  `drifted` cliff.
- `docs/versioning.md` — the reserved names, and why executing a new path is
  still additive.
- `docs/project-setup.md` — a `mods/` row in "What's in `.paraspace/`", the page
  a new user reads first.
- `docs/parafile.md` — link "Your own vars" rather than re-deriving it.
- `docs/cookbook.md` — "Bring your dotfiles" and "Add a `para` verb" are the two
  recipes a mod supersedes.
- `void-jchook` is named in: `README.md` (including "three runnable templates"),
  `docs/project-setup.md` ×2, `docs/commands.md`, `docs/agents.md`,
  `docs/shared-auth.md`, `CLAUDE.md` ×2 — plus **relative links from
  `templates/void-docker-gh/README.md` and `templates/void-minimal/README.md`**,
  which ship in the tarball and would 404, and a mention in `void-minimal`'s
  `skel/zshrc`. `docs/agents.md` is the sharpest: it teaches `para claude`, so it
  must now say *mod*, not *template*.
- `plans/minimal-engine.md` says there is no third hook class. This supersedes
  that; add a row to its line-budget table, which is the repo's own stated gate
  for policy creeping back into the engine.
- `plans/init-from-git-url.md` is **stale** (it references `templates_dir`,
  `examples/`, and a `PARA_IMAGE` personalization step `cmd_init` no longer
  has). This work *builds* `is_git_spec`/`git_clone_spec`; `para init <git-url>`
  adopts them later. Use two explicit `git clone` branches rather than
  `${ref:+--branch "$ref"}`.

## Test checklist

The fixture mod is **committed**, not vendored at test time. `sandbox.sh` points
`PARA_PROJECT_DIR` at the in-repo `test/fixtures/hello` and teardown doesn't
cover it, so a test that ran `mod add` there would dirty the working tree, make
`bin/lint` lint the vendored copy as well as the source, and fail on the second
run with "already vendored" — order-independence and re-runnability both gone.

CLI tier — and most of this belongs here, so CI actually runs it. `add`/`rm`/
`update` drive a **copied** project (`cp -R "$FIXTURE_DIR" "$(scratch)/hello"`),
which needs no incus:

- `mod add` from a local path and a URL → files land, exec bits preserved,
  `.git`/`.gitignore` stripped, shape check refuses a non-mod, name derived
  without the `paraspace-mod-` prefix, `--as` overrides.
- `update` removes an upstream-deleted file; refuses a modified tree without
  `--force`; warns and skips a hand-written mod and a modified one in a bare
  `update` rather than dying mid-list.
- a freshly added mod does **not** report `modified` (the `.mod-source`
  self-reference).
- `rm`/`add` refuse a name with a path in it; `cmd_mod` outside a project fails
  with para's own error.
- command precedence (mod verb resolves, project verb wins, engine verb beats
  both), `para commands` still one bare name per line, `PARA_MOD_DIR` exported
  to a mod's command.
- `para mod` present in all four registration sites, including
  `para mod rm <TAB>` offering mod names rather than workspaces.

e2e tier (run it — CI won't): the committed fixture mod through a full `up` —
two points, a command, a skel file; **`mod add` onto an already-seeded volume**
(assert the half-applied reality); **`mod rm` followed by `up`** (assert the
shared volume and symlinks survive, because that is the documented behavior);
`para image build` with a mod's build hook, then `image status` after editing it
→ rebuild needed, which needs `PARA_TEST_REBUILD=1` since the fixture image is
cached and this would otherwise pass vacuously.

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
