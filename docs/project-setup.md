# Project setup

`para` needs one thing from a project: a **`.paraspace/`** directory at the repo
root, holding a **`Parafile`** (config) and a **`hooks/`** dir (provisioning).
`para` finds your project by walking up from `$PWD` for the `.paraspace/` dir.

## Scaffold with `para init`

From your project root:

```sh
para init              # scaffold .paraspace/ from the void-docker-gh template
para init --list       # see available templates
para init <template>   # a specific one
```

It copies the template's `.paraspace/` (Parafile + hooks + skel +
image-build.sh) into the current directory, **skipping any file that already
exists** — so it safely adds `para` to an existing repo without touching your
code — and sets the project's identity (`PARA_PROJECT`) to your directory name.
The base image (`PARA_IMAGE`) derives from that, so it's named for your project
without the Parafile having to carry the name twice.

## Make it yours

The scaffolded files are commented and carry working defaults — read them in
place. The usual adaptation is:

1. **`Parafile`** — point `PARA_ORIGIN` at your repo and list your
   `PARA_ROUTES` (one `https://` site per routed port). Every key is documented
   in [the Parafile reference](./parafile.md).
2. **`hooks/provision`** — everything before boot: seed the shared volume,
   clone, render `.env`. The template's version already handles the common
   case; see [Hooks](./hooks.md) for the contract.
3. **`hooks/boot`** — bring your stack up (compose: `up -d --wait`). Return
   zero only once every routed service is actually listening.
4. **`image-build.sh`** — the packages and pre-pulled images your stack needs
   baked into the base image; see [The image contract](./image.md).

Then build and launch:

```sh
para image build       # build the project's base image (per arch, several min)
para up my-feature     # clone, provision, boot
```

`para up` is idempotent — on an existing or stopped workspace it (re)starts and
reconverges instead of erroring, so fixing a hook and re-running is the normal
loop.

## What's in `.paraspace/`

| Entry | Read by | Purpose |
|---|---|---|
| `Parafile` | `para` (host-side) | the keys `para` reads — [reference](./parafile.md) |
| `hooks/` | the workspace | `provision`, `boot`, plus any shared code they source |
| `skel/` | your hooks | seed files (dotfiles etc.) synced to `~/.para/skel` |
| `image-build.sh` | `para image build` (host-side) | builds the base image |

`.paraspace/` is set-up-once plumbing, hidden like `.github` — commit it with the
project so every machine (and every teammate) gets the same workspaces.

## Pin the contract

Set `PARA_VERSION` in the `Parafile` to the `para` contract you build against.
A globally-updated `para` then refuses with a clear error instead of silently
misbehaving if the interface changed — see
[Contract versioning](./versioning.md).
