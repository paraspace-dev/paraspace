# Running coding agents

Run one coding agent per workspace. Each workspace has a working copy,
running services, and a URL you can open.

## One workspace per task

Name the workspace after the task, because the name is also the hostname:

```sh
para up fix-login       # → https://fix-login.paraspace.dev
para up dark-mode
para up flaky-tests
```

Agents in separate workspaces can edit the same file without affecting each
other's checkout. Review and submit their changes as separate PRs.

## Agent permissions

The agent runs in an unprivileged container with no host directories mounted.
You can let it install packages and change files inside the workspace, then
delete the workspace with `para rm`.

The agent still has access to the network and shared credentials:

- Workspaces have outbound network access. Configure an Incus network ACL
  if you need egress filtering.
- The [shared volume](./internals.md#the-shared-home-volume)
  holds the project's key, so an agent can push to whatever that key is
  authorized for. Scope it narrowly if that matters; see
  [Shared authentication](./shared-auth.md).

Your host home directory, including SSH keys and cloud credentials stored
there, is not mounted in the workspace.

## Driving one

Use `para sh` to run an agent or another command in the clone with a PTY:

```sh
para sh fix-login                      # a shell in the clone
para sh fix-login -c 'npm test'        # one command, exits with its status
```

`para add dotfiles` provides `para claude` and `para run`. To define them
yourself, add scripts under `.paraspace/layers/project/commands/`:

```sh
# .paraspace/layers/project/commands/claude ("para claude <ws>")
exec "$PARA_BIN" sh "$1" -c "exec claude --name $1"
```

```sh
# .paraspace/layers/project/commands/run ("para run <ws>"), tmux with claude in one window
exec "$PARA_BIN" sh "$1" -c "
  tmux has-session -t $1 2>/dev/null && exec tmux attach -t $1
  tmux new-session -d -s $1 -n claude \"claude --name $1\"
  tmux new-window  -t $1: -n sh
  exec tmux attach -t $1
"
```

`para sh` handles the terminal. The layer's scripts also quote and forward
arguments, so `para claude ws -p 'write a test'` passes the prompt to Claude
Code as one argument. See [Commands](./commands.md#project-commands).

To make a workspace feel like your own machine, put your dotfiles in your
project layer's `skel/` (`.paraspace/layers/project/skel/`) and have your
provision hook link them in, or add a layer that brings its own (`para add
dotfiles` installs Claude Code, an editor and a shell in one step). The agent's
own config (`CLAUDE.md`, `AGENTS.md`) travels with the repo, so it's already in
the clone.

## Working across several

```sh
para ls
```

```
NAME                 STATE     IP               PROJECT        URL
fix-login            RUNNING   10.62.14.201     myapp          https://fix-login.paraspace.dev
dark-mode            RUNNING   10.62.14.202     myapp          https://dark-mode.paraspace.dev
```

One workspace per window-manager desktop works well: each desktop holds that
task's terminal and its browser tab, and you switch tasks with the keybindings
you already use. `para ls --all` lists workspaces across all projects on the
machine.

## Reviewing and landing

Review changes and run tests inside the workspace:

```sh
para sh fix-login -c 'git diff'        # or: git log --oneline main..
para sh fix-login                      # then push, open a PR, run the suite
```

Open the URL to exercise the change against its own database rather than a
shared one. When the branch has landed:

```sh
para rm fix-login
```

The shared volume survives, and with it your authentication.

## When something's wrong

When an `up` fails for reasons that don't look like your project's, run
`para doctor`. See [Troubleshooting](./troubleshooting.md).
