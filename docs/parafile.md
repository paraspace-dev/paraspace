# The Parafile

`.paraspace/Parafile` is your project's config, the few `PARA_*` variables
`para` itself reads. It is **sourced as bash** and follows the
[precedence](#precedence) rules. Most vars default sensibly and can be left out
for a lean and simple config.

Every value is a **scalar**. An array is not forwarded to your hooks (it
arrives as its first element), so write a list as a delimited string. See
[Hooks](./hooks.md#the-environment-para-injects).

## A minimal Parafile

ParaSpace can't guess which port your app listens on, so a project that serves
HTTP declares `PARA_ROUTES`. Everything else has a default, and `PARA_ORIGIN`
and `PARA_IMAGE_BOOTSTRAP` derive theirs from your project rather than pinning
one, so a whole `Parafile` can be two lines:

```sh
: "${PARA_CONTRACT:=1}"
PARA_ROUTES="${PARA_ROUTES-8080}"
```

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
| `PARA_READY_HOST` | `paraspace.dev` | a hostname the guest must resolve before hooks run |
| `PARA_USER` / `PARA_UID` / `PARA_GID` | `app` / `1000` / `1000` | the workspace user para runs everything as |
| `PARA_WORKCOPY_PORT` | none | proxy `https://localhost` to a stack you run on the **host** |
| `PARA_WORKCOPY_HOST` | `localhost` | matters only if that host stack terminates TLS with SNI |

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

The order is **`sub:port`**, so left is where you arrive and right is where it
goes, the same direction as `docker -p` and `ssh -L`.

Commas, spaces, tabs and newlines all separate entries, so a long list can go
one route per line. [Hooks](./hooks.md#the-environment-para-injects) see one
normalized space-separated list.

`caddy validate` runs before every reload, so any configuration issues
fail loudly.

Empty means this workspace serves no HTTP, which is what a worker or a bare box
wants. `para ls`
shows no URL, `$PARA_URL` is empty in your hooks, and `para doctor` mentions it
in case you didn't mean it. Note that only a **bare port** creates
`https://<name>.$PARA_DOMAIN`; a subdomain-only list has no apex site.

### `PARA_IMAGE_NAME`

Set it only to point several projects at one image, or to name an image built
elsewhere. Aliases are Incus-daemon-global, so two projects naming the same
image share it, and `para image build` in either republishes it for both.

### `PARA_IMAGE_BASE` and `PARA_IMAGE_BOOTSTRAP`

Any Incus image works as a base (`images:debian/13`, `images:voidlinux`,
`images:alpine/edge`, …), and para defaults to `images:voidlinux`, which is what
the bundled templates' `hooks/image-build` are written against.

The bootstrap is one `sh -c` line run in the builder before your
`.paraspace/hooks/image-build`. Its job is to leave **bash** in the image, since
para runs that hook with `bash`. para fills it in from the base you name:

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
default template, the `PARA_PREPULL_IMAGES` the templates' `hooks/image-build`
reads). See
[Hooks](./hooks.md#the-environment-para-injects), and
[One workspace, a custom env var](./cookbook.md#one-workspace-a-custom-env-var)
for varying one per workspace.

> 💡 `para` never clones anything, so `PARA_ORIGIN` and `PARA_CLONE_BRANCH` are
> resolved and forwarded, and your provision hook is what acts on them.

## Precedence

Two sourced bash files and the engine's defaults, in that order:

```
environment  >  user config  >  Parafile  >  para's defaults
```

Write your vars with these idioms and the environment can still win:

```sh
: "${PARA_DOMAIN:=myapp.dev}"      # a value, unless the environment has one
PARA_ROUTES="${PARA_ROUTES-3000}"  # same, but the environment can set it empty
PARA_CLONE_DIR=src                 # "I insist", legitimate for a project to say
```

So `PARA_ROUTES="3000" para up ws` works for a one-off.

## User config, not Parafile

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
