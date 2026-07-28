# Mods

A template is a **starting point** — copy it once, own it forever. A mod is a
**dependency** — copy it, update it, don't edit it.

So when you want your dotfiles, or a credential helper, or a language runtime in
a project that already has a `.paraspace/`, you vendor the piece instead of
forking a whole template to get it:

```sh
para mod add dotfiles-jchook
para image build            # only if the mod fills image-build — most do
para up feat-x
```

## Adding one

```sh
para mod add --list         # the mods this para ships
para mod add <name>         # copy one into .paraspace/mods/<name>/
```

That is a **copy**, not a fetch: the mod lands in your repo, you read it before
you run it, and it shows up in your own git history like any other file. `para
up` never goes looking for it.

Adding the same mod again **replaces** the directory — that's the update path,
so commit before you run it. Removing one is `rm -rf .paraspace/mods/<name>`,
and `ls .paraspace/mods/` is the list. There is no `para mod rm`, `ls` or
`update`, because the filesystem and git already do all three.

> v1 installs **bundled mods only**. `para mod add <git-url>` is not built yet.

## What's in one

A mod is a directory shaped like a `.paraspace/`:

```
.paraspace/mods/dotfiles-jchook/
  README.md
  hooks/{provision,image-build,helpers}
  skel/{zshrc,nvim,tmux,claude,bin}
  commands/{claude,run}
```

Which is why almost nothing had to be invented for it: `para up` already pushes
your whole `.paraspace/` into the workspace, so a mod arrives with it and its
hooks run there like yours do.

The one entry a mod does **not** have is a `Parafile` — mods are never sourced
on the host, so a mod's knobs are ordinary `PARA_*` variables it defaults in its
own hook and documents in its README.

## Verbs a mod brings

A mod's `commands/` become `para <verb>` like the project's own — see
[Commands](./commands.md#project-commands) for what a command is. Three rules
settle who answers to a name:

- **Engine verbs always win.** Nothing can redefine `para up`.
- **Your own `commands/` beats any mod's.** Dropping a file in
  `.paraspace/commands/<verb>` is how you override one you don't like.
- **Two mods defining one verb is refused**, naming both files, because para
  promises no order between mods and picking one would be a coin toss you can't
  see the result of. Delete one or shadow it with your own.

`para --help` names the mod each verb came from, and `para doctor` reports a
conflict before you trip over it.

> [!WARNING]
> A command runs **on your machine, with your privileges** — not in the
> workspace. `para mod add` says so when a mod ships any. Read them.

A mod's command reaches its own files through **`$PARA_MOD_DIR`** — e.g.
`cp -R "$PARA_MOD_DIR/skel/nvim" ~/.config/nvim`. `$PARA_HOOKS` and `$PARA_SKEL`
are no help: they name guest paths, and para unsets them on the host precisely
so a host path can't cross into a container.

## Which of a mod's hooks run

`provision`, `boot` and `image-build` run for every owner, every time — para
runs each name through the project's hook first, then each mod's, in
[no promised order](./hook-points.md#filling-one).

Any other name is a [hook point](./hook-points.md), and a mod filling one
**only runs where that point is opened**. No bundled template opens any, so a
mod that fills `clone:before` does nothing until you add that one line to your
own `provision`. A mod's README says which names it fills; if one of them isn't
`provision`, `boot` or `image-build`, that's the line you owe it.

## Writing one

The hook environment is [the same one your own hooks
get](./hooks.md#the-environment-para-injects), with `$PARA_HOOKS` and
`$PARA_SKEL` pointing at **the mod's** `hooks/` and `skel/`. So a mod's hook is
written exactly like a project's — `. "$PARA_HOOKS/helpers"`, `cp
"$PARA_SKEL/zshrc" …` — and needs no idea where it was installed.

What it must not assume:

- **The project's `helpers`.** That's one template's habit, not para's contract,
  and `$PARA_HOOKS/helpers` resolves to the mod's own copy anyway. Ship one —
  copy it from any bundled mod or template, where they're byte-identical on
  purpose and a test keeps them that way.
- **Its position, or that any other mod ran.** Read another mod's artifacts
  defensively, [through a file](./hooks.md#passing-something-to-a-later-hook).
- **A terminal.** `provision` may prompt when there's a human on both ends;
  `image-build` never can — there is no stdin at all in the builder.
- **The distro.** A build hook is package-manager-coupled by nature. Say in the
  README which base you target.

### Own your files

**A mod seeds; it never replaces.** Write a file only when nothing is there, and
never touch it again — then edits survive every `para up` forever, and `rm` plus
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

Now nothing has to arbitrate: `~/.zshrc` is a link, mods run after the project,
and the last link written wins. The template's file stays the template's.

Name everything you write after the mod — `$PARA_SHARED/<mod>/`,
`/etc/profile.d/<mod>.sh`. **Two mods claiming `~/.zshrc` is a conflict para
will not detect**, and naming is all that keeps them apart.

> [!WARNING]
> A shared volume outlives every workspace on it, so assume there is real work
> in there — an editor config someone has tuned for months, a tool's login and
> history. `rm -rf` on a path you did not create is how a mod eats it.

## What it costs

**Mods are not reversible.** Removing one doesn't undo what it wrote — the files
on the shared volume, the symlinks in existing workspaces, the packages in the
image. Nor does adding one reach backwards: on a volume you have already been
using, a mod seeds only what isn't there yet, so a path you already had keeps
whatever was in it and you get a half-applied setup with nothing said about it.

To take a seed the mod skipped, move your version out of the way and converge —
seeding guards on the destination, so the next `up` fills the gap:

```sh
para sh feat-x -c 'mv /para/shared/nvim /para/shared/nvim.mine'
para up feat-x
```

**A mod with an `image-build` hook does nothing until you rebuild.** Add the
mod, run `para up`, and the dotfiles are there but the editor they configure
isn't. Nothing warns you — [para tracks no image drift at all](./image.md) — so
read the mod's README for whether it fills `image-build`, and budget the minutes
if it does.
