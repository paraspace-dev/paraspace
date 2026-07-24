# Getting started

## Install

```sh
npm i -g paraspace
```

`para` drives [Incus](https://linuxcontainers.org/incus/) and Caddy on the
host:

- **macOS** — `brew install caddy colima incus`
- **Linux** — [install Caddy](https://caddyserver.com/docs/install) and
  [install Incus](https://linuxcontainers.org/incus/docs/main/tutorial/first_steps/)

## Using a para-enabled repo

If the repo already has a `.paraspace/` dir (a maintainer committed one),
you're four commands from a running workspace:

```sh
para image-build  # build the project's base image — once per machine
para up ws1       # launch an isolated workspace
para sh ws1       # shell into the clone
para web ws1      # open its https URL
```

`para up` starts the backend and Caddy for you when needed. The full command
surface (`down`, `rm`, `run`, …) is in [Commands](./commands.md).

## Enabling your project

`para` needs one thing from a project: a `.paraspace/` dir at the repo root — a
`Parafile` (config) and `hooks/` (provision + boot). Commit it, and every
contributor — and every agent — gets the workflow above:

```sh
para init         # scaffold .paraspace/ from a working template
```

Then point it at your repo and your stack — the walkthrough is
[Project setup](./project-setup.md).

## Next

- [How it works](./how-it-works.md) — what problem this solves, and the
  architecture that solves it.
- [Workspace URLs](./urls.md) — clean `:443` URLs, your own domain, browser
  trust.
