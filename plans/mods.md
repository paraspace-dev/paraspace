# Plan: mods — vendored, reusable `.paraspace/` components

> **Working document.** Delete it once `docs/mods.md` exists, the migration is
> adopted, and `void-jchook` is gone. Built on
> [`plans/hook-runner.md`](./hook-runner.md), which also holds the
> [landing order](./hook-runner.md#landing-order) and the
> [contract decision](./hook-runner.md#para_contract-stays-1) for both plans.

## Goal

Let a project vendor reusable pieces of provisioning — dotfiles, a language
runtime, a CI helper — instead of forking a whole template to get them.

```sh
para mod add dotfiles-jchook
para up feat-x
```

The near-term case is `templates/void-jchook`: against `void-docker-gh` it forks
`provision` (125 vs 88 lines), `boot`, `image-build.sh`, `Parafile` and
`README.md`, and every one of those diffs carries **dotfiles and the toolchain
they need**. None of it is a different *kind* of workspace, so an engine fix to
the base has to be hand-ported into the fork. It rots instead.

The longer-term case is bigger: **templates become composable**. `void-docker-gh`
decomposes into docker / gh-auth / ssh-key / dotfiles-base and a template
*references* those instead of copying them — sequenced after `dotfiles-jchook`
proves the seams.

A template is a **starting point** — copy once, own it forever. A mod is a
**dependency** — copy it, update it, don't edit it.

## Why the vocabulary is the product

para is a thin wrapper over incus, Caddy and a project's own `.paraspace/`
scripts. It has no opinion about the distro, the packages, the toolchain, or
what "provisioned" even means — the project's config decides all of it, down to
whether the workspace is Void or Debian. That is the design.

It is also the bill. When the engine bakes in nothing, **the conventions are the
only thing anyone shares**, and they settle by imitation rather than by decree.
So the reference templates, the hook-point names and the shape of the first
bundled mod are not scaffolding around the feature — they *are* its public
surface, and whatever the first handful of mods do is what the next hundred copy.
This is the [generic-mechanism boundary](../CLAUDE.md) read from the other side:
the boundary says what para must not contain, this says what it costs to keep it
that way.

Two things follow for this plan. Precedents get set deliberately — a naming
grammar ([`<subject>:<when>`](./hook-runner.md#naming-a-point)), a mod layout
that is literally a `.paraspace/`, one obvious way to install one. And the
opt-in pieces have to be legible: a reader should be able to tell from a
project's `.paraspace/` which parts are para's, which are the template's, and
which came from someone else — which is what `mods/<name>/` is for.

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

A mod is **a directory with the same shape as a `.paraspace/`**. That is the
whole idea, and it is why little has to be invented: `push_project` already
pushes `.paraspace/` verbatim, so a mod reaches the guest with no engine change,
`up` stays offline, review-before-you-run holds, and every mod change lands in
the project's own git history.

**v1 opens no named point in any bundled template.** A mod fills `provision`,
`boot` and `image-build` — the three para already runs — and `dotfiles-jchook`,
the only mod this plan builds, needs nothing else: seeding and symlinking `$HOME`
is order-free.

The mechanism still ships with the runner, because the constraint behind it is
real and `void-docker-gh` has one: anything that changes **how git reaches the
origin** — a credential helper, an `insteadOf` rewrite to an internal mirror, an
ssh config — has to land before the clone, and a mod at `provision` runs after
the project's *entire* provision. The day a mod needs that, the template opens
`clone:before` in one line. Opening it now is a promise with no consumer, and a
named point in a shipped template is a promise you keep.

The trade, for that day: **a mod that fills a named point only runs where the
point is opened.** `provision`, `boot` and `image-build` run everywhere. A mod's
README says which it fills.

## `para mod add`

```
para mod add <name>    copy a bundled mod into .paraspace/mods/
para mod add --list    the mods this para ships
```

**v1 installs bundled mods only — no URLs, no git.** `para init` already copies a
bundled `templates/<name>` into your project; this is the same move against a
bundled `mods/<name>`, and it inherits `cmd_init`'s `pkg_root`, its
`case */*|.|..` name check and its `--list`.

That is not a smaller version of the git verb, it is a different and much smaller
verb. Gone with the URL: `need git`, the clone, `--depth`, `#ref` parsing,
`advice.detachedHead`, deriving a directory name from a basename, stripping
`.git`/`.gitignore`/`.gitattributes`, the local-path branch that existed only so
CI could test without network, and the empty-basename `rm -rf` hazard that came
with parsing user-supplied paths at all. A bundled name is a plain directory
name; the shape does the work, which is the rule this repo already follows.

The body is `rm -rf "$dest"` → `mkdir -p "$dest"` → `cp -R "$src/." "$dest"`. The
`mkdir` is not optional: `cp` creates the last component but not `mods/` above
it, so without it the **first** `mod add` in any project fails with a raw `cp:
cannot create directory … No such file or directory`.

The other three verbs stay unbuilt:

- **No `rm`** — it is `rm -rf .paraspace/mods/<name>`, and letting the tool do
  its job takes the `mod rm ''` → `rm -rf mods/` hazard with it.
- **No `ls`** — the directory is the list, and `--list` answers the other
  question.
- **No `update`** — `add` always replaces, which is what `update` was. It is in
  your git history either way.
- **No `.mod-source`** — provenance belongs in the commit message that vendors
  it, not in a file para writes into someone else's mod.

`cmd_mod` needs `require_project`, or outside a project the destination becomes
`/.paraspace/mods/<name>` and `add` fails with a raw `cp` error instead of
para's own. Register `mod` in four places or it half-exists: `main`'s dispatch,
`usage`'s PROJECT block (CLAUDE.md requires `--help` and `docs/commands.md`
share one grouping), `is_engine_verb`, and `cmd_completions`.

### What para bundles

`mods/dotfiles-jchook/` ships in the tarball beside `templates/`, and
`package.json`'s `files` gains `mods`.

An earlier draft ruled that **para bundles no mods** — its tarball would become
the registry, and para the vendor-of-record for one person's nvim config against
an engine that changes far more slowly. That reasoning inverts on inspection:
para *already* vendors those exact dotfiles, wrapped in a whole forked template.
Replacing `templates/void-jchook` with `mods/dotfiles-jchook/` makes the tarball
smaller and para's obligation narrower — the same files, minus a duplicated
`provision`, `boot`, `Parafile` and `image-build`. The rule earns its keep the
day a *second* person wants one bundled, which is the same day
[fetching](#deferred) earns itself.

Bundling also pays for coverage: `bin/lint`'s shebang discovery lints the mod's
hooks, `.shellcheckrc` resolves its own `helpers`, and the CLI tier installs a
real mod with no network and no fixture of its own. The separate fixture mod
under `test/fixtures/` still stays — it is what the e2e tier's Alpine workspace
can actually run, and [why it can't be installed at test time](#test-checklist).

## Image build

**This is [PR 2](./hook-runner.md#landing-order): it lands alone, ahead of the
runner.** A mod that ships dotfiles has to reach the image, or its dotfiles
reference tools that aren't there. So the builder gets the same two steps a
workspace gets — push the tree, run the name:

```sh
push_paraspace "$builder" /opt
incus exec "$builder" -- bash -c '. /opt/.paraspace/env; exec bash /opt/.paraspace/hooks/image-build' &
wait "$!"
```

`bash <path>`, not the path alone: `push_paraspace` has no `chmod`, and the
runner sources hooks anyway, so the exec bit never becomes load-bearing in the
builder. PR 3 rewrites that one path to `/opt/.paraspace/run-hook image-build`
and nothing else here moves.

**`.paraspace/image-build.sh` becomes `.paraspace/hooks/image-build`.** Without
the rename there are two mechanisms from day one — a root-level payload for the
project, a hook for the mods — and every question about ordering has to be
answered twice. With it there is one rule everywhere: a hook name resolves to the
project's, then each mod's. It is a contract change that [stays at contract
1](./hook-runner.md#para_contract-stays-1) — one consumer, migrated by hand — and
it retires the `bash -s` stdin pipe, which is what made a build hook running
`xbps-install` without `-y` able to swallow the rest of the script.

`push_paraspace <instance> <dest>` is `push_project`'s first half — the `rm -rf`,
the `incus file push -r -p`, the generated `env` — and `push_project` becomes
that plus `host.env` and the `chown`. The builder gets no `host.env`: it
publishes into an image. When the runner lands, **`push_paraspace` is what pushes
it**, not `push_project` — the builder execs its copy too.

- **`/opt/.paraspace`, not `/root`** — 0700 blocks `su - "$PARA_USER" -c 'cat
  $PARA_SKEL/…'`, which is exactly what a dotfiles build hook does. `-p` because
  `/opt` may not exist on a minimal base.
- **`rm -rf` before the push**, because `incus file push -r` merges — otherwise
  `para image build -i` runs mods you deleted, still sitting in the image.
- **`rm -rf` before `image_publish`**, which snapshots the builder's whole
  rootfs.
- **The `&` + `wait "$!"` interrupt dance is unchanged**, and still gives the
  build `/dev/null` for stdin. Prompting is an `up`-only promise; the docs must
  say so.
- **`[ -f "$payload" ] || die` survives PR 2** pointed at the new path, and goes
  away with the runner: whether any owner has an `image-build` hook is the
  runner's business, not the host's. What replaces it is [the runner's `no 'X'
  hook` line](./hook-runner.md#the-runner) — which matters more than it looks,
  because the contract does not bump, so nothing refuses a project that still
  ships `image-build.sh`. Silence there is a published image with no
  provisioning in it.

`cmd_image_build` ends up shorter than its current 55 lines, so nothing needs
extracting from it.

### Drift detection goes away

`image_src_sha`, the `user.para.src_sha` stamp and `image status`'s comparison
are **deleted**, in their own small PR ahead of this one. Once the builder
consumes all of `.paraspace/`, an honest hash has to cover all of it — and then
it reports `drifted` after a comment in the `Parafile` or an edit to a
guest-only hook, which is most commits. It can't be narrowed by rule either: a
var like `PARA_PREPULL_IMAGES` genuinely *is* an image input.

`image status` still reports when the image was built and from what. If you
rebuild too rarely you find out because your tool isn't there.

## What a mod may assume

Only para's contract: `$PARA_*`, `$HOME`, `$PARA_SHARED`, and its own
`$PARA_HOOKS`/`$PARA_SKEL`.

- **Not the project's `helpers`.** Template policy, not engine contract, and
  `$PARA_HOOKS/helpers` resolves to the mod's own anyway. (Promoting `helpers`
  into the engine would make para own log formatting.)
- **Not its position**, and not that another mod ran.
- **Not stdin past its own prompt**, and no stdin at all in the builder.
- **Not that it can write to its caller.** A hook reads its environment and
  writes to the filesystem. Anything the rest of the workspace must see goes in
  the image (`/etc/profile.d`) or on the filesystem.
- **Not that its context survives `su -`/`sudo`.**
- **Not the `Parafile`.** Mods are never sourced on the host. A mod's knobs are
  ordinary `PARA_*`, defaulted in its own hook and documented in its README.
- **Not the distro.** Build hooks are package-manager-coupled; the README says
  which base it targets.

A mod **owns its own files**, and where it must replace one the base wrote, it
does so **once, behind its own sentinel** — so the base seeds, the mod replaces,
and neither touches it again. Your later edits survive both. Two mods that both
claim `~/.zshrc` is a conflict para will not detect: a hook must be idempotent,
and where the outcome depends on order para promises nothing.

**Mods have no `commands/` in v1 — and that is the first thing v2 should fix.**
A mod that ships nvim, tmux and Claude Code wants to ship `para claude` with
them; today `dotfiles-jchook`'s `claude` and `run` have to stay *project*
commands, so the one piece a consumer must hand-copy is the piece they most
wanted. Nothing about it is conceptually hard — `project_commands`,
`is_engine_verb`, `usage_project_commands` and `cmd_completions` each resolve one
directory, and mods turn that into a short search path. What has to be decided
rather than discovered is the collision rule (the project's verb wins, and
`para doctor` says when two mods claim one name), which is why it is
[deferred](#deferred) rather than bolted on here.

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
`PARA_PREPULL_IMAGES`, `known_hosts`, recording the clone dir — is already in
the base and moves nowhere.

**The gitconfig split is the shape that makes this simple.** git reads system →
global → local and merges them, so aliases (static, everyone's) go in
`/etc/gitconfig` at image build, and identity (per-user, mutable, and written
through the symlink by `git config --global`) stays in `$shared/gitconfig`,
which only the base writes. Two owners, two lifetimes, no `[include]`, no
`gitconfig.d/`, no ordering constraint, and nothing that can clobber `[user]`.
An earlier draft had all of that machinery because both wanted the same file.

Three wrinkles to settle rather than discover:

- **`$BROWSER` fits no hook point** — `void-jchook` exports it so the base's
  `authorize_key` device flow sees it, and a hook can't write to its caller. The
  mod's build hook writes `/etc/profile.d/` instead.
- **`ln -sfn` onto a real `~/.claude` nests inside it.** The trigger is a
  workspace where `claude` ran once and recreated it before the mod was added.
  The mod's hook does `[ -L ~/.claude ] || rm -rf ~/.claude` first.
- **A failed clone costs you the mod.** The mod runs at `provision`, after the
  base's, which `die`s if the clone fails — so an unauthorized key leaves a
  workspace with none of your tools. Recoverable (fix the key, re-run) and mostly
  the non-interactive path, since `authorize_key` normally prints the key and
  waits. This is the concrete price of [not opening `clone:before`](#shape) yet,
  and the thing to watch for whether it earns the point.

**Migration check** (a one-time manual equivalence, not a test):
`para init void-docker-gh && para mod add dotfiles-jchook` reproduces today's
`void-jchook`. If it doesn't, the mechanism is wrong.

## Docs impact

- new `docs/mods.md` — needs a `.vitepress/config.mts` sidebar entry **and** a
  `docs/README.md` router line.
- **the `image-build.sh` → `hooks/image-build` rename** is 44 mentions across 21
  files, and lands with [PR 2](./hook-runner.md#landing-order) rather than here.
  The ones that are not a search-and-replace: `docs/image.md`'s numbered build
  steps (it documents the `bash -s` pipe), the three templates' `Parafile`
  comments (same), `docs/hooks.md`'s "para reads it on the host" line,
  `test/README.md` and `test/lib/sandbox.sh`'s "rebuild the fixture image if you
  touched…" rule, and `CLAUDE.md`'s lint inventory.
- `docs/commands.md` — `para mod add` and `--list`, next to `para init`, which
  they mirror; and the template→commands table.
- `mods/dotfiles-jchook/README.md` — the mod's own page, the way each template
  has one. It says which hooks it fills, which base it targets, and what it
  claims in `$HOME`. It does **not** ship into a consumer's `.paraspace/`
  unread — `cp -R` takes it along, which is the point: the copy in your repo is
  the documentation for the copy in your repo.
- `templates/` — **nothing.** No bundled template opens a named point in v1, so
  `docs/hooks.md` documents the grammar with the [test fixture](#test-checklist)
  as its worked example.
- `docs/image.md` — the builder push, `hooks/image-build`, no stdin in the
  builder, and drift detection being gone.
- `docs/project-setup.md` — a `mods/` row in "What's in `.paraspace/`".
- `docs/cookbook.md` — "Bring your dotfiles" is the recipe a mod supersedes.
- `void-jchook` is named in `README.md` ("three runnable templates"),
  `docs/project-setup.md` ×2, `docs/commands.md`, `docs/agents.md`,
  `docs/shared-auth.md`, `CLAUDE.md` ×2 — plus **relative links from
  `templates/void-docker-gh/README.md` and `templates/void-minimal/README.md`**,
  which ship in the tarball and would 404, and a mention in `void-minimal`'s
  `skel/zshrc`. `docs/agents.md` is the sharpest: it teaches `para claude`, so it
  must say *mod*, not *template*.
- `plans/minimal-engine.md` — a budget-table row.
- `plans/init-from-git-url.md` is **untouched** by this work now that `mod add`
  takes no URL — whichever of the two grows a git spec first builds it, and the
  other adopts it.

## Test checklist

The fixture mod is **committed**, not installed at test time: `sandbox.sh` points
`PARA_PROJECT_DIR` at the tracked `test/fixtures/hello` and teardown doesn't
cover it, so a test running `mod add` there would dirty the working tree, make
`bin/lint` lint the installed copy, and fail on a second run.

CLI tier — `add` drives a **copied** project
(`cp -R "$FIXTURE_DIR" "$(scratch)/hello"`), no incus:

- `add <name>` → the bundled mod's files land under `mods/<name>/`, including
  into a project with no `mods/` yet (the `mkdir -p`), and running it twice
  replaces rather than merges.
- `--list` names what the tarball ships.
- `add` outside a project fails with para's own error; `add ../x`, `add .` and
  `add ..` are refused by `cmd_init`'s name check.
- `para mod` in all four registration sites.
- `npm pack --dry-run` covers `mods/`.

e2e (run it — CI won't): the committed fixture mod through a full `up`; **a mod
added to an already-seeded volume** (assert the half-applied reality); `para
image build` with the fixture mod's `hooks/image-build` actually running.

## Deferred

- `mod ls`, `mod rm`, `mod update`, `.mod-source`, local-edit protection —
  the filesystem and git already do all of it.
- **Third-party mods** — `para mod add <git-url>`, and whatever a mod author
  publishes *to*. v1 is bundled-only on purpose: the fetch story is the part with
  real questions in it (what a ref means, what gets stripped, how a consumer
  reviews a tree before running it, whether a `paraspace-mod-*` naming
  convention is worth enforcing), and none of them can be answered honestly
  before a second person has written a mod. The install target — a plain
  directory under `mods/`, committed to the consumer's repo — is the same either
  way, so nothing about v1 has to be undone to get there. Note the shape of the
  eventual verb is `git clone` + `rm -rf .git` into a path `mod add` already
  owns.
- **Mod `commands/`** — the [first thing after this](#what-a-mod-may-assume),
  and the reason to keep `project_commands` easy to turn into a search path.
- `PARA_MODS`, so a template can declare the mods it wants and `para init`
  installs them. This is what makes templates composable; it comes after
  `dotfiles-jchook` proves the seams.
- `docs/conventions.md` — the shared vocabulary mods assume. Only the
  [`<subject>:<when>`](./hook-runner.md#naming-a-point) grammar is settled here,
  and it goes in `docs/hooks.md`; the rest (`$PARA_SHARED`'s layout, which
  base a mod targets, what a mod may own in `$HOME`) is worth a page of its own
  at two or three mods, when you know what they actually collide over. Per
  [Why the vocabulary is the product](#why-the-vocabulary-is-the-product) this is
  the highest-leverage page in the eventual docs — it is just too early to write
  it honestly.
- A `seed-shared` point, and the per-destination guards it would need to replace
  `void-docker-gh`'s one-time `.seeded`. A mod that must replace a base-seeded
  file does it once behind its own sentinel instead, which needs no template
  change and survives a volume that's been live for months.
- A mod declaring the `PARA_CONTRACT` it targets; mod dependencies.
- Fetch-at-`up` mods, or a lockfile. Vendoring is the model.
- Warning when a mod's build hooks postdate the image. "Added the mod, ran `up`,
  nvim isn't there" is the day-one report; drift detection is gone, so the cheap
  version is a hint at the end of `mod add`.
