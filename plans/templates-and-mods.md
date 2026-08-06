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
that, and it earns its keep by differing from `void-docker-gh` in a clone block
and one `Parafile` key.

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
block and `PARA_ORIGIN`. Two seventy-line Parafiles kept in sync is not worth
that, and a template is a thing you own after `init`, so "I have no repo yet" is
deleting a block from your own file.

Ship one `void`, clone active, with the Parafile comment saying what to cut.
Around 200 lines of near-duplicate content goes away, and the README funnel goes
from one command to three, which puts the mod system on the front page instead
of three pages in.

### Mods compose through drop-in directories, not ordering

The base owns `/etc/zsh/zshrc.d/` and its `skel/zshrc` sources it. A mod that
wants shell integration writes `/etc/zsh/zshrc.d/<mod>.zsh`, the same way
`dotfiles-jchook` already writes `/etc/profile.d/dotfiles-jchook.sh` for
`$BROWSER`. `/etc/profile.d` stays for environment that has to reach
non-interactive login shells too.

Then the docker mod never learns zsh exists, the zshrc never learns docker does,
and no order can be wrong because nothing overwrites. Completions come with the
distro packages, so a zshrc running `compinit` picks up whatever is installed.
**Verify that on Void for docker-cli and github-cli before relying on it.**

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
   adds a three-line `image-build` beside it that dies with the fix named.

Above all three, the project's own `provision` opens points and the person who
vendored both mods decides the order. That is the right owner.

**Refused:** a `requires:` field, transitive `para mod add`, a resolver. That is
a package manager, and `para mod add` is defensible because it is a copy you
read, offline, with no graph behind it. It would also mean giving mods a
manifest, and the one entry a mod does not have is the best property mods have.

**Also refused:** promising alphabetical mod order, even though `paraspace_dirs`
makes it true today. Once promised, people reach for `10-docker` /
`20-dotfiles`, and numeric prefixes break `para mod add docker` landing in
`mods/docker`, which breaks re-adding as the update path.

### para ships the helpers

Not for deduplication. `interactive()` encodes **para's own rule** about when a
hook may prompt, reading `PARA_NONINTERACTIVE`, which para sets and honors, and
the color-on-tty check exists so hook output matches para's output. Three
user-editable copies of engine semantics is a drift risk.

- `libexec/helpers` beside `libexec/run-hook`, pushed to `~/.paraspace/helpers`
  on every push, mode 0644 since it is sourced rather than run.
- Injected as `$PARA_HELPERS`, so a hook does `. "$PARA_HELPERS"`.
- `~/.paraspace/helpers` becomes a name para owns, beside `env`, `host.env` and
  `run-hook`.
- Additive, so `PARA_CONTRACT` stays 1. A project with its own `hooks/helpers`
  keeps working untouched.

**Set it on the host too.** `$PARA_HOOKS` and `$PARA_SKEL` are unset for host
commands because they name paths inside a workspace, and that reasoning does not
apply here, since para ships the file and knows where it is on both sides. Point
it at `$(pkg_root)/libexec/helpers` and `commands/key` and `commands/web` stop
hand-rolling `echo >&2; exit 1`.

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
to be shell in the mod's own hook no matter what, and once that line is written
the engine feature adds nothing:

```sh
[ -n "${PARA_HELPERS:-}" ] || die "this mod needs a para that injects \$PARA_HELPERS. Upgrade paraspace, then: para doctor"
```

Breaking changes are already caught from the other side, at the project level,
before anything launches. The gap is additive features only, and `$PARA_HELPERS`
is the first one worth noticing. If per-feature probes ever stop reading well,
the cheap fix is a minor on the contract (para exports `1.3`, projects still pin
the integer `1`, mods compare two integers). Not worth building for one feature.

### The docker mod owns `boot`

`docker compose up -d --wait` moves into the mod, guarded on a compose file
existing in the clone, so the demo works untouched and `--wait` honors the
readiness contract. The template's `boot` becomes today's `void-minimal` one.

