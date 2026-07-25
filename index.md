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
      text: Why ParaSpace
      link: /docs/why

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
    title: Caddy at the doorway
    details: Each workspace has its own IP, so your app binds its usual ports — nothing remapped, nothing path-rewritten, so WebSockets and hot reload work with no configuration.
  - icon:
      light: /icons/key-light.svg
      dark: /icons/key-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Authenticate once
    details: Credentials live on a shared per-project volume. Run gh auth login in one workspace and the whole project is authed — one revocable key per project, never your host keys.
  - icon:
      light: /icons/console-light.svg
      dark: /icons/console-dark.svg
      width: 32
      height: 32
      wrap: true
    title: A real terminal
    details: <code>para sh</code> is a native shell in the container — a real pty, your dotfiles, no web terminal. One workspace per desktop, switched with your own window manager.
  - icon:
      light: /icons/rocket-light.svg
      dark: /icons/rocket-dark.svg
      width: 32
      height: 32
      wrap: true
    title: A thin engine
    details: About a thousand lines of bash over Incus and Caddy. Your project's <code>.paraspace</code> dir owns the image, the provisioning, the boot — and adds <code>para</code> verbs of its own.
  - icon:
      light: /icons/helmet-light.svg
      dark: /icons/helmet-dark.svg
      width: 32
      height: 32
      wrap: true
    title: Made for agents
    details: One agent per workspace, a dozen at a time. Every one has its own clone, its own database, and its own URL — and <code>para ls</code> shows you the whole fleet.
---

## Install

```sh
npm i -g paraspace
```

`para` drives [Incus](https://linuxcontainers.org/incus/) and Caddy on the host
— `brew install caddy colima incus` on macOS; Linux installs both from their
own docs. Full prerequisites: [Getting started](/docs/getting-started).

## Quick start

```sh
cd your-project   # a repo set up for para
para image build  # build the project's base image — once per project, per arch
para up ws1       # launch an isolated workspace
para sh ws1       # shell into the clone
```

New project? `para init` scaffolds a working `.paraspace/` dir — the
walkthrough is [Project setup](/docs/project-setup).
