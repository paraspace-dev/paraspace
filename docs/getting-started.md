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

Then check the machine is ready:

```sh
para doctor
```

It prints what's wrong and how to fix it — see
[Troubleshooting](./troubleshooting.md).

## Using a `para`-enabled repo

If the repo already has a `.paraspace/` directory, you're three commands from a
running workspace:

```sh
para image build  # build the project's base image — once per project, per arch
para up ws1       # launch an isolated workspace
para sh ws1       # shell into the clone
```

`para ls` prints each workspace's URL. Opening one is a
[project command](./commands.md#project-commands) — most templates ship
`para web`.

Two things to expect on a fresh machine:

- **`para image build` takes several minutes.** It's per-project and per-arch,
  and it only happens again when the image source changes.
- **The first `up` may pause at a printed SSH key**, so you can authorize it
  with your git host — see [Git authentication](./git-auth.md).

Your browser will distrust the workspace's certificate until you run
`caddy trust` once — see [Workspace URLs](./urls.md).

`para up` starts everything it needs, including para's Caddy. The full surface
is in [Commands](./commands.md).

## Enabling your own project

`para` needs one thing from a project: a `.paraspace/` directory at the repo
root. Commit it, and every contributor — and every agent — gets the workflow
above.

```sh
para init         # scaffold .paraspace/ from a working template
```

Then point it at your repo and your stack — the walkthrough is
[Project setup](./project-setup.md).

## Next

- [Running coding agents](./agents.md) — the workflow para is built for.
- [How it works](./how-it-works.md) — the architecture.
- [Workspace URLs](./urls.md) — clean `:443` URLs, your own domain, browser
  trust.