That does put policy in a mod. The alternative is the template carrying a
commented compose line, which makes the quick start a four-step with an edit in
the middle. The mod's README states what it boots.

`PARA_PREPULL_IMAGES` and the overlayfs refusal move with it, and become the
docker mod's own documented knobs, which is what `docs/mods.md` says a mod's
`PARA_*` vars are.

## Shape

```
templates/void/.paraspace/
  Parafile            contract, image base + bootstrap, origin, ready, routes
  hooks/image-build   base packages, writable /tmp, the user, sudoers, zshrc.d
  hooks/provision     seed the volume, link $HOME, clone:before, clone, .env
  hooks/boot          nothing to boot, with the compose line shown
  skel/zshrc          sources /etc/zsh/zshrc.d/*.zsh
  commands/{key,web}

mods/docker/
  hooks/image-build   docker + compose, runit, driver refusal, group, prepull,
                      /etc/zsh/zshrc.d/docker.zsh, then RUN_HOOK docker:after
  hooks/boot          compose up --wait, if the clone has a compose file
  README.md           targets Void/xbps, PARA_PREPULL_IMAGES, dir/ext4 pool

mods/gh/
  hooks/image-build   github-cli
  hooks/clone:before  authorize this machine's key when PARA_GH_AUTH is set
  hooks/provision     link $PARA_SHARED/gh at ~/.config/gh
  README.md           PARA_GH_AUTH

mods/dotfiles-jchook/  unchanged, minus its helpers copy
```

The clone flow in the template gets simpler, since the gh branch leaves it:

```sh
"$PARA_RUN_HOOK" clone:before        # the gh mod uploads the key here
if ! clone; then
  stage "Authorize this machine's para key on your git host:"
  cat ~/.ssh/id_ed25519.pub >&2
  pause "Press Enter once the key is added"
  clone || die "clone still failing. Re-run: para up $PARA_NAME"
fi
```

That also makes `clone:before` real. `docs/hook-points.md` currently describes a
mechanism no bundled template opens.

## Landing order

1. **`$PARA_HELPERS`.** Engine only, additive, independent of everything below.
   Templates and the mod switch to `. "$PARA_HELPERS"` and delete their copies.
   `test/fixtures/hello` keeps its own `hooks/helpers` so the
   `$PARA_HOOKS/helpers` path stays covered, and the test enforcing that the
   copies are byte-identical goes away with them.
2. **`para mod add a b c`.** Several names per invocation. Small.
3. **The composition change.** `templates/void` replaces both templates,
   `mods/docker` and `mods/gh` come out of it, docs follow in the same change.
4. **e2e coverage** for a mod-opened hook point and for a mod filling `boot`,
   since the fixture currently exercises neither.

## Docs impact

Step 3 is mostly prose. Pages naming a template or the mod, all of which need a
pass: `README.md`, `docs/agents.md`, `docs/commands.md`, `docs/cookbook.md`,
`docs/image.md`, `docs/mods.md`, `docs/project-setup.md`, `docs/shared-auth.md`,
`docs/versioning.md`, plus `CLAUDE.md` and the template and mod READMEs.

Specifics worth not losing:

- `docs/mods.md` loses the paragraph telling mod authors to ship a
  byte-identical `helpers`, and gains the drop-in convention plus the
  dependency posture above.
- `docs/hooks.md` gains `PARA_HELPERS` in the injected environment.
- `docs/hook-points.md` drops "no bundled template opens any", since one does
  now.
- `docs/versioning.md` gains bullets under "Changes inside contract 1" for
  `~/.paraspace/helpers` and for the helper functions becoming contract surface.
- `.vitepress/config.mts` needs no new page, but check the sidebar for template
  names in link text.

## Open

- Do docker-cli and github-cli on Void actually ship zsh completions into
  `/usr/share/zsh/site-functions`? The drop-in design assumes so and falls back
  to the mod writing its own `zshrc.d` file if not.
- Does the base install `tmux`? It is ergonomics rather than contract per
  `docs/image.md`, and `dotfiles-jchook` installs it already. Leaning yes for
  the base, since `para sh` into a long-running task wants it.
