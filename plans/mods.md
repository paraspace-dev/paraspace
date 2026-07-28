# Plan: mods — vendored, reusable `.paraspace/` components

> **Working document.** Delete it once `docs/mods.md` exists, the migration is
> adopted, and `void-jchook` is gone. Built on
> [`plans/hook-runner.md`](./hook-runner.md), which holds the
> [landing order](./hook-runner.md#landing-order) and the
> [contract decision](./hook-runner.md#para_contract-stays-1) for both plans.

## Goal

Vendor reusable pieces of provisioning instead of forking a template to get them.

```sh
para mod add dotfiles-jchook
para up feat-x
```

`templates/void-jchook` is the near-term case: against `void-docker-gh` it forks
`provision` (125 vs 88 lines), `boot`, `image-build.sh`, `Parafile` and
`README.md`, and every one of those diffs carries **dotfiles and the toolchain
they need**. None of it is a different *kind* of workspace, so an engine fix to
the base has to be hand-ported into the fork, and rots instead.

Longer term, **templates become composable**: `void-docker-gh` decomposes into
docker / gh-auth / ssh-key / dotfiles-base and a template *references* those.

> A template is a **starting point** — copy once, own it forever. A mod is a
> **dependency** — copy it, update it, don't edit it.

## Why the vocabulary is the product

When the engine bakes in nothing, **the conventions are the only thing anyone
shares**, and they settle by imitation. The reference templates, the hook-point
names and the shape of the first bundled mod aren't scaffolding around the
feature — they *are* its public surface, and whatever the first handful of mods
do is what the next hundred copy. That is the
[generic-mechanism boundary](../CLAUDE.md) read from the other side: the boundary
says what para must not contain, this says what it costs to keep it that way.

So precedents get set deliberately — the naming grammar, a mod layout that is
literally a `.paraspace/`, one obvious way to install one — and the opt-in
pieces stay legible, which is what `mods/<name>/` is for.

## Shape

```
project/.paraspace/
  Parafile  hooks/{provision,boot,image-build}  commands/  skel/
  mods/
    dotfiles-jchook/
      README.md
      hooks/{helpers,provision,image-build}
      skel/{nvim,tmux,claude,zshrc}
```

A mod is **a directory shaped like a `.paraspace/`**. That is why little has to
be invented: `push_project` already pushes the tree verbatim, so a mod reaches
the guest with no engine change, `up` stays offline, review-before-you-run
holds, and every mod change lands in the project's own git history.

**v1 opens no named point in any bundled template.** A mod fills `provision`,
`boot` and `image-build`; `dotfiles-jchook` needs nothing else, since seeding and
symlinking `$HOME` is order-free.

The mechanism still ships with the runner because the constraint is real and
`void-docker-gh` has one: anything that changes **how git reaches the origin** —
a credential helper, an `insteadOf` rewrite, an ssh config — has to land before
the clone, and a mod at `provision` runs after the project's *entire* provision.
The day a mod needs that, the template opens `clone:before` in one line. Opening
it now is a promise with no consumer.

The trade, for that day: **a mod that fills a named point only runs where the
point is opened.** `provision`, `boot` and `image-build` run everywhere; a mod's
README says which it fills.

## `para mod add`

```
para mod add <name>    copy a bundled mod into .paraspace/mods/
para mod add --list    the mods this para ships
```

**v1 installs bundled mods only — no URLs, no git.** It is `cmd_init`'s move
against `mods/<name>`, inheriting its `pkg_root`, its `case */*|.|..` name check
and its `--list`. Dropping the URL drops `need git`, the clone, `--depth`, `#ref`
parsing, basename-derived directory names, `.git`/`.gitignore` stripping, the
local-path branch that existed only for CI, and the empty-basename `rm -rf`
hazard that came with parsing user-supplied paths at all.

The body is `rm -rf "$dest"` → `mkdir -p "$dest"` → `cp -R "$src/." "$dest"`. The
`mkdir` is not optional: `cp` creates the last component but not `mods/` above
it, so without it the **first** `mod add` in any project fails in raw `cp`.

The other verbs stay unbuilt: **`rm`** is `rm -rf .paraspace/mods/<name>` (and
letting the tool do its job takes the `mod rm ''` hazard with it), **`ls`** is
the directory, **`update`** is what `add` already does, and **`.mod-source`**
belongs in the commit message that vendors it, not in a file para writes into
someone else's mod.

`cmd_mod` needs `require_project`, or the destination becomes
`/.paraspace/mods/<name>` and `add` fails in raw `cp` instead of para's own
error. Register `mod` in four places or it half-exists: `main`, `usage`'s PROJECT
block, `is_engine_verb`, `cmd_completions`.

### What para bundles

`mods/dotfiles-jchook/` ships beside `templates/`, and `package.json`'s `files`
gains `mods`.

An earlier draft ruled that para bundles no mods — the tarball becomes the
registry. That inverts on inspection: para *already* vendors those exact
dotfiles wrapped in a forked template, so replacing `void-jchook` with
`mods/dotfiles-jchook/` makes the tarball smaller and para's obligation
narrower. The rule earns its keep the day a *second* person wants one bundled,
which is the same day [fetching](#deferred) earns itself.

Bundling also pays for coverage: `bin/lint` lints the mod's hooks,
`.shellcheckrc` resolves its own `helpers`, and the CLI tier installs a real mod
with no network. The separate fixture mod under `test/fixtures/` still stays —
it is what the e2e tier's Alpine workspace can run, and
[why it can't be installed at test time](#test-checklist).

## Image build

**This is [PR 2](./hook-runner.md#landing-order), landing alone ahead of the
runner.** A mod that ships dotfiles has to reach the image, so the builder gets
the same two steps a workspace gets:

```sh
push_paraspace "$builder" /opt
incus exec "$builder" -- bash -c '. /opt/.paraspace/env; exec bash /opt/.paraspace/hooks/image-build' &
wait "$!"
```

`bash <path>` because `push_paraspace` has no `chmod` — and it is the form
[the runner settles on](./hook-runner.md#a-hook-is-a-process), so PR 3 rewrites
that one path to `run-hook image-build` and nothing else moves.

**`.paraspace/image-build.sh` becomes `.paraspace/hooks/image-build`.** Without
the rename there are two mechanisms from day one — a root-level payload for the
project, a hook for the mods — and every ordering question gets answered twice.
It also retires the `bash -s` stdin pipe, which is what let a build hook running
`xbps-install` without `-y` swallow the rest of the script.

`push_paraspace <instance> <dest>` is `push_project`'s first half — the `rm -rf`,
the `incus file push -r -p`, the generated `env`; `push_project` becomes that
plus `host.env` and the `chown`. The builder gets no `host.env`: it publishes
into an image. When the runner lands, `push_paraspace` is what pushes it.

- **`/opt/.paraspace`, not `/root`** — 0700 blocks the `su - "$PARA_USER" -c 'cat
  $PARA_SKEL/…'` a dotfiles build hook does. `-p`, since `/opt` may not exist.
- **`rm -rf` before the push** (`incus file push -r` merges, so `-i` would rerun
  mods you deleted) and **before `image_publish`**, which snapshots the rootfs.
- **The `&` + `wait "$!"` interrupt dance is unchanged**, and still gives the
  build `/dev/null` for stdin. Prompting is an `up`-only promise; docs must say.
- **`[ -f "$payload" ] || die` survives PR 2** pointed at the new path and
  **stays on the host** through PR 3, learning about mods. Resolution is the
  runner's business; refusing isn't — the runner's line prints inside the
  builder, minutes in, after which the build publishes and exits 0. A
  `.paraspace/` from `0.1.0` still shipping `image-build.sh` would get one line
  of scrollback and an image with no provisioning in it.

The host answers it locally, since `mods/` is a directory it already has:

```sh
have_hook() { # have_hook <name> — does any owner fill it?
  local f
  for f in "$PARA_PROJECT_DIR/.paraspace/hooks/$1" \
           "$PARA_PROJECT_DIR"/.paraspace/mods/*/hooks/"$1"; do
    if [ -f "$f" ]; then return 0; fi
  done
  return 1
}
```

`cmd_image_build` still ends up shorter than its current 55 lines.

### Drift detection goes away

`image_src_sha`, the `user.para.src_sha` stamp and `image status`'s comparison
are **deleted**, in their own small PR ahead of this one. Once the builder
consumes all of `.paraspace/`, an honest hash covers all of it — and then reports
`drifted` after a `Parafile` comment or an edit to a guest-only hook, which is
most commits. It can't be narrowed by rule either: `PARA_PREPULL_IMAGES`
genuinely *is* an image input. `image status` still reports when the image was
built and from what: a `user.para.base` stamp replaces the hash, since the base
is one fact fixed at build time rather than a signature over a tree that keeps
moving.

## What a mod may assume

Only para's contract: `$PARA_*`, `$HOME`, `$PARA_SHARED`, and its own
`$PARA_HOOKS`/`$PARA_SKEL`.

- **Not the project's `helpers`.** Template policy, not engine contract, and
  `$PARA_HOOKS/helpers` resolves to the mod's own anyway.
- **Not its position**, and not that another mod ran.
- **Not stdin past its own prompt**, and no stdin at all in the builder.
- **Not that it can write to its caller** —
  [the channels are below](#how-a-hook-reaches-a-later-hook).
- **Not that its context survives `su -`/`sudo`.**
- **Not the `Parafile`.** Mods are never sourced on the host; a mod's knobs are
  ordinary `PARA_*`, defaulted in its own hook and documented in its README.
- **Not the distro.** Build hooks are package-manager-coupled.

A mod **owns its own files**, and where it must replace one the base wrote it
does so **once, behind its own sentinel** — the base seeds, the mod replaces,
neither touches it again, and your later edits survive both. Two mods claiming
`~/.zshrc` is a conflict para will not detect.

**Mods have no `commands/` in v1 — the first thing v2 should fix.** A mod
shipping nvim, tmux and Claude Code wants to ship `para claude` with them, so
today the one piece a consumer must hand-copy is the piece they most wanted.
`project_commands`, `is_engine_verb`, `usage_project_commands` and
`cmd_completions` each resolve one directory and would take a short search path.
What has to be *decided* is the collision rule — hence [deferred](#deferred).

### A mod may open a point

A mod **may** open its own [named point](./hook-runner.md#naming-a-point), named
after the mod: `dotfiles-jchook:after`, never `dotfiles:after`. If it does, the
README lists it — that is public API.

Not a SHOULD, for the same reason [v1's templates open none](#shape): a point you
ship is a promise you keep. And it wouldn't buy the dependency it looks like it
buys — `B` filling `A:after` still needs `A` to have anticipated `B`.

- **A hook filling a point nobody opened never runs, silently**, with no
  diagnostic today.
- **Ordering between mods is [`PARA_MODS`](#deferred)'s job, not a point's.**
  Declaring the list is declaring the order, in one place, for every mod at once.

### How a hook reaches a later hook

A hook never writes to its caller, so anything a later hook must see goes through
a file, chosen by **lifetime**:

| To pass | Write | Read by | Lives as long as |
|---|---|---|---|
| "I already did this" | a sentinel beside what it guards | the same hook, next `up` | the thing it guards |
| "the tool is here" | nothing — install it on `PATH` | anyone, via `command -v` | the image |
| a variable later hooks need | an `export` line appended to `~/.paraspace/env` | every later `ws_exec` | this `up` |
| a variable every workspace's hooks need | `/etc/profile.d/<mod>.sh`, from `image-build` | bash login shells, which is what para runs hooks in | the image |
| a variable the user's shell needs | the mod's `skel/` — dotfiles | that shell, per its own rules | the volume |
| a value only this workspace knows | a file under `$HOME` | whoever needs it, when they need it | the workspace |
| a value every workspace shares | `$PARA_SHARED/<mod>/` | every workspace of the project | the volume |

Name each after the owner, write values with `%q` the way `para_env` does, and
read another mod's artifact defensively — it may not have run.

Appending to `env` needs nothing built: `push_paraspace` writes it fresh before
provision and `chown`s it, and the next `up` regenerates it so appends can't
accumulate. `docs/hooks.md` has to say so — nothing in `bin/para` does, and the
file is para's to generate and a hook's to append.

Two things that surprise people:

- **Inside one phase the environment doesn't cross; files do.** Every owner's
  `provision` runs in one `ws_exec`, sourced before the runner started, so a line
  mod A appends reaches `boot`, not mod B's `provision`. Hand off within a phase
  through a file read at the moment it's needed.
- **para owns the shell its hooks run in, not the one `para sh` gives you.**
  Hooks get `-s /bin/bash`, so `/etc/profile.d` is reliable there. `para sh` is
  whatever login shell the image set — zsh in all three templates — which reads
  dotfiles, and `/etc/profile.d` only if the distro bridges it. Configuring that
  shell is a mod's `skel/`, not para's job.

### Mods are not reversible

Adding or removing a mod does not undo what it wrote — `$PARA_SHARED` files, the
symlinks in existing workspaces, the shell it `chsh`'d, the packages in the
image. Adding one to an already-seeded volume is the same asymmetry the other
way: it gets its *new* paths and skips what the base already wrote, so you get
the mod's editor with the base's shell, half-applied and silent. `docs/mods.md`
carries the manual path (`rm $shared/zshrc; para up`); the e2e tier asserts this
is what happens, not that it's desirable.

## Migrating `void-jchook`

| Today | Becomes |
|---|---|
| the `skel/` tree (nvim, tmux, claude, zshrc, bin) | `mods/dotfiles-jchook/skel/` |
| the provision diff (seed, symlink, `chsh`, Claude policy) | `hooks/provision`, replacing the base's seeded files once behind its own sentinel |
| the `image-build.sh` diff (packages, Claude Code) | `hooks/image-build` |
| the `[alias]` block in `$shared/gitconfig` | `/etc/gitconfig`, written by `hooks/image-build` |
| `commands/{claude,run}` | stay project commands — [until mods get their own](#what-a-mod-may-assume) |
| the `Parafile` and `boot` diffs | nothing — prose differences |
| the template itself | deleted; its README becomes `mods/dotfiles-jchook/README.md` |

Everything else in that diff — `/tmp` perms, the docker group,
`PARA_PREPULL_IMAGES`, `known_hosts`, recording the clone dir — is already in the
base and moves nowhere.

**The gitconfig split is what makes this simple.** git merges system → global →
local, so aliases (static, everyone's) go in `/etc/gitconfig` at image build and
identity (per-user, mutable, written through the symlink by `git config
--global`) stays in `$shared/gitconfig`, which only the base writes. Two owners,
two lifetimes, no `[include]`, nothing that can clobber `[user]`.

Two wrinkles to settle rather than discover:

- **`ln -sfn` onto a real `~/.claude` nests inside it**, when `claude` ran once
  and recreated it before the mod was added. The hook does
  `[ -L ~/.claude ] || rm -rf ~/.claude` first.
- **A failed clone costs you the mod.** The mod runs at `provision`, after the
  base's, which `die`s if the clone fails — so an unauthorized key leaves a
  workspace with none of your tools. Recoverable, and mostly the non-interactive
  path since `authorize_key` normally prints the key and waits. This is the
  concrete price of [not opening `clone:before`](#shape) yet.

**Migration check** (a one-time manual equivalence, not a test):
`para init void-docker-gh && para mod add dotfiles-jchook` reproduces today's
`void-jchook`. If it doesn't, the mechanism is wrong.

## Docs impact

- new `docs/mods.md` — needs a `.vitepress/config.mts` sidebar entry **and** a
  `docs/README.md` router line.
- **the `image-build.sh` → `hooks/image-build` rename** is ~50 mentions across
  ~27 files (re-grep at execution time), landing with
  [PR 2](./hook-runner.md#landing-order). The ones that aren't search-and-replace:
  `docs/image.md`'s numbered build steps and the three templates' `Parafile`
  comments (both document the `bash -s` pipe), `docs/hooks.md`'s "para reads it
  on the host" line, `test/lib/sandbox.sh`'s "rebuild the fixture image if you
  touched…" rule, and `CLAUDE.md`'s lint inventory.
- `docs/commands.md` — `para mod add` and `--list` next to `para init`, and the
  template→commands table.
- `mods/dotfiles-jchook/README.md` — which hooks it fills, which base it targets,
  what it claims in `$HOME`. `cp -R` takes it along, which is the point: the copy
  in your repo documents the copy in your repo.
- `templates/` — **nothing**, since no bundled template opens a point in v1;
  `docs/hooks.md` documents the grammar with the test fixture as its example.
- `docs/image.md` — the builder push, `hooks/image-build`, no stdin in the
  builder, drift detection gone.
- `docs/project-setup.md` — a `mods/` row in "What's in `.paraspace/`".
- `docs/cookbook.md` — "Bring your dotfiles" is the recipe a mod supersedes.
- `void-jchook` is named in `README.md`, `docs/project-setup.md` ×2,
  `docs/commands.md`, `docs/agents.md`, `docs/shared-auth.md` and `CLAUDE.md` —
  plus **relative links from `templates/void-docker-gh/README.md` and
  `templates/void-minimal/README.md`**, which ship in the tarball and would 404,
  and a mention in `void-minimal`'s `skel/zshrc`. `docs/agents.md` is the
  sharpest: it teaches `para claude`, so it must say *mod*, not *template*.
- `plans/minimal-engine.md` — a budget-table row.
- `plans/init-from-git-url.md` is **untouched** now that `mod add` takes no URL;
  whichever grows a git spec first builds it and the other adopts it.

## Test checklist

The fixture mod is **committed**, not installed at test time: `sandbox.sh` points
`PARA_PROJECT_DIR` at the tracked `test/fixtures/hello` and teardown doesn't
cover it, so a test running `mod add` there would dirty the working tree, make
`bin/lint` lint the installed copy, and fail on a second run.

CLI tier — `add` drives a **copied** project
(`cp -R "$FIXTURE_DIR" "$(scratch)/hello"`), no incus:

- `add <name>` lands the bundled mod under `mods/<name>/`, including into a
  project with no `mods/` yet (the `mkdir -p`); twice replaces rather than merges.
- `--list` names what the tarball ships.
- `add` outside a project fails with para's own error; `add ../x`, `add .` and
  `add ..` are refused by the name check.
- `para mod` in all four registration sites.
- a stray file under `mods/` isn't treated as a mod — the same assert as
  [the runner's](./hook-runner.md#test-checklist), from the `add` side.
- `npm pack --dry-run` covers `mods/`, its own assert beside `libexec/` and
  `templates/`.

e2e (run it — CI won't): the committed fixture mod through a full `up`; **a mod
added to an already-seeded volume** (assert the half-applied reality); `para
image build` with the fixture mod's `hooks/image-build` actually running.

## Deferred

- `mod ls`, `mod rm`, `mod update`, `.mod-source`, local-edit protection — the
  filesystem and git already do all of it.
- **Third-party mods** — `para mod add <git-url>`, and whatever a mod author
  publishes *to*. The fetch story is where the real questions are (what a ref
  means, what gets stripped, how a consumer reviews a tree before running it),
  and none can be answered before a second person has written a mod. The install
  target is the same either way, so nothing about v1 gets undone; the eventual
  verb is `git clone` + `rm -rf .git` into a path `mod add` already owns.
- **Mod `commands/`** — the [first thing after this](#what-a-mod-may-assume), and
  the reason to keep `project_commands` easy to turn into a search path.
- **`PARA_MODS` — the designated follow-up PR.** An ordered list a template
  declares and `para init` installs: what makes templates composable, and the
  answer to [ordering between mods](#a-mod-may-open-a-point). Lands after
  `dotfiles-jchook` proves the seams.
- `docs/conventions.md` — the shared vocabulary mods assume. Only the naming
  grammar is settled here and it goes in `docs/hooks.md`; the rest
  (`$PARA_SHARED`'s layout, what a mod may own in `$HOME`) is worth a page at two
  or three mods, when you know what they actually collide over. Per
  [Why the vocabulary is the product](#why-the-vocabulary-is-the-product) it is
  the highest-leverage page in the eventual docs — just too early to write
  honestly.
- A `seed-shared` point, and the per-destination guards it would need to replace
  `void-docker-gh`'s one-time `.seeded`. A sentinel in the mod's own hook needs
  no template change and survives a volume that's been live for months.
- A mod declaring the `PARA_CONTRACT` it targets; mod dependencies.
- Fetch-at-`up` mods, or a lockfile. Vendoring is the model.
- Warning when a mod's build hooks postdate the image. "Added the mod, ran `up`,
  nvim isn't there" is the day-one report; drift detection is gone, so the cheap
  version is a hint at the end of `mod add`.
