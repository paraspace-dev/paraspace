---
layout: home

hero:
  name: ParaSpace
  text: Parallel dev workspaces on your machine
  tagline: Every task gets its own universe — a full, isolated copy of your project with its own clone, stack, and https URL. Built for the LLM era.
  actions:
    - theme: brand
      text: Get started
      link: /docs/getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/paraspace-dev/paraspace

features:
  - icon:
      light: /icons/planet-light.svg
      dark: /icons/planet-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Real isolation
    details: Each workspace is an unprivileged Incus system container with its own clone, app stack, and bridge IP. Safely run your coding agents in YOLO mode, without impacting your host or other workspaces.
  - icon:
      light: /icons/sputnik-light.svg
      dark: /icons/sputnik-dark.svg
      width: 32
      height: 32
      wrap: true
    title: A subdomain per workspace
    details: Caddy routes <code>*.name.paraspace.dev</code> to each exposed http(s) service. Same ports in every workspace, no offsets to juggle.
  - icon:
      light: /icons/key-light.svg
      dark: /icons/key-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Authenticate once
    details: Credentials live on a shared per-project volume. Run gh auth login in one workspace and the whole project is authed — one revocable key per machine, never your host keys.
  - icon:
      light: /icons/console-light.svg
      dark: /icons/console-dark.svg
      width: 32
      height: 32
      wrap: true
    title: A real terminal
    details: para sh is a native shell in the container — a real pty, your dotfiles, no web terminal needed. Bring your zsh, tmux, and Neovim config.
  - icon:
      light: /icons/rocket-light.svg
      dark: /icons/rocket-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Bring your own stack
    details: ParaSpace is a generic mechanism, like docker compose. Your project's <code>.paraspace</code> dir has total control, top to bottom.
  - icon:
      light: /icons/helmet-light.svg
      dark: /icons/helmet-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Made for agents
    details: Run several coding agents in parallel, each in its own workspace, without collisions on ports, databases, or checkouts.
---

## Install

```sh
npm i -g paraspace
```

`para` uses [Incus](https://linuxcontainers.org/incus/) and Caddy on the host —
`brew install caddy colima incus` on macOS; see the
[README](https://github.com/paraspace-dev/paraspace#install) for Linux.

## Quick start

```sh
cd your-project   # a repo set up for para
para image build  # once per machine — build the project's base image
para up ws1       # launch an isolated workspace
para sh ws1       # shell into the clone
```

New project? `para init` scaffolds a working `.paraspace/` dir — the
walkthrough is [Project setup](/docs/project-setup).
