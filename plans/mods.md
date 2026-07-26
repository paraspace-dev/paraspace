# Plan: mods — vendored, reusable `.paraspace/` components

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
toolchain they need** (zsh/tmux/nvim/Claude Code). None of it is a different
*kind* of workspace. Today an engine-level fix to the base template has to be
hand-ported into the fork; the fork silently rots instead.

A template is a **starting point** — copy once, own it forever. A mod is a
**dependency** — copy it, update it, don't edit it. `void-jchook` wants to be
the second thing.

## Shape

```
project/.paraspace/
  Parafile
  image-build.sh
  hooks/{provision,boot,helpers}
  commands/{key,web}
  skel/zshrc
  mods/
    dotfiles-jchook/
      README.md
      hooks/{helpers,seed-shared,provision,packages}
      commands/{claude,run}
      skel/{nvim,tmux,claude,zshrc}
      .mod-source
```

A mod is **a directory with the same shape as a `.paraspace/`** — that is the
whole idea, and it is why almost nothing new has to be invented below.

**Mods are vendored** — copied in at `mod add` time and checked into the
project's repo, not fetched at `up` time. That falls out of what para already
does: `push_project` pushes `.paraspace/` verbatim into the guest, so a mod
reaches the workspace with no engine change at all. It also keeps `para up`
offline, keeps the trust model ("review the hooks you're about to run") intact,
and puts every mod change in the project's own git history.

`para mod add` is a convenience, not a requirement: a mod is just a directory,
so a project can write one by hand and a test fixture can ship one inline.

## The one new rule: a hook name resolves to a list

Today `run_hook provision` runs one file. It runs **the project's, then one per
mod**:

```
hooks/provision                    # the project's own
mods/<m>/hooks/provision           # each mod's, mods in LC_ALL=C directory order
```

One file per hook name per mod. Nothing else — no `provision.d/`, no numeric
prefixes, no priority field. **A hook is execution-order-agnostic**: it does its
own work, guarded so it is idempotent, and it does not care who ran before it.

Where order genuinely matters, it is expressed by *which point you attach to*,
never by position within one:

> **Hooks are order-agnostic. Where order matters, fill a named point.**

Mods run in `LC_ALL=C` directory-name order so a run is reproducible and a log
is readable — not so you can rely on it. The `LC_ALL=C` is load-bearing rather
than decorative: a plain glob collates by the developer's locale, so `Zsh` and
`dotfiles` sort one way on the host and the other in the guest, and the image
hash below would then differ between two machines with identical trees.

Each hook is a separate process, run by path, so its shebang decides and a `cd`
in one doesn't leak into the next.

**It is additive**, so no `PARA_CONTRACT` bump — a project with one
`hooks/provision` and no mods resolves to exactly one file and behaves
identically. Two things still have to be written down as contract, because both
are new claims on a tree the project ships verbatim: para now **executes**
`.paraspace/mods/*/hooks/*`, and `.paraspace/run-hook` joins `env` and
`host.env` as a name para owns and overwrites. `hooks/helpers` stays inert —
only an exact name match is a candidate.

## The runner: `~/.paraspace/run-hook`

para pushes its own runner into the guest beside `env`, and the host's
`run_hook` becomes one `ws_exec`:

```sh
run_hook() { # run_hook <hook> <name>
  ws_exec "$2" "exec ~/.paraspace/run-hook $1" || die "the '$1' hook failed (above)."
}
```

Resolution, order and the per-hook env live in that one script. Which is what
buys the thing mods are actually for — **anything can open a hook point, and
mods fill it by name**:

```sh
# .paraspace/hooks/provision, once the clone is in place
~/.paraspace/run-hook post-clone
```

para knows nothing about `post-clone`, `seed-shared`, `packages`, or whatever a
project calls the moment its mods care about. Those are contracts between a
project and the mods written for it, which is the right place for them to live —
and a mod can open a point of its own the same way.

The alternative — enumerate on the host, one `ws_exec` per hook — was rejected:
every named hook point would then hand-roll its own glob-and-sort in a project
hook, which is a second spelling of an idea para already has.

