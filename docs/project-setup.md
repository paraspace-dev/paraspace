# Add ParaSpace to a project

This guide adds ParaSpace to a repository you maintain. Finish
[Install ParaSpace](./install.md) first, so that `para doctor` reports your
machine is ready.

Install ParaSpace as a project development dependency, so the lockfile pins both
the engine and the layer code that provisions workspaces. Contributors get both
from `npm install`, and a globally installed `para`
[hands off to this copy](./install.md).

```sh
npm install --save-dev paraspace
```

## Scaffold `.paraspace/`

From the repository root, run:

```sh
para init
```

In a fresh repository, this builds a Void workspace with zsh that starts
nothing. It creates a `.paraspace/` directory containing an `env` file that
pins `PARA_CONTRACT=1`, a `stack` file, and a project layer with `image-build`,
`provision`, and `boot` hooks.

`para init` keeps files that already exist, so you can run it in a repository
that already has application code or an earlier ParaSpace setup. The default
stack starts with `node_modules/paraspace/layers/base/void` and ends with
`.paraspace/layers/project`.

## Configure the project

Add the capabilities this project needs. A typical Git and Compose project
uses:

```sh
para add git docker gh
```

New layers are inserted before the project layer. To see the available catalog,
including layers already in your stack, run:

```sh
para add --list
```

The `git` layer owns cloning, `docker` boots a Compose file when present, and
`gh` provides optional GitHub key authorization. The Docker layer also tries to
infer image pre-pulls and routes from `docker compose config`; without Compose
or Node it warns and leaves that configuration to you.

Layers remain under `node_modules/paraspace/layers/` and update with the
package rather than being copied into the repository. A layer's host-side
`configure` runs when you add it with your privileges, so read third-party
layer READMEs first.

### 1. Set up the base image

Edit `.paraspace/layers/project/hooks/image-build` to add what your image
needs, such as a toolchain or resources prefetched once instead of on every
provision.

> [!TIP]
> The hooks are just bash.

### 2. Set up the provisioner

Edit `.paraspace/layers/project/hooks/provision` if needed, which runs before
the project boots. It usually prepares the shared home volume, configures
authentication, copies files out of `skel/`, renders `.env`, or does one-time
setup. The `git` layer handles the common clone and `.env` flow.

### 3. Set up application services

Edit `.paraspace/layers/project/hooks/boot`, which starts the application
services. It must return zero only once every routed service is listening. See
[Hooks](./hooks.md).

### 4. Check or set the routes

Inspect `.paraspace/env`. The Docker layer may have proposed `PARA_ROUTES` when
you added it. Otherwise add one entry per service port that should get a URL,
or declare it yourself before adding Docker to override inference.

```sh
# Caddy will proxy:
#   <ws>.paraspace.dev    --> :3000
#   db.<ws>.paraspace.dev --> :8081
PARA_ROUTES="3000, db:8081"
```

Any `PARA_*` environment variables defined here are forwarded to all of your
hooks. See [The env file](./env.md) for every pre-defined setting.

## Build and launch

```sh
para image build
```

Expect a couple of minutes the first time. Every workspace you create afterwards
is a clone of that image, so you build again only when you change what goes into
it, or move to a machine with a different CPU architecture.

```sh
para up my-feature
```

`para up` creates the workspace, runs your hooks, and configures its routes.

To list the URL mapping and get a shell inside the workspace:

```sh
para ls
para sh my-feature
```

With the `git` layer, the first SSH clone may pause after printing a public key.
See [Shared authentication](./shared-auth.md).

## Iterate on the setup

`para up` is idempotent. Run it against an existing or stopped workspace and it
restarts and reconverges that workspace instead of failing, which makes the
setup loop:

```sh
# edit a hook or the env file
para up my-feature
```

Once a workspace boots, commit `.paraspace/`, `package.json`, and the lockfile
so every contributor and coding agent gets the same environment. para finds
`.paraspace/` by walking up from the working directory. On a fresh clone,
contributors run `npm install` and then `para up`.

## What is in `.paraspace/`

| Entry     | Used by                                | Purpose                                                             |
| --------- | -------------------------------------- | ------------------------------------------------------------------- |
| `env`     | `para` on the host                     | Project settings and the [contract version](./versioning.md) pin    |
| `stack`   | `para` on the host                     | Ordered layer list, with one path per line                          |
| `layers/` | The host, workspace, and image builder | Project-owned layers, each with `hooks/`, `skel/`, and `commands/`  |

To go further:

- declare your own `PARA_*` knobs
  ([Your own vars](./env.md#your-own-vars));
- drop an executable in `.paraspace/layers/project/commands/` to add a `para`
  verb of your own ([Project commands](./commands.md#project-commands));
- run `para add` for setup you would rather not maintain
  ([Layers](./layers.md));
- run `para add --new <name>` to start a reusable layer of your own.

The scaffolded project layer is yours. Bundled layers stay where npm put them
and update with the package. To customize one, copy it under
`.paraspace/layers/` and point its stack line at the copy. See
[Layers](./layers.md#customize-a-packaged-layer).

## Next

[Running coding agents](./agents.md) covers the parallel-development workflow.
[The Cookbook](./cookbook.md) covers database seeding, authentication,
dotfiles, image pre-pulling, monorepos, and custom commands.
[Use a ParaSpace project](./using-a-project.md) is the shorter daily loop
contributors follow once setup is done.
