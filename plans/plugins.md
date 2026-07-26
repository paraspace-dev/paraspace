# Plan: plugins — composable `.paraspace/` fragments

## Goal

Let a project vendor reusable pieces of provisioning — dotfiles, a language
runtime, a CI helper — instead of forking a whole template to get them.

```sh
para plugin add dotfiles-jchook
para up feat-x
```

The test case is `templates/void-jchook`. Diffed against `void-docker-gh`, it
forks `provision` (125 vs 88 lines), `boot`, `image-build.sh`, `Parafile` and
`README.md` — and every one of those diffs exists to carry **dotfiles and the
toolchain they need** (zsh/tmux/nvim/Claude Code). None of it is a different
*kind* of workspace. Today an engine-level fix to the base template has to be
hand-ported into the fork; the fork silently rots instead.

A template is a **starting point** — copy once, own it forever. A plugin is a
**dependency** — copy it, update it, don't edit it. `void-jchook` wants to be
the second thing.

## What a plugin plugs into

Not para. **para has no plugin API** — it doesn't load them, doesn't know their
names, and gains no behavior when you add one. A plugin extends *your project's
`.paraspace/`*: it fills hook points, and the ones past `provision`/`boot` are
points the project itself opened. The generic-mechanism boundary is unchanged,
and the word is only accurate in that direction.

That is the one cost of calling these plugins, and it is paid in prose: every
page that names them says what they plug into in the same breath. It is the
same discipline `para claude` already needs — a file the default template ships,
never engine behavior. Get it wrong and people file engine bugs about their own
hooks.

## Shape

```
project/.paraspace/
  Parafile
  image-build.sh
  hooks/{provision,boot,helpers}
  commands/{key,web}
  skel/zshrc
  plugins/
    dotfiles-jchook/
      README.md
      hooks/{helpers,provision}
      image-build.sh
      commands/{claude,run}
      skel/{nvim,tmux,claude,zshrc}
```

**Plugins are vendored** — copied in at `plugin add` time and checked into the
project's repo, not fetched at `up` time. That falls out of what para already
does: `push_project` pushes `.paraspace/` verbatim into the guest, so a plugin
reaches the workspace with no engine change at all. It also keeps `para up`
offline, keeps the trust model ("review the hooks you're about to run") intact,
and puts every plugin change in the project's own git history.

## The one new rule: a hook name resolves to a list

Today `run_hook provision` runs one file. It runs **the project's, then one per
plugin**:

```
hooks/provision                        # the project's own
plugins/<p>/hooks/provision            # each plugin's, plugins in directory order
```

One file per hook name per plugin. Nothing else — no `provision.d/`, no numeric
prefixes, no priority field. **The contract is that a plugin is
execution-order-agnostic**: it does its own work, guarded so it is idempotent,
and it does not care who ran before it. A plugin that needs to run at a
particular moment says so by attaching to a *named* hook point (below), not by
sorting itself into a position it had to guess.

Plugins run in directory-name order so a run is reproducible and a log is
readable — not so you can rely on it. (Renaming a plugin directory therefore
moves it. If you ever need that, the plugin wanted a named hook point.)

Each hook is a separate process, run by path, so its shebang decides and a `cd`
in one doesn't leak into the next.

**It is additive**, so no `PARA_CONTRACT` bump. A project with one
`hooks/provision` and no plugins resolves to exactly one file and behaves
identically. `hooks/helpers` stays inert — only an exact name match is a
candidate, which is the same promise [`docs/hooks.md`](../docs/hooks.md)
already makes.

## The runner: `~/.paraspace/run-hook`

para pushes its own small POSIX runner into the guest beside `env`, and the
host's `run_hook` becomes one `ws_exec`:

```sh
run_hook() { # run_hook <hook> <name>
  ws_exec "$2" "exec ~/.paraspace/run-hook $1" || die "the '$1' hook failed."
}
```

Resolution, order and the per-hook env live in that one script. Which is what
buys the thing plugins are actually for — **anything can define a hook point,
and plugins fill it by name**:

```sh
# .paraspace/hooks/provision, once the clone is in place
~/.paraspace/run-hook post-clone
```

para knows nothing about `post-clone`. Neither does it know about
`xbps-install`, `seed-shared`, or whatever a project calls the moment its
plugins care about. Those are contracts between a project and the plugins
written for it, which is the right place for them to live — and a plugin can
open a point of its own the same way, for plugins written against *it*.

This is what replaces ordering. "Run after the clone" is a name, not a number,
and it means the same thing to every plugin that reads it.

The alternative — enumerate on the host, one `ws_exec` per hook — was rejected:
every named hook point would then hand-roll its own glob-and-sort in a project
hook, which is a second spelling of an idea para already has.

It lives at `libexec/run-hook` in the package (`bin/lint` finds it by shebang),
and it is **runnable on the host against a fixture `.paraspace/`** — so the
resolution rule gets CLI-tier tests with no incus.

