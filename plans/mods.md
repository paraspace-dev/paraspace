# Plan: mods — vendored, reusable `.paraspace/` components

> **Working document.** Delete it once `docs/mods.md` exists, the migration is
> adopted, and `void-jchook` is gone. Built on
> [`plans/hook-runner.md`](./hook-runner.md), which lands first.

## Goal

Let a project vendor reusable pieces of provisioning — dotfiles, a language
runtime, a CI helper — instead of forking a whole template to get them.

```sh
para mod add https://github.com/jchook/paraspace-mod-dotfiles
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

## Shape

```
project/.paraspace/
  Parafile  image-build.sh  hooks/  commands/  skel/
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

**v1 changes no template.** A mod fills `provision`, `boot` and `image-build` —
the three points para already runs — so nothing in `templates/` has to open a
named point for `dotfiles-jchook` to work. The named-point mechanism ships with
the runner and has no bundled consumer on day one, which is the honest state of
a mechanism with one user.

## `para mod add`

```
para mod add <git-url|path>    vendor a mod into .paraspace/mods/
```

That is the whole verb.

- **No `rm`** — it is `rm -rf .paraspace/mods/<name>`, and letting the tool do
  its job takes the `mod rm ''` → `rm -rf mods/` hazard with it.
- **No `ls`** — the directory is the list.
- **No `update`** — `add` always replaces, which is what `update` was. It is in
  your git history either way.
- **No `.mod-source`** — provenance belongs in the commit message that vendors
  it, not in a file para writes into someone else's mod.

Vendoring is fetch → `rm -rf "$dest"` → `cp -R "$tmp/." "$dest"`. No copy loop,
no parameterized `copy_tree`, `cmd_init` untouched.

The name is the spec's basename minus `.git`, any `#ref`, and a leading
`paraspace-mod-` — the naming convention would otherwise put the prefix in every
directory. **No name validator is needed**: a basename can't contain a slash, so
the shape does the work. One `case … .|..)` guard, the same one `cmd_init`
already has.

Load-bearing details:

- **Strip `.git`, `.gitignore`, `.gitattributes`.** `.git` or "the tree in git
  is the truth" is false and `push_project` ships the object store into every
  workspace. The other two apply to the vendored copy *inside the consumer's
  repo*: a dotfiles mod ignoring `lazy-lock.json` means `git add` silently omits
  it and a teammate runs a different mod than the author shipped.
- **A local path is copied, not cloned**, and absolutized — cloning would vendor
  the last commit while the author iterates uncommitted, and para finds the
  project by walking *up*, so cwd varies. It is also what makes `mod add`
  testable in CI without network.
- **`need git`**, plus `git -c advice.detachedHead=false clone`: `--branch <tag>`
  otherwise dumps twelve lines of detached-HEAD advice into para's output.
  `--branch` takes a branch or tag, never a sha.
- **No shape check.** A vendored tree with no `hooks/` is inert — nothing
  resolves, nothing runs — so refusing it protects against nothing.

`cmd_mod` needs `require_project`, or outside a project every path becomes
`/.paraspace/mods/<name>` and `add` fails with a raw `cp` error instead of
para's own. Register `mod` in four places or it half-exists: `main`'s dispatch,
`usage`'s PROJECT block (CLAUDE.md requires `--help` and `docs/commands.md`
share one grouping), `is_engine_verb`, and `cmd_completions`.

### What ships bundled

para's tarball ships **its own reference mods** — the components
`void-docker-gh` will decompose into — and no personal ones. The line is
maintenance, not principle: para's own building blocks are what `templates/`
already is, while bundling someone's nvim config makes para the vendor-of-record
for a tree that changes weekly against an engine that doesn't. `dotfiles-jchook`
ships as its own repo.

