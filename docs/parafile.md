# The Parafile

`.paraspace/Parafile` is the per-project config: the few knobs `para` itself reads.
It is **sourced as bash**, and every key is a scalar: they use `: "${PARA_X:=…}"`
so a real environment variable still wins.

Any `PARA_FOO` you set here — documented or not — is forwarded into your hooks'
environment for free, so the Parafile is also where a project declares its own
knobs (the default template's `PARA_GH_AUTH` is one). See
[Hooks](./hooks.md#the-environment-para-injects).

Most keys have a sensible default and can simply be left out. The bundled
templates keep only the must-decide keys active and list the rest commented out —
a Parafile that restates a default is a copy that goes stale.

## What has to be there

Two keys para itself requires, plus one your hooks will:

| Key | Needed by | Why there's no default |
|---|---|---|
| `PARA_BASE_IMAGE` | `para image build` | para never picks your distro |
| `PARA_ROUTES` | `para up` | which port your app listens on is project policy |
| `PARA_ORIGIN` | the clone hook, not para | para doesn't guess your repo |

`PARA_ORIGIN` is listed because the bundled templates' `provision` hook needs it
— para itself never reads it (see [below](#keys-para-only-forwards-to-hooks)). A
project whose hooks don't clone, like `void-minimal`, omits it entirely.

Everything else either defaults or is genuinely optional. `PARA_VERSION` has no
default either, but it's a version pin rather than a setting — see
[Contract versioning](./versioning.md).

## Keys para reads

### `PARA_PROJECT`

Project **identity** — the single key `para` uses for workspace ownership,
`para ls` scoping, and the shared-volume name. A plain slug (`[a-z0-9-]`),
independent of where the checkout lives, so moving or renaming the dir keeps
its workspaces bound to it. `para init` bakes it to the dir name; unset falls
back to the dir's basename.

### `PARA_IMAGE`

Image alias `para up` launches and `para image build` publishes. You build it
with `para image build` — see [The image contract](./image.md).

**Defaults to `$PARA_PROJECT`**, so a project normally never sets it. Incus image
aliases are daemon-global: a fixed default would put two projects that both left
this unset on the same image, and a build in either would delete and republish the
other's out from under it. Set it explicitly only to point several projects at one
shared image, or to name an image built elsewhere.

### `PARA_BASE_IMAGE`

The Incus image `para image build` launches its builder from — any image works
(`images:debian/13`, `images:voidlinux`, `images:alpine/edge`, …). **Required**
to build: `para` pins no default, so your image's distro is never `para`'s choice
and can't change under you when `para` updates. `image build` refuses with a clear
error until you declare one. Not used by `para up`, which launches the *built*
image (`PARA_IMAGE`).

### `PARA_IMAGE_BOOTSTRAP`

Optional one-liner run via `sh -c` inside the builder **before** your
`.paraspace/image-build.sh`. Its job is to leave bash in the image (`para` runs
the payload with `bash -s`) and to refresh the package index if the base needs
it — `xbps-install -Syu xbps bash` on Void (what the templates declare),
`apk add --no-cache bash` on Alpine, `apt-get update` on Debian. Unset or empty
means no bootstrap step; `--from-current` skips it. See
[The image contract](./image.md).

### `PARA_ROUTES`

A **comma-separated** list of `"[sub:]port"` entries — one TLS Caddy site each.
A bare port is the workspace apex:

```sh
PARA_ROUTES="3000,api:3001"
# https://<name>.$PARA_DOMAIN      -> :3000
# https://api.<name>.$PARA_DOMAIN  -> :3001
```

**Required — para pins no default port.** Declare it empty for a workspace that
serves no HTTP at all (a worker, a queue consumer, a bare box):

```sh
PARA_ROUTES=""   # no Caddy site; `para ls` shows no URL
```

`para up` refuses an *unset* `PARA_ROUTES` rather than guessing, so a project
can't silently lose its URL to a typo: empty is a decision, unset is an oversight.

It's a plain scalar like every other key, so it follows the ordinary precedence —
a one-off `PARA_ROUTES="3000" para up ws` works — and it reaches your hooks
through the [usual forwarding](./hooks.md#the-environment-para-injects). Split it
with the `parse_routes` helper the templates ship, or inline:

```sh
IFS=, read -ra routes <<<"$PARA_ROUTES"
```

Each entry must be `[sub:]port` — a port is digits, an optional subdomain a DNS
label. para validates them, because an entry containing a space (or an empty one
from a stray comma) would corrupt its workspace registry and break routing for
every workspace on the machine.

### `PARA_DOMAIN`

Wildcard domain workspaces are served under (`https://<name>.$PARA_DOMAIN`).
`*.$PARA_DOMAIN` must resolve to `127.0.0.1`. Default `paraspace.dev`, which
already resolves — see [Workspace URLs](./urls.md).

### `PARA_VOLUME`

Shared-volume name. Default `para-home-<PARA_PROJECT>`; pin several projects
to one name to share auth across them.

### `PARA_CLONE_DIR`

Directory under `~` to clone into — and the directory `para run`, `para claude`,
and `para sh -c` start in. A guest path only, not tied to project identity.
Default `app`.

### `PARA_HOST_ENV`

Base `.env` seeded into the clone. Unset = the project's own `.env` if it has
one (else nothing); empty = always nothing; a set path must exist.

### `PARA_USER` / `PARA_UID` / `PARA_GID`

The workspace user para runs hooks, `para sh`, and `para run` as, and chowns
every pushed file to. Defaults: `app`, `1000`, `1000`.

It's your `.paraspace/image-build.sh` that makes use of these — it creates the
user in `$PARA_IMAGE`, and para's runtime chowns target the same ids. Change
them only if `1000` is already taken in your base image, **and rebuild
afterwards**, or the chowns land on a uid with no passwd entry and the shared
volume becomes unwritable.

para helps with exactly one part of that: `para image build` records the
`PARA_UID`/`PARA_GID` **it was configured with** onto the image, and `para up`
refuses to launch when they no longer match the ids configured now.
`para image status` shows them and flags the mismatch. That's the whole
guarantee — para compares its own build-time config against its current config.
It is *not* a check on what your payload actually created, because para assumes
nothing about `image-build.sh`; a payload that ignores the ids it's handed is
still on its own.

They default to a stable `1000` rather than your host `id -u`: para bind-mounts
nothing host-side, so there's nothing to line up with. A project that adds
host-guest file sharing can have its `image-build.sh` honor an override (env or
user config, which both win over the Parafile) to align the ids.

### `PARA_WORKCOPY_HOST` / `PARA_WORKCOPY_PORT`

Optional: proxy `https://localhost` to a working copy of the stack you run on
the **host**, so its familiar URL keeps working. Off unless `PARA_WORKCOPY_PORT`
is set (the port your host stack listens on); `PARA_WORKCOPY_HOST` defaults to
`localhost` and matters only when that stack terminates TLS with SNI.

### `PARA_VERSION`

Optional but recommended: the `para` contract version your hooks target. `para`
refuses with a clear error on a mismatch, and warns when a project declares none
— see [Contract versioning](./versioning.md).

## Keys para only forwards to hooks

These belong to the **hook** contract, not to para's own config: para never acts
on them, it just forwards them like any other `PARA_*` (see
[Hooks](./hooks.md#the-environment-para-injects)). A project whose hooks don't
clone has no use for either. They're documented here because the Parafile is
where you set them.

### `PARA_ORIGIN`

Git URL the clone hook clones. Project-declared — `para` does not guess it. A
Parafile at its own repo's toplevel can derive it from that repo's `origin`:

```sh
: "${PARA_ORIGIN:=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null)}"
```

para deliberately won't do that itself: for a project nested inside a larger
repo, it would walk up to the *enclosing* repo's origin and clone the wrong thing.

### `PARA_CLONE_BRANCH`

Optional: which branch the clone hook checks out. Handy for iterating on the
hooks themselves — `PARA_CLONE_BRANCH=my-feature para up ws`. Applies at clone
time only; to move an existing workspace to another branch, `para rm` then
`para up` it again. para validates the value (it reaches guest shell commands)
but never reads it otherwise.

## Precedence

**environment > user config > Parafile default**, with two exceptions worth
knowing.

### 1. Per-project keys are refused from the user config

The user config (`~/.config/para/config`) describes *your box*, so it applies to
every project on it — which makes a box-wide value for a per-project key
incoherent. One global `PARA_PROJECT` would collapse every project's ownership,
`para ls` scoping, and shared volume onto a single name; a global
`PARA_BASE_IMAGE` would rebuild every project's image on a distro its
`image-build.sh` doesn't target. So these keys are ignored there (with a warning)
and refused by `para config-set`:

> `PARA_PROJECT`, `PARA_IMAGE`, `PARA_BASE_IMAGE`, `PARA_IMAGE_BOOTSTRAP`,
> `PARA_VERSION`, `PARA_ORIGIN`, `PARA_CLONE_DIR`, `PARA_VOLUME`, `PARA_ROUTES`

Set them in the Parafile, or in the environment for a one-off run. Every *other*
`PARA_*` is fair game in the user config — including keys para has never heard
of, which is how you pass your own knobs to your hooks machine-wide.

`PARA_DOMAIN` is deliberately **not** on that list, even though it's project
config. A personal wildcard domain (`*.dev.mybox.lan`) is a reasonable thing to
want box-wide, and it can't collide: workspace names are unique per machine, and
each workspace records its own domain at `up` time, so projects on different
domains coexist.

### 2. The environment can't override a `:=` key to empty

`: "${X:=default}"` fires on empty as well as unset, so `PARA_HOST_ENV= para up ws`
does **not** clear a Parafile-declared `PARA_HOST_ENV` — the default reasserts.
This matters only for the keys where empty *means* something (`PARA_HOST_ENV`,
`PARA_IMAGE_BOOTSTRAP`). To keep such a key overridable to empty from the
environment, declare it with a plain assignment instead:

```sh
PARA_IMAGE_BOOTSTRAP="${PARA_IMAGE_BOOTSTRAP-apk add --no-cache bash}"
```

## User config, not Parafile

Some knobs describe *your box*, not the project, so they live in the per-user
config file — `$XDG_CONFIG_HOME/para/config`, i.e. `~/.config/para/config` by
default. Persist them with `para config-set KEY VALUE`. Notable ones:

- `PARA_HTTPS_PORT` — the port `para` Caddy binds (default `8443`; set `443` for
  port-less URLs — see [Workspace URLs](./urls.md)).
- `PARA_POOL` — the Incus storage pool; `para` writes this itself when it has to
  create a `dir` pool for nested Docker.
- `PARA_BRIDGE` — the Incus bridge workspaces attach to (default `incusbr0`).
