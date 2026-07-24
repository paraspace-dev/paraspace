# ParaSpace

`para` is an LLM-era coding tool that enables you to parallelize tasks across
isolated environments on your local machine.

Each workspace is a full, isolated copy of your project — its own clone, its
own stack, its own `https://<name>.<domain>` URL — so several agents
(or you) can build, run, and break things side by side without colliding.

## Install

```sh
npm i -g paraspace
```

### Prerequisites

ParaSpace uses [Incus] and Caddy on the host to enable workspace isolation and
a comfortable developer experience.

**macOS**

```sh
brew install caddy colima incus
```

**Linux**

* [Install Caddy](https://caddyserver.com/docs/install)
* [Install Incus](https://linuxcontainers.org/incus/docs/main/tutorial/first_steps/)

## Quick start

```sh
cd <your project> # a repo set up for para — see below
para up ws1       # launch an isolated workspace
para sh ws1       # shell into the clone
```

The full command surface (`down`, `rm`, `run`, `web`, …) is in
[Commands](./docs/commands.md).

## Set up your project

para needs one thing from a project: a `.paraspace/` dir at the repo root — a
`Parafile` (config) and `hooks/` (provision + boot). Scaffold it from a
working template:

```sh
para init         # from your project root
```

Then point `PARA_ORIGIN` at your repo, list your `PARA_ROUTES`, and adapt the
hooks to your stack. The scaffolded files are commented and carry working
defaults; the walkthrough is [Project setup](./docs/project-setup.md).

## Documentation

Full documentation lives in [`docs/`](./docs/README.md):

- [How it works](./docs/how-it-works.md) — the host Caddy, the shared home
  volume, self-describing workspaces, where state lives.
- [Project setup](./docs/project-setup.md) — adapting para to your project.
- [Commands](./docs/commands.md) — the full CLI surface + shell completion.
- [The Parafile](./docs/parafile.md) · [Hooks](./docs/hooks.md) ·
  [The image contract](./docs/image.md) ·
  [Contract versioning](./docs/versioning.md) — the para↔project contract.

Workspace URLs default to `https://<name>.paraspace.dev:8443` — dropping the
`:8443`, using your own domain, and browser certificate trust are all covered
in [Workspace URLs](./docs/urls.md).

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

## License

[MIT](./LICENSE)

[Incus]: https://linuxcontainers.org/incus/
