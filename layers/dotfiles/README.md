# dotfiles

A personal zsh, tmux, Neovim, and Claude Code environment for the bundled Void
base.

```sh
para add dotfiles
para image build
para up feat-x
```

The image hook installs the tools these files use. The provision hook seeds
editable state once on the shared volume, then links it into each workspace.
Existing seeds are never replaced.

The layer owns `$PARA_SHARED/dotfiles/zshrc`, `nvim`, `nvim-data`, `tmux`,
`claude`, `claude.json`, and `bin/open-url`. It links those paths to
`~/.zshrc`, `~/.config/nvim`, `~/.local/share/nvim`, `~/.config/tmux`,
`~/.claude`, and `~/.claude.json`. A real directory at one of those home paths
is replaced by the link, so move any data you want to retain before the first
`para up`.

The image also writes `/etc/gitconfig` aliases,
`/etc/profile.d/dotfiles.sh`, and the Claude Code managed policy. The layer adds
the host-side `para claude` and `para run` commands; read `commands/` before
running them.
