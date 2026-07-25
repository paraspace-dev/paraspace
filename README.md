# ParaSpace

`para` runs any number of full, isolated copies of your project side by side on
your own machine. Each workspace is an unprivileged [Incus] system container
with its own clone, its own stack, and its own `https://<name>.<domain>` URL —
so several coding agents (or you) can build, run and break things in parallel
without colliding.

📖 **[Documentation](https://paraspace.dev)** · [Why
ParaSpace](./docs/why.md) · [Getting started](./docs/getting-started.md)

## Install

```sh
npm i -g paraspace
```

`para` drives [Incus] and Caddy on the host:

- **macOS** — `brew install caddy colima incus`
- **Linux** — [install Caddy](https://caddyserver.com/docs/install) and
  [install Incus](https://linuxcontainers.org/incus/docs/main/tutorial/first_steps/)

Then `para doctor` tells you if the machine is ready.

## Quick start

```sh
cd <your project>  # a repo with a .paraspace/ dir — see below
para image build   # build the project's base image — once per project, per arch
para up ws1        # launch an isolated workspace
para sh ws1        # shell into the clone
```

## Set up your project

`para` needs one thing from a project: a `.paraspace/` dir at the repo root —
a `Parafile` (config), `hooks/` (provision + boot), an `image-build.sh`, and
optionally `commands/` (your own `para` verbs). Scaffold it from a working
template:

```sh
para init          # from your project root
```

Then point `PARA_ORIGIN` at your repo, list your `PARA_ROUTES`, and adapt the
hooks to your stack. The walkthrough is
[Project setup](./docs/project-setup.md).

## Documentation

Full docs at **[paraspace.dev](https://paraspace.dev)**, and in
[`docs/`](./docs/README.md):

- [Why ParaSpace](./docs/why.md) — the case, and what it costs ·
  [Prior art](./docs/prior-art.md) — how it compares, and when to pick
  something else.
- [Getting started](./docs/getting-started.md) · [How it
  works](./docs/how-it-works.md) · [Running coding
  agents](./docs/agents.md)
- [Project setup](./docs/project-setup.md) — adapting `para` to your project ·
  [Cookbook](./docs/cookbook.md) — recipes for the common needs.
- [Commands](./docs/commands.md) · [The Parafile](./docs/parafile.md) ·
  [Hooks](./docs/hooks.md) · [The image contract](./docs/image.md) ·
  [Contract versioning](./docs/versioning.md)
- [Troubleshooting](./docs/troubleshooting.md) — `para doctor` and what its
  checks mean.

## Templates

[`templates/`](./templates) holds three runnable templates —
`void-docker-gh` (the `para init` default), `void-minimal` and `void-jchook`.
Each has its own README; [Project setup](./docs/project-setup.md) compares them.

## Development

`bin/lint` (ShellCheck) and `test/run` (the behavioral suite) both gate every
PR. The e2e tier is Linux-only and not run in CI — run it locally before
merging anything touching `up`, routes or lifecycle. See
[`test/README.md`](./test/README.md).

`npm run site` previews the VitePress docs; `npm run site:build` checks for
dead links.

## License

[MIT](./LICENSE)

[Incus]: https://linuxcontainers.org/incus/
