---
layout: home

hero:
  name: ParaSpace
  text: Parallel dev workspaces on your machine
  tagline: A full, isolated copy of your project per task — its own clone, its own stack, its own https URL. Run coding agents in parallel without collisions.
  actions:
    - theme: brand
      text: Get started
      link: /docs/getting-started
    - theme: alt
      text: Why ParaSpace
      link: /docs/why

features:
  - icon:
      light: /icons/planet-light.svg
      dark: /icons/planet-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Sandboxed
    details: Set your coding agent to YOLO mode and enjoy peace of mind. Each workspace runs in an unprivileged system container. Boot up is fast, system memory and compute are shared, and you can run containerized stacks inside it.
  - icon:
      light: /icons/key-light.svg
      dark: /icons/key-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Authenticate once
    details: Run <code>gh auth login</code> in one workspace and every workspace on the project is authenticated — including the one you create next week, and after a reboot. One revocable key per project, and never your host's.
  - icon:
      light: /icons/helmet-light.svg
      dark: /icons/helmet-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Made for agents
    details: Run a dozen at once and none of them can see another's branch, database, or half-finished edits. Every task stays a separate PR, and <code>para ls</code> shows you the whole fleet.
  - icon:
      light: /icons/sputnik-light.svg
      dark: /icons/sputnik-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Workspace subdomains
    details: <code>https://fix-login.paraspace.dev</code> the moment it's up — no DNS to set up; local TLS & CA trust is automatic. Your stack keeps its usual ports, so hot reload and WebSockets need no configuration.
  - icon:
      light: /icons/rocket-light.svg
      dark: /icons/rocket-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Thin wrapper
    details: It's just bash. Your project has total control over virtually every aspect of the parallel workspace lifecycle, from building the image and booting the stack, to custom verbs and execution hooks.
  - icon:
      light: /icons/console-light.svg
      dark: /icons/console-dark.svg
      width: 32
      height: 32
      wrap: true
    title: A real terminal
    details: No iframes, no web terminal. <code>para sh</code> is a real pty on your own machine, so tmux, Neovim and Claude Code behave well and support custom dotfiles per box. Each workspace feels like an extension of your normal environment.
---

## Install

```sh
npm i -g paraspace
```

`para` drives [Incus](https://linuxcontainers.org/incus/) and Caddy on the
host — `brew install caddy colima incus` on macOS, or install both from their
own docs on Linux. Full prerequisites: [Getting started](/docs/getting-started).

## Quick start

```sh
cd your-project   # a repo set up for para
para image build  # build the project's base image — once per project, per arch
para up ws1       # launch an isolated workspace
para sh ws1       # shell into the clone
```

New project? `para init` scaffolds a working `.paraspace/` dir — the
walkthrough is [Project setup](/docs/project-setup).

<div class="home-cta">
  <h2>Give every task its own machine</h2>
  <p>Point <code>para</code> at a repo and run as many workspaces as you have work.</p>
  <div class="home-cta-actions">
    <a class="home-cta-btn brand" href="/docs/getting-started">Get started</a>
    <a class="home-cta-btn alt" href="https://github.com/paraspace-dev/paraspace">View on GitHub</a>
  </div>
</div>
