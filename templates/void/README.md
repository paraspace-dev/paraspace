# void, the ParaSpace base

The bundled [ParaSpace](../../README.md) template builds a Void Linux workspace
with a user, passwordless sudo, zsh, terminal definitions, and extension points
for shell drop-ins and completions. It clones and boots nothing by itself.

```sh
para init void
para mod add git docker gh
para image build
para up feat-x
```

`git` clones the project, `docker` boots a Compose stack when one exists, and
`gh` can authorize the shared SSH key. Add only the capabilities the project
uses. `dotfiles` adds the bundled personal shell, tmux, Neovim, and Claude Code
setup.

`PARA_ROUTES=8080` maps Caddy to port 8080 on the workspace container. Docker is
not involved in that mapping. A runit service under `svdir`, a process launched
by a hook, or anything else listening on that port works identically. Change or
empty the route when your project listens elsewhere or nowhere.

The template is a starting point you own after `para init`. See
[`docs/project-setup.md`](../../docs/project-setup.md) for the workflow and
[`docs/mods.md`](../../docs/mods.md) for composition rules.
