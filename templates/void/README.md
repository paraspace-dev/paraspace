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

The scaffolded Parafile contains only `PARA_CONTRACT=1` as active configuration.
Add `PARA_ROUTES` for a runit service or another process, or add the Docker mod
and let it propose routes from Compose when the required host tools are present.
Routes remain ordinary Caddy-to-workspace mappings; Docker is not involved once
they have been declared.

The template is a starting point you own after `para init`. See
[`docs/project-setup.md`](../../docs/project-setup.md) for the workflow and
[`docs/mods.md`](../../docs/mods.md) for composition rules.
