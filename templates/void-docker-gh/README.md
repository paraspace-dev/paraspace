# void-docker-gh — the runnable paraspace starter

A small, complete [para](../../README.md) template on Void Linux: just a
`.paraspace/` config — no app of its own. Out of the box it points at a tiny public
demo repo ([`jchook/docker-caddy`](https://github.com/jchook/docker-caddy), one
Caddy service on `:8080`), so you can watch para clone, provision, route, and
boot before pointing it at your own project. The **`gh`** in the name is the git
auth on offer: para prints its ssh key for you to add by hand, or (`PARA_GH_AUTH=1`)
lets the GitHub CLI upload it for you — the path a private repo needs.

This is what `para init` scaffolds by default. Its siblings:
[`void-minimal`](../void-minimal) (the barest box — installs and runs nothing,
just comments showing where to start) and [`void-jchook`](../void-jchook) (this
same demo carrying a full personal dev environment — zsh, tmux, Neovim, Claude Code).

```
void-docker-gh/
  .paraspace/                # all the para plumbing — hidden, set-up-once
    Parafile               # the few knobs para reads (version, image, origin, routes)
    hooks/provision        # seed+link the shared volume, clone, copy .env
    hooks/boot             # docker compose up -d --wait
    hooks/helpers          # colored output + small guards, sourced by the hooks
    image-build.sh         # the base image (docker + git + a $PARA_USER user)
    skel/zshrc             # dotfiles seeded onto the shared volume
```

## Try it

```sh
# install para once (from a paraspace checkout), if you haven't
bin/para install                        # -> ~/.local/bin/para

# from a copy of this .paraspace/ (or after `para init`) — needs incus + caddy;
# see the ParaSpace README for one-time host setup
para image build                        # build the base image
para up demo                            # clone + provision + boot a workspace
para web demo                           # open https://demo.<your PARA_DOMAIN>
```

On the **first** `up`, para prints this machine's para ssh key and pauses — add it
to your git host, press Enter, and the clone proceeds. (For a private repo, set
`PARA_GH_AUTH=1` in the `Parafile` and `gh` uploads the key for you instead.)

## Make it yours

Drop this `.paraspace/` into your own repo — `para init` copies it in and names the
base image after your directory. Then edit `.paraspace/`:

- **`Parafile`** — point `PARA_ORIGIN` at your repo, list your `PARA_ROUTES`
  (`"[sub:]port"` each), set `PARA_CLONE_DIR`.
- **`hooks/provision`** — grow the shared-volume seeding and `.env` handling for
  your stack. It's yours; make it as robust as you like.
- **`hooks/boot`** — the readiness contract: return 0 only once every routed
  service is actually listening (`docker compose up -d --wait` does this when your
  services have healthchecks).
- **`image-build.sh`** — add your toolchain. Keep the image contract:
  docker→overlayfs, a `$PARA_USER`/`$PARA_UID` user in the `docker` group,
  bash + git.

Your services must publish their routed ports on `0.0.0.0` (docker's default
`"8080:80"` mapping does), so para Caddy can reach them at the container's IP.

Full schema + the hook/image contracts: [`../../docs/`](../../docs/README.md).
