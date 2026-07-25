# Cookbook

Recipes for things projects actually need. Each one is a fragment for your
`.paraspace/` — see [Project setup](./project-setup.md) for how the pieces fit
together, and [Hooks](./hooks.md) for the contract they run under.

## Authenticate `gh` during provisioning

`gh` keeps its login under `~/.config/gh`. Link that to the shared volume and
one `gh auth login` covers every workspace of the project, permanently.

```sh
# .paraspace/hooks/provision
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

The `PARA_NONINTERACTIVE` guard matters: `para up` runs hooks with a tty only
when there's a human on both ends, and `gh auth login` hangs forever without
one. Prompt when you can, warn when you can't, and never block.

To have `gh` upload the workspace key for you instead of printing it:

```sh
gh ssh-key add ~/.ssh/id_ed25519.pub --title "para $PARA_PROJECT ($PARA_HOSTNAME)"
```

That needs the `admin:public_key` scope — add
`--scopes admin:public_key` to the `gh auth login` above. The `void-docker-gh`
template does all of this behind `PARA_GH_AUTH=1`; read its `provision` hook
for the version with the error handling filled in.

## Share an agent's session

Same shape as `gh` — link whatever directory the tool keeps state in:

```sh
mkdir -p "$PARA_SHARED/claude"
ln -sfn "$PARA_SHARED/claude" ~/.claude
```

Sign in once in any workspace and every workspace of the project is signed in.
More in [Shared authentication](./shared-auth.md).

## Bring your dotfiles

Put them in `.paraspace/skel/`, which para pushes to `~/.paraspace/skel` before
hooks run. Copy them for files you'll edit per workspace, link them through the
shared volume for ones you want to change everywhere at once:

```sh
cp    ~/.paraspace/skel/zshrc  ~/.zshrc          # per workspace
mkdir -p "$PARA_SHARED/nvim"
ln -sfn "$PARA_SHARED/nvim" ~/.config/nvim       # shared across workspaces
```

`skel/` is re-pushed on every `up`, so editing a dotfile in your checkout and
re-running `para up` is the whole update loop — no image rebuild.

## Pre-pull images so the first boot is fast

`para` forwards every `PARA_*` to your image build, so a key it has never heard
of gets there anyway. Declare the tags in your `Parafile`:

```sh
: "${PARA_PREPULL_IMAGES:=postgres:17-alpine redis:8-alpine}"
```

and pull them in `image-build.sh`, where they bake into the base image once
instead of downloading in every workspace:

```sh
for img in $PARA_PREPULL_IMAGES; do
  docker pull -q "$img" || echo "warn: could not pre-pull $img" >&2
done
```

Both Docker templates ship that loop already.

## Seed a database

Boot the stack, then load a dump the workspace can reach. Keep the dump on the
shared volume so you download it once per project, not once per workspace:

```sh
# .paraspace/hooks/boot
docker compose up -d --wait

if [ ! -f "$PARA_SHARED/seed.sql" ]; then
  curl -fsSL "$SEED_URL" -o "$PARA_SHARED/seed.sql"
fi
docker compose exec -T db psql -U app app < "$PARA_SHARED/seed.sql"
```

Guard it if reseeding an existing workspace would be destructive — `boot` runs
on every `up`.

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

Anything your team types often. Drop an executable in `.paraspace/commands/`:

```sh
#!/usr/bin/env bash
# summary: tail the app logs
set -euo pipefail
exec "$PARA_BIN" sh "$1" -c 'docker compose logs -f --tail=100'
```

`chmod +x` it and `para logs ws1` works. It runs on the host with every
`PARA_*` exported — see [Commands](./commands.md#project-commands).

## Work on a project nested in a bigger repo

`para` finds the nearest `.paraspace/` walking up from `$PWD`, so a
subdirectory can have its own. One thing to avoid: deriving `PARA_ORIGIN` from
`git remote` in that case, since it walks up to the *enclosing* repo and clones
the wrong thing. Name the URL explicitly.

## Point two projects at one credential store

Give them the same volume name — `: "${PARA_VOLUME:=para-home-acme}"` — and both
projects' workspaces mount the same `/para/shared`. Only where you'd be happy
with either project's workspaces holding the other's credentials; see
[Shared authentication](./shared-auth.md#what-sharing-costs).
