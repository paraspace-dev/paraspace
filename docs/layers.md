# Layers

A layer is a directory that contributes project setup to a ParaSpace workspace.
It may contain `hooks/`, `skel/`, `commands/`, and a `configure` script. Every
part is optional.

Hooks run in stack order. See [Hooks](./hooks.md) for the hook contract. A
layer can keep seed files in `skel/`; its hooks can copy them from
`$PARA_LAYER_DIR/skel`. Files in `commands/` provide project commands as
described in [Commands](./commands.md).

On every `para up`, the resolved layers are pushed into the workspace fresh at
`~/.paraspace/stack/<layer name>`. Symlinks are followed on the push, so a
package installed with `npm link` or `bun link` lands as real files in the
guest. See [Hooks](./hooks.md) for the guest layout.

## The stack file

`.paraspace/stack` is the project's layer list. It contains one directory path
per line:

```text
node_modules/paraspace/layers/base/void
node_modules/paraspace/layers/docker
node_modules/paraspace/layers/git
.paraspace/layers/project
```

Inspect or edit it directly:

```sh
cat .paraspace/stack
${EDITOR:-vi} .paraspace/stack
```

The list composes from top to bottom. `para` resolves each nonblank,
noncomment line against the project root. Leading and trailing whitespace and
trailing slashes are ignored. Each resolved path must already be a directory
before `para` performs an operation. Blank lines and lines beginning with `#`
are ignored, so comments can document a non-obvious choice.

The paths are literal. `para` does not search for layer names, resolve
packages at runtime, or normalize equivalent paths. In a hoisted monorepo,
write the path that is true for this project, such as `../../node_modules/...`.

Check the resolved stack order with:

```sh
para doctor
```

If a layer under `node_modules/` is missing after a fresh clone, install the
project's dependencies:

```sh
npm install
```

Each layer also needs a unique layer name. Bundled and plugin layers use their
catalog names, project-owned layers keep their path beneath
`.paraspace/layers/`, and other paths use their final directory name. If two
entries share a name, rename one directory or copy one under
`.paraspace/layers/` with a different name.

After changing the list by hand, run:

```sh
para init
```

This rechecks the list and reruns layer configuration without recreating
entries already present.

## Start a project

Install `para` as a project dependency, then create the `.paraspace/`
directory:

```sh
npm install --save-dev paraspace
para init
```

A bare `para init` writes a stack with `node_modules/paraspace/layers/base/void`
first and `.paraspace/layers/project` last. It creates the env file, the layer
list, and the project-owned layer with `image-build`, `provision`, and `boot`
hook stubs. Use that layer for setup specific to this repository.

A bare `para init` refuses when `node_modules/paraspace` is absent. Install it
first, or name a layer or path when initializing. When the first `para init`
names layers, the default base is not added; the explicit list is exactly what
the stack contains.

## Add a layer

Add bundled layers by name:

```sh
para add docker git
```

Add an existing directory by path:

```sh
para add ../shared/paraspace-layer
```

`para add` expands accepted names into explicit paths in `.paraspace/stack`.
Bundled names resolve beneath `para`'s `layers/` directory. Installed plugin
layers use `vendor/name` entries. Other arguments are paths, tried as written
and then beneath `node_modules/`.

If a name matches more than one candidate, such as both a directory and a
plugin layer, `para add` refuses and names each candidate. Use the full path
for the layer you mean.

List bundled, installed plugin, and project-owned layers with the entries
already in use marked:

```sh
para add --list
```

Adding a layer already present leaves the layer list unchanged. New layers are
inserted before project-owned layers, which remain last so their files and
verbs take precedence.

## Create a project layer

Create a new layer owned by this project and add it to the layer list:

```sh
para add --new local-tools
```

This creates `.paraspace/layers/local-tools/` with `image-build`, `provision`,
and `boot` hook stubs and places it before the project layer. Add hooks, seed
files, commands, or a `configure` script as the layer needs.

## Base layers

By convention, the first layer is a base. It establishes the image, bootstrap,
and workspace user. A base is identified by a `base/` component in its stack
path. `para` composes base layers like any other layer, but `para doctor` warns
when the list has no base or more than one.

## Customize a packaged layer

Copy a packaged layer into the project, replace its packaged path in the stack,
and apply the updated configuration:

```sh
cp -R node_modules/paraspace/layers/docker .paraspace/layers/docker
${EDITOR:-vi} .paraspace/stack
para init
```

The copy is now project-owned. npm updates do not modify it.

## Configure layers

`para init` and `para add` run each layer's optional `configure` script in
stack order. These scripts run on the host from the project root with your
privileges, so review third-party layers before adding them.

Every `PARA_*` variable is exported to a configure script, and
`PARA_LAYER_DIR` identifies that script's layer directory. A script can
propose env values through the `maybe_write_env` helper from `$PARA_HELPERS`:

```sh
maybe_write_env PARA_ROUTES "3000"
```

Existing declarations in `.paraspace/env` take precedence; see
[The env file](./env.md) for its rules. The bundled docker layer uses
configuration to derive `PARA_ROUTES` and `PARA_PREPULL_IMAGES` from a
resolved Compose model.

A failing configure script stops the chain with that layer's exit status.
After fixing the layer, rerun `para add` to converge. Configuration does not
run during `para up`, so routine workspace startup does not change committed
project files.
