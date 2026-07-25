# Hooks

Hooks are where all the provisioning lives. `para` runs them **inside the
workspace**, as the workspace user (`$PARA_USER`, uid `$PARA_UID` — `app`/`1000`
by default). Everything domain-specific — git, `gh`, dotfiles, `.env`, booting
the stack — belongs here, never in `para`.

The working directory is `~/$PARA_CLONE_DIR` when it exists and `$HOME`
otherwise — so a provision hook starts in `$HOME` on the first `up` and in the
clone on every one after. Use absolute paths rather than relying on it.

## The two hooks

### `provision`

Everything before boot: seed and symlink the shared volume (you decide what's
shared), clone the repo, authenticate, render `.env`, and whatever else your
stack needs.

It must be **idempotent** — `para up` re-runs it on every converge, and
"fix the hook, re-run `up`" is the normal loop. It may prompt: para gives it a
tty when there's a human on both ends, which is where the ssh-key and `gh`
flows live.

### `boot`

Brings the stack up. The **readiness contract**: return zero only once every
routed service is actually listening.

```sh
docker compose up -d --wait          # blocks until healthchecks pass
```

para gates on the container agent (and `$PARA_READY_HOST`, if you set one)
before hooks run, then trusts your boot hook's exit code. A hook that returns
early is why a workspace comes up and its URL then 502s.

An absent hook is a visible no-op, so write only the ones you need. para runs
*only* the two named hooks — anything else under `.paraspace/hooks/` is synced
along and never executed, which is how the templates keep a shared `helpers`
file beside them.

Hooks are executed **by path**, so their own shebang decides the interpreter.

## How your project reaches the workspace

Before the hooks run, para replaces the guest's `~/.paraspace` with your
project's `.paraspace/` directory. Same name on both sides:

| In the guest | What it is |
|---|---|
| `~/.paraspace/hooks/` | your hooks, plus anything they source |
| `~/.paraspace/skel/` | your seed files (dotfiles etc.), for a hook to copy or link |
| `~/.paraspace/env` | para's context as export lines. Every `PARA_*` except the handful that name paths on the *host* (`PARA_BIN`, `PARA_PROJECT_DIR`, `PARA_CONFIG`, `PARA_CONFIG_DIR`, `PARA_STATE_DIR`), which are unset here rather than pointing at files that don't exist; `PARA_HOST_ENV` names the copy in this directory |
| `~/.paraspace/host.env` | `$PARA_HOST_ENV` from the host, if that file exists |
| `~/.paraspace/commands/` | synced along, but these run on the *host* — see [Commands](./commands.md#project-commands) |

para reads the `Parafile` and `image-build.sh` itself, on the host. Like
`commands/`, they are synced into the guest as well, but nothing in the
workspace runs them — so don't put a host-only secret in a `Parafile`.

Files come from your **host checkout**, not the clone, and are pushed fresh on
every `up` — so editing a hook takes effect on the next `para up` without
re-cloning anything. A hook can seed from `~/.paraspace/skel` before the clone
even exists.

## The environment para injects

para forwards **every `PARA_*` variable in scope** — your user config,
everything your `Parafile` sets, and the per-workspace values para computes.
So any `PARA_FOO` you invent reaches your hooks for free, no para change
needed.

**Scalars only.** Forwarding is one `export NAME=value` line per variable, so
a bash array does not survive it — `PARA_PORTS=(3000 3001)` arrives as just
`3000`, silently, because that's what `$PARA_PORTS` expands to. Associative
arrays fare no better. Pass a delimited string and split it in the hook, the
way `PARA_ROUTES` does.

The documented contract is:

| Variable | Meaning |
|---|---|
| `PARA_NAME` | this workspace's name |
| `PARA_URL` | its apex URL — **empty** unless a bare port routes the apex |
| `PARA_ROUTES` | the routes para publishes, space-separated `[sub:]port` (empty if none) |
| `PARA_DOMAIN` | the wildcard domain it's served under |
| `PARA_PROJECT` | the project identity slug |
| `PARA_SHARED` | the shared volume's mount point (`/para/shared`) |
| `PARA_CLONE_DIR`, `PARA_CLONE_BRANCH`, `PARA_ORIGIN` | what to clone, and where |
| `PARA_USER`, `PARA_UID`, `PARA_GID` | the workspace user's identity |
| `PARA_HOSTNAME` | the host's short hostname — the ssh-key label |
| `PARA_GIT_NAME`, `PARA_GIT_EMAIL` | your host git identity, for a seeded gitconfig |
| `PARA_CONTRACT` | the [contract](./versioning.md) your `Parafile` targets — para has already refused a mismatch by the time a hook runs, so this is only ever the one you asked for |

`PARA_NONINTERACTIVE` is yours rather than para's: set it in the environment to
force the scripted path, and para forwards it like any other `PARA_*` so your
hooks can skip their prompts too.

Routes are space-separated, so splitting them needs no helper:

```sh
for route in $PARA_ROUTES; do
  port="${route##*:}"           # "api:3001" -> 3001, "3000" -> 3000
  wait_for_port "$port"
done
```

para's own internals may also appear in the environment; only the variables
above are the [versioned contract](./versioning.md).

## Waiting for the network

Guest DNS comes up a beat after the container does, so a provision hook that
clones can race it. If your hooks depend on reaching a host, name it:

```sh
: "${PARA_READY_HOST:=github.com}"
```

`para up` then blocks until the guest resolves it before running anything.
Leave it unset and para waits only for the container agent.