### What the runner must get right

Each of these is a way the obvious first draft breaks:

- **Bash, not POSIX sh.** `ws_exec` already hard-requires bash (`su … -s
  /bin/bash`), and `bin/lint` selects files by a `bash` shebang — a `#!/bin/sh`
  runner would ship unlinted.
- **Pushed with `--mode 0755`, after the recursive push.** `incus file push -`
  defaults to `0600`, which execs as 126; pushing it last means a project that
  happens to ship a `.paraspace/run-hook` can't shadow para's.
- **In `package.json`'s `files`.** It lives at `libexec/run-hook`, and `files`
  currently lists `bin/para` — *not* `bin/` — so a new top-level directory is
  invisible to npm. Miss this and every published `para` execs a file that was
  never packaged, on the first hook of every project, mods or not.
- **Root from its own path**, never from `$PARA_HOOKS` — which the runner itself
  re-points. A mod hook that opens a nested point would otherwise enumerate
  `mods/<m>/mods/*` and silently skip every other owner.
- **`for dir in "$root"/mods/*/`, not `find | while read`.** A piped loop hands
  the hook list to the hook as stdin, which kills every prompt — and `provision`
  is documented to prompt (`gh auth login`, the ssh-key flow).
- **The documented cwd, per hook** — `~/$PARA_CLONE_DIR` if it exists, else
  `$HOME`. Today `GUEST_PRELUDE` sets it once; with named points, a hook that has
  already `cd`'d would otherwise hand its cwd to every mod filling that point.
- **A recursion guard.** The runner carries the active stack in an env var and
  dies naming it: `hook point 'provision' is already running (provision →
  post-clone → provision)`. This is a guard rather than a shape, deliberately: a
  hook is arbitrary code and can always call the runner, and what it prevents is
  a fork bomb inside a nesting-enabled container during `para up`.
- **Errors name the file.** With N candidates, `the 'provision' hook failed` no
  longer says which one. The runner prints the failing path and propagates its
  exit status; the host keeps the `Running hook:` banner, so para's log
  vocabulary stays in one place instead of gaining a second implementation.

It is **runnable on the host against a fixture `.paraspace/`** — so all of the
above gets CLI-tier tests with no incus.

### A mod is a `.paraspace/`, so its hooks read like the project's