The repo also needs a mod under `test/fixtures/`, **committed** — see
[Tests](#test-checklist) for why it can't be vendored at test time. Without one,
`bin/lint` never lints a mod hook and no test sees the documented shape.
(Confirmed: `bin/lint`'s shebang discovery picks it up and `.shellcheckrc`
resolves its own `helpers`.)

## Image build

A mod that ships dotfiles has to reach the image, or its dotfiles reference
tools that aren't there. `.paraspace/` goes into the builder, and after the
project's payload the engine runs `"$PARA_RUN_HOOK" image-build` — the same
resolution rule as `provision`, so a mod's build steps live in
`hooks/image-build` and run after the base has created the user and upgraded
packages. No template change.

- **The tree lands in `/opt/.paraspace`, pushed `-r -p`.** Not
  `/root/.paraspace`: that is mode 0700, so `su - "$PARA_USER" -c 'cat
  $PARA_SKEL/…'` can't read it. `-p` because `/opt` may not exist on a minimal
  base.
- **Push the runner there too** and set `PARA_RUN_HOOK` in the generated env.
- **Stop piping the payload.** `cmd_image_build` pipes
  `{ para_env; cat "$payload"; }` into `bash -s`, so **the payload is stdin**,
  and the runner hands stdin to each hook. A build hook running `xbps-install`
  without `-y` swallows the rest of `image-build.sh`: the docker enable, the
  daemon wait and the overlay-driver check never run, the pipeline exits 0, and
  `image_publish` publishes the broken image that driver check exists to refuse.
  Run it by path —
  `incus exec … bash -c '. /opt/.paraspace/env; exec bash …/image-build.sh' &`
  + `wait "$!"` — which keeps the interrupt dance byte for byte. Note the `&`
  gives the async list `/dev/null` for stdin, so a build hook gets EOF, not a
  terminal: prompting is an `up`-only promise and the docs must say so.
- **`rm -rf` the builder's tree before pushing.** `incus file push -r` merges;
  `push_project` opens with this `rm -rf` for the same reason. Without it,
  `para image build -i` runs mods you deleted, because they're still in the
  image.
- **Don't bake it into the published image** — `image_publish` snapshots the
  builder's whole rootfs.
- **Reuse `guest_env`** from the runner PR, so a build hook doesn't get
  `PARA_BIN`/`PARA_PROJECT_DIR`/`PARA_CONFIG*` as host paths.

Inlined, this pushes `cmd_image_build` past 70 lines, so the builder body
extracts to `image_provision()` and `cmd_image_build` ends up below its current
55.

### Drift detection goes away

`image_src_sha`, the `user.para.src_sha` stamp and `image status`'s comparison
are **deleted**, in their own small PR. Extending them to cover mods was the
single largest source of complexity in this plan, and the signal was bad anyway:
hashing all of `.paraspace/` reports `drifted` after a comment in the `Parafile`
or an edit to a guest-only hook — most commits — and it can't be narrowed by
rule, because a var like `PARA_PREPULL_IMAGES` genuinely *is* an image input.
The per-file hash it needed also cost 2.5s on a 365-file nvim config against
0.011s batched.

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

**Mods have no `commands/` in v1.** Host-side verbs mean a resolver refactor and
a new path variable, and they exist to serve composable templates.
`dotfiles-jchook`'s `claude` and `run` stay project commands until then.

### Mods are not reversible

Deleting a mod's directory does not touch what it wrote: `$PARA_SHARED` files,
symlinks in every existing workspace, the login shell it `chsh`'d, packages
baked into the image. Nothing re-seeds them either, so a new workspace still
links the removed mod's files. `docs/mods.md` carries the manual path
(`rm $shared/zshrc; para up`).

The same asymmetry bites on add: a mod added to an already-seeded volume gets
its *new* paths and skips what the base already wrote — the mod's editor with
the base's shell, half-applied and silent. The e2e tier asserts that this is
what happens, not that it's desirable.

## Migrating `void-jchook`

| Today | Becomes |
|---|---|
| the `skel/` tree (nvim, tmux, claude, zshrc, bin) | `mods/dotfiles-jchook/skel/` |
| the provision diff (seed, symlink, `chsh`, Claude policy) | `hooks/provision`, replacing the base's seeded files once behind its own sentinel |
| the `image-build.sh` diff (packages, Claude Code) | `hooks/image-build` |
| the `[alias]` block in `$shared/gitconfig` | `/etc/gitconfig`, written by `hooks/image-build` |
| `commands/{claude,run}` | stay project commands for now |
| the `Parafile` and `boot` diffs | nothing — prose differences |
| the template itself | deleted; its README content moves to the mod's repo |

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

Two wrinkles to settle rather than discover:

- **`$BROWSER` fits no hook point** — `void-jchook` exports it so the base's
  `authorize_key` device flow sees it, and a hook can't write to its caller. The
  mod's build hook writes `/etc/profile.d/` instead.
- **`ln -sfn` onto a real `~/.claude` nests inside it.** The trigger is a
  workspace where `claude` ran once and recreated it before the mod was added.
  The mod's hook does `[ -L ~/.claude ] || rm -rf ~/.claude` first.

Known cost: mods at `provision` run after the base's, which `die`s on a failed
clone — so an unauthorized key leaves a workspace with none of your tools. It is
recoverable (fix the key, re-run) and mostly the non-interactive path, since
`authorize_key` normally prints the key and waits. A `pre-clone` point fixes it
if it turns out to annoy.

**Migration check** (a one-time manual equivalence, not a test):
`para init void-docker-gh && para mod add <url>` reproduces today's
`void-jchook`. The committed fixture mod is what the tiers actually run.

## Docs impact

- new `docs/mods.md` — needs a `.vitepress/config.mts` sidebar entry **and** a
  `docs/README.md` router line.
- `docs/commands.md` — `para mod add`, and the template→commands table.
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
- `plans/init-from-git-url.md` is **stale**; this work builds
  `is_git_spec`/`git_clone_spec` and `para init <git-url>` adopts them later.

## Test checklist

The fixture mod is **committed**, not vendored at test time: `sandbox.sh` points
`PARA_PROJECT_DIR` at the tracked `test/fixtures/hello` and teardown doesn't
cover it, so a test running `mod add` there would dirty the working tree, make
`bin/lint` lint the vendored copy, and fail on a second run.

CLI tier — `add` drives a **copied** project
(`cp -R "$FIXTURE_DIR" "$(scratch)/hello"`), no incus:

- `add` from a local path and a URL → files land, `.git`/`.gitignore` stripped,
  name derived without the `paraspace-mod-` prefix, an existing mod replaced.
- `add` outside a project fails with para's own error; `add .` and `add ..` are
  refused.
- `para mod` in all four registration sites.

e2e (run it — CI won't): the committed fixture mod through a full `up`; **a mod
added to an already-seeded volume** (assert the half-applied reality); `para
image build` with the fixture mod's `hooks/image-build` actually running.

## Deferred

- `mod ls`, `mod rm`, `mod update`, `.mod-source`, local-edit protection —
  the filesystem and git already do all of it.
- Mod `commands/` and the command resolver — with composable templates.
- `PARA_MODS`, so a template can declare the mods it wants and `para init`
  vendors them. This is what makes templates composable; it comes after
  `dotfiles-jchook` proves the seams.
- `docs/conventions.md` — the shared vocabulary mods assume (hook point names,
  `$PARA_SHARED` layout, base image, `paraspace-mod-*` naming). Worth writing at
  two or three mods, when you know what they actually collide over.
- `seed-shared`/`pre-clone` points in `void-docker-gh`, and the per-destination
  seeding guards they'd need.
- A mod declaring the `PARA_CONTRACT` it targets; mod dependencies.
- Fetch-at-`up` mods, or a lockfile. Vendoring is the model.
- Warning when a mod's build hooks postdate the image. "Added the mod, ran `up`,
  nvim isn't there" is the day-one report; drift detection is gone, so the cheap
  version is a hint at the end of `mod add`.
