# The env file

`.paraspace/env` is your project's config, the few `PARA_*` variables
`para` itself reads. It is **sourced as bash** and follows the
[precedence](#precedence) rules. Most vars have a sensible default, so leave out
the ones you don't need.

Every value is a **scalar**. An array is not forwarded to your hooks (it
arrives as its first element), so write a list as a delimited string. See
[Hooks](./hooks.md#the-environment-para-injects).

## A minimal env file

Everything has a safe default, and optional layers may propose settings they can
infer, so the env file scaffolded by `para init` has one line:

```sh
PARA_CONTRACT=1
```

A project serving HTTP still needs `PARA_ROUTES`; declare it manually, or let
the Docker layer propose it from a resolved Compose model when `para init` or
`para add` runs. Existing declarations always win, including
`PARA_ROUTES=""`. A layer's host-side `configure` script never runs during
`para up`.

## Every var para reads

| Var | Default | What it does |
|---|---|---|
| `PARA_CONTRACT` | none | the [contract](./versioning.md) your `.paraspace/` targets. para refuses on a mismatch |
| `PARA_PROJECT_NAME` | the directory name, slugified (`My.App` → `my-app`) | project identity: workspace ownership, `para ls` scoping, the shared-volume name |
| `PARA_IMAGE_NAME` | `$PARA_PROJECT_NAME` | the image `para up` launches and `para image build` publishes |
| `PARA_IMAGE_BASE` | `images:voidlinux` | the Incus image `para image build` builds *from* |
| `PARA_IMAGE_BOOTSTRAP` | [derived from the base](#para_image_base-and-para_image_bootstrap) | one `sh -c` line run in the builder before your `image-build` hook |
| `PARA_ORIGIN` | [the project checkout's git origin](#para_origin) | the repo your provision hook clones |
| `PARA_ROUTES` | empty | `[sub:]port` entries, one Caddy site each |
| `PARA_DOMAIN` | `paraspace.dev` | wildcard domain workspaces are served under |
| `PARA_VOLUME` | `para-home-$PARA_PROJECT_NAME` | the shared home volume's name |
| `PARA_CLONE_DIR` | `app` | directory under `~` to clone into; also where `para sh` starts |
| `PARA_CLONE_BRANCH` | empty | the branch your provision hook clones, if it reads this |
| `PARA_HOST_ENV` | `$PARA_PROJECT_DIR/.env` | a base `.env` pushed to `~/.paraspace/host.env` **if the file exists** |
| `PARA_READY_HOST` | `paraspace.dev` | a hostname the guest must resolve before hooks run. Empty skips the wait, which belongs in your [user config](#user-config-vs-the-env-file) |
| `PARA_USER` / `PARA_UID` / `PARA_GID` | `app` / `1000` / `1000` | the workspace user para runs everything as |
| `PARA_WORKCOPY_PORT` | none | proxy `https://localhost` to a copy of the app or services you run on the **host** |
| `PARA_WORKCOPY_HOST` | `localhost` | matters only if that host copy terminates TLS with SNI |

Anything else you set is [forwarded to your hooks](#your-own-vars) untouched.

## The ones with subtleties

### `PARA_ROUTES`

A list of `[sub:]port` entries, one TLS Caddy site each. A bare port is the
workspace apex:

```sh
PARA_ROUTES="3000,api:3001"
# https://<name>.$PARA_DOMAIN      -> :3000
# https://api.<name>.$PARA_DOMAIN  -> :3001
```

Caddy proxies each site to that port on the workspace container. The listener
can be a Docker container, a runit service under `svdir`, a process started by
your boot hook, or anything else bound there. Routing has no Docker dependency.

The order is **`sub:port`**, so left is where you arrive and right is where it
goes, the same direction as `docker -p` and `ssh -L`.

Commas, spaces, tabs and newlines all separate entries, so a long list can go
one route per line. [Hooks](./hooks.md#the-environment-para-injects) see one
normalized space-separated list.

`caddy validate` runs before every reload, so any configuration issues
fail loudly.

Empty means this workspace serves no HTTP, which is what a worker or a bare box
wants. `para ls` shows no URL, `$PARA_URL` is empty in your hooks, and
`para doctor` mentions it in case you didn't mean it. Only a **bare port**
creates `https://<name>.$PARA_DOMAIN`, so a subdomain-only list has no apex
site.

### `PARA_STACK`

`PARA_STACK` is derived from `.paraspace/stack` on every invocation and cannot
be overridden by a declaration in `.paraspace/env`. Comments and blank lines
are dropped, whitespace is trimmed, and the result contains one resolved
directory path per line in the order listed.

It holds host paths on the host and guest paths in the guest. Hooks can read it
to inspect the composition. See [Layers](./layers.md) for the stack file.

### `PARA_IMAGE_NAME`

Set it only to point several projects at one image, or to name an image built
elsewhere. Aliases are Incus-daemon-global, so two projects naming the same
image share it, and `para image build` in either republishes it for both.

### `PARA_IMAGE_BASE` and `PARA_IMAGE_BOOTSTRAP`

Any Incus image works as a base (`images:debian/13`, `images:voidlinux`,
`images:alpine/edge`, …), and para defaults to `images:voidlinux`, which is what
the bundled `base/void` layer and the other bundled layers target.

The bootstrap is one `sh -c` line run in the builder before your `image-build`
hook. Its job is to leave **bash** in the image, since para runs that hook with
`bash`. para fills it in from the base you name:

| Base contains | Bootstrap |
|---|---|
| `voidlinux` | `xbps-install -Syu xbps bash` (Void's bundled xbps is a snapshot too stale to install against, so it refreshes itself first) |
| `alpine` | `apk add --no-cache bash` |
| anything else | empty, so declare your own. Debian and Ubuntu ship bash but no package index, so a hook that installs anything wants `apt-get update` |

A base that needs nothing declares `PARA_IMAGE_BOOTSTRAP=""`, and that survives:
para fills in an **unset** value, never an empty one. `para image build` prints
the line it runs.

### `PARA_ORIGIN`

The repo each workspace clones. para never acts on it, but it defaults it to
`git remote get-url origin` in your project checkout, so a `.paraspace/` living
in the repo it describes doesn't declare it at all. The lookup walks up from
`$PARA_PROJECT_DIR` the way git does, so a `.paraspace/` in a monorepo
subdirectory resolves to the monorepo's origin.

Declare it to clone a different repo, and expect the
[provision hook](./hooks.md#provision) to refuse when there's neither a
declaration nor an origin to derive one from. `para doctor` reports which repo
it resolved to.

### `PARA_USER` / `PARA_UID` / `PARA_GID`

The workspace user para runs hooks and `para sh` as, and chowns every pushed
file to. Your `hooks/image-build` creates that user, and gets all three in its
environment. If you change them, **rebuild the image**, or the chowns land on a
uid with no passwd entry and the shared volume becomes unwritable.

## Your own vars

Any `PARA_FOO` you set reaches your hooks, project commands and image build
untouched, which is how a project declares its own knobs (`PARA_GH_AUTH` in the
`gh` layer, or `PARA_PREPULL_IMAGES` in the `docker` layer). See
[Hooks](./hooks.md#the-environment-para-injects), and
[One workspace, a custom env var](./cookbook.md#one-workspace-a-custom-env-var)
for varying one per workspace.

> 💡 `para` never clones anything. It resolves and forwards `PARA_ORIGIN` and
> `PARA_CLONE_BRANCH`; the bundled `git` layer is one provision hook that acts
> on them.

## Precedence

Two sourced bash files and the engine's defaults, in that order:

```
environment  >  user config  >  project env  >  para's defaults
```

Write your vars with these idioms and the environment can still win:

```sh
PARA_CLONE_DIR=src                 # "I insist"
: "${PARA_DOMAIN:=myapp.dev}"      # a value, unless the environment has one
PARA_ROUTES="${PARA_ROUTES-3000}"  # same, but the environment can set it empty
```

Write a key the second way and `PARA_DOMAIN=other.test para up ws` wins for
that one run. The scaffolded env states `PARA_CONTRACT=1` flatly, because a
contract pin the environment can move cannot refuse a mismatch.

## User config vs. the env file

Some knobs describe *your box*, not the project, so they belong in
`$XDG_CONFIG_HOME/para/config`. Open it with `para config edit`, which creates
it from a commented template on first use. It's sourced bash with the same two
idioms.

| Var | Default | What it does |
|---|---|---|
| `PARA_HTTPS_PORT` | `8443` | the port para's Caddy binds, `443` for port-less URLs ([Workspace URLs](./urls.md)) |
| `PARA_POOL` | `default` | the Incus storage pool |
| `PARA_BRIDGE` | `incusbr0` | the Incus bridge workspaces attach to |
| `PARA_IP_LO` / `PARA_IP_HI` | `200` / `249` | the band static IPs are allocated from |
| `PARA_CADDY_ADMIN` | Caddy's default | give para's Caddy its own admin address when something else has `localhost:2019` |

Nothing stops you putting a project var here, but a box-wide
`PARA_PROJECT_NAME` or `PARA_ROUTES` applies to *every* project on the machine,
which is rarely what you want. `para doctor` says so when it sees one.
