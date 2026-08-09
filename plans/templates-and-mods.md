# Plan: one `void` template, capability mods, engine helpers

> **Working document.** Delete it once the `void` template ships, `docker` and
> `gh` exist as mods, `$PARA_HELPERS` is injected, and `docs/mods.md` carries
> the composition guidance this note works out.

## Goal

Stop shipping a template per combination. A base template decides the distro and
the box; the pieces you might or might not want arrive as mods.

```sh
para init void
para mod add docker gh
para image build
para up feat-x
```

Today that is `para init void-docker-gh`, and wanting the same box without
Docker means forking the template. `templates/void-minimal` exists to answer
that, and once docker and gh are mods it earns its keep by differing from
`void-docker-gh` in a clone block and three `Parafile` keys.

## Decisions

### Split on capability vs taste, not tool by tool

`docker` and `gh` are **capabilities**. Each installs a thing, wires it to the
user the base already made, and carries no opinion.

`nvim`, `tmux` and `zsh` as they exist inside `dotfiles-jchook` are **taste**.
`skel/nvim` alone is a thousand lines of one person's keymaps plus a
`lazy-lock.json`. Three mods named after tools would all mean "jchook's version
of X", and the mod list stops being readable. `dotfiles-jchook` stays whole, and
its own commands agree, since `para run` opens tmux with claude in one window
and no single-tool mod could own that.

Keeping the capability set small also keeps the distro problem small. Every
capability mod is package-manager-coupled, so `docker` means the Void docker.
`docs/mods.md` already tells a mod's README to name the base it targets. When a
second base arrives, either prefix the mod (`debian-docker`) or teach one mod to
branch on the package manager it finds. Each new capability mod is another copy
of that decision.

### One `void` template

With docker and gh gone, `void-docker-gh` and `void-minimal` differ by a clone
block in `hooks/provision` and three `Parafile` lines: `PARA_ORIGIN`,
`PARA_READY_HOST` and `PARA_ROUTES`. Two Parafiles of sixty-eight and ninety
lines kept in sync is not worth that, and a template is a thing you own after
`init`, so "I have no repo yet" is one block deleted and three lines changed in
files you already own.

Ship one `void`, clone active, with a Parafile comment beside each of the three
saying what to change and what it costs if you don't. Around 200 lines of
near-duplicate content goes away, and the setup step in
`docs/project-setup.md` goes from one command to two, which puts the mod
system into the first commands a new project runs.

The clone block in `hooks/provision` is the block. The three `Parafile` keys are
single lines, and each one fails differently when left alone:

- `PARA_ORIGIN`. The best case of the three, since `hooks/provision` already
  dies with the fix named.
- `PARA_READY_HOST=github.com`. `wait_ready` gates on `getent hosts github.com`
  inside the workspace, so an offline box waits the full ~120s and then blames
  guest DNS. Empty means "don't wait on a name".
