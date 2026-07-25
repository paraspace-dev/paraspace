# Running coding agents

The workflow para is built for: one agent per workspace, several at a time,
each with a real stack running and a URL you can open.

## One workspace per task

Name the workspace after the task, because the name is also the hostname:

```sh
para up fix-login       # → https://fix-login.paraspace.dev:8443
para up dark-mode
para up flaky-tests
```

Each gets its own clone, its own database, its own stack on its own IP. Two
agents editing the same file in different workspaces never see each other's
edits, so the diffs stay separable and each one becomes its own PR.

`para up` is idempotent — re-running it on an existing workspace restarts and
reconverges rather than erroring, which is the normal loop when you're
iterating on a hook.

## Let the agent off the leash

The reason to run an agent with permissions wide open is that the workspace is
the boundary. It's an unprivileged container with none of your host mounted, so
the agent can install packages, rewrite the tree, and run whatever it likes;
`para rm` resets it.

Two things are *not* isolated, and both are worth deciding about deliberately:

- **the network** — workspaces have ordinary outbound access. para does no
  egress filtering; that's an Incus network ACL if you want it.
- **the git key** — the [shared volume](./internals.md#the-shared-home-volume)
  holds one key per machine, so an agent can push to whatever that key is
  authorized for. Scope it narrowly if that matters; see
  [Git authentication](./git-auth.md).

Everything else — your home directory, your host SSH keys, your cloud
credentials — isn't reachable from inside a workspace, because it was never
mounted there.

## Driving one

Agents are not a para feature. `para sh` gives you a real pty in the clone, and
a project command wraps whatever you actually run:

```sh
para sh fix-login                      # a shell in the clone
para sh fix-login -c 'npm test'        # one command, exits with its status
```

A one-line project command turns that into a verb. `void-jchook` ships these
two; `para init` scaffolds `void-docker-gh`, which doesn't, so copy them in if
you want them:

```sh
# .paraspace/commands/claude — "para claude <ws>"
exec "$PARA_BIN" sh "$1" -c "exec claude --name $1"
```

```sh
# .paraspace/commands/run — "para run <ws>", tmux with claude in one window
exec "$PARA_BIN" sh "$1" -c "
  tmux has-session -t $1 2>/dev/null && exec tmux attach -t $1
  tmux new-session -d -s $1 -n claude \"claude --name $1\"
  tmux new-window  -t $1: -n sh
  exec tmux attach -t $1
"
```

Because `para sh` owns the terminal handling, these stay one-liners — see
[Commands](./commands.md#project-commands).

For the agent to feel like home, put your dotfiles in `.paraspace/skel/` and
have your provision hook link them in. The agent's own config (`CLAUDE.md`,
`AGENTS.md`) travels with the repo, so it's already in the clone.

## Working across several

```sh
para ls
```

```
NAME                 STATE     IP               PROJECT        URL
fix-login            RUNNING   10.62.14.201     myapp          https://fix-login.paraspace.dev:8443
dark-mode            RUNNING   10.62.14.202     myapp          https://dark-mode.paraspace.dev:8443
```

One workspace per window-manager desktop works well: each desktop holds that
task's terminal and its browser tab, and you switch tasks with the keybindings
you already use. `para ls --all` spans every project on the machine, which is
how you find the one you forgot.

## Reviewing and landing

The workspace is a full checkout with a booted stack, so review happens where
the work happened:

```sh
para sh fix-login -c 'git diff'        # or: git log --oneline main..
para sh fix-login                      # then push, open a PR, run the suite
```

Open the URL to exercise the change against its own database rather than a
shared one. When the branch has landed:

```sh
para rm fix-login
```

The shared volume — and with it your authentication — survives. Only the
workspace goes.

## When something's wrong

`para doctor` checks the host and prints the resolved config; it's the first
thing to run when an `up` fails for reasons that don't look like your project's.
Common failures and what they mean are in
[Troubleshooting](./troubleshooting.md).
