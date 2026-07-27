# Hooks

Hooks are where all your provisioning lives.

To let other hooks slot into the middle of one of yours, open a
[hook point](./hook-points.md).

## The three official hooks

Hooks can be named anything you want, but there are three blessed hooks that
`para` knows about and runs for you.

### `provision`

Everything before boot: seed and symlink the shared volume (you decide what's
shared), clone the repo, authenticate, render `.env`, and whatever else your
stack needs.

It must be **idempotent** — `para up` re-runs it on every converge, and
"fix the hook, re-run `up`" is the normal loop. It may prompt: para gives it a
tty when there's a human on both ends, which is where the ssh-key and `gh`
flows live.

Guest DNS comes up a beat after the container, so a hook that clones can race
it. Name the host you need in your [Parafile](./parafile.md) and `para up`
blocks until the guest resolves it:

```sh
: "${PARA_READY_HOST:=github.com}"
```

### `boot`

Brings the stack up. The **readiness contract**: return zero only once every
routed service is actually listening, e.g.

```sh
docker compose up -d --wait          # blocks until healthchecks pass
```

`para` gates on the container agent (and `$PARA_READY_HOST`, if you set one)
before hooks run, then trusts your boot hook's exit code.

### `image-build`

Everything you want baked into the base image rather than installed per
workspace: packages, the workspace user, a toolchain. `para image build` runs it
once, in a throwaway container, and every workspace is a clone of the result.

You're **root** here, and there is no workspace yet — no `$HOME`, and the user
you're about to create doesn't exist. `$PARA_HOOKS` and `$PARA_SKEL` still point
at your files (under `/opt`), so seeding from `skel/` works the same as it does
in `provision`. Your `.env` is the one thing that does *not* follow you in:
`$PARA_HOST_ENV` names a file that exists only in a workspace, so read secrets
at `provision`, not here.

**Nothing can prompt you.** There's no terminal on this path, so a package
manager that stops to ask will hang the build — pass `-y`, or whatever your
distro's equivalent is.

See [The image contract](./image.md) to learn what your final image must contain.

## How your project reaches the workspace

Your `.paraspace/` becomes the workspace's `~/.paraspace` — same name on both
sides. Reach into it by variable rather than by `$HOME`: the layout is para's to
change, the variable is what it promises.

| In the guest | Reach it as | What it is |
|---|---|---|
| `~/.paraspace/hooks/` | `$PARA_HOOKS` | your hooks, plus anything they source |
| `~/.paraspace/skel/` | `$PARA_SKEL` | your seed files (dotfiles etc.), for a hook to copy or link |
| `~/.paraspace/host.env` | `$PARA_HOST_ENV` | your `.env` from the host, if that file exists. Workspaces only — never pushed to the image builder |
| `~/.paraspace/env` | — | para's context as export lines. Every `PARA_*` except the handful that name paths on the *host* (`PARA_BIN`, `PARA_PROJECT_DIR`, `PARA_CONFIG`, `PARA_CONFIG_DIR`, `PARA_STATE_DIR`), which are unset here rather than pointing at files that don't exist |
| `~/.paraspace/commands/` | — | synced along, but these run on the *host* — see [Commands](./commands.md#project-commands) |
| `~/.paraspace/run-hook` | `$PARA_RUN_HOOK` | reserved for internal use by `para` |

`para` reads the `Parafile` itself, on the host. Like `commands/`, it is synced
into the guest as well, but nothing in the workspace runs it — so don't put a
host-only secret in a `Parafile`.

Files come from your **host checkout**, not the clone, and are pushed fresh on
every `up` — so editing a hook takes effect on the next `para up` without
re-cloning anything. A hook can seed from `$PARA_SKEL` before the clone even
exists.

## The environment para injects

`para` forwards **every `PARA_*` variable in scope** — your user config,
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
| `PARA_HOOKS`, `PARA_SKEL` | the `hooks/` and `skel/` of whoever owns the running hook. Guest-side only — on the host these two are unset, and `commands/` use `$PARA_PROJECT_DIR` |
| `PARA_RUN_HOOK` | para's hook runner — see [Hook points](./hook-points.md) |
| `PARA_CLONE_DIR`, `PARA_CLONE_BRANCH`, `PARA_ORIGIN` | what to clone, and where |
| `PARA_USER`, `PARA_UID`, `PARA_GID` | the workspace user's identity |
| `PARA_HOSTNAME` | the host's short hostname — the ssh-key label |
| `PARA_GIT_NAME`, `PARA_GIT_EMAIL` | your host git identity, for a seeded gitconfig |
| `PARA_CONTRACT` | the [contract](./versioning.md) your `Parafile` targets — para has already refused a mismatch by the time a hook runs, so this is only ever the one you asked for |

`PARA_NONINTERACTIVE` is yours rather than para's: set it in the environment to
force the scripted path, and para forwards it like any other `PARA_*` so your
hooks can skip their prompts too.

Routes arrive space-separated, so a `boot` hook can split them with plain word
splitting — see [Serve more than one
port](./cookbook.md#serve-more-than-one-port) for the loop.

para's own internals may also appear in the environment; only the variables
above are the [versioned contract](./versioning.md).

## Passing something to a later hook

You can't add to that environment from inside a hook — an `export` you write
lives and dies with it. Anything a *later* hook, your shell, or a project
command has to see goes through a file, and **which file is decided by how long
the value should live**:

| To pass | Write | Read by | Lives as long as |
|---|---|---|---|
| "I already did this" | a sentinel beside the thing it guards | the same hook, next `up` | the thing it guards |
| "the tool is installed" | nothing — just install it | anyone, via `command -v` | the image |
| a shell variable (`PATH`, `$BROWSER`) | `/etc/profile.d/<name>.sh`, from `image-build` | every login shell after it — later hooks, `para sh`, your commands | the image |
| a value only this workspace knows | a file under `$HOME` | whoever needs it, when they need it | the workspace |
| a value every workspace shares | a file under `$PARA_SHARED` | every workspace of the project | the shared volume |

Name what you write after whoever owns it — `/etc/profile.d/dotfiles.sh`,
`$PARA_SHARED/dotfiles/` — so two things filling the same hook can't quietly
land on one path.

**The one that surprises people:** a `/etc/profile.d` file doesn't reach the
hooks running beside it. The shell that runs your hooks read its environment
before any of them started, so the file takes effect on the *next* thing para
runs — `boot`, `para sh`, the next `up`. Two hooks that have to hand off within
a single `provision` do it through a file each reads at the moment it needs it.
