# The Parafile

`.paraspace/Parafile` is your project's config: the few `PARA_*` variables
`para` itself reads. It is **sourced as bash**, every key is a scalar, and
[precedence](#precedence) is whatever bash does. Most keys default sensibly and
can be left out — a Parafile that restates a default is a copy that goes stale.

## What you have to decide

| Key | Needed by | Why there's no default |
|---|---|---|
| `PARA_BASE_IMAGE` | `para image build` | para never picks your distro |
| `PARA_ROUTES` | `para up` | which port your app listens on is project policy |
| `PARA_ORIGIN` | your clone hook, not para | para doesn't guess your repo |

`PARA_ORIGIN` is here because the bundled templates' `provision` hook needs it;
para itself never reads it. A project whose hooks don't clone omits it.

## Every key para reads

| Key | Default | What it does |
|---|---|---|
| `PARA_VERSION` | — | the [contract](./versioning.md) your `.paraspace/` targets. para refuses on a mismatch |
| `PARA_PROJECT` | the directory's name | project identity: workspace ownership, `para ls` scoping, the shared-volume name |
| `PARA_IMAGE` | `$PARA_PROJECT` | the image `para up` launches and `para image build` publishes |
| `PARA_BASE_IMAGE` | — | the Incus image `para image build` builds *from* |
| `PARA_IMAGE_BOOTSTRAP` | — | one `sh -c` line run in the builder before your payload |
| `PARA_ROUTES` | empty | `[sub:]port` entries, one Caddy site each |
| `PARA_DOMAIN` | `paraspace.dev` | wildcard domain workspaces are served under |
| `PARA_VOLUME` | `para-home-$PARA_PROJECT` | the shared home volume's name |
| `PARA_CLONE_DIR` | `app` | directory under `~` to clone into; also where `para sh` starts |
| `PARA_HOST_ENV` | `$PARA_PROJECT_DIR/.env` | a base `.env` pushed to `~/.paraspace/host.env` **if the file exists** |
| `PARA_READY_HOST` | — | a hostname the guest must resolve before hooks run |
| `PARA_USER` / `PARA_UID` / `PARA_GID` | `app` / `1000` / `1000` | the workspace user para runs everything as |
| `PARA_WORKCOPY_PORT` | — | proxy `https://localhost` to a stack you run on the **host** |
| `PARA_WORKCOPY_HOST` | `localhost` | matters only if that host stack terminates TLS with SNI |

Anything else you set is [forwarded to your hooks](#your-own-keys) untouched.

## The ones with subtleties

### `PARA_ROUTES`

A list of `[sub:]port` entries — one TLS Caddy site each. A bare port is the
workspace apex:

```sh
PARA_ROUTES="3000,api:3001"
# https://<name>.$PARA_DOMAIN      -> :3000
# https://api.<name>.$PARA_DOMAIN  -> :3001
```

The order is **`sub:port`** — left is where you arrive, right is where it goes,
the same direction as `docker -p` and `ssh -L`.

Separate entries with commas, spaces, tabs or newlines, whichever reads best —
a long list laid out one route per line is a first-class spelling. para
normalizes them to one space-separated form, which is what your hooks see and
what `for r in $PARA_ROUTES` reads.

para does **not** validate routes — [`caddy validate`](./urls.md) does, before
every reload, and it names the site it rejected. A bad port or two workspaces
claiming one hostname fails loudly, with nothing written.

Empty means "this workspace serves no HTTP" — a worker, a bare box. `para ls`
shows no URL, `$PARA_URL` is empty in your hooks, and `para doctor` mentions it
in case you didn't mean it. Note that only a **bare port** creates
`https://<name>.$PARA_DOMAIN`; a subdomain-only list has no apex site.

### `PARA_IMAGE`

Defaults to `$PARA_PROJECT`, so a project normally never sets it. Incus image
aliases are daemon-global: a fixed default would put two projects that both
left this unset on the same image, and a build in either would republish the
other's out from under it. Set it explicitly only to point several projects at
one shared image, or to name an image built elsewhere.

### `PARA_BASE_IMAGE` and `PARA_IMAGE_BOOTSTRAP`

The base is **required to build**, and any Incus image works
(`images:debian/13`, `images:voidlinux`, `images:alpine/edge`, …): para pins no
default, so your distro can't change under you when para updates.

The bootstrap is one `sh -c` line run in the builder before your
`.paraspace/image-build.sh`. Its job is to leave **bash** in the image (para
runs the payload with `bash -s`) and refresh the package index if the base
needs it — `xbps-install -Syu xbps bash` on Void, `apk add --no-cache bash` on
Alpine, `apt-get update` on Debian. Leave it unset if your base needs nothing.

### `PARA_USER` / `PARA_UID` / `PARA_GID`

The workspace user para runs hooks and `para sh` as, and chowns every pushed
file to. Your `image-build.sh` creates that user — it gets all three in its
environment — so if you change them, **rebuild the image**, or the chowns land
on a uid with no passwd entry and the shared volume becomes unwritable. They
default to a stable `1000` because para bind-mounts nothing host-side, so
there's nothing to line up with.

## Keys para only forwards to hooks

These belong to the **hook** contract. para never acts on them; it forwards
them like any other `PARA_*`. They're documented here because the Parafile is
where you set them.

- **`PARA_ORIGIN`** — the git URL your clone hook clones. A Parafile at its own
  repo's toplevel can derive it:
  `: "${PARA_ORIGIN:=$(git -C "$PARA_PROJECT_DIR" remote get-url origin)}"`.
  para won't do that itself: for a project nested inside a larger repo it would
  walk up and clone the wrong thing.
- **`PARA_CLONE_BRANCH`** — which branch to check out. Applies at clone time
  only; to move an existing workspace, `para rm` then `para up`.

## Your own keys

**Any `PARA_FOO` you set here reaches your hooks, your project commands, and
your image build for free** — documented or not, no para change needed. That's
how a project declares its own knobs: the default template's `PARA_GH_AUTH` is
one, and a project that pre-pulls Docker images sets its own `PARA_PREPULL` and
reads it in `image-build.sh`. The engine never learns the key exists.

## Precedence

Two sourced bash files and the engine's defaults, in that order:

```
environment  >  user config  >  Parafile  >  para's defaults
```

No code implements that — it falls out of bash and two idioms:

```sh
: "${PARA_DOMAIN:=myapp.dev}"      # a value, unless the environment has one
PARA_ROUTES="${PARA_ROUTES-3000}"  # same, but the environment can set it empty
PARA_CLONE_DIR=src                 # "I insist" — legitimate for a project to say
```

So `PARA_ROUTES="3000" para up ws` works for a one-off.

## User config, not Parafile

Some knobs describe *your box*, not the project, so they belong in
`$XDG_CONFIG_HOME/para/config` — seed it with `para config init`, edit it with
`$EDITOR "$(para config path)"`. It's sourced bash with the same two idioms.

| Key | Default | What it does |
|---|---|---|
| `PARA_HTTPS_PORT` | `8443` | the port para's Caddy binds — `443` for port-less URLs ([Workspace URLs](./urls.md)) |
| `PARA_POOL` | `default` | the Incus storage pool |
| `PARA_BRIDGE` | `incusbr0` | the Incus bridge workspaces attach to |
| `PARA_IP_LO` / `PARA_IP_HI` | `200` / `249` | the band static IPs are allocated from |
| `PARA_CADDY_ADMIN` | Caddy's default | give para's Caddy its own admin address when something else has `localhost:2019` |

Nothing stops you putting a project key here, but a box-wide `PARA_PROJECT` or
`PARA_ROUTES` applies to *every* project on the machine, which is rarely what
you want. `para doctor` says so when it sees one.

`PARA_DOMAIN` is the deliberate exception: a personal wildcard domain is a
reasonable box-wide setting, and workspaces record their own domain, so
projects on different domains coexist.
