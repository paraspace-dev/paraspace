# void-jchook — a full personal dev environment in a paraspace workspace

The same runnable demo as [`void-docker-gh`](../void-docker-gh) (it clones
[`jchook/docker-caddy`](https://github.com/jchook/docker-caddy), one Caddy service
on `:8080`) — but instead of a bare shell, every workspace comes up carrying a
**complete personal dev environment**, seeded from `skel/` onto the shared volume:

- **zsh** — a git-aware prompt (announces which workspace you're in) and a full
  alias set
- **tmux** — truecolor config
- **Neovim** — the whole config; plugins, treesitter parsers, and LSP servers
  install **once** on first launch (onto the shared volume) and are reused by
  every workspace, not rebuilt per image
- **Claude Code** — installed in the image, with its config/auth on the shared
  volume and a root-owned managed policy (`acceptEdits`)
- a shared **git identity** (with `unstage`/`graph` aliases), one **ssh key** you
  authorize once, and a **`$BROWSER`** helper so `gh`'s device-auth flow works
  with no browser in the container

It's the pattern for "bring my whole workstation setup into every workspace." The
stack itself is the tiny public demo, so it runs standalone before you point it at
your own repo.

```
void-jchook/
  .paraspace/
    Parafile               # identity, the demo origin, one route (:8080)
    image-build.sh         # docker + git + zsh/tmux/Neovim toolchain + Claude Code
    hooks/provision        # seed + link the shared dev env, clone, copy .env
    hooks/boot             # docker compose up -d --wait
    hooks/helpers          # colored output + small guards, sourced by the hooks
    skel/                  # the seeded dotfiles:
      zshrc                #   shell: aliases, git-aware prompt, PATH/editor/browser
      tmux/tmux.conf       #   tmux
      claude/              #   Claude Code settings + statusline
      nvim/                #   the full Neovim config (config only — see below)
      bin/open-url         #   $BROWSER helper for a browserless container
```

## Try it

```sh
bin/para install                        # -> ~/.local/bin/para (once, from a checkout)
para image-build                        # build the base image (pulls the toolchain)
para up demo                            # clone + provision + boot a workspace
para web demo                           # open https://demo.<your PARA_DOMAIN>
para sh demo                            # drop into the configured shell
```

On the **first** `up`, para prints this machine's para ssh key and pauses — add it
to your git host, press Enter, and the clone proceeds. (For a private repo, set
`PARA_GH_AUTH=1` in the `Parafile` and `gh` uploads the key for you instead.)

## Neovim: config shared, plugins installed once

The image carries the nvim **toolchain** (Neovim, Node, `tree-sitter`,
`fd`/`rg`/`bat`/`fzf`) but **not** the plugins. The config is seeded from
[`skel/nvim/`](./.paraspace/skel/nvim) onto the shared volume and symlinked in
(`~/.config/nvim`), and plugin/parser/LSP state lives on the shared volume too
(`~/.local/share/nvim` → `nvim-data`). So a config edit is instantly live
everywhere, and plugins install **once** on first `nvim` launch.

- **Caveat:** `nvim-data` is read-mostly at runtime (many workspaces reading is
  fine), but don't run plugin/parser/LSP installs (`:Lazy sync`, first-launch
  `:TSInstall`, Mason) in two workspaces *simultaneously* — they write the same
  shared tree and can corrupt a parser or clobber `lazy-lock.json`. Set up once,
  then it's just reads.

## Make it yours

Swap the dotfiles under `skel/` for your own, point `PARA_ORIGIN` at your repo,
and adapt the hooks to your stack (`hooks/provision` seeds + clones,
`hooks/boot` brings services up). `para config-sync` pushes `skel/` edits live to
running workspaces with no image rebuild. Add a language runtime in
`image-build.sh` (there's a commented Bun example). Keep the image contract:
docker→overlayfs, a uid-1000 user in the `docker` group, bash + git.

Full schema + the hook/image contracts: [`../../docs/`](../../docs/README.md).
