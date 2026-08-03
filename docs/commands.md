# Commands

`para --help` is always current for the build you're running; this page is the
same surface with room to explain. It comes in two halves: the **engine verbs**
below, which are fixed, and the **project commands** your repo adds, including
any a [mod](./mods.md) brought with it.

Only `para up`, `para image …` and `para mod add` must run inside a project (a
`.paraspace/` directory, found from `$PWD` upward). Everything else works from
anywhere, including `para init`, which is how you *create* one.

## Workspaces

| Command | What it does |
|---|---|
| `para up <name>` | create or reconverge a workspace, then boot it: launch, attach the shared volume, push `.paraspace/`, run the hooks, publish the routes. Idempotent |
| `para down <name>` | stop the container. Data is kept; `para up` resumes it |
| `para rm <name>` | delete the workspace. The shared volume is untouched |
| `para ls [-a\|--all] [--names]` | list this project's workspaces; `--all` spans every project, `--names` prints bare names (this is what completion reads) |
| `para sh <name> [-c <command>]` | a shell in the clone, or [one command in it](#running-one-command) |

`up`, `down` and `rm` converge. They warn and succeed when the world is already
in the state you asked for, so teardown scripts and retries stay simple.

```
$ para ls
NAME                 STATE     IP               PROJECT        URL
fix-login            RUNNING   10.62.14.201     myapp          https://fix-login.paraspace.dev
dark-mode            STOPPED   10.62.14.202     myapp          https://dark-mode.paraspace.dev
```

### Running one command

`para sh <name> -c '<command>'` runs one command in the clone and exits with its
status, so it composes with your host shell:

```sh
para sh ws1 -c 'make test' || echo "tests failed"
echo data | para sh ws1 -c 'cat > /tmp/in'
diff <(para sh ws1 -c 'cat package.json') package.json
```

The command is handed to bash as a single string, so pipes, redirects and `&&`
work as written, but quote the whole thing or your host shell eats them first.
Two caveats:

- It's a **non-interactive login bash**, so `/etc/profile` and `~/.bash_profile`
  are read but the interactive rc your `skel/` installs is not, and `PATH`
  entries added there are missing. Ask for that shell explicitly if you need it,
  with `para sh ws1 -c 'zsh -ic "npm test"'`.
- A pty is allocated only when para's own stdin *and* stdout are terminals, so
  `-c 'vim …'` works from a terminal while `| tee`, `> file` and `$(…)` stay
  byte-clean. `PARA_NONINTERACTIVE=1` forces the no-pty path.

There is no `para exec`; this is it.

## Host

| Command | What it does |
|---|---|
| `para caddy <start\|stop\|status>` | the para Caddy that serves `*.$PARA_DOMAIN`. `para up` starts it for you; `stop` leaves workspaces running |
| `para doctor` | check this machine and print the resolved config (see [Troubleshooting](./troubleshooting.md)) |
| `para config <edit\|init\|path>` | open, seed, or locate the [user config](./parafile.md#user-config-not-parafile) |

The user config is hand-edited, so `config` just gets you to it:

```sh
para config edit    # opens it in $VISUAL/$EDITOR, creating it first if needed
```

That's the only one you need day to day. `init` seeds the file without opening
it (`--force` overwrites); `path` prints its location. Both are for scripting.

## Project

| Command | What it does |
|---|---|
| `para init [<template>] [--list] [-f\|--force] [--full]` | scaffold `.paraspace/` from a bundled template (default `void-docker-gh`), skipping files that already exist; `--full` copies the whole template tree, not just `.paraspace/` |
| `para mod add <name>` | vendor a bundled [mod](./mods.md) into `.paraspace/mods/<name>/`, replacing it if it's already there. `--list` in place of a name prints what this `para` ships |
| `para image build [-i\|--from-current]` | build and publish the project's base image; `-i` layers onto the current one for fast iteration (see [The image contract](./image.md)) |
| `para image status` | when `$PARA_IMAGE` was built, and from what base |
| `para image rm` | delete `$PARA_IMAGE`. Running workspaces are clones and keep running |
| `para commands` | list the verbs this project adds, its mods' included, one per line |
| `para completions <bash\|zsh>` | print a completion script |

```sh
source <(para completions bash)   # ~/.bashrc
source <(para completions zsh)    # ~/.zshrc
```

## Project commands

A project adds its own `para` verbs by dropping an executable in
`.paraspace/commands/`. `para <verb> [args…]` runs it **on the host**, with your
tty, with every `PARA_*` exported, and with its arguments passed through
untouched.

```sh
#!/usr/bin/env bash
# summary: open a workspace in the browser
set -euo pipefail
url="https://$1.$PARA_DOMAIN"
[ "$PARA_HTTPS_PORT" = 443 ] || url="$url:$PARA_HTTPS_PORT"
xdg-open "$url"
```

Save that as `.paraspace/commands/web`, make it executable, and `para web ws1`
works. Three variables exist for exactly this. **`PARA_BIN`** is the path to
this `para`, so a command can call back without relying on `$PATH`.
**`PARA_PROJECT_DIR`** is the project directory. **`PARA_MOD_DIR`** is the
directory a mod was vendored into, and para sets it only when the command came
from a [mod](./mods.md).

Because [`para sh`](#running-one-command) owns all the terminal handling,
commands that drive something inside a workspace stay one-liners:

```sh
#!/usr/bin/env bash
# summary: run Claude Code in the workspace clone
exec "$PARA_BIN" sh "$1" -c "exec claude --name $1"
```

A few rules keep this safe to have in a repo you cloned:

- **Engine verbs always win.** A project can't redefine `para up`. `para doctor`
  warns about a command that's shadowed and therefore never runs.
- **Nothing runs invisibly.** Everything discovered is listed under `PROJECT
  COMMANDS` in `para --help`, with the `# summary:` line from the file if it has
  one.
- They run with **your** privileges, on the host, like any other script in the
  repo. Read them before you run them.

The bundled templates ship a few as examples, not as features, so delete the
ones you don't want:

| Template | Commands |
|---|---|
| `void-docker-gh` (the `para init` default) | `key`, `web` |
| `void-minimal` | none |

A [mod](./mods.md) you vendored can add verbs too, listed the same way with the
mod named beside them. [The precedence rules are
there](./mods.md#verbs-a-mod-brings).
