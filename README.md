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
para image build   # once per machine — build the project's base image
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

- [Why ParaSpace](./docs/why.md) — the case, and what it costs.
- [Getting started](./docs/getting-started.md) · [How it
  works](./docs/how-it-works.md) · [Running coding
  agents](./docs/agents.md)
- [Project setup](./docs/project-setup.md) — adapting `para` to your project.
- [Commands](./docs/commands.md) · [The Parafile](./docs/parafile.md) ·
  [Hooks](./docs/hooks.md) · [The image contract](./docs/image.md) ·
  [Contract versioning](./docs/versioning.md)
- [Troubleshooting](./docs/troubleshooting.md) — `para doctor` and what its
  checks mean.

## Templates

[`templates/`](./templates) holds three runnable templates:
[`void-docker-gh`](./templates/void-docker-gh) (the `para init` default — a
small, complete Docker demo), [`void-minimal`](./templates/void-minimal) (the
barest box, all comments), and [`void-jchook`](./templates/void-jchook) (a full
personal dev environment on the same demo). Each has its own README.

## Development

Two gates, both run on every push/PR:

- **`bin/lint`** (or `npm run lint`) — [ShellCheck](https://www.shellcheck.net)
  over every bash script in the package, discovered by shebang. Uses a
  `shellcheck` on your `PATH`, or falls back to the pinned docker image.
- **`test/run`** (or `npm test`) — the behavioral suite, in two tiers. The CLI
  tier (`--cli`) needs nothing but bash and runs in CI; the e2e tier (`--e2e`)
  drives a real Incus workspace off a tiny Alpine fixture and is **Linux-only,
  not run in CI** — run it locally before you merge anything touching the
  `up`/route/lifecycle mechanism. See [`test/README.md`](./test/README.md).

The docs site is [VitePress](https://vitepress.dev): `npm run site` to preview,
`npm run site:build` to check for dead links.

## License

[MIT](./LICENSE)

[Incus]: https://linuxcontainers.org/incus/
