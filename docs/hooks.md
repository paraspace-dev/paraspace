# Hooks

Hooks are where all your provisioning lives. They live in layers. A project's own
hooks are in `.paraspace/layers/project/hooks/`; when `para` runs a hook name,
it runs that hook from every layer that defines it, in stack order with the top
of the stack first.

## The three official hooks

Name a hook anything you like. These three are the ones `para` runs for you.
`para init` writes stubs for them into `.paraspace/layers/project/hooks/`.
Every plain hook runs between automatic `:before` and `:after` points; see
[Hook points](./hook-points.md) to run hooks around one or open a point in its
middle.

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
[`PARA_READY_HOST`](./env.md#every-var-para-reads), which is `paraspace.dev`
unless you name a host you'd rather gate on.

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
you're about to create doesn't exist. `$PARA_LAYER_DIR` still points at your
layer in the builder, and the whole stack is pushed there at `/opt/.paraspace`,
so seeding from `$PARA_LAYER_DIR/skel` works as it does in `provision`. Your
`.env` is the exception, because `$PARA_HOST_ENV` names a file only a workspace
has, so read secrets at `provision`. **Nothing can prompt you** either, so a
package manager that stops to ask will hang the build. Pass `-y`.

See [The image contract](./image.md) to learn what your final image must contain.

## A hook is a process

para runs each hook as its own `bash` process, and a name can resolve to more
than one file across the layer stack. So:

- **The shebang and the exec bit are ignored**, and a checkout with
  `core.fileMode=false`, a tarball or a zip all still work.
- **`$0` is the hook.** Source para's helpers with the same two lines in every
  layer's hooks:

  ```sh
  # shellcheck source=/dev/null
  . "$PARA_HELPERS"
  ```
- **There are no arguments.** A hook fills in behavior; it never takes input.
- **`exit` ends that hook alone**, including a `die` out of a sourced `helpers`.
  A non-zero one stops the run, and its status is what `para up` reports.

## How layers reach the workspace

The composed stack becomes the workspace's `~/.paraspace/stack/`. Reach into
your layer by variable rather than by `$HOME`, because the layout is para's to
change and the variable is what it promises.

| In the guest | Reach it as | What it is |
|---|---|---|
| `~/.paraspace/stack/<layer>/` | `$PARA_LAYER_DIR` for your own layer | every layer in the composed stack, named by layer name and holding its own `hooks/`, `skel/`, and `commands/` |
| `~/.paraspace/host.env` | `$PARA_HOST_ENV` | your `.env` from the host, if that file exists. Workspaces only, never pushed to the image builder |
| `~/.paraspace/env` | none | para's context as export lines. Every `PARA_*` except the handful that name paths on the *host* (`PARA_BIN`, `PARA_PROJECT_DIR`, `PARA_CONFIG`, `PARA_CONFIG_DIR`, `PARA_STATE_DIR`), which are unset here rather than pointing at files that don't exist. `PARA_HOOK_CHAIN` and `PARA_LAYER_DIR` are also unset because para sets them fresh per run |
| `~/.paraspace/run-hook` | `$PARA_RUN_HOOK` | para's hook runner, which you call to open a [hook point](./hook-points.md) |
| `~/.paraspace/helpers` | `$PARA_HELPERS` | para's output and interactivity helpers, replaced by para on every push |

A layer's `commands/` travels inside its layer directory, but those commands run
on the *host* (see [Commands](./commands.md#project-commands)).

Files come from your **host checkout**, not the clone, and the composed stack is
pushed fresh on every `up`, replacing what was there. Editing a hook takes
effect on the next `para up` without re-cloning; a layer dropped from the stack
disappears from the guest too, and a hook can seed from
`$PARA_LAYER_DIR/skel` before the clone exists.

`para` sources `.paraspace/env` on the host, and the file itself is never
pushed. Every `PARA_*` variable it declares reaches the guest as an export line
in `~/.paraspace/env`, so a secret in a `PARA_*` variable reaches every
workspace. A non-`PARA_*` variable stays on the host.

## The environment para injects

`para` forwards **every `PARA_*` variable in scope**: your user config,
everything your env file sets, and the per-workspace values para computes. So
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
| `PARA_LAYER_DIR` | the layer that owns the running hook or command. A guest path in hooks and a host path in commands |
| `PARA_STACK` | the composed layers in stack order, one path per line. Guest paths in the guest and host paths on the host |
| `PARA_RUN_HOOK` | para's hook runner (see [Hook points](./hook-points.md)) |
| `PARA_HELPERS` | para's helper library. Guest hooks and host commands both receive a path valid on their side |
| `PARA_HOOK_CHAIN` | the points para is currently inside, for the failure trace. para rewrites it at every level, so it is yours to read, never to set |
| `PARA_CLONE_DIR`, `PARA_CLONE_BRANCH`, `PARA_ORIGIN` | what to clone, and where |
| `PARA_USER`, `PARA_UID`, `PARA_GID` | the workspace user's identity |
| `PARA_HOSTNAME` | the host's short hostname, used as the ssh-key label |
| `PARA_GIT_NAME`, `PARA_GIT_EMAIL` | your host git identity, for a seeded gitconfig |
| `PARA_CONTRACT` | the [contract](./versioning.md) your env file targets. para has already refused a mismatch by the time a hook runs, so this is only ever the one you asked for |

Alongside the output helpers, an image hook targeting Void may call
`xbps_install <package>...`. It queries each name and runs at most one
`xbps-install -Sy`, carrying only the ones that are missing. It talks XBPS, so
it is for a guest that has it and nothing else.

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
