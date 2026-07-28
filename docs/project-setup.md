# Project setup

`para` needs one thing from a project: a **`.paraspace/`** directory at the repo
root. `para` finds it by walking up from `$PWD`.

## Scaffold with `para init`

From your project root:

```sh
para init              # scaffold from the void-docker-gh template
para init --list       # see available templates
para init <template>   # a specific one
```

It copies the template's `.paraspace/` into the current directory, **skipping
any file that already exists** — so it safely adds `para` to an existing repo
without touching your code. The scaffolded `Parafile` already pins the
[contract](./versioning.md) it was written against, so there's nothing to set
up there.

## What's in `.paraspace/`

| Entry | Read by | Purpose |
|---|---|---|
| `Parafile` | `para`, host-side | the keys para reads — [reference](./parafile.md) |
| `hooks/` | the workspace, and the image builder | `provision`, `boot` and `image-build`, plus anything they source |
| `skel/` | your hooks | seed files (dotfiles etc.) your hooks copy or link |
| `commands/` | `para`, host-side | your own `para` verbs — [reference](./commands.md#project-commands) |
| `mods/` | `para` host-side, the workspace, and the image builder | reusable pieces you vendored with `para mod add`, hooks and verbs both — [reference](./mods.md) |

It's set-up-once plumbing, hidden like `.github`. Commit it, so every machine
and every teammate gets the same workspaces.

## Make it yours

The scaffolded files are commented and carry working defaults — read them in
place. The usual adaptation, in order:

1. **`Parafile`** — point `PARA_ORIGIN` at your repo, list your `PARA_ROUTES`
   (one entry per port you want a URL for), and name a `PARA_IMAGE_BASE`.
   Every var is in [the Parafile reference](./parafile.md).
2. **`hooks/image-build`** — the packages your stack needs baked into the base
   image, and the workspace user. See [The image contract](./image.md).
3. **`hooks/provision`** — everything before boot: seed the shared volume,
   clone, render `.env`. The template's version handles the common case.
4. **`hooks/boot`** — bring your stack up, and return zero only once every
   routed service is actually listening. See [Hooks](./hooks.md).

Then build and launch:

```sh
para image build       # per arch, several minutes
para up my-feature     # clone, provision, boot
```

`para up` is idempotent — on an existing or stopped workspace it restarts and
reconverges instead of erroring, so "fix a hook, re-run `up`" is the normal
loop.

The [Cookbook](./cookbook.md) has recipes for what usually comes next:
authenticating `gh`, seeding a database, bringing your dotfiles, pre-pulling
images, splitting a monorepo, and adding `para` verbs of your own.

## Add your own env vars

Any `PARA_*` variable you set in your `Parafile` reaches the hooks, the project
commands and `hooks/image-build`. See [the Parafile](./parafile.md#your-own-vars).

```sh
# Custom env var
: "${PARA_CUSTOM:=my-scalar-value}"
```

## Add your own verbs

Anything your team types often can become a `para` verb: drop an executable in
`.paraspace/commands/` and `para <name>` runs it on the host with every `PARA_*`
exported. `void-docker-gh` ships `web` and `key` as examples to keep or delete
(`void-minimal` ships none). See [Commands](./commands.md#project-commands).

## Templates

Two runnable templates share one shape and vary in weight:

- **`void-docker-gh`** — the `para init` default: a small, complete Docker demo
  that exercises the whole mechanism.
- **`void-minimal`** — the barest box. Installs and runs nothing, with comments
  marking where your stack goes.

Each has its own README in
[`templates/`](https://github.com/paraspace-dev/paraspace/tree/main/templates).

For a piece you'd rather keep as a dependency than own outright — someone's
dotfiles, a credential helper — `para mod add` vendors one into
`.paraspace/mods/`. See [Mods](./mods.md).