- `PARA_ROUTES=8080`. Publishes a Caddy site for a port nothing listens on.
  See [The docker mod owns `boot`](#the-docker-mod-owns-boot) for why this one
  can't move into the mod that decides it.

### Mods compose through drop-in directories, not ordering

The base's `image-build` creates a `zshrc.d/` beside zsh's global rc and puts
the loop that sources it into that rc, the same way `dotfiles-jchook` already
writes `/etc/profile.d/dotfiles-jchook.sh` for `$BROWSER`. A mod that wants
shell integration writes `<etcdir>/zshrc.d/<mod>.zsh`. `/etc/profile.d` stays
for environment that has to reach non-interactive login shells too.

**The global rc's path is compiled into zsh** (`--enable-etcdir`), so it is
`/etc/zsh/zshrc` on Debian and Arch and plain `/etc/zshrc` on a default build.
Nothing in this repo pins Void's, and writing the loop to the wrong one leaves
every drop-in dead with no error. Confirm it before writing the base hook, with
`xbps-query -f zsh | grep etc` or `zsh -i -o sourcetrace -c exit`, then hardcode
what it says. Tracked in [Open](#open).

The global rc rather than `skel/zshrc`, for two reasons. `dotfiles-jchook`
relinks `~/.zshrc` to its own file and never sources the base's, so a user rc
would leave every drop-in dead for the one mod this package ships. And
`skel/zshrc` is copied only behind the volume's `.seeded` marker, so a line
added to it never reaches a project that has already run `para up`, which is
every project that would run `para mod add docker`.

Then the docker mod never learns zsh exists, the zshrc never learns docker does,
and no order can be wrong because nothing overwrites.

**A drop-in may not call `compdef`.** zsh reads the global rc before `~/.zshrc`,
and `compinit` runs in the user rc, so a drop-in sourcing `docker completion
zsh` fails with "compdef: unknown command". Completions belong in the image, not
in a startup file. A mod whose package ships one gets it for free in
`/usr/share/zsh/site-functions`, and a mod whose package doesn't writes it there
from `image-build`:

```sh
docker completion zsh > /usr/share/zsh/site-functions/_docker
```

Either way `compinit` finds it on the default `fpath`, and neither path costs
anything at shell startup. Drop-ins are for aliases, environment and functions.

### A mod that depends on another mod gets no engine support

Three mechanisms, in order of preference, all of them documented rather than
built:

1. **Most of them are not dependencies.** `dotfiles-jchook`'s zshrc carries four
   docker aliases. An alias to a binary that is not installed is inert until you
   type it, and then it prints the same "command not found" it would have
   without the alias. No guard needed.
2. **Detect the artifact, not the mod.** `command -v docker` is also true when
   the base installed docker, or you did. `docs/mods.md` already says this, and
   `dotfiles-jchook`'s image-build already practices it against the base with
   its `no home for '$PARA_USER'` die.
3. **When order genuinely matters, the provider opens a hook point.** A mod can
   call `$PARA_RUN_HOOK` like a template can, so `docker`'s image-build ends
   with `"$PARA_RUN_HOOK" docker:after` and a mod needing docker present ships
   `hooks/docker:after` rather than `hooks/image-build`. Docker not vendored
   means the point never opens means the hook never runs, which is right for an
   optional integration and wrong for a hard requirement, so a hard requirement
   adds a three-line `provision` hook beside it that dies with the fix named.
   `image-build` is too early for that probe, since mods build in glob order and
   a mod sorting before `mods/docker` runs first, where `command -v docker` is
   false even when docker is vendored. By `provision` the image is finished and
   the probe is authoritative.

   **A hard requirement probes the point, not the artifact**, which is the one
   place rule 2 inverts. `command -v docker` is true for a user who installed
   docker in their own `image-build` and never vendored `mods/docker`, so the
   `docker:after` point never opened, the depender's integration never ran, and
   an artifact probe passes anyway. Have the provider touch a marker in the
   image next to where it opens the point (`/etc/paraspace/points/docker`, root
   at `image-build` time) and have the depender's `provision` test that. The
   error then names the actual fix, `para mod add docker && para image build`.

   **What this costs:** the refusal lands late. `have_hook`'s comment says
   refusing is the host's job precisely because a guest note prints minutes in,
   and this one prints after `para image build` finished and `para up` reached
   provision. Refusing earlier means the engine reading a mod's requirements,
   which is the manifest refused below. A mod with a hard requirement says so in
   the first line of its README, and that is the whole mitigation.

Above all three, the project's own `provision` opens points and the person who
vendored both mods decides the order. That is the right owner.

**Refused:** a `requires:` field, transitive `para mod add`, a resolver. That is
a package manager, and `para mod add` is defensible because it is a copy you
read, offline, with no graph behind it. It would also mean giving mods a
manifest, and the one entry a mod does not have is the best property mods have.

**Also refused:** promising alphabetical mod order, even though `paraspace_dirs`
on the host and `libexec/run-hook`'s `mods/*` glob in the guest both make it
true today. Once promised, people reach for `10-docker` /
`20-dotfiles`, and numeric prefixes break `para mod add docker` landing in
`mods/docker`, which breaks re-adding as the update path.

### para ships the helpers

Deduplication is not the reason. `interactive()` encodes **para's own rule**
about when a hook may prompt, reading `PARA_NONINTERACTIVE`, which para sets and
honors. Three user-editable copies of engine semantics is a drift risk.

`bin/para` and the hooks' `helpers` have already drifted, in two ways, and
shipping one file means deciding both first:

- **Interactivity.** `bin/para`'s `interactive()` tests `[ -t 0 ] && [ -t 1 ]`;
  the hooks' copy tests `[ -t 0 ]` alone. A host command that sources the
  shipped file has to get the same answer para itself gets, so these have to
  become one definition.
- **Output.** `bin/para` and `libexec/run-hook` emit escape codes
  unconditionally; the hooks' copy gates on `[ -t 2 ]` and the formats differ
  besides (`\033[36m` on the arrow alone versus `\033[36;1m` around the whole
  line). So `para up ws > log 2>&1` today writes a log that is half raw escapes
  and half plain text. Pick one gate and one format for both, and prefer
  honoring the gate everywhere over dropping it, since para does capture hook
  output to logs.

Where the file lives and how it arrives:

- `libexec/helpers` beside `libexec/run-hook`, pushed by `push_paraspace` to
  `<dest>/.paraspace/helpers`, mode 0644 since it is sourced rather than run.
  That is `~/.paraspace` for a workspace and `/opt/.paraspace` in the builder.
  It lands after the tree, the way `run-hook` does, so a project cannot shadow
  it.
- Injected as `$PARA_HELPERS`, so a hook does `. "$PARA_HELPERS"`. It joins the
  keys `guest_env` rewrites per destination, or `para_env` forwards the host's
  `$(pkg_root)/libexec/helpers` verbatim into a container with no such path.
- `~/.paraspace/helpers` becomes a name para owns, beside `env`, `host.env` and
  `run-hook`. `push_paraspace` replaces the whole dir, so a project that ships
  its own `.paraspace/helpers` loses it without a word. `docs/versioning.md`
  says so.
- Additive, so `PARA_CONTRACT` stays 1. A project with its own `hooks/helpers`
  keeps working untouched.

**Set it on the host too.** `$PARA_HOOKS` and `$PARA_SKEL` are unset for host
commands because they name paths inside a workspace, and that reasoning does not
apply here, since para ships the file and knows where it is on both sides. Point
it at `$(pkg_root)/libexec/helpers` and `commands/key` and `commands/web` stop
hand-rolling `echo >&2; exit 1`.

**The source line is bare**, guest hooks and host commands alike. Additive
means an existing project keeps working on the new para, and it says nothing
about the reverse. A project scaffolded by the new para under an older global
one passes `require_project`, gets no `PARA_HELPERS` injected, and dies on
`set -u` with `PARA_HELPERS: unbound variable` at the first hook or command
that sources it. That is the whole check. A `:?` message naming the fix was
considered and dropped, because it would ride verbatim in every template hook,
every command, every mod and the `docs/mods.md` snippet, and N copies of prose
rot while `unbound variable` cannot. One consumer today; the message can come
back the day the error confuses a second one.

```sh
# shellcheck source=/dev/null
. "$PARA_HELPERS"
```

It goes in the bundled templates' hooks and `commands/`, in every mod's, and
in the snippet `docs/mods.md` shows.

**What may go in: only things para itself defines.** Output format,
interactivity, paths para injects. That admits exactly today's file (`stage`,
`info`, `warn`, `die`, `interactive`, `pause`) and keeps out `seed()` and
`relink()`, because para owns the shared volume's existence and mount point, not
the discipline about what may overwrite what inside it. Both stay three-line
patterns in the hook that uses them, where `docs/mods.md` already shows them.

**What it costs.** Six function names become contract surface. Adding one is
additive; changing `stage`'s output or dropping `pause` is a break, and
`docs/versioning.md` has to say so. Customizing a helper also stops being "edit
your copy" and becomes "define over it after sourcing".

### No `para require >=0.2.0`

`docs/versioning.md` already forecloses the syntax, since `PARA_CONTRACT` is a
plain integer compared with `=` and that will not change. A `>=` gate would
either contradict it or pin the npm release number, which is not the interface.

The decisive problem is retroactivity. **A `para require` shipped in 0.2 is not
understood by 0.1**, which is the exact para it would be catching. The check has
to be shell in the mod's own hook no matter what, and that line already exists.
It is the `. "$PARA_HELPERS"` source line, which dies under `set -u` when an
older para injected nothing, from
[para ships the helpers](#para-ships-the-helpers). Once a mod is writing that,
the engine feature adds nothing.

Breaking changes are already caught from the other side, at the project level,
before anything launches. The gap is additive features only, and `$PARA_HELPERS`
is the first one worth noticing.

**And no minor on the contract either.** `1.3` would contradict the same
`docs/versioning.md` rule invoked two paragraphs up, and `require_project`
compares with `!=`, so exporting `1.3` makes every Parafile pinning
`PARA_CONTRACT:=1` die on mismatch. Keeping both would mean a second variable
for mods to read, which is a version scheme with a second version scheme beside
it. If per-feature probes ever stop reading well, that is evidence the additive
pile has grown large enough to be worth a contract **2**, not evidence the
integer needs a decimal point.

### The docker mod owns `boot`

`docker compose up -d --wait` moves into the mod, guarded on a compose file
existing in the clone, so the demo works untouched and `--wait` honors the
readiness contract.

That does put policy in a mod. The alternative is the template carrying a
commented compose line, which makes the quick start a four-step with an edit in
the middle. The mod's README states what it boots.

**The route cannot follow the boot.** Mods have no `Parafile` (`load_config`
sources the user config and the project's, nothing else), so the mod that
decides what listens on 8080 is not allowed to declare 8080. `PARA_ROUTES` stays
in the template, which means `para init void` without `para mod add docker`
publishes a Caddy site with nothing behind it, and para does not probe the port
after `boot`, so the first sign is a 502 on the URL `up` just printed.

Three ways to close it, in order of preference:

1. **Tie them in the Parafile comment.** One line beside `PARA_ROUTES=8080`
   saying it assumes `mods/docker` and the demo clone, and to empty it
   otherwise. Free, and the reader is already there when they cut the clone.
2. **Say it in the mod's README and the quick start**, since the two-command
   `para init void && para mod add docker` is the documented path and the
   mismatch only appears when you deviate from it.
3. **Have para check.** Probing every `PARA_ROUTES` port after `boot` returns
   would turn a 502 into a named error for everyone, not just this case, and it
   is the readiness contract the docs already claim. It is also a real engine
   change with its own timeout question, so it is out of scope here. Worth a
   `TODO.md` entry.

The template's `boot` **does not announce anything.** It becomes today's
`void-minimal` hook minus its `stage "Bare box, nothing to boot…"` line: the
commented compose block stays as the place to add your app, and the body does
nothing. `libexec/run-hook` runs the project's hook before any mod's, so that
line would otherwise print "nothing to boot" immediately before the docker mod
boots the stack, under a `cmd_up` log line that already said "Booting the
stack". `run-hook` still prints `==> hook: hooks/boot`, so the file does not
look skipped, and a project with no mod filling `boot` sees exactly that and
nothing more.

`PARA_PREPULL_IMAGES` and the overlayfs refusal move with it, and become the
docker mod's own documented knobs, which is what `docs/mods.md` says a mod's
`PARA_*` vars are.

## Shape

```
templates/void/.paraspace/
  Parafile            contract, image base + bootstrap, origin, ready,
                      routes=8080 + the comment tying it to mods/docker
  hooks/image-build   base packages, writable /tmp, the user, sudoers,
                      <etcdir>/zshrc.d + the loop in the global zshrc
  hooks/provision     seed the volume, link $HOME, clone:before, clone, .env
  hooks/boot          empty body, the compose line shown in comments
  skel/zshrc          the shared user rc, seeded once
  commands/{key,web}  sourcing $PARA_HELPERS instead of hand-rolled die

mods/docker/
  hooks/image-build   docker + compose, runit, driver refusal, group, prepull,
                      _docker into site-functions, zshrc.d/docker.zsh (aliases
                      only), points/docker, then RUN_HOOK docker:after
  hooks/boot          compose up --wait, if the clone has a compose file
  README.md           targets Void/xbps, PARA_PREPULL_IMAGES, dir/ext4 pool,
                      and that it expects PARA_ROUTES=8080

mods/gh/
  hooks/image-build   github-cli, _gh into site-functions
  hooks/clone:before  relink $PARA_SHARED/gh at ~/.config/gh, then authorize
                      this machine's key when PARA_GH_AUTH is set and the
                      shared volume has no key marker yet
  README.md           PARA_GH_AUTH, and that it claims ~/.config/gh

mods/dotfiles-jchook/  unchanged, minus its helpers copy
```

The clone flow in the template gets simpler, since the gh branch leaves it:

```sh
"$PARA_RUN_HOOK" clone:before        # the gh mod uploads the key here
if ! clone; then
  stage "Authorize this machine's para key on your git host:"
  cat ~/.ssh/id_ed25519.pub >&2
  pause "Press Enter once the key is added"
  clone || die "clone still failing. Is the key authorized on the git host? Re-run: para up $PARA_NAME"
fi
```

Two things travel with the gh branch.

**Ordering, and a real directory.** A mod's `provision` runs after the project's
whole provision, clone included, so everything `clone:before` needs belongs in
`clone:before`. That gets the link in before `gh` writes to it on a fresh
workspace, but ordering does nothing for a workspace that already has a real
`~/.config/gh` sitting there, which is every workspace that ran gh before the
mod was vendored. So the mod carries `relink()`, the same three lines
`dotfiles-jchook` already has and the case `docs/mods.md` warns about under "A
link into `$HOME` is not a seed":

```sh
relink() { # relink <target> <link>
  if [ ! -L "$2" ]; then rm -rf "$2"; fi
  ln -sfn "$1" "$2"
}
```

That is deliberate duplication, and it is what
[para ships the helpers](#para-ships-the-helpers) already decided, since `para`
owns the volume's existence and not the discipline about what may overwrite what
inside it.

**Repeat cost.** gh stops being the fallback it is today. `authorize_key`
currently runs only after the first clone fails, so it touches GitHub at most
once per workspace, while a `clone:before` runs on every `para up`. `gh auth
status` is no help as the guard, because it is a round trip to api.github.com
rather than a local check, so using it puts the network ahead of every clone and
an offline box or an expired token fails on a path that used to be skipped
entirely. Guard on the shared volume instead, where the key already lives:

```sh
relink "$PARA_SHARED/gh" ~/.config/gh    # every run, it is cheap and local

marker="$PARA_SHARED/gh/.key-authorized"
if [ -n "${PARA_GH_AUTH:-}" ] && [ ! -f "$marker" ] && authorize_key; then
  touch "$marker"
fi
```

Only past both conditions does the mod talk to GitHub, so the second `para up`
and every one after it costs nothing. Without the marker, a passing `gh auth
status` would still fall through to `gh ssh-key add` on every boot, posting a
duplicate-key write that today's `|| true` swallows in silence. Deleting the
marker is the retry, and it lives on the shared volume because the key does, so
one authorization covers every workspace of the project.

That guard rewrites `authorize_key`, whose template version ends `|| true` and
never fails. The mod's copy treats an already-authorized key as success and
returns nonzero on real failure (offline, expired token, missing scope), so
the marker records authorized rather than attempted. A failure leaves the
marker absent and the hook alive, because the call sits in the `if` condition
where `set -e` does not apply, and the next `para up` retries.

That also makes `clone:before` real. `docs/mods.md` currently says no bundled
template opens a point.

## Landing order

1. **`$PARA_HELPERS`.** Engine only, additive, independent of everything below.
   Templates and the mod switch to the source line above and delete
   their copies. `test/fixtures/hello` keeps both of its own `hooks/helpers`,
   the project's and `mods/e2e-mod`'s, so the `$PARA_HOOKS/helpers` path stays
   covered, and `test_bundled_helpers_do_not_drift` goes away with the copies it
   guards.

   `.shellcheckrc`'s `source-path=SCRIPTDIR` resolves `. "$PARA_HOOKS/helpers"`
   by basename, and the new line gives it no literal component to resolve, so
   each one needs a directive above it or `bin/lint` fails on every hook. That
   directive is `# shellcheck source=/dev/null`, which is already what
   `bin/para` uses for its two runtime sources, not a `disable=SC1090`. A
   `source=<path>` would be the wrong tool, since a scaffolded template has no
   path back to `libexec/`, but `/dev/null` names no path and silences the
   warning cleanly. Confirmed against shellcheck 0.10.0.

   Add `test_helpers_are_packaged` beside the three that already exist
   (`test_run_hook_is_packaged`, `test_templates_are_packaged`,
   `test_mods_are_packaged`), its own assert per the convention that file
   states. `libexec/helpers` rides in on `package.json`'s existing `libexec`
   entry today, so nothing fails yet, and narrowing that entry later would ship
   a para whose every hook dies on a missing `$PARA_HELPERS` with a green suite.
2. **`para mod add a b c`.** Several names per invocation. `cmd_mod` currently
   validates and copies one name inline, so looping it would vendor `docker` and
   `gh` and then die on `dcoker`, leaving `.paraspace/mods` half-populated and
   the commands warning printed for only some of them. Resolve every `src` first
   and copy only once they all exist, which is the shape that needs no
   partial-failure story.
3. **The composition change.** `templates/void` replaces both templates,
   `mods/docker` and `mods/gh` come out of it, docs follow in the same change.
   `cmd_init`'s `template="${template:-void-docker-gh}"` becomes `void`, or a
   bare `para init`, which is the form `docs/project-setup.md` shows, dies on
   a template that no longer exists.
4. **e2e coverage** for a mod-opened hook point and for a mod filling `boot`,
   since the fixture currently exercises neither.

Not in this work, but write it down while it is visible: a `TODO.md` entry for
para probing the `PARA_ROUTES` ports once `boot` returns, per option 3 under
[The docker mod owns `boot`](#the-docker-mod-owns-boot).

## Docs impact

Step 3 is mostly prose. Pages naming a template or the mod, all of which need a
pass: `TODO.md`, `docs/agents.md`, `docs/commands.md`,
`docs/cookbook.md`, `docs/image.md`, `docs/mods.md`, `docs/parafile.md`,
`docs/project-setup.md`, `docs/shared-auth.md`, `docs/versioning.md`, plus
`CLAUDE.md` and the template and mod READMEs.

Code and tests name them too, and `npm run check` gates every release. Four
places hold a template name. `cmd_init`'s default in `bin/para`, the
`para init void-minimal` and `para init --list` assertions in
`test/cli/test_cli.sh`, `test_templates_are_packaged` in
`test/cli/test_run_hook.sh`, which asserts
`templates/void-docker-gh/.paraspace/Parafile` is in the tarball, and
`docs/image.md`'s deep link to a template hook on GitHub, which 404s after the
rename.

Specifics worth not losing:

- `docs/mods.md` loses the paragraph telling mod authors to ship a
  byte-identical `helpers` and the `helpers` entry in its layout block, drops
  "No bundled template opens any", and gains four things from above: the
  `zshrc.d` drop-in convention and its no-`compdef` rule, the
  source line, the dependency posture, and the point-marker a hard requirement
  probes. Its "A link into `$HOME` is not a seed" paragraph stays where it is
  and `mods/gh` is now a second thing pointing at it.
- `docs/parafile.md`'s "Your own vars" illustrates the idea with exactly the two
  keys this moves, `PARA_GH_AUTH` "in the default template" and the
  `PARA_PREPULL_IMAGES` "the templates' `hooks/image-build` reads". After step 3
  both live in mods and neither appears in any template, so the only worked
  example on the page points at files that no longer exist. It stays the right
  example, re-attributed to `mods/gh` and `mods/docker`, and it is the natural
  place to say a mod's knobs are ordinary project vars with no `Parafile` of
  their own.
- `docs/hooks.md` gains `PARA_HELPERS` in the injected environment.
- `docs/versioning.md` gains bullets under "Changes inside contract 1" for
  `~/.paraspace/helpers`, for the helper functions becoming contract surface,
  and for a project's own `.paraspace/helpers` being replaced. Those land with
  step 1, not step 3.
- `.vitepress/config.mts` needs no new page, but check the sidebar for template
  names in link text.

## Open

- **Where is zsh's global rc on Void?** `/etc/zsh/zshrc` or `/etc/zshrc`,
  compiled in, and the whole drop-in mechanism is dead silently if the base
  writes the loop to the wrong one. Answer it before writing the base's
  `image-build`. Blocking.
- Do docker-cli and github-cli on Void ship zsh completions into
  `/usr/share/zsh/site-functions`? Not blocking either way, since a mod whose
  package doesn't can generate one there from `image-build`. It only decides
  whether the mods carry that line.
- Does the base install `tmux`? It is ergonomics rather than contract per
  `docs/image.md`, and `dotfiles-jchook` installs it already. Leaning yes for
  the base, since `para sh` into a long-running task wants it.
