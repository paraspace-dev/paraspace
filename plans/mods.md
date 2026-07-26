# Plan: mods — vendored, reusable `.paraspace/` components

> **Working document.** Delete it once `docs/mods.md` and `docs/conventions.md`
> exist, the migration is adopted, and `void-jchook` is gone. Built on
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
*references* those instead of copying them. That is sequenced after
`dotfiles-jchook` proves the seams — see
[Templates that declare mods](#next-templates-that-declare-mods).

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
      skel/{nvim,tmux,claude,zshrc}
      .mod-source
```

A mod is **a directory with the same shape as a `.paraspace/`**. That is the
whole idea, and it is why little has to be invented: `push_project` already
pushes `.paraspace/` verbatim, so a mod reaches the guest with no engine change,
`up` stays offline, review-before-you-run holds, and every mod change lands in
the project's own git history.

Hook names above are **this template's vocabulary, not para's** — see
[Conventions](#conventions-are-the-real-interface).

## `para mod`

```
para mod add <git-url|path> [--force]   vendor a mod into .paraspace/mods/
para mod ls                             what's vendored, and from where
para mod rm <name>                      delete it
```

**There is no `update`.** It would be `rm -rf` plus a fresh copy, which is what
`add --force` already is — a second spelling of one idea. `ls` prints each mod's
source so you can re-run `add`.

Vendoring is `rm -rf "$dest" && cp -R "$tmp/." "$dest"`. No copy loop, no
parameterized `copy_tree`, `cmd_init` untouched. `add` refuses an existing
directory without `--force`.

The name is the spec's basename minus `.git`, any `#ref`, and a leading
`paraspace-mod-` — the naming convention would otherwise put the prefix in every
directory and in the resolution order. It needs its own `validate_mod_name`;
`validate_name` is the *workspace* validator (31 chars, must start `a-z`, error
message says "workspace").

Load-bearing details:

- **Strip `.git`, `.gitignore`, `.gitattributes`.** `.git` or "the tree in git
  is the truth" is false and `push_project` ships the object store into every
  workspace. The other two apply to the vendored copy *inside the consumer's
  repo*: a dotfiles mod ignoring `lazy-lock.json` means `git add` silently omits
  it and a teammate runs a different mod than the author shipped.
- **Check the shape** — refuse a fetch with neither `hooks/` nor `skel/`, the
  way `para init` refuses a repo with no `.paraspace/`.
- **Validate the name before it reaches a path.** `para mod rm ''` is
  `rm -rf .paraspace/mods/`; `para mod rm ../hooks` takes the project's hooks.
- **A local path is copied, not cloned**, and absolutized — cloning would vendor
  the last commit while the author iterates uncommitted, and para finds the
  project by walking *up*, so cwd varies.
- **`need git`**, plus `git -c advice.detachedHead=false clone`: `--branch <tag>`
  otherwise dumps twelve lines of detached-HEAD advice into para's output.
  `--branch` takes a branch or tag, never a sha.

`.mod-source` holds the spec verbatim, `#ref` included, so `ls` can show it. It
is one line, written at vendor time, and nothing reads it but `ls`.

**Register `mod` in four places** or it half-exists: `main`'s dispatch, `usage`'s
PROJECT block (CLAUDE.md requires `--help` and `docs/commands.md` share one
grouping), `is_engine_verb`, and `cmd_completions`' verb list plus a `mod)` arm
completing `add|ls|rm`.

`cmd_mod` needs `require_project`, or outside a project every path becomes
`/.paraspace/mods/<name>` and `add` fails with a raw `cp` error instead of
para's own.

### What ships bundled

para's tarball ships **its own reference mods** — the components
`void-docker-gh` will decompose into — and no personal ones. The line is
maintenance, not principle: para's own building blocks are what `templates/`
already is, while bundling someone's nvim config makes para the vendor-of-record
for a tree that changes weekly against an engine that doesn't.
`dotfiles-jchook` ships as its own repo.

The repo also needs a mod under `test/fixtures/`, **committed** — see
[Tests](#test-checklist) for why it can't be vendored at test time. Without one,
`bin/lint` never lints a mod hook and no test sees the documented shape.
(Confirmed: `bin/lint`'s shebang discovery picks it up and `.shellcheckrc`
resolves its own `helpers`.)

## Image build

A mod that ships dotfiles has to reach the image or its dotfiles reference tools
that aren't there. So `.paraspace/` goes into the builder and the project's
payload opens named points — the same resolution rule as everywhere else.

- **The tree lands in `/opt/.paraspace`, pushed `-r -p`.** Not
  `/root/.paraspace`: that is mode 0700, so `su - "$PARA_USER" -c 'cat
  $PARA_SKEL/…'` — the migration's own spelling — can't read it. `-p` because
  `/opt` may not exist on a minimal base.
- **Push the runner there too** and set `PARA_RUN_HOOK` in the generated env, or
  the migrated `image-build.sh`'s first named point is an unbound variable under
  `set -u` and `para image build` fails for every project on day one.
- **Stop piping the payload.** `cmd_image_build` pipes
  `{ para_env; cat "$payload"; }` into `bash -s`, so **the payload is stdin**,
  and the runner hands stdin to each hook. A build hook running `xbps-install`
  without `-y` swallows the rest of `image-build.sh`: the docker enable, the
  daemon wait and the overlay-driver check never run, the pipeline exits 0, and
  `image_publish` publishes the broken image that driver check exists to refuse.
  Run it by path instead —
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

Inlined, this pushes `cmd_image_build` to ~72 lines, so the builder body extracts
to `image_provision()` and `cmd_image_build` ends up below its current 55.

### Drift detection goes away

`image_src_sha`, the `user.para.src_sha` stamp and `image status`'s comparison
are **deleted**, in their own small PR. Extending them to cover mods was the
single largest source of complexity in this plan and the signal was bad anyway:
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
- **Never clobber** — but see [Conventions](#conventions-are-the-real-interface):
  never-clobber and append-a-fragment are different rules for different files,
  and which applies is a property of the file.
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

Two mods that both symlink `~/.zshrc` is a conflict para will not detect: **a
hook must be idempotent and must not clobber; where the outcome depends on
order, para promises nothing and you resolve it by hand.**

**Mods have no `commands/` in v1.** Host-side verbs mean a resolver refactor and
a new path variable, and they exist to serve composable templates — which is
sequenced later. `dotfiles-jchook`'s `claude` and `run` stay project commands
until then.

### Mods are not reversible

`para mod rm` deletes the directory. It does not touch what the mod wrote:
`$PARA_SHARED` files, symlinks in every existing workspace, the login shell it
`chsh`'d, packages baked into the image. Nothing re-seeds them either, so a new
workspace still links the removed mod's files.

So `mod rm` warns and names `$PARA_SHARED`, and `docs/mods.md` carries the
manual path (`rm $shared/zshrc; para up`). The same asymmetry bites on add: a
mod added to an already-seeded volume gets its *new* paths and skips what the
base already wrote — the mod's editor with the base's shell, half-applied and
silent. The e2e tier asserts that this is what happens, not that it's desirable.

## The first PR has nothing to do with mods

`void-docker-gh` seeds the shared volume inside a one-time `$shared/.seeded`
guard. Replacing that with per-destination guards converges, and is what lets
`seed-shared` exist at all.

**It is not a bug fix, and an earlier draft claimed it was.** The sentinel does
mean a file added to `skel/` later never reaches an existing volume — but
`void-docker-gh` and `void-minimal` each seed exactly one file, so it needs a
second to bite; the only template where it occurs is `void-jchook`, which
already worked around it per-file; and templates are copy-once, so no existing
project would get the fix. The honest claim is **it fixes the shape users copy,
and it unblocks the mod work.**

Traps, all verified:

- **`[ -e dest ] || cp` is not a drop-in for `[ -f src ] && cp`.** Under
  `set -euo pipefail` the `&&` form survives a missing source (the failing test
  isn't the list's last command) while the `||` form runs `cp` on a nonexistent
  file and aborts the hook. Guard **both**:
  `if [ -f "$skel/zshrc" ] && [ ! -e "$shared/zshrc" ]; then …`
- **Retire `.seeded`** rather than keeping it. It is never removed from
  already-upgraded volumes — migration code in a copy-once file lives forever,
  so don't write any.
- **`void-minimal` and `test/fixtures/hello` carry the same sentinel.**
  `void-jchook` does too and is being **deleted**, not converted.
- **`stage "Seeding shared volume (one-time)"` becomes a lie**, and an
  unconditional header prints on every `up`. Pick deliberately.
- **This PR carries the first test of the seam.** `sandbox.sh` creates a
  run-unique volume and deletes it at teardown, so every e2e run seeds fresh and
  the sentinel and the guards are indistinguishable — both tiers pass unchanged
  on the converted tree, i.e. the change is invisible to CI. The test is
  `para sh <ws> -c 'rm /para/shared/marker'` → `para up` → assert it came back.

## Migrating `void-jchook`

A naive additive port doesn't work. Both templates ship a `skel/zshrc` and the
base seeds `$shared/zshrc` in its one-time guard, so a mod running after it can
only clobber or skip. And mods at the `provision` point run after the project's
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
| `commands/{claude,run}` | stay project commands for now |
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
  fails `git commit` with "Please tell me who you are". The base **owns** it:
  identity written create-if-absent *before* `seed-shared`, include loop *after*
  it (mods write their fragments **in** that point, so a loop running before
  picks them up only on the next `up`). Create-if-absent is essential:
  `git config --global` inside a workspace writes through the symlink, so
  regenerating every `up` would eat every alias and signing key the user set.
  Idempotence is `grep -qxF "path = $f"` — the `-x` is load-bearing, since `-qF`
  prefix-matches and a mod named `dot` would never be included alongside
  `dotfiles`. Iterate with `[ -f "$f" ] || continue`, never `cat gitconfig.d/*`.
- **A fragment must never write `[user]`.** git resolves includes at read time
  and `git config --global user.name` edits the existing section in place, so a
  fragment's `[user]` silently overrides both the base identity and the user's
  own later edit. Ordering can't prevent it; it's a conventions rule.
- **`$BROWSER` fits no hook point** — `void-jchook` exports it so the base's
  `authorize_key` device flow sees it, and a hook can't write to its caller. The
  mod's `packages` build hook writes `/etc/profile.d/`.
- **`packages` runs late and its name says early.** It must follow the base's
  `useradd` (Claude Code installs *as* `$PARA_USER`) and the base's `-Syu`, or
  it's Void's partial-upgrade footgun. Document the position where the point is
  defined.

**Migration check** (a one-time manual equivalence, not a test):
`para init void-docker-gh && para mod add <url>` reproduces today's
`void-jchook`. The committed fixture mod is what the tiers actually run.

## Conventions are the real interface

para has no opinions, so every opinion lives somewhere else or mods don't
compose. Two mods coexist only because their authors independently assumed the
same hook point names, shared-volume layout and package manager. None of that is
enforceable and all of it is required.

**`docs/conventions.md`** is a compatibility target, not a style guide, and opens
by saying para enforces none of it. Two audiences: project authors ("open these
points if you want mods to work with you"), mod authors ("assume only these").
The editorial test: **if para still works when you ignore it, it's a convention;
if para breaks, it's contract** and belongs in `versioning.md`/`hooks.md`.

Contents: the hook point names (`seed-shared`, `pre-clone`, `post-clone`,
`packages`) *and where each sits*, with the reference template as their
executable definition; the `$PARA_SHARED` layout; the base image;
`paraspace-mod-*` repo naming; and the two that must be stated together or they
read as contradictory —

- **Never clobber** a file with a single owner (`zshrc`, `tmux.conf`).
- **Append a fragment** to a file with many (`gitconfig.d/<mod>`), where the base
  owns the file and mods only ever add — and never touch `[user]`.

Which rule applies is a property of the file, and the layout says which.

**Conventions are more expensive to change than contracts.** A `PARA_CONTRACT`
bump has a mechanism — para refuses and says so. Renaming `post-clone` has none;
mods just stop running.

## Next: templates that declare mods

`PARA_MODS` in the `Parafile` — the specs a project intends to have vendored —
and `para init` runs `mod add` for each. This is what makes templates
composable: `void-docker-gh` decomposes into reference mods and *references*
them, so the duplication between templates goes the way the duplication inside
`void-jchook` does. Mod `commands/` land here too, since `key` and `web` would
travel with their mods.

`PARA_MODS` is a **manifest, not the source of truth for what runs** — the
directory is, the way `package.json` relates to `node_modules` — so a
declared-but-missing mod is a `doctor` warning, not a behavior change. And para
never writes to a `Parafile`; `config-set` was deleted in favor of hand-editing.
`init` gains `--no-mods` and prints each fetch, since it now touches the network.

Sequenced after `dotfiles-jchook` proves the seams as a single external consumer.

## Settled: no ordering knob, and the name

An earlier draft gave hooks `H.d/*` fragments with `NN-` prefixes and had to pick
whether numbers were scoped or global. Scoped makes the number a lie across mods;
global makes every author guess against projects they've never seen. Named points
replace both, and the resolution rule **is** the contract — adding position
semantics later reorders existing hooks; adding named points never does.

`mod`, not `plugin` (implies an extension API para doesn't have), not `pod` (para
is a container tool; a workspace *is* a container), not `fragment` (long in the
CLI, connotes a broken-off piece). A mod **composes into** a `.paraspace/`.

## Docs impact

- new `docs/mods.md` and `docs/conventions.md` — each needs a
  `.vitepress/config.mts` sidebar entry **and** a `docs/README.md` router line.
- `docs/commands.md` — `para mod`, and the template→commands table.
- `docs/image.md` — the builder push, named build points, no stdin in the
  builder, and drift detection being gone.
- `docs/project-setup.md` — a `mods/` row in "What's in `.paraspace/`".
- `docs/cookbook.md` — "Bring your dotfiles" is the recipe a mod supersedes.
- `docs/shared-auth.md` — one line on `$PARA_SHARED/gitconfig.d/`.
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

CLI tier — most of this belongs here so CI runs it. `add`/`rm` drive a **copied**
project (`cp -R "$FIXTURE_DIR" "$(scratch)/hello"`), no incus:

- `add` from a local path and a URL → files land, `.git`/`.gitignore` stripped,
  shape check refuses a non-mod, name derived without the `paraspace-mod-`
  prefix, an existing directory refused without `--force`.
- `rm`/`add` refuse a name with a path in it; `cmd_mod` outside a project fails
  with para's own error.
- `para mod` in all four registration sites.

e2e (run it — CI won't): the committed fixture mod through a full `up`;
**`mod add` onto an already-seeded volume** (assert the half-applied reality);
**`mod rm` then `up`** (assert the shared volume and symlinks survive);
`para image build` with a mod's build hook actually running.

## Deferred

- `mod update`, and any local-edit protection — `add --force` and `git status`.
- Mod `commands/` and the command resolver — with composable templates.
- A mod declaring the `PARA_CONTRACT` it targets.
- Mod dependencies, or declaring which points a mod needs.
- Fetch-at-`up` mods, or a lockfile. Vendoring is the model.
- Mod-contributed `Parafile` defaults — deliberately not a thing.
- Warning when a mod's build hooks postdate the image. "Added the mod, ran `up`,
  nvim isn't there" is the day-one report; drift detection is gone, so the cheap
  version is a hint at the end of `mod add`.