### A plugin is a `.paraspace/`, so it needs no new path variable

This plan **depends on [#18](https://github.com/paraspace-dev/paraspace/pull/18)**
(`PARA_HOOKS` / `PARA_SKEL`, open at time of writing) and gets most of its
ergonomics from it. Those two are set once in `push_project`, so the runner only
has to **re-point them at whoever owns the hook it is about to run**:

```sh
PARA_HOOKS=$owner/hooks PARA_SKEL=$owner/skel "$hook"
```

The payoff is that a plugin's hook is written *identically* to a project's:

```sh
. "$PARA_HOOKS/helpers"                  # the plugin's own helpers
cp "$PARA_SKEL/zshrc" ~/.zshrc           # the plugin's own skel
```

So a plugin is structurally just a `.paraspace/` — same directory names, same
variable spellings, no `$PARA_PLUGIN_DIR/…` prefix to remember and no second way
to name the same thing. The only identity the runner adds is `PARA_PLUGIN`: the
plugin's directory name, empty for the project's own hooks, useful for log lines
and for a plugin's own sentinel (`$PARA_SHARED/.$PARA_PLUGIN-seeded`).

`.shellcheckrc`'s `source-path=SCRIPTDIR` already resolves `$PARA_HOOKS/helpers`
by basename, so a plugin's `hooks/helpers` follows for free and the lint gate
needs no change.

Without #18 this needs a `PARA_PLUGIN_DIR` and every plugin hook spells its
paths differently from every project hook. Land #18 first.

## Image build

Most of the `void-jchook` diff is packages — nvim, tmux, ripgrep, Claude Code —
so a plugin that ships dotfiles has to reach the image or its dotfiles reference
tools that aren't there.

`cmd_image_build` pipes one payload over stdin (`{ para_env; cat "$payload"; } |
incus exec … bash -s`). It becomes a loop over the same list, project first:

```
image-build.sh
plugins/<p>/image-build.sh
```

Each gets its own `bash -s` pass, so a fragment's `exit 0` ends that fragment
rather than the build, and one `set -euo pipefail` can't leak into the next.

**`image_src_sha` must hash all of them, in the same order.** It currently
`cat`s only `.paraspace/image-build.sh`; leave it and `para image status`
reports "up to date" after a `plugin add` that changed what the image contains.

Known limit for v1: nothing is *pushed* into the builder, so a build fragment
gets `para_env` and its own text, not its plugin directory. A plugin that needs
files at build time does that work in `provision` instead. (Deferred:
`incus file push -r .paraspace` into the builder and run fragments by path.)

## Commands

`plugins/<p>/commands/<verb>` becomes `para <verb>`, run on the host like
`.paraspace/commands/` already is. That is how the dotfiles plugin ships
`para claude` and `para run` without the project's `commands/` knowing.

Precedence, first match wins: **engine verb → project command → plugin command**
(plugins in directory order). `para commands` grows a column naming the source,
so a shadowed verb is visible rather than mysterious.

## What a plugin may assume

Only para's contract: `$PARA_*`, `$HOME`, `$PARA_SHARED`, and its own
`$PARA_HOOKS` / `$PARA_SKEL`. Specifically:

- **Not the project's `helpers`.** That file is template policy, not engine
  contract — `void-minimal` happens to ship one, a project that never ran
  `para init` won't, and `$PARA_HOOKS/helpers` resolves to the *plugin's* own
  anyway. So a plugin ships one. (Tempting to promote `helpers` into the engine
  and be done. Don't: para would then own log formatting, and the
  generic-mechanism boundary is the whole point.)
- **Not the project's shared-volume sentinel.** `void-docker-gh`'s
  `$PARA_SHARED/.seeded` guards *its* one-time seed. A plugin is idempotent on
  its own terms — self-guarding `[ -e … ] ||` steps, or its own sentinel.
- **Not its position.** Another plugin may or may not have run; there is no way
  to ask, and the order is not a promise. Do the work, guard it, be idempotent.
- **Not the `Parafile`.** Plugins are never sourced on the host, so nothing in a
  plugin runs at config time. A plugin's knobs are ordinary `PARA_*` variables —
  para forwards every one of them for free — defaulted inside its own fragment
  with `: "${PARA_FOO:=…}"` and documented in its README.

Two plugins that both symlink `~/.zshrc` is a conflict para will not detect;
last one wins. Document it, don't build detection for it.

## `para plugin`

```
para plugin add <name|git-url>   copy a bundled or remote plugin into .paraspace/plugins/
para plugin ls                   what this project has vendored
para plugin rm <name>            delete it
para plugin update [<name>]      re-copy over the top (--force semantics)
```

`add` is `cmd_init`'s copy loop with a different source and destination — factor
that loop out (`copy_tree <src> <dest> <force>`) and both call it. It must
`chmod +x` `hooks/` and `commands/` the way `cmd_init` does, and `push_project`
must extend its `chmod -R +x` to `plugins/*/hooks` for the same reason.

A git URL resolves exactly like
[`plans/init-from-git-url.md`](./init-from-git-url.md) — same `is_git_spec` +
shallow-clone helper, built once and used by both commands. Worth sequencing
the two together.

`update` and `ls` need to know where a plugin came from, so `add` drops
`plugins/<p>/.plugin-source` (one line: the spec, and the ref if pinned). No
lockfile, no resolution — vendored means the tree in git is the truth.

Bundled plugins live at `plugins/` in this repo (add it to package.json
`files`), listed by `para plugin add --list`, mirroring `para init --list`.

Optional sugar: `para init <template> --with <plugin>`, repeatable. Nice, not
load-bearing — `para plugin add` right after `init` is the same thing.

## Migrating `void-jchook`

The point of the exercise. `templates/void-jchook/` becomes
`plugins/dotfiles-jchook/`:

| Today | Becomes |
|---|---|
| the `skel/` tree (nvim, tmux, claude, zshrc, bin) | `plugins/dotfiles-jchook/skel/` |
| the provision diff (seed, symlink, chsh, managed Claude policy) | `hooks/provision`, self-guarding |
| the `image-build.sh` diff (packages, Claude Code, /tmp) | `plugins/dotfiles-jchook/image-build.sh` |
| `commands/{claude,run}` | `plugins/dotfiles-jchook/commands/` |
| the `Parafile` and `boot` diffs | nothing — they were prose differences |
| the template itself | deleted; its README's content moves to the plugin's |

`void-docker-gh` is then untouched, and `para init && para plugin add
dotfiles-jchook` reproduces `void-jchook`. If it doesn't, the mechanism is
wrong — that equivalence is the acceptance test.

## Settled: there is no ordering knob

An earlier draft gave hooks `H.d/*` fragments with `NN-` prefixes, and then had
to pick whether the numbers were scoped per plugin or global across all of them.
Both answers are bad. Scoped means the number is a lie — plugin `a`'s `10-x`
still runs before plugin `b`'s `05-y`. Global means every plugin author picks a
number against projects they have never seen, and two plugins that both chose
`50-` are now a silent coin flip.

The mechanism that survives is the named hook point: a plugin that must run
after the clone attaches to `post-clone` and says so out loud. So `.d/`
directories are **not** in v1 and neither is any priority syntax. If a plugin
appears to need one, the project it targets is missing a hook point — that is
the fix, and it is a fix the project can make without para changing.

The cost of getting this wrong later is real either way: the resolution rule
**is** the contract, so adding position semantics after the fact reorders
existing projects' hooks and bumps `PARA_CONTRACT`. Adding *named* points never
does.

## Docs impact

Same change, or it's drift:

- new `docs/plugins.md` — using and authoring one; **needs a sidebar entry** in
  `.vitepress/config.mts`. Opens by saying what a plugin plugs into (above);
  every other page that names one repeats it in a clause, not a section.
- `docs/hooks.md` — the resolution rule, `run-hook`, `PARA_PLUGIN*`, and the
  guest-layout table. This page is at 122 of ~150 lines; authoring detail goes
  in `plugins.md` and links back.
- `docs/commands.md` — plugin commands and the precedence order.
- `docs/image.md` — build fragments.
- `docs/versioning.md` — additive, plus the new `~/.paraspace/run-hook`.
- `README.md` / templates list — `void-jchook` is gone.

## Test checklist

CLI tier (no incus — this is why the runner is a standalone script):

- `libexec/run-hook` against a fixture `.paraspace/`: project before plugins and
  plugins in directory order, a failing hook aborting the rest, `PARA_HOOKS` /
  `PARA_SKEL` / `PARA_PLUGIN` re-pointed per hook and restored for the next, a
  plugin with no `H` skipped silently, no plugins → unchanged behavior, and
  `hooks/helpers` never executed.
- `para plugin add` bundled → files land, `hooks/`+`commands/` executable;
  re-add without `--force` skips; `ls`, `rm`.
- command precedence: a plugin verb resolves; a project verb of the same name
  wins; an engine verb beats both.

e2e tier (run it — CI won't):

- fixture plugin that appends its name to a file in `provision` and in a named
  `post-clone` point the fixture project opens; assert both ran, in order, and
  that `para up` is still idempotent.
- `para image build` with a plugin fragment, then `para image status` after
  editing that fragment → reports a rebuild is needed.

## Deferred

- Any ordering syntax — `H.d/` fragments, `NN-` prefixes, priority fields
  (above). Named hook points instead.
- Plugin dependencies, or a plugin declaring which hook points it needs.
- Fetch-at-`up` plugins / a lockfile. Vendoring is the model.
- Pushing `.paraspace/` into the image builder so build fragments get files.
- Plugin-contributed `Parafile` defaults — deliberately not a thing.
