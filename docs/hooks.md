# Hooks

Hooks are where all your provisioning lives.

## The three official hooks

Name a hook anything you like. These three are the ones `para` runs for you. To
let other hooks slot into the middle of one, open a
[hook point](./hook-points.md).

### `provision`

Everything before boot: seed and symlink the shared volume (you decide what's
shared), clone the repo, authenticate, render `.env`, and whatever else your
stack needs.

It must be **idempotent**, because `para up` re-runs it on every converge, and
"fix the hook, re-run `up`" is the normal loop. It may also prompt: para gives
it a tty when there's a human on both ends, which is where the ssh-key and `gh`
flows live.

Guest DNS comes up a beat after the container, so a hook that clones can race
it. `para up` blocks until the guest resolves
[`PARA_READY_HOST`](./parafile.md#every-var-para-reads), which is `paraspace.dev`
unless your Parafile names a host you'd rather gate on, or declares it empty to
skip the wait.

### `boot`

Brings the stack up, whatever your stack is. The **readiness contract** is to
return zero only once every routed service is actually listening:

```sh
docker compose up -d --wait                    # if you use Compose
until nc -z localhost 3000; do sleep 1; done   # or wait on the port yourself
```

`para` gates on the container agent and on `$PARA_READY_HOST` resolving before
hooks run, then trusts your boot hook's exit code.

### `image-build`

Everything you want baked into the base image rather than installed per
workspace: packages, the workspace user, a toolchain. `para image build` runs it
once, in a throwaway container, and every workspace is a clone of the result.

You're **root** here, and there is no workspace yet: no `$HOME`, and the user
you're about to create doesn't exist. `$PARA_HOOKS` and `$PARA_SKEL` still point
at your files, so seeding from `skel/` works as it does in `provision`. Your
`.env` is the exception, because `$PARA_HOST_ENV` names a file only a workspace
has, so read secrets at `provision`. **Nothing can prompt you** either, so a
package manager that stops to ask will hang the build. Pass `-y`.

See [The image contract](./image.md) to learn what your final image must contain.

## A hook is a process

para runs each hook as its own `bash` process, and a name can resolve to
[more than one file](./hook-points.md#filling-one). So:

- **The shebang and the exec bit are ignored**, and a checkout with
  `core.fileMode=false`, a tarball or a zip all still work.
- **`$0` is the hook.** `. "$PARA_HOOKS/helpers"` is the spelling to reach for,
  because it keeps resolving when the hook belongs to someone else.
- **There are no arguments.** A hook fills in behavior; it never takes input.
- **`exit` ends that hook alone**, including a `die` out of a sourced `helpers`.
  A non-zero one stops the run, and its status is what `para up` reports.

## How your project reaches the workspace

Your `.paraspace/` becomes the workspace's `~/.paraspace`, the same name on both
sides. Reach into it by variable rather than by `$HOME`, because the layout is
para's to change and the variable is what it promises.

| In the guest | Reach it as | What it is |
|---|---|---|
| `~/.paraspace/hooks/` | `$PARA_HOOKS` | your hooks, plus anything they source. A [mod](./mods.md)'s hook sees its own, per the table below |
| `~/.paraspace/skel/` | `$PARA_SKEL` | your seed files (dotfiles etc.), for a hook to copy or link |
| `~/.paraspace/mods/` | none | the [mods](./mods.md) you vendored, each with its own `hooks/`, `skel/` and `commands/` |
| `~/.paraspace/host.env` | `$PARA_HOST_ENV` | your `.env` from the host, if that file exists. Workspaces only, never pushed to the image builder |
| `~/.paraspace/env` | none | para's context as export lines. Every `PARA_*` except the handful that name paths on the *host* (`PARA_BIN`, `PARA_PROJECT_DIR`, `PARA_CONFIG`, `PARA_CONFIG_DIR`, `PARA_STATE_DIR`, `PARA_MOD_DIR`), which are unset here rather than pointing at files that don't exist |
| `~/.paraspace/commands/` | none | synced along, but these run on the *host* (see [Commands](./commands.md#project-commands)) |
| `~/.paraspace/run-hook` | `$PARA_RUN_HOOK` | para's hook runner, which you call to open a [hook point](./hook-points.md) |

`para` reads the `Parafile` on the host. Like `commands/`, it is synced into the
guest as well but nothing there runs it, so don't put a host-only secret in one.

Files come from your **host checkout**, not the clone, and are pushed fresh on
every `up`, so editing a hook takes effect on the next `para up` without
re-cloning, and a hook can seed from `$PARA_SKEL` before the clone exists.

## The environment para injects

`para` forwards **every `PARA_*` variable in scope**: your user config,
everything your `Parafile` sets, and the per-workspace values para computes. So
any `PARA_FOO` you invent reaches your hooks for free.

**Scalars only.** Forwarding is one `export NAME=value` line per variable, so
a bash array does not survive it. `PARA_PORTS=(3000 3001)` arrives as just
`3000`, silently, because that's what `$PARA_PORTS` expands to. Associative
arrays fare no better. Pass a delimited string and split it in the hook, the way
`PARA_ROUTES` does. The documented contract is:

| Variable | Meaning |
|---|---|
| `PARA_NAME` | this workspace's name |
| `PARA_URL` | its apex URL, **empty** unless a bare port routes the apex |
| `PARA_ROUTES` | the routes para publishes, space-separated `[sub:]port` (empty if none) |
| `PARA_DOMAIN` | the wildcard domain it's served under |
| `PARA_PROJECT_NAME` | the project identity slug |
| `PARA_SHARED` | the shared volume's mount point (`/para/shared`) |
| `PARA_HOOKS`, `PARA_SKEL` | the `hooks/` and `skel/` of whoever owns the running hook. Guest-side only. On the host these two are unset, and [commands](./commands.md#project-commands) use `$PARA_PROJECT_DIR` or `$PARA_MOD_DIR` |
| `PARA_RUN_HOOK` | para's hook runner (see [Hook points](./hook-points.md)) |
| `PARA_HOOK_STACK` | the points para is currently inside, for the failure trace. para rewrites it at every level, so it is yours to read, never to set |
| `PARA_CLONE_DIR`, `PARA_CLONE_BRANCH`, `PARA_ORIGIN` | what to clone, and where |
| `PARA_USER`, `PARA_UID`, `PARA_GID` | the workspace user's identity |
| `PARA_HOSTNAME` | the host's short hostname, used as the ssh-key label |
| `PARA_GIT_NAME`, `PARA_GIT_EMAIL` | your host git identity, for a seeded gitconfig |
| `PARA_CONTRACT` | the [contract](./versioning.md) your `Parafile` targets. para has already refused a mismatch by the time a hook runs, so this is only ever the one you asked for |

`PARA_NONINTERACTIVE` is yours rather than para's. Set it in the environment to
force the scripted path, and para forwards it like any other `PARA_*` so your
hooks can skip their prompts too.

para's own internals may also appear in the environment; only the variables
above are the [versioned contract](./versioning.md).

## Passing something to a later hook

You can't add to that environment from inside a hook, because an `export` you
write lives and dies with it. Anything a *later* hook, your shell, or a project
command has to see goes through a file, and **which file is decided by how long
the value should live**:

| To pass | Write | Read by | Lives as long as |
|---|---|---|---|
| "I already did this" | a sentinel beside the thing it guards | the same hook, next `up` | the thing it guards |
| "the tool is installed" | nothing, just install it | anyone, via `command -v` | the image |
| a shell variable (`PATH`, `$BROWSER`) | `/etc/profile.d/<name>.sh`, from `image-build` | every login shell after it, so later hooks, `para sh`, your commands | the image |
| a value only this workspace knows | a file under `$HOME` | whoever needs it, when they need it | the workspace |
| a value every workspace shares | a file under `$PARA_SHARED` | every workspace of the project | the shared volume |

Name what you write after whoever owns it (`/etc/profile.d/dotfiles.sh`,
`$PARA_SHARED/dotfiles/`), so two things filling the same hook can't collide on
one path.

**The one that surprises people.** Within a single `provision`, files cross but
the environment doesn't. Every hook filling a name inherits the environment para
set up before the first of them ran, so a `/etc/profile.d` file one writes takes
effect on the *next* thing para runs (`boot`, `para sh`, the next `up`), not on
the hook beside it. Every other row above is fine, because each hook reads the
filesystem as it finds it, so a sentinel, an installed tool or a `$PARA_SHARED`
file written seconds earlier is right there.
