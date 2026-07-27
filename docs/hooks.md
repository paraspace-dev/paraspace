# Hooks

Hooks are where all the provisioning lives. `provision` and `boot` run **inside
the workspace**, as the workspace user (`$PARA_USER`), starting in
`~/$PARA_CLONE_DIR` when it exists and `$HOME` when it doesn't — so `provision`
starts in `$HOME` on the first `up` and in the clone every time after. Use
absolute paths rather than relying on it. `image-build` is the odd one out: it
runs in the image builder, as root, before any workspace exists.

## The three hooks

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
before hooks run, then trusts your boot hook's exit code.

### `image-build`

Builds the base image every workspace is cloned from: packages, the workspace
user, whatever belongs in the image rather than installed per workspace. `para
image build` runs it in a throwaway builder, **as root**, with your whole
`.paraspace/` pushed to `/opt/.paraspace` — so `$PARA_HOOKS` and `$PARA_SKEL`
point in there, not at a `$HOME` no one has created yet.

It gets **no tty and no stdin**: prompting is an `up`-only promise, so a package
manager that stops to ask hangs the build. Pass `-y`. Your `.env` is the one
thing that does *not* follow it in — `$PARA_HOST_ENV` names a file that exists
only in a workspace, so read secrets at `provision`, not here.

What the image has to end up containing is [its own page](./image.md).

An absent hook is a no-op, and para says so — `warn: no 'provision' hook` — so
write only the ones you need and you still see what ran.

Those three are the only names para invokes, but the whole directory is synced,
so anything else you put there is yours to source or hand off to:

```sh
. "$PARA_HOOKS/helpers"             # a library — what the templates do
bash "$PARA_HOOKS/seed-dotfiles"    # a step a long hook factors out
```

## How para runs a hook

Each one runs as **`bash <the file>`**, in its own process. Three things follow:

- **The exec bit doesn't matter** — which is why the line above says `bash` — so
  a checkout with `core.fileMode=false`, a tarball or a zip can't break a
  workspace.
- **The shebang is ignored.** Keep `#!/usr/bin/env bash` on your hooks anyway
  (`bin/lint` finds files to check *by* shebang), but a `python3` shebang runs
  as bash.
- **A hook gets no arguments**, and nothing it does — `cd`, `set -o`, a stray
  variable — reaches para or the next hook. `exit` ends that hook, and a non-zero
  status stops the run.

The model in one sentence: **a hook reads its environment and writes to the
filesystem, never to its caller.** If the rest of the workspace must see
something, put it on the filesystem or in the image (`/etc/profile.d`). A hook
can also run [a hook point of its own](./hook-points.md).

## How your project reaches the workspace

Before the hooks run, para replaces the guest's `~/.paraspace` with your
project's `.paraspace/` directory — same name on both sides. Name these by the
variables para injects rather than by `$HOME`: the layout is para's to change,
the variable is the part it promises.

| In the guest | Reach it as | What it is |
|---|---|---|
| `~/.paraspace/hooks/` | `$PARA_HOOKS` | your hooks, plus anything they source |
| `~/.paraspace/skel/` | `$PARA_SKEL` | your seed files (dotfiles etc.), for a hook to copy or link |
| `~/.paraspace/host.env` | `$PARA_HOST_ENV` | your `.env` from the host, if that file exists. Workspaces only — never pushed to the image builder |
| `~/.paraspace/env` | — | para's context as export lines. Every `PARA_*` except the handful that name paths on the *host* (`PARA_BIN`, `PARA_PROJECT_DIR`, `PARA_CONFIG`, `PARA_CONFIG_DIR`, `PARA_STATE_DIR`), which are unset here rather than pointing at files that don't exist |
| `~/.paraspace/commands/` | — | synced along, but these run on the *host* — see [Commands](./commands.md#project-commands) |
| `~/.paraspace/run-hook` | `$PARA_RUN_HOOK` | para's own — it runs each hook. A name para owns: a file of yours at that path is overwritten |

para reads the `Parafile` itself, on the host. Like `commands/`, it is synced
into the guest as well, but nothing in the workspace runs it — so don't put a
host-only secret in a `Parafile`.

Files come from your **host checkout**, not the clone, and are pushed fresh on
every `up` — so editing a hook takes effect on the next `para up` without
re-cloning anything. A hook can seed from `$PARA_SKEL` before the clone even
exists.

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
