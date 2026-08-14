# Layers

A layer is a directory that contributes project setup to a ParaSpace workspace.
It may hold `hooks/`, `skel/`, `commands/`, and a `configure` script, and every
part is optional.

Its hooks run in stack order, against the contract in [Hooks](./hooks.md). Its
seed files sit in `skel/`, where its own hooks reach them at
`$PARA_LAYER_DIR/skel`, and anything in `commands/` becomes a
[project command](./commands.md).

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

The list composes from top to bottom, and each line resolves against the project
root. Blank lines and `#` comments are skipped, and surrounding whitespace and
trailing slashes are trimmed, so you can document a non-obvious entry in place.
Every path in the list has to be a directory that already exists.

The paths are literal. Nothing searches for layer names, resolves packages at
runtime, or normalizes equivalent paths, so in a hoisted monorepo write the path
that is true for this project, such as `../../node_modules/...`.

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

That rechecks the list and reruns each layer's configure script, without
recreating what is already there.

## Start a project

```sh
npm install --save-dev paraspace
para init
```

[Add ParaSpace to a project](./project-setup.md) covers the rest of the setup. A
bare `para init` refuses when `node_modules/paraspace` is absent, so install it
first, or name a layer or path when initializing. Naming layers on that first
run skips the default base, so the stack holds exactly the list you gave.

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

See the catalog of bundled, plugin, and project-owned layers, with the entries
already in your stack marked:

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

You get `.paraspace/layers/local-tools/` with `image-build`, `provision`, and
`boot` hook stubs, placed before the project layer. Fill in the hooks, seed
files, commands, or a `configure` script the layer needs.

## Base layers

By convention, the first layer is a base, and it establishes the image,
bootstrap, and workspace user. A base is any layer with a `base/` component in
its stack path. It composes like any other layer, but `para doctor` warns when
the list has no base or more than one.

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
[The env file](./env.md) for its rules. The bundled docker layer's configure
script derives `PARA_ROUTES` and `PARA_PREPULL_IMAGES` from a resolved Compose
model.

A failing configure script stops the chain with that layer's exit status. Fix
the layer, then rerun `para add` to converge. Configure scripts never run during
`para up`, so starting a workspace never rewrites files you committed.
