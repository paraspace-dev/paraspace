# void-minimal — the barest paraspace box

The smallest possible [para](../../README.md) template: it **installs nothing and
boots nothing**. `para image build` + `para up <name>` stands up a Void Linux
workspace with a user and a shell, and that's it — `para sh <name>` drops you in.
Every place you'd normally add a toolchain, a clone, or an app is marked with a
comment pointing at where the code goes.

Use it when you want to start from a clean box and grow your own setup, rather
than trimming down the runnable [`void-docker-gh`](../void-docker-gh) template.

```
void-minimal/
  .paraspace/
    Parafile               # identity, the base image to build from, no routes
    hooks/image-build      # user + writable /tmp; the pkgs="" install block is EMPTY
    hooks/provision        # seed + link the shell rc; comments mark where a clone goes
    hooks/boot             # no-op: nothing to boot (returns 0 immediately)
    hooks/helpers          # colored output + small guards, sourced by the hooks
    skel/zshrc             # a small shell rc, seeded onto the shared volume
```

## Try it

```sh
npm i -g paraspace                      # once (or run bin/para from a checkout)
para image build                        # build the bare base image
para up box                             # stand up a workspace named "box"
para sh box                             # get a shell inside it
```

`para up` succeeds and the workspace runs, but it publishes **no URL** — this box
boots nothing, so its Parafile declares an empty `PARA_ROUTES` and `para ls` shows no
address for it. That's expected for a bare box: list a port in `PARA_ROUTES` once
you have something listening, and the URL appears on the next `para up`.

## Grow it into a real project

The scaffold tells you where each piece goes:

- **`hooks/image-build`** — the `pkgs=""` block is empty. Add your packages
  (`pkgs="zsh tmux neovim git"`, or `docker docker-compose` for a stack), then
  `para image build`. Installing `zsh` makes the provision hook switch your login
  shell to it so `skel/zshrc` applies.
- **`hooks/provision`** — add a clone step, `.env` handling, and richer
  shared-volume seeding. [`void-docker-gh`](../void-docker-gh/.paraspace/hooks/provision)
  is this same hook fully written out (git-key auth included).
- **`hooks/boot`** — put your app's start command here (e.g. `docker compose up
  -d --wait`) and return 0 only once the routed service is listening.
- **`Parafile`** — set `PARA_ORIGIN`/`PARA_CLONE_DIR`, and list your service's
  port in `PARA_ROUTES` (it ships as `PARA_ROUTES=""`, the explicit "serves no
  HTTP", because this box boots nothing).

For a fuller starting point, see [`void-docker-gh`](../void-docker-gh) — a
runnable docker demo. For a full personal dev environment on top of either, add
the [`dotfiles-jchook`](../../mods/dotfiles-jchook) mod instead of forking a
template: `para mod add dotfiles-jchook`.

Full schema + the hook/image contracts: [`../../docs/`](../../docs/README.md).
