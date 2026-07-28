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
  skel/{zshrc,nvim,tmux,claude}
```

Which is why almost nothing had to be invented for it: `para up` already pushes
your whole `.paraspace/` into the workspace, so a mod arrives with it and its
hooks run there like yours do.

Two entries a mod does **not** have. There is no `Parafile` — mods are never
sourced on the host, so a mod's knobs are ordinary `PARA_*` variables it
defaults in its own hook and documents in its README. And there is no
`commands/`: `para <verb>` resolves only against the project's, so a mod that
wants to ship you a verb has to tell you to copy it in.

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
  and `$PARA_HOOKS/helpers` resolves to the mod's own copy anyway. Ship one.
- **Its position, or that any other mod ran.** Read another mod's artifacts
  defensively, [through a file](./hooks.md#passing-something-to-a-later-hook).
- **A terminal.** `provision` may prompt when there's a human on both ends;
  `image-build` never can — there is no stdin at all in the builder.
- **The distro.** A build hook is package-manager-coupled by nature. Say in the
  README which base you target.

### Own your files

A mod **owns what it writes**, and where it has to replace a file the base
already wrote, it does so **once, behind its own sentinel**:

```sh
mine="$PARA_SHARED/dotfiles-jchook"          # named after the owner
mkdir -p "$mine"
if [ ! -e "$mine/zshrc" ]; then
  cp "$PARA_SKEL/zshrc" "$PARA_SHARED/zshrc"
  touch "$mine/zshrc"
fi
```

The base seeds, the mod replaces, and then neither touches it again — so your
own edits survive both, on every `para up` forever. Name everything you write
after the mod: `$PARA_SHARED/<mod>/`, `/etc/profile.d/<mod>.sh`. **Two mods
claiming `~/.zshrc` is a conflict para will not detect**, and naming is all that
keeps them apart.

## What it costs

**Mods are not reversible.** Removing one doesn't undo what it wrote — the files
on the shared volume, the symlinks in existing workspaces, the packages in the
image. Nor does adding one reach backwards: on a shared volume that's already
seeded, a mod writes its *new* paths and skips whatever the base already wrote,
so you get the mod's editor with the base's shell, half-applied and silent. Undo
it by hand, then converge:

```sh
para sh feat-x -c 'rm /para/shared/zshrc'
para up feat-x
```

**A mod with an `image-build` hook does nothing until you rebuild.** Add the
mod, run `para up`, and the dotfiles are there but the editor they configure
isn't. Nothing warns you — [para tracks no image drift at all](./image.md) — so
read the mod's README for whether it fills `image-build`, and budget the minutes
if it does.
