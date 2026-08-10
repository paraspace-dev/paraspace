# void-docker-gh, the runnable paraspace starter

A small, complete [para](../../README.md) template on Void Linux, just a
`.paraspace/` config with no app of its own. Each workspace clones whatever
`PARA_ORIGIN` names, which defaults to the git origin of the checkout you ran
`para init` in, so the scaffold runs against your own repo without an edit. The
**`gh`** in the name is the git auth on offer. para prints its ssh key for you
to add by hand, or (`PARA_GH_AUTH=1`) lets the GitHub CLI upload it for you,
the path a private repo needs.

This is what `para init` scaffolds by default. Its sibling is
[`void-minimal`](../void-minimal), the barest box, installing and running
nothing, just comments showing where to start. To carry a full personal dev
environment (zsh, tmux, Neovim, Claude Code) on top of this one, add the
[`dotfiles-jchook`](../../mods/dotfiles-jchook) mod rather than forking:
`para mod add dotfiles-jchook`.

```
void-docker-gh/
  .paraspace/                # all the para plumbing, hidden and set-up-once
    Parafile               # the few knobs para reads (version and routes; the rest have defaults)
    hooks/provision        # seed+link the shared volume, clone, copy .env
    hooks/boot             # docker compose up -d --wait
    hooks/helpers          # colored output + small guards, sourced by the hooks
    hooks/image-build      # the base image (docker + git + a $PARA_USER user)
    skel/zshrc             # dotfiles seeded onto the shared volume
```

## Try it

```sh
# install para once, if you haven't
npm i -g paraspace                      # or run it from a checkout: bin/para

# in an empty directory, so PARA_ORIGIN lands on the demo app rather than on
# whatever repo you're standing in. Needs incus + caddy; see the ParaSpace
# README for one-time host setup
mkdir para-demo && cd para-demo
para init void-docker-gh                # scaffold this .paraspace/
                                        # then uncomment PARA_ORIGIN in it
para image build                        # build the base image
para up demo                            # clone + provision + boot a workspace
para web demo                           # open https://demo.<your PARA_DOMAIN>
```

With no git origin to read, `para init` writes
[`paraspace-dev/example-docker-app`](https://github.com/paraspace-dev/example-docker-app)
into the scaffolded `Parafile`'s commented `PARA_ORIGIN`, one Caddy service on
`:8080`, the port this template routes. Uncomment it and the demo clones. In a
repo of your own there is nothing to uncomment, since `PARA_ORIGIN` already
resolves to that repo's origin.

On the **first** `up`, para prints this machine's para ssh key and pauses. Add it
to your git host, press Enter, and the clone proceeds. (For a private repo, set
`PARA_GH_AUTH=1` in the `Parafile` and `gh` uploads the key for you instead.)

## Make it yours

Drop this `.paraspace/` into your own repo. `para init` copies it in and sets the
project's identity (`PARA_PROJECT_NAME`) to your directory name, which the
base image name derives from. Then edit `.paraspace/`:

- **`Parafile`.** List your `PARA_ROUTES` (`"[sub:]port"` each,
  comma/space/newline separated). Each workspace clones the origin of the
  checkout the `Parafile` sits in, so set `PARA_ORIGIN` only to clone something
  else. To clone somewhere other than `~/app`, uncomment `PARA_CLONE_DIR` in the
  optional block.
- **`hooks/provision`.** Grow the shared-volume seeding and `.env` handling for
  your stack. It's yours; make it as robust as you like.
- **`hooks/boot`.** The readiness contract is to return 0 only once every routed
  service is actually listening (`docker compose up -d --wait` does this when your
  services have healthchecks).
- **`hooks/image-build`.** Add your toolchain, and keep the image contract:
  docker→overlayfs, a `$PARA_USER`/`$PARA_UID` user in the `docker` group,
  bash + git.

Your services must publish their routed ports on `0.0.0.0` (docker's default
`"8080:80"` mapping does), so para Caddy can reach them at the container's IP.

Full schema + the hook/image contracts: [`../../docs/`](../../docs/README.md).
