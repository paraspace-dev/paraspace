# Publishing plugins

A ParaSpace plugin is an npm package that ships layers for other projects to
add. Name the package `paraspace-plugin-<vendor>`, where `<vendor>` is the
name users will type with `para add`.

For example, publish `paraspace-plugin-acme` to let consumers add
`acme/web` or `acme/base/node`. A plugin is the distribution unit. A layer is
the unit ParaSpace composes into a stack.

## Package your layers

Put shareable layers in a top-level `layers/` directory. This directory uses
the same layout as a project's `.paraspace/layers/` directory and contains
only layers. Put base layers under `layers/base/`.

```text
paraspace-plugin-acme/
├── package.json
├── README.md
└── layers/
    ├── web/
    │   ├── README.md
    │   ├── hooks/
    │   └── skel/
    └── base/
        └── node/
            └── README.md
```

The rest of the package is yours to organize. ParaSpace discovers only
`node_modules/paraspace-plugin-*/layers/`, so the package needs no registry
entry or other registration step.

Build each layer as described in [Layers](./layers.md). Keep a `README.md` in
each layer. The bundled layer READMEs are useful examples of documenting what
a layer installs, which base it targets, and the `PARA_*` settings it reads.

Use [Hooks](./hooks.md) for hook behavior and execution order. Hooks run in
stack order, so a hook can assume every layer earlier in the stack has already
run. When a layer needs to run at a moment another layer exposes, use that
layer's hook point. For example, the bundled git layer opens `git:before`
during provision, and the bundled gh layer fills it to authorize the shared
SSH key. See [Hook points](./hook-points.md) for the available pattern and
examples.

Use [Commands](./commands.md) for custom `para` commands. A layer's
`commands/<verb>` includes a `# summary: ...` line that `para --help` shows.

A layer may include a root-level `configure` program. It runs on the
consumer's machine when the layer is added, so keep it minimal and
idempotent. Use `maybe_write_env` from `$PARA_HELPERS` to propose environment
values; existing declarations in the consumer's `.paraspace/env` always win.
Consumers should be able to review it before adding the layer. See
[Layers](./layers.md) for configure semantics. The bundled docker layer
provides the reference example.

## Declare the contract you target

Publishing makes the layer layout and its hook behavior part of the contract
your users depend on. State in the plugin README which `PARA_CONTRACT` your
layers target. The current contract is `1`.

Read [Contract versioning](./versioning.md) before deciding how to communicate
compatibility changes.

## Publish and use the plugin

Publish the package through npm using your usual release process:

```sh
npm publish
```

A consuming project installs the plugin as a development dependency:

```sh
npm install --save-dev paraspace-plugin-acme
```

It can then add a layer by vendor name:

```sh
para add acme/web
```

That name resolves to
`node_modules/paraspace-plugin-acme/layers/web`. Base layers use the same
vendor prefix, such as `acme/base/node`.

`para add --list` includes layers from installed plugins, shown as
`acme/<layer>` entries. A project can therefore discover the layers available
from every installed plugin without additional setup.

## Names and scopes

Vendor shorthand applies only to packages named `paraspace-plugin-*`.
`@paraspace/*` packages are reserved for official packages and do not use
vendor shorthand. Add one of their layers by full path, such as
`node_modules/@paraspace/x/layers/y`.

The unscoped `paraspace-*` namespace without `-plugin-` is kept clear by
request rather than enforcement.
