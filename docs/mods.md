# Mods

A template is a **starting point** you copy once and own forever. A mod is a
**dependency** you copy, update, and don't edit.

So when you want your dotfiles, or a credential helper, or a language runtime in
a project that already has a `.paraspace/`, you vendor the piece instead of
forking a whole template to get it:

```sh
para mod add dotfiles-jchook
para image build            # if the mod fills image-build (its README says)
para up feat-x
```

## Adding one

```sh
para mod add --list         # the mods this para ships
para mod add <name>         # copy one into .paraspace/mods/<name>/
```

That is a **copy**, not a fetch. The mod lands in your repo, you read it before
you run it, and it shows up in your own git history like any other file. `para
up` never goes looking for it.

Adding the same mod again **replaces** the directory, which is the update path,
so commit first. There is no `para mod rm`, `ls` or `update`, because
`rm -rf .paraspace/mods/<name>`, `ls .paraspace/mods/` and `add` already are.

> [!NOTE]
> `para mod add` installs the mods this `para` ships. A git URL is not
> supported yet.

## What's in one

A mod is a directory shaped like a `.paraspace/`:

```
.paraspace/mods/dotfiles-jchook/
  README.md
  hooks/{provision,image-build,helpers}
  skel/{zshrc,nvim,tmux,claude,claude.json,bin}
  commands/{claude,run}
```

`para up` pushes your whole `.paraspace/` into the workspace, so a mod arrives
with it and its hooks run there like yours do.

The one entry a mod does **not** have is a `Parafile`. Mods are never sourced
on the host, so a mod's knobs are ordinary `PARA_*` variables it defaults in its
own hook and documents in its README.

## Verbs a mod brings

A mod's `commands/` become `para <verb>` like the project's own. See
[Commands](./commands.md#project-commands) for what a command is, and note that
one runs on your host rather than in a workspace, so `para mod add` warns you
when a mod ships any. Past the engine's own verbs, two rules settle a name:

- **Your own `commands/` beats any mod's.** Dropping a file in
  `.paraspace/commands/<verb>` is how you override one you don't like.
- **More than one mod defining a verb is refused**, and the error names every
  file, because para promises no order between mods. Delete one, or shadow it
  with your own.

`para --help` names the mod each verb came from, and marks a verb that can't run;
`para doctor` reports why before you trip over it.

A mod's command reaches its own files through **`$PARA_MOD_DIR`**, e.g.
`cp -R "$PARA_MOD_DIR/skel/nvim" ~/.config/nvim`. `$PARA_HOOKS` and `$PARA_SKEL`
are no help, because they name paths inside a workspace, and para keeps them
unset on the host so a command can't be handed one that doesn't exist.

## Hooks a mod fills

`provision`, `boot` and `image-build` run every time. para runs each name
through the project's hook first, then each mod's, in
[no promised order](./hook-points.md#filling-one).

Any other name is a [hook point](./hook-points.md), and a mod filling one
**only runs where that point is opened**. No bundled template opens any, so if a
mod's README says it fills `clone:before`, that line is yours to add:

```sh
# .paraspace/hooks/provision, wherever the ordering actually matters
"$PARA_RUN_HOOK" clone:before
```

## Writing one

The hook environment is [the same one your own hooks
get](./hooks.md#the-environment-para-injects), with `$PARA_HOOKS` and
`$PARA_SKEL` pointing at **the mod's** `hooks/` and `skel/`. So a mod's hook is
written exactly like a project's (`. "$PARA_HOOKS/helpers"`, `cp
"$PARA_SKEL/zshrc" …`) and needs no idea where it was installed.

What it must not assume:

- **The project's `helpers`.** That's one template's habit, not para's contract,
  and `$PARA_HOOKS/helpers` resolves to the mod's own copy anyway. Ship one,
  copied from any bundled mod or template, where they're byte-identical on
  purpose and a test keeps them that way.
- **Its position, or that any other mod ran.** Read another mod's artifacts
  defensively, [through a file](./hooks.md#passing-something-to-a-later-hook).
- **A terminal.** `provision` may prompt when there's a human on both ends;
  `image-build` never can, because there is no stdin at all in the builder.
- **The distro.** A build hook is package-manager-coupled by nature. Say in the
  README which base you target.

### Own your files

**A mod seeds; it never replaces.** Write a file only when nothing is there, and
never touch it again. Then edits survive every `para up` forever, and `rm` plus
one more `up` is a reliable way to take a seed back:

```sh
seed() { if [ -e "$2" ]; then return 0; fi; cp -R "$1" "$2"; }
seed "$PARA_SKEL/nvim" "$PARA_SHARED/nvim"
```

That rule holds only if you seed somewhere nothing else writes. **Claim a flat
name on the shared volume only when it's yours**; where a template already owns
one, seed under your own directory and point the symlink there instead:

```sh
seed "$PARA_SKEL/zshrc" "$PARA_SHARED/dotfiles-jchook/zshrc"
ln -sfn "$PARA_SHARED/dotfiles-jchook/zshrc" ~/.zshrc
```

Now nothing has to arbitrate. `~/.zshrc` is a link, mods run after the project,
and the last link written wins. The template's file stays the template's.

Name everything you write after the mod, `$PARA_SHARED/<mod>/` and
`/etc/profile.d/<mod>.sh`. **Two mods claiming `~/.zshrc` is a conflict para
will not detect**, and naming is all that keeps them apart.

> [!WARNING]
> A shared volume outlives every workspace on it, so assume there is real work
> in there, an editor config someone has tuned for months, a tool's login and
> history. `rm -rf` on a path you did not create is how a mod eats it.

## What it costs

**Mods are not reversible.** Removing one doesn't undo what it wrote (the files
on the shared volume, the symlinks in existing workspaces, the packages in the
image). Nor does adding one reach backwards. On a volume you have already been
using, a mod seeds only what isn't there yet, so a path you already had keeps
whatever was in it and you get a half-applied setup with nothing said about it.

To take a seed the mod skipped, move your version out of the way and converge.
Seeding guards on the destination, so the next `up` fills the gap:

```sh
para sh feat-x -c 'mv /para/shared/nvim /para/shared/nvim.mine'
para up feat-x
```

**A link into `$HOME` is not a seed.** `ln -sfn` onto a real directory nests
inside it, so a mod that links `~/.claude` deletes what a workspace already had
there. Its README lists every path it claims; read that before the first `up`.

**A mod with an `image-build` hook does nothing until you rebuild.** Add the
mod, run `para up`, and the dotfiles are there but the editor they configure
isn't. Nothing warns you, because [para tracks no image drift at
all](./image.md). Read the mod's README for whether it fills `image-build`, and
budget the minutes if it does.
