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
  - icon: 🪐
    title: Real isolation
    details: Each workspace is an unprivileged Incus system container with its own clone, app stack, and bridge IP. Safely run your coding agents in YOLO mode, without impacting your host or other workspaces.
  - icon: 🛰️
    title: A subdomain per workspace
    details: Caddy routes <code>*.name.paraspace.dev</code> to each exposed http(s) service. Same ports in every workspace, no offsets to juggle.
  - icon: 🔑
    title: Authenticate once
    details: Credentials live on a shared per-project volume. Run gh auth login in one workspace and the whole project is authed — one revocable key per machine, never your host keys.
  - icon: 💻
    title: A real terminal
    details: para sh is a native shell in the container — a real pty, your dotfiles, no web terminal needed. Bring your zsh, tmux, and Neovim config.
  - icon: 🔌
    title: Bring your own stack
    details: ParaSpace is a generic mechanism, like docker compose. Your project's <code>.paraspace</code> dir has total control, top to bottom.
  - icon: 🤖
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
