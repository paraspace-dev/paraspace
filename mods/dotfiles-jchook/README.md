# dotfiles-jchook

A full personal dev environment in every workspace of a project — zsh, tmux,
Neovim and Claude Code — without forking a template to get it.

```sh
para mod add dotfiles-jchook
para image build                 # the toolchain is baked in, so this is required
para up demo
```

## What it fills

| Hook | What it does |
|---|---|
| `image-build` | the Neovim toolchain, the shell tools the zshrc reaches for, Claude Code, `/etc/gitconfig` aliases, `$BROWSER`, and zsh as the login shell |
| `provision` | seeds `skel/` onto the shared volume and links it into `$HOME` |

It opens no [hook point](https://paraspace.dev/docs/hook-points) of its own.

**Targets [`void-docker-gh`](https://github.com/paraspace-dev/paraspace/tree/main/templates/void-docker-gh).** Two couplings:
the build hook is `xbps`, so another distro means rewriting the package list;
and it installs Claude Code as `$PARA_USER`, so the base's `image-build` has to
have created that user already — which [the image
contract](https://paraspace.dev/docs/image) requires of every base anyway.

## What it claims

On the **shared volume**, written only if nothing is there already and yours from
then on: `tmux/`, `nvim/`, `nvim-data/`, `claude/`, `claude.json`,
`bin/open-url`, and `dotfiles-jchook/zshrc`. Nothing here is ever replaced — if
you have used this volume before, everything you had survives untouched,
including your Claude Code login and history under `claude/`. To take a seed
again, delete it and run `para up`.

The zshrc lives under `dotfiles-jchook/` rather than at `zshrc` because the base
template owns that name. Yours stays exactly where it is; this mod just points
`~/.zshrc` at its own copy instead.

In **`$HOME`**, as symlinks onto the above: `~/.zshrc`, `~/.config/tmux`,
`~/.config/nvim`, `~/.local/share/nvim`, `~/.claude`, `~/.claude.json`. Anything
real already sitting at one of those paths is **deleted**, because `ln -sfn` onto
a real directory would otherwise nest the link inside it — so a workspace that
predates this mod loses its local `~/.claude` in favour of the shared one.

In the **image**: `/etc/gitconfig`, `/etc/claude-code/managed-settings.json`
(`acceptEdits`, highest precedence), `/etc/profile.d/dotfiles-jchook.sh`,
`/usr/local/bin/claude`.

## Neovim: config shared, plugins installed once

The image carries the toolchain — Neovim, Node, `tree-sitter`, `fd`/`rg`/`bat`/
`fzf` — but not the plugins. The config is seeded from `skel/nvim/` onto the
shared volume and linked in at `~/.config/nvim`; plugin, parser and LSP state
lives beside it (`~/.local/share/nvim` → `nvim-data`). So a config edit is live
everywhere at once, and plugins install **once** on first `nvim` launch.

> [!WARNING]
> `nvim-data` is read-mostly at runtime and many workspaces reading it is fine,
> but don't run installs (`:Lazy sync`, a first-launch `:TSInstall`, Mason) in
> two workspaces *simultaneously* — they write the same tree and can corrupt a
> parser or clobber `lazy-lock.json`. Set it up once, then it's just reads.

## Making it yours

It's vendored — the copy under your `.paraspace/mods/` is in your git history,
so edit `skel/` freely and `para up` pushes the change with no image rebuild.
Adding packages or another runtime means editing `hooks/image-build` and
rebuilding.

`para claude` and `para run` aren't here: v1 mods ship no `commands/`. Both are
one-liners you copy into your own `.paraspace/commands/` — see
[Running coding agents](https://paraspace.dev/docs/agents#driving-one).

More about mods: [paraspace.dev/docs/mods](https://paraspace.dev/docs/mods).
