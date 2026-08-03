# Use a ParaSpace project

This path is for repositories that already contain a `.paraspace/` directory.
From the repository root, the whole loop is three commands:

```sh
para image build
para up ws1
para sh ws1
```

## Build the project image

```sh
para image build
```

This builds the base image the project defines. The first build can take
several minutes. Images are per project and per architecture, and para rebuilds
them only when their source changes.

## Launch a workspace

```sh
para up ws1
```

This creates an isolated workspace named `ws1` and runs the project's hooks in
it, which is what clones the repository, provisions the environment, and starts
the stack.

On a fresh machine the first launch may pause after printing an SSH public key.
Add that key to your Git host, then continue. See
[Shared authentication](./shared-auth.md).

## Enter the workspace

```sh
para sh ws1
```

That opens a shell in the workspace's clone, where you can run your editor,
coding agent, tests, and the project's own commands.

## Open the application

List the active workspaces and their URLs:

```sh
para ls
```

Opening one in a browser is a
[project command](./commands.md#project-commands) rather than something para
knows how to do. Most templates ship this one:

```sh
para web ws1
```

Which commands exist depends on the project.

## Create more workspaces

Each workspace gets its own clone, IP address, running stack, and URLs:

```sh
para up another-feature
para sh another-feature
```

Use `para ls` to inspect them and `para rm` when one is finished with:

```sh
para rm ws1
```

See [Commands](./commands.md) for the full reference.

## Next

[Running coding agents](./agents.md) covers the parallel-development workflow
this is built for. [Workspace URLs](./urls.md) explains routing, custom
domains, and certificate trust.
