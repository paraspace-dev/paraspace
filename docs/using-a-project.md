# Use a ParaSpace project

For a repository that already has a `.paraspace/` directory, run these commands
from the repository root:

```sh
npm install
para image build
para up ws1
para sh ws1
```

## Install the dependencies

```sh
npm install
```

Most projects ship their setup layers as npm dependencies, so run this before
any command that touches a workspace. Skip it if this project keeps its layers
in the repository; check the paths in `.paraspace/stack`. If layers are missing,
`para` stops and lists the paths it could not find.

## Build the project image

```sh
para image build
```

Every workspace you create is a clone of one base image, so build it once before
your first `para up`, and give it several minutes. Build again when the
project's image hooks change, and once more if you move to a machine with a
different CPU architecture. See [The image contract](./image.md).

## Launch a workspace

```sh
para up ws1
```

The project's hooks clone the repository, provision the environment, and start
services in an isolated workspace named `ws1`. The exact setup depends on the
repository's hooks.

On a fresh machine, the first launch may print an SSH public key and pause. Add
that key to your Git host and continue. See
[Shared authentication](./shared-auth.md).

## Enter the workspace

```sh
para sh ws1
```

You land in a shell in the clone, where you can run your editor, your coding
agent, the tests, and the project's own commands.

## Open the application

```sh
para ls
```

Copy a workspace URL into your browser, or open it with the bundled base
layer's [project command](./commands.md#project-commands):

```sh
para web ws1
```

Run `para --help` to see which commands this project gives you.

## Create more workspaces

Each one gets its own clone, IP address, services, and URLs, so you can leave
`ws1` running while you work in another:

```sh
para up another-feature
para sh another-feature
```

Use `para ls` to see everything you have running, and delete the ones you have
finished with:

```sh
para rm ws1
```

See [Commands](./commands.md) for the full reference.

## Next

[Running coding agents](./agents.md) covers the parallel-development workflow
this is built for. [Workspace URLs](./urls.md) explains routing, custom
domains, and certificate trust.
