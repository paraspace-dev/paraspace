# Hooks

`para` runs a project's hooks **inside the workspace, in `$HOME`**, as the
workspace user (`$PARA_USER`, uid `$PARA_UID` — `app`/`1000` by default).
Everything domain-specific — git, gh, dotfiles, `.env`, booting the stack —
lives here, never in `para`.

## The two hooks

### `provision`

Owns everything before boot: seed and symlink the shared volume (decide *what's
shared*), clone the repo (and authenticate — see
[Git authentication](./git-auth.md)), render `.env`, and whatever else your
stack needs. **Idempotent** — `para up` re-runs it on every converge. May
prompt: `para` gives it a tty when interactive, which is where the ssh-key/gh
flow lives.

### `boot`

Brings the stack up. **Readiness contract:** return zero only once every
routed service is up *and actually listening* — compose: `up -d --wait`; bare
processes: start detached under a supervisor and wait until listening. `para`
gates on agent + DNS before hooks, then trusts the boot hook's exit code.

An absent hook is a visible no-op; a project only writes the ones it needs.
`para` runs only the named hooks, so a project can drop shared code beside them —
the default template factors colored output into a `helpers` file its hooks
source. Anything else under `.paraspace/hooks/` is just synced along, never run.

## How hooks reach the workspace

Hook files come from your **host checkout**, not the clone, so edits take
effect on the next `up`. Before the hooks run, `para` syncs the project's
`.paraspace/hooks/` and `.paraspace/skel/` to `~/.para/` in the workspace (the
`Parafile` and `image-build.sh` stay host-side — `para` reads those itself), so
a hook can seed from `~/.para/skel` before the clone even exists.

## The environment `para` injects

`para` forwards **every `PARA_*` variable in scope** — the user config,
everything your `Parafile` sets, and the per-workspace values `para` computes —
into the hook's environment. So beyond the documented set below, **any
`PARA_FOO` you put in your `Parafile` reaches your hooks for free**, no `para`
change needed. The same is true of your own keys in the user config, which is
how you pass a machine-wide knob to your hooks.

Two caveats on where a value may come from: the [per-project
keys](./parafile.md#1-per-project-keys-are-refused-from-the-user-config) —
`PARA_PROJECT`, `PARA_CLONE_DIR` and `PARA_ORIGIN` among them — are **not** read
from the user config, so set those in the `Parafile`. And `PARA_ROUTES` is an
array, so it isn't forwarded at all (see below).

The documented context is:

| Variable | Meaning |
|---|---|
| `PARA_NAME`, `PARA_URL`, `PARA_DOMAIN` | this workspace + its host/domain. `PARA_URL` is **empty** when the project declares `PARA_ROUTES=()` — there's no site to point at |
| `PARA_PROJECT` | the project identity slug (also the shared-volume suffix) |
| `PARA_CLONE_DIR`, `PARA_CLONE_BRANCH`, `PARA_ORIGIN` | what/where to clone |
| `PARA_SHARED=/para/shared` | the shared-volume mount |
| `PARA_USER`/`UID`/`GID` | the workspace user's identity |
| `PARA_HOSTNAME` | the ssh-key label |
| `PARA_GIT_NAME`/`EMAIL` | the seeded gitconfig |
| `PARA_CONTRACT` | the contract version `para` provides |

Two caveats:

- `PARA_ROUTES` is an array and is **not** forwarded — read routes from the
  `Parafile`.
- `para`'s own internals may also appear in the env; only the variables above are
  the [versioned contract](./versioning.md).
