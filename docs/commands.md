# Commands

`para --help` is always current for the build you're running (bare `para` prints
a short everyday cheat-sheet, and the full text also reports the resolved
`PARA_*` values for the current project); this page organizes
the same surface. Only `up`, `image-build`, and `config-sync` must run inside a
project (a `.paraspace/` dir, found from `$PWD` up); everything else — including
`para init`, which is how you *create* that dir — works from anywhere.

## Host lifecycle

| Command | What it does |
|---|---|
| `para start` | backend up (macOS: colima) + para Caddy on `:8443` (or `$PARA_HTTPS_PORT`); `para up` runs this for you when needed |
| `para stop` | stop para Caddy (workspaces + backend untouched) |

## Workspaces

| Command | What it does |
|---|---|
| `para up <name>` | launch a workspace: clone, provision, boot the stack. Idempotent — on an existing/stopped workspace it (re)starts and reconverges |
| `para down <name>` | stop its container (data + registry entry preserved; `up` resumes it) |
| `para rm <name>` | delete a workspace |
| `para ls [-a\|--all] [--names]` | list this project's workspaces (IPs, state, URLs); `-a`/`--all` lists every project's; `--names` prints bare names (feeds completion). Combinable — `--all --names` spans projects |
| `para sh <name> [-c <command>]` | shell into the clone. With `-c`, run a single command in the clone instead — stdin/stdout piped through, a pty only when both are terminals, and para exits with the command's status: `para sh ws1 -c 'just check'` (see [the note below](#running-one-command-with--c)) |
| `para run <name>` | tmux session: claude in window 1, a shell in window 2 (re-attaches) |
| `para claude <name>` | straight into `claude` in the clone |
| `para web <name>` | open `https://<name>.<domain>:$PARA_HTTPS_PORT` (port-less when the port is `443` — see [Workspace URLs](./urls.md)) |
| `para reconcile [--prune]` | rebuild the registry from Incus (workspaces are [self-describing](./how-it-works.md#workspaces-are-self-describing)); `--prune` drops rows with no live container |

### Running one command with `-c`

`para sh <name> -c '<command>'` runs a single command in the clone and exits
with its status, so it composes with the host shell:

```sh
para sh ws1 -c 'make test' || echo "tests failed"
echo data | para sh ws1 -c 'cat > /tmp/in'
diff <(para sh ws1 -c 'cat package.json') package.json
```

The command is handed to bash as one string, so pipes, redirects and `&&` work
as written — quote the whole thing, or the host shell eats them first. Two
things to know:

- It is a **non-interactive login bash**. `/etc/profile` and `~/.bash_profile`
  are read; the interactive rc your `skel/` installs (`~/.zshrc`) is **not** —
  so `PATH` entries added there are missing. If you need them, ask for that
  shell explicitly: `para sh ws1 -c 'zsh -ic "npm test"'`.
- A pty is allocated only when para's own stdin *and* stdout are terminals, so
  `-c 'vim …'` works from a terminal while `| tee`, `> file` and `$(…)` stay
  byte-clean (a pty would translate `\n` to `\r\n` and echo NULs into them).
  `PARA_NONINTERACTIVE=1` forces the no-pty path. With a pty, stderr merges
  into stdout; without one the two stay separate.

There is no `para exec`: this is that command, and `sh` is where it lives
because the command runs through a login shell in the clone rather than being
`exec`'d as bare argv the way `incus exec` and `docker exec` do.

## Project & image

| Command | What it does |
|---|---|
| `para init [<template>] [--list\|--names\|-f\|--force\|--full]` | scaffold `.paraspace/` from a bundled template (default `void-docker-gh`), skipping existing files; `-f`/`--force` overwrites, `--full` copies the whole template tree |
| `para image-build [-q\|-v] [-i]` | build + publish the base image: launch `$PARA_BASE_IMAGE`, run `$PARA_IMAGE_BOOTSTRAP` then `.paraspace/image-build.sh` in it, publish as `$PARA_IMAGE`; `-q`/`--quiet` and `-v`/`--verbose` force or keep incus progress bars; `-i`/`--from-current` (alias `--incremental`) layers onto the existing image for fast iteration — see [The image contract](./image.md) |

## Config & auth

| Command | What it does |
|---|---|
| `para key` | print this machine's para pubkey — see [Git authentication](./git-auth.md) |
| `para config-set KEY VALUE` | persist a `PARA_*` override to the user config (`${XDG_CONFIG_HOME:-~/.config}/para/config`) |
| `para config-import <name> <path>…` | copy host dotfiles into workspace `<name>`'s shared volume |
| `para config-sync [<name>]` | re-push `skel/` to the shared volume — dotfile edits go live in every workspace, no image rebuild |
| `para install [prefix]` | install the `para` script to `PREFIX/bin/para` (default `~/.local`) + stage templates for `para init`; re-run to update |

## Shell completion

`para completions <bash|zsh>` prints a completion script to stdout. Source it
from your shell rc:

```sh
# ~/.bashrc
source <(para completions bash)

# ~/.zshrc
source <(para completions zsh)
```