This plan **depends on [#18](https://github.com/paraspace-dev/paraspace/pull/18)**
(`PARA_HOOKS` / `PARA_SKEL`, open at time of writing). Those are set once in
`push_project`, so the runner **re-points them at whoever owns the hook it is
about to run**:

```sh
PARA_HOOKS=$owner/hooks PARA_SKEL=$owner/skel PARA_MOD=$name PARA_MOD_DIR=$owner "$hook"
```

The payoff is that a mod's hook is written *identically* to a project's:

```sh
. "$PARA_HOOKS/helpers"                  # the mod's own helpers
cp "$PARA_SKEL/zshrc" ~/.zshrc           # the mod's own skel
```

`.shellcheckrc`'s `source-path=SCRIPTDIR` already resolves `$PARA_HOOKS/helpers`
by basename, so a mod's `hooks/helpers` follows for free and the lint gate needs
no change.

`PARA_MOD_DIR` is not redundant with that, for two reasons the ergonomic
spelling cannot cover:

- **`~/.paraspace/env` still holds the project's values.** `GUEST_PRELUDE`
  re-sources it on every `ws_exec`, so a hook that re-sources it — or a `para sh`
  you run to reproduce that hook by hand — silently rewinds `PARA_HOOKS`/
  `PARA_SKEL` to the project's. Wrong file, no error. `$PARA_MOD_DIR/hooks/…` is
  the spelling that is always right.
- **A mod's `commands/` run on the host**, where `PARA_HOOKS`/`PARA_SKEL` are
  unset by design. Without `PARA_MOD_DIR` a mod command cannot find its own files
  at all.

So: `PARA_MOD` (name) and `PARA_MOD_DIR` (path) in both places — set by the
runner in the guest, and by `run_project_command` when a verb resolved to a mod.
Both are empty for the project's own hooks and commands. #18's `docs/hooks.md`
row needs rewording in the same change, from "your `hooks/` and `skel/`" to "the
`hooks/` and `skel/` of whoever owns the hook you're in".

## Image build

Most of the `void-jchook` diff is packages — nvim, tmux, ripgrep, Claude Code —
so a mod that ships dotfiles has to reach the image, or its dotfiles reference
tools that aren't there.

**`.paraspace/` goes into the builder too, and the same runner runs there.**
`cmd_image_build` keeps running exactly one payload — the project's
`image-build.sh`, unchanged — and that payload opens named points:

```sh
# .paraspace/image-build.sh, after the user exists
/root/.paraspace/run-hook packages
```

That is one `incus file push -r` plus the runner, and it buys: the same
resolution rule as every other hook point (rather than a second list-and-loop
kept in step by prose), `$PARA_HOOKS`/`$PARA_SKEL`/`$PARA_MOD_DIR` inside build
hooks, and an answer to an ordering problem a flat list cannot solve —
`dotfiles-jchook` installs Claude Code *as* `$PARA_USER`, a user the project's
payload creates, so "mods run after the project" has to be a promise someone
makes rather than a coincidence.

The interrupt dance stays exactly as it is (`… | incus exec … bash -s &` then
`wait "$!"`, which is the only reason Ctrl-C tears the builder down), because
there is still one payload.

**`image_src_sha` must cover the mods.** It hashes `image-build.sh` today; a
mod's build hooks change what the image contains, so the hash covers
`.paraspace/mods/` as well — one `image_inputs()` helper that prints only paths
that exist, consumed by the hasher. Two traps: an unmatched glob handed to `cat`
exits non-zero, and `set -o pipefail` turns that into "the image inputs could not
be hashed" for every project with no mods at all; and the enumeration is
`LC_ALL=C` for the same reason the runner's is. Hashing all of `mods/` is
deliberately over-broad — editing a mod's host-side `commands/` marks the image
drifted — because the failure mode is a spurious rebuild rather than a stale
image reported as current.

## Commands

`mods/<m>/commands/<verb>` becomes `para <verb>`, run on the host like
`.paraspace/commands/` already is. That is how the dotfiles mod ships
`para claude` and `para run` without the project's `commands/` knowing.

Precedence, first match wins: **engine verb → project command → mod command**
(mods in `LC_ALL=C` directory order).

**`para commands` stays one bare name per line.** It is a scripting surface, and
the shipped completion script feeds it straight into `compgen -W` — a second
column would offer mod names as if they were verbs. The source belongs in
`para --help`'s `PROJECT COMMANDS` block, which already has a second column, and
a shadowed verb belongs in `para doctor`, which already warns when a project
command collides with an engine verb. Extend that warning to two mods shipping
the same verb; a silent no-op is the failure mode here.

## What a mod may assume

Only para's contract: `$PARA_*`, `$HOME`, `$PARA_SHARED`, and its own
`$PARA_HOOKS` / `$PARA_SKEL` / `$PARA_MOD_DIR`. Specifically:

- **Not the project's `helpers`.** That file is template policy, not engine
  contract — `void-minimal` happens to ship one, a project that never ran
  `para init` won't, and `$PARA_HOOKS/helpers` resolves to the *mod's* own
  anyway. So a mod ships one. (Tempting to promote `helpers` into the engine and
  be done. Don't: para would then own log formatting, and the generic-mechanism
  boundary is the whole point. The cost is a byte-identical fourth copy in this
  repo, and `test_template_helpers_do_not_drift` should grow to cover it.)
- **Not the project's shared-volume sentinel.** `void-docker-gh`'s
  `$PARA_SHARED/.seeded` guards *its* one-time seed.
- **Never clobber.** Every seeder — the project's and every mod's — guards on the
  destination: `[ -e "$shared/zshrc" ] || cp …`. **First writer wins.** This is
  what makes `mod add` safe against a shared volume that has been live for months
  with hand-edited files, and it is the rule that makes the migration below work
  at all.
- **Not its position.** Another mod may or may not have run; there is no way to
  ask, and the order is not a promise.
- **Not stdin past its own prompt.** One tty and one stdin now feed the project's
  hook *and* every mod's; a hook that over-reads starves the next.
- **Not the `Parafile`.** Mods are never sourced on the host, so nothing in a mod
  runs at config time. A mod's knobs are ordinary `PARA_*` variables — para
  forwards every one for free — defaulted inside its own hook with
  `: "${PARA_FOO:=…}"` and documented in its README.
- **Not the distro.** A mod's build hooks are coupled to whatever base image the
  project builds on (`xbps-install` works on a Void project and nowhere else).
  The mod's README states which base it targets; there is no mechanism here, and
  shouldn't be.

Two mods that both symlink `~/.zshrc` is a conflict para will not detect; last
one wins. Document it, don't build detection for it.

## `para mod`

```
para mod add <git-url>      vendor a mod into .paraspace/mods/
para mod ls                 what this project has vendored
para mod rm <name>          delete it
para mod update [<name>]    re-vendor from .mod-source
```

**No bundled mods, and no `--list`.** A template is copy-once — para's obligation
ends at `cp`, which is why the bundled ones can be called reference consumers. A
bundled *mod* would be a dependency para is expected to keep current, shipped
through a verb that exists to update it; making para's tarball the
vendor-of-record for one person's nvim config is a new and permanent obligation,
and `--list` would quietly make it the registry. `dotfiles-jchook` ships as its
own repo.

Git resolution is the `is_git_spec` + shallow-clone helper from
[`plans/init-from-git-url.md`](./init-from-git-url.md) — built once, used by
`init` and `add`. **That plan is stale** (it references `templates_dir`,
`examples/`, and a `PARA_IMAGE` personalization step `cmd_init` no longer has);
refresh it before treating it as the shared design.

Load-bearing details:

- **`rm -rf` the mod's `.git`** after cloning. Otherwise "the tree in git is the
  truth" is false in the consumer's repo, and `push_project` ships the whole
  object store into every workspace on every `up`.
- **`update` is `rm -rf` then a fresh copy**, not an overlay. Force-overwrite
  never removes a file the author deleted upstream: a hook renamed `provision` →
  `post-clone` would leave both, and the stale one runs forever. This is also
  simpler than `--force` semantics, and licensed by the framing — don't edit it.
- **Validate the name** against `validate_name`'s character class before it
  reaches a path. `para mod rm ''` is `rm -rf .paraspace/mods/` and takes every
  mod; `para mod rm ../hooks` takes the project's hooks. `add` and `update` need
  the same guard on the write side.
- **`cmd_init`'s copy loop needs parameters, not just a new root.** Two of its
  lines are init-specific: the `chmod +x` predicate matches
  `.paraspace/hooks/*|.paraspace/commands/*`, which matches *nothing* when the
  walk is rooted at a mod (`hooks/provision`) — leaving mod commands
  non-executable, to fail at `exec` with EACCES — and it skips `README.md`, which
  for a mod is content you want vendored. Lift both to the caller.
- **`push_project` chmods the whole tree**: one `incus exec … chmod -R +x
  "$home/.paraspace"`. `incus exec` runs execve with no shell, so `mods/*/hooks`
  would be passed as a literal and glob nothing — and chmodding the whole
  directory also **deletes** the existing `[ -d … ]` guard. The cost is `+x` on
  an inert `Parafile` copy, which nothing runs.

`update` and `ls` need provenance, so `add` writes `mods/<m>/.mod-source` — one
line, the spec and the ref if pinned. No lockfile, no resolution.

## Migrating `void-jchook`

The point of the exercise — and the part that proves the mechanism, because a
naive additive port **does not work**. Two things break:

1. Both templates ship a `skel/zshrc`, and `void-docker-gh` seeds `$shared/zshrc`
   and `$shared/gitconfig` inside its one-time `.seeded` guard. A mod running
   *after* it can only clobber the file or skip it.
2. Mods run after the project's *entire* provision, and that provision `die`s on
   a failed clone. Today `void-jchook` seeds zsh/nvim/tmux *before* cloning, so an
   unauthorized key still leaves you a usable box; as a plain mod you would get a
   workspace with none of your tools and no way to bootstrap out.

So `void-docker-gh` **gains two hook points** — it is not untouched, and this
plan should never have claimed it would be:

```sh
~/.paraspace/run-hook seed-shared     # before its own seeding
…                                     # [ -e … ] || cp, so a mod's file survives
~/.paraspace/run-hook pre-clone
clone || authorize_key
```

With **first writer wins**, both problems dissolve: the mod seeds at
`seed-shared`, the base skips what already exists, and on a volume that has been
live for months every hand-edited file survives untouched.

| Today | Becomes |
|---|---|
| the `skel/` tree (nvim, tmux, claude, zshrc, bin) | `mods/dotfiles-jchook/skel/` |
| the provision diff (seed, symlink, chsh, managed Claude policy) | `hooks/seed-shared` + `hooks/provision`, both guarded |
| the `image-build.sh` diff (packages, Claude Code, /tmp) | `hooks/packages`, on the point the project's payload opens |
| `commands/{claude,run}` | `mods/dotfiles-jchook/commands/` |
| the `Parafile` and `boot` diffs | nothing — they were prose differences |
| the template itself | deleted; its README's content moves to the mod's |

Two wrinkles to settle during implementation rather than discover:

- **The gitconfig is written whole by both.** jchook's version adds an `[alias]`
  block its own zsh aliases depend on; under first-writer-wins the mod would have
  to duplicate the base's identity `printf`, which is the fork-rot problem
  relocated one level down. The fix is an `[include]` in the base's gitconfig and
  an included file from the mod.
- **`ln -sfn` onto a real `~/.claude` nests inside it.** The image build defends
  with `rm -rf ~/.claude`, but its `[ ! -x … ]` guard skips that on
  `para image build -i` — and splitting install (build hook) from symlink
  (provision hook) makes "add the mod, forget the rebuild, use `-i`" a normal
  sequence. The mod's provision does `[ -L ~/.claude ] || rm -rf ~/.claude` first.

**Acceptance test:** `para init void-docker-gh && para mod add <dotfiles-jchook
url>` reproduces today's `void-jchook`. If it doesn't, the mechanism is wrong.
That template is then deleted.

## Settled: there is no ordering knob

An earlier draft gave hooks `H.d/*` fragments with `NN-` prefixes, and then had
to pick whether the numbers were scoped per mod or global. Both answers are bad.
Scoped means the number is a lie — mod `a`'s `10-x` still runs before mod `b`'s
`05-y`. Global means every author picks a number against projects they have never
seen, and two mods that both chose `50-` are a silent coin flip.

The mechanism that survives is the named hook point. So `.d/` directories are
**not** in v1 and neither is any priority syntax. If a mod appears to need one,
the project it targets is missing a hook point — that is the fix, and it is one
the project can make without para changing.

The cost of getting this wrong later is real: the resolution rule **is** the
contract, so adding position semantics after the fact reorders existing hooks and
bumps `PARA_CONTRACT`. Adding *named* points never does.

## Settled: the name

`mod` — `.paraspace/mods/`, `para mod add`, "a vendored, reusable `.paraspace/`
component".

- **`plugin`** implies para has an extension API. It doesn't: para never loads a
  mod and gains no behavior from one. Keeping the word would have meant a
  standing prose tax on every page to walk the implication back.
- **`pod`** fits ParaSpace beautifully, and is the most dangerous option for
  exactly that reason — para is a container tool (72 mentions of "container" in
  `docs/`; a workspace *is* an Incus container), so a reader meets "pod" in a
  container CLI and assumes a running thing.
- **`fragment`** is accurate and carries the order-agnostic sense for free, but
  it is long in the CLI and connotes a broken-off piece.

`mod` is short, distinctive, noun-then-verb like `para image build`, and implies
no runtime. The one thing to hold in the prose: a mod **composes into** a
`.paraspace/`; it never *modifies* or *overrides* the engine's behavior.

## Docs impact

Same change, or it's drift:

- new `docs/mods.md` — using and authoring one; **needs a sidebar entry** in
  `.vitepress/config.mts`. Likely two entries (Guides vs Reference) given the
  page gate — decide before writing, it changes the voice.
- `docs/hooks.md` — the resolution rule, `run-hook` (its argument form and env
  are now public API), `PARA_MOD`/`PARA_MOD_DIR`, the guest-layout table, and
  #18's re-pointing reword. At 122 of ~150 lines, so authoring detail goes in
  `mods.md` and links back.
- `docs/commands.md` — mod commands, precedence, and the `void-jchook` row of the
  template→commands table.
- `docs/image.md` — the builder push and named build points.
- `docs/versioning.md` — additive, plus the reserved names (`run-hook`, `mods/`)
  and why executing a new path is still additive.
- `docs/parafile.md` — link "Your own keys" from `mods.md` rather than
  re-deriving it, and add mod hooks to its "reaches your hooks" list.
- `void-jchook` is named in six places that all have to change: `README.md:72`,
  `docs/project-setup.md:81,92`, `docs/commands.md:135`, `docs/agents.md:51`,
  `docs/shared-auth.md:55` — plus `CLAUDE.md:34` and `CLAUDE.md:154`, the latter
  being the line #18 just rewrote. `docs/agents.md:51` is the sharpest: it
  teaches `para claude`, so after this it must say *mod*, not *template*.

## Test checklist

CLI tier (no incus — this is why the runner is a standalone script):

- `libexec/run-hook` against a fixture `.paraspace/`: project before mods and
  mods in `LC_ALL=C` order; a failing hook aborts the rest and its **path** is in
  the error; `PARA_HOOKS`/`PARA_SKEL`/`PARA_MOD`/`PARA_MOD_DIR` re-pointed per
  hook; the documented cwd per hook; a mod with no `H` skipped silently; no mods
  → unchanged behavior; `hooks/helpers` never executed.
- a **nested** point called from inside a mod hook still resolves every owner
  (the `$PARA_HOOKS`-derived-root trap), and a recursive one dies naming the
  cycle.
- a hook that reads stdin still gets it (the prompt path), not the hook list.
- `para mod add` → files land, `hooks/` + `commands/` executable, `.git`
  stripped; `update` removes an upstream-deleted file; `rm`/`add`/`update` refuse
  a name with a path in it; `ls`.
- command precedence: a mod verb resolves; a project verb of the same name wins;
  an engine verb beats both; `para commands` is still one bare name per line (the
  completion contract).
- **`npm pack --dry-run`'s file list covers everything `pkg_root` resolves
  against.** There is no such test today, which is exactly why `libexec/` being
  absent from `files` is invisible.

e2e tier (run it — CI won't):

- fixture mod that appends its name in `provision` and in a named point the
  fixture project opens; assert both ran, in order, and `para up` idempotent.
- `mod add` onto an **already-seeded** shared volume leaves every existing file
  untouched. This is the only scenario that can lose user data.
- `para image build` with a mod's build hook, then `para image status` after
  editing it → reports a rebuild is needed. Needs `PARA_TEST_REBUILD=1`; the
  fixture's image is cached and reused, so without it this passes vacuously.

## Deferred

- Any ordering syntax — `H.d/` fragments, `NN-` prefixes, priority fields. Named
  hook points instead.
- Mod dependencies, or a mod declaring which hook points it needs.
- Fetch-at-`up` mods / a lockfile. Vendoring is the model.
- Mod-contributed `Parafile` defaults — deliberately not a thing.
- `para init <template> --with <url>`. Sugar; `para mod add` right after `init`
  is the same thing.
