# The Parafile

`.paraspace/Parafile` is the per-project config: the few knobs para itself reads.
It is **sourced as bash**. Scalars use `: "${PARA_X:=…}"` so a real environment
variable still wins; arrays are set plainly.

Any `PARA_FOO` you set here — documented or not — is forwarded into your hooks'
environment for free, so the Parafile is also where a project declares its own
knobs (the default template's `PARA_GH_AUTH` is one). See
[Hooks](./hooks.md#the-environment-para-injects).

## Keys

### `PARA_PROJECT`

Project **identity** — the single key para uses for workspace ownership,
`para ls` scoping, and the shared-volume name. A plain slug (`[a-z0-9-]`),
independent of where the checkout lives, so moving or renaming the dir keeps
its workspaces bound to it. `para init` bakes it to the dir name; unset falls
back to the dir's basename.

### `PARA_IMAGE`

Base image alias `para up` launches. You build it with `para image-build` —
see [The image contract](./image.md). `para init` names it after your
directory.

### `PARA_BASE_IMAGE`

The Incus image `para image-build` launches its builder from — any image works
(`images:debian/13`, `images:voidlinux`, `images:alpine/edge`, …). **Required**
to build: para pins no default, so your image's distro is never para's choice
and can't change under you when para updates. `image-build` refuses with a clear
error until you declare one. Not used by `para up`, which launches the *built*
image (`PARA_IMAGE`).

### `PARA_IMAGE_BOOTSTRAP`

Optional one-liner run via `sh -c` inside the builder **before** your
`.paraspace/image-build.sh`. Its job is to leave bash in the image (para runs
the payload with `bash -s`) and to refresh the package index if the base needs
it — `xbps-install -Syu xbps bash` on Void (what the templates declare),
`apk add --no-cache bash` on Alpine, `apt-get update` on Debian. Unset or empty
means no bootstrap step; `--from-current` skips it. See
[The image contract](./image.md).

### `PARA_ORIGIN`

Git URL the clone hook clones. Project-declared — para does not guess it (a
toplevel Parafile can derive it from its own `origin`).

### `PARA_CLONE_DIR`

Directory under `~` to clone into. A guest path only — not tied to project
identity.

### `PARA_CLONE_BRANCH`

Optional: which branch the clone hook checks out. Handy for iterating on the
hooks themselves.

### `PARA_DOMAIN`

Wildcard domain workspaces are served under (`https://<name>.$PARA_DOMAIN`).
`*.$PARA_DOMAIN` must resolve to `127.0.0.1`. Default `paraspace.dev`, which
already resolves — see [Workspace URLs](./urls.md).

### `PARA_ROUTES`

A bash array of `"[sub:]port"` entries — one TLS Caddy site each. A bare port
is the workspace apex:

```sh
PARA_ROUTES=( "3000" "api:3001" )
# https://<name>.$PARA_DOMAIN      -> :3000
# https://api.<name>.$PARA_DOMAIN  -> :3001
```

As an array it is **not** forwarded to hooks — a hook that needs routes reads
them from the Parafile.

### `PARA_VOLUME`

Shared-volume name. Default `para-home-<PARA_PROJECT>`; pin several projects
to one name to share auth across them.

### `PARA_HOST_ENV`

Base `.env` seeded into the clone. Unset = the project's own `.env` if it has
one (else nothing); empty = always nothing; a set path must exist.

### `PARA_WORKCOPY_HOST` / `PARA_WORKCOPY_PORT`

Optional: proxy `https://localhost` to a working copy of the stack you run on
the **host**, so its familiar URL keeps working. Off unless `PARA_WORKCOPY_PORT`
is set (the port your host stack listens on); `PARA_WORKCOPY_HOST` defaults to
`localhost` and matters only when that stack terminates TLS with SNI.

### `PARA_VERSION`

Optional but recommended: the para contract version your hooks target. para
refuses with a clear error on a mismatch — see
[Contract versioning](./versioning.md).

## Machine config, not Parafile

Machine-level overrides live in `~/.config/para/config`, not the Parafile —
persist them with `para config-set KEY VALUE`. Notable ones:

- `PARA_HTTPS_PORT` — the port para Caddy binds (default `8443`; set `443` for
  port-less URLs — see [Workspace URLs](./urls.md)).
- `PARA_POOL` — the Incus storage pool; para writes this itself when it has to
  create a `dir` pool for nested Docker.

Precedence everywhere is: environment > machine config > Parafile default.
