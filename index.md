---
layout: home

hero:
  name: ParaSpace
  text: Parallel dev workspaces on your machine
  tagline: Every task gets a full, isolated copy of your project — its own clone, its own stack, its own https URL. Built for the LLM era.
  actions:
    - theme: brand
      text: Get started
      link: /docs/
    - theme: alt
      text: View on GitHub
      link: https://github.com/paraspace-dev/paraspace

features:
  - icon: 📦
    title: Real isolation
    details: Each workspace is an unprivileged Incus system container with its own clone, Docker stack, and bridge IP. Build, run, and break things side by side.
  - icon: 🌐
    title: A URL per workspace
    details: One host Caddy routes https://name.paraspace.dev to each workspace. Open two branches in two tabs and compare.
  - icon: 🔌
    title: Bring your own stack
    details: para is a generic mechanism, like docker compose. Your project's .paraspace/ dir — a Parafile and hooks — holds everything project-specific.
  - icon: 🤖
    title: Made for agents
    details: Run several coding agents in parallel, each in its own workspace, without collisions on ports, databases, or checkouts.
---

## Install

```sh
npm i -g paraspace
```

para uses [Incus](https://linuxcontainers.org/incus/) and Caddy on the host —
`brew install caddy colima incus` on macOS; see the
[README](https://github.com/paraspace-dev/paraspace#install) for Linux.

## Quick start

```sh
cd your-project   # a repo set up for para
para up ws1       # launch an isolated workspace
para sh ws1       # shell into the clone
```

New project? `para init` scaffolds a working `.paraspace/` dir — the
walkthrough is [Project setup](/docs/project-setup).
