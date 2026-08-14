# Cookbook

Recipes for the things projects keep needing. Each one is a fragment for your
`.paraspace/`. See [Project setup](./project-setup.md) for how the pieces fit
together, and [Hooks](./hooks.md) for the contract they run under.

## Authenticate `gh` during provisioning

`gh` keeps its login under `~/.config/gh`. Link that to the shared volume and
one `gh auth login` covers every workspace of the project, permanently.

```sh
# .paraspace/layers/project/hooks/provision
mkdir -p "$PARA_SHARED/gh"
ln -sfn "$PARA_SHARED/gh" ~/.config/gh

if ! gh auth status >/dev/null 2>&1; then
  if [ -z "${PARA_NONINTERACTIVE:-}" ]; then
    gh auth login --hostname github.com --git-protocol ssh
  else
    echo "warn: gh is not authenticated; run 'para sh $PARA_NAME -c \"gh auth login\"'" >&2
  fi
fi
```

The `PARA_NONINTERACTIVE` guard matters. `para up` runs hooks with a tty only
when there's a human on both ends, and `gh auth login` hangs forever without
one. Prompt when you can, warn when you can't, and never block.

To have `gh` upload the workspace key for you instead of printing it:

```sh
gh ssh-key add ~/.ssh/id_ed25519.pub --title "para $PARA_PROJECT_NAME ($PARA_HOSTNAME)"
```

That needs the `admin:public_key` scope, so add
`--scopes admin:public_key` to the `gh auth login` above. The bundled `gh`
layer does this behind `PARA_GH_AUTH=1` at the `git` layer's `git:before`
point. Read its hook for the version with the retry marker and error handling
filled in.

## Share an agent's session

Same shape as `gh`. Link whatever directory the tool keeps state in:

```sh
mkdir -p "$PARA_SHARED/claude"
ln -sfn "$PARA_SHARED/claude" ~/.claude
```

Sign in once in any workspace and every workspace of the project is signed in.
More in [Shared authentication](./shared-auth.md).

## Bring your dotfiles

Put them in `.paraspace/layers/project/skel/`, and copy them from the layer for
files you'll edit per workspace. Link them through the shared volume for ones
you want to change everywhere at once:

```sh
cp "$PARA_LAYER_DIR/skel/zshrc" ~/.zshrc          # per workspace
mkdir -p "$PARA_SHARED/nvim"
ln -sfn "$PARA_SHARED/nvim" ~/.config/nvim        # shared across workspaces
```

`skel/` is re-pushed on every `up`, so editing a dotfile in your checkout and
re-running `para up` is the whole update loop, with no image rebuild.

If someone has already packaged the set you want, add it instead of writing
this by hand. `para add dotfiles` provides a zsh/tmux/Neovim/Claude Code
environment and the hooks that install it. Its layer stays under `node_modules`
and updates with the package. See [Layers](./layers.md).

## Pre-pull images so the first boot is fast

`para` forwards every `PARA_*` to your image build, so a key it has never heard
of gets there anyway. Declare the tags in your `.paraspace/env`:

```sh
: "${PARA_PREPULL_IMAGES:=postgres:17-alpine redis:8-alpine}"
```

and pull them in `hooks/image-build`, where they bake into the base image once
instead of downloading in every workspace:

```sh
for img in $PARA_PREPULL_IMAGES; do
  docker pull -q "$img" || echo "warn: could not pre-pull $img" >&2 &
done
wait
```

The bundled `docker` layer ships that loop already.

## Seed a database

Boot the services, then load a dump the workspace can reach. Keep the dump on
the shared volume so you download it once per project, not once per workspace:

```sh
# .paraspace/layers/project/hooks/boot
docker compose up -d --wait

if [ ! -f "$PARA_SHARED/seed.sql" ]; then
  curl -fsSL "$SEED_URL" -o "$PARA_SHARED/seed.sql"
fi
docker compose exec -T db psql -U app app < "$PARA_SHARED/seed.sql"
```

Guard it if reseeding an existing workspace would be destructive, because
`boot` runs on every `up`.

## Serve more than one port

One `PARA_ROUTES` entry per site. A bare port is the workspace apex; `sub:port`
adds a subdomain:

```sh
PARA_ROUTES="
  3000
  api:3001
  mail:8025
"
```

That publishes `https://<name>.<domain>`, `https://api.<name>.<domain>` and
`https://mail.<name>.<domain>`. Your `boot` hook should wait for all of them:

```sh
for route in $PARA_ROUTES; do
  port="${route##*:}"
  timeout 60 sh -c "until nc -z localhost $port; do sleep 1; done"
done
```

## A workspace with no HTTP

A worker, a queue consumer, a bare box to poke at. Declare no routes:

```sh
PARA_ROUTES=""
```

`para up` still gives you a full workspace and `para sh`; it just publishes no
site, and `para ls` shows no URL.

## Add a `para` verb

Anything your team types often. Drop an executable in
`.paraspace/layers/project/commands/`:

```sh
#!/usr/bin/env bash
# summary: tail the app logs
set -euo pipefail
exec "$PARA_BIN" sh "$1" -c 'docker compose logs -f --tail=100'
```

`chmod +x` it and `para logs ws1` works. It runs on the host with every
`PARA_*` exported. See [Commands](./commands.md#project-commands).

## A monorepo with more than one service set

If you don't want every sub-project booting in every workspace, there are two
ways to avoid it.

### One `.paraspace/` per project

para uses the nearest `.paraspace/` above `$PWD`, so `cd` picks the project:

```sh
cd apps/web  && para up web-ws     # apps/web/.paraspace
cd apps/docs && para up docs-ws    # apps/docs/.paraspace
```

```sh
# apps/docs/.paraspace/env
: "${PARA_PROJECT_NAME:=acme-docs}"    # "docs" alone is too generic to identify a project
```

Both clone the whole monorepo, since `PARA_ORIGIN` resolves by walking up to the
repository each `.paraspace/` sits in.

### One workspace, a custom env var

Keep a single `.paraspace/` and let a variable decide which services `boot`
starts. The hooks store it in the workspace, so you pass it once:

```sh
# .paraspace/layers/project/hooks/provision
PROFILE_FILE="$HOME/.para-profile"
if [ -n "${PARA_PROFILE:-}" ]; then printf '%s\n' "$PARA_PROFILE" > "$PROFILE_FILE"; fi
if [ -f "$PROFILE_FILE" ]; then PARA_PROFILE="$(cat "$PROFILE_FILE")"; fi
: "${PARA_PROFILE:=web}"
```

```sh
# .paraspace/layers/project/hooks/boot
docker compose --profile "$PARA_PROFILE" up -d --wait
```

`PARA_PROFILE=docs para up ws1` sets that workspace's profile, and a later
`para up ws1` reconverges the same one.

For a verb rather than an env var, a
`.paraspace/layers/project/commands/docs` that exports `PARA_PROFILE=docs` and
runs `exec "$PARA_BIN" up "$@"` gives you `para docs ws1`.

## Point two projects at one credential store

Give them the same volume name (`: "${PARA_VOLUME:=para-home-acme}"`) and both
projects' workspaces mount the same `/para/shared`. Only do that where you'd be
happy with either project's workspaces holding the other's credentials; see
[Shared authentication](./shared-auth.md).
