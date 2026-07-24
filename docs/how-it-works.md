# How it works

## The problem

You want several full copies of a project running at once — one per branch, one
per agent. The usual routes:

- **Hosted dev environments** do the isolation in the cloud, and the interface
  is the price: web terminals, browser IDEs, routing that fights you — metered
  by the hour while your own machine idles.
- **DIY on your machine** — worktrees, port offsets, devcontainers — shares one
  network and one Docker daemon, so ports, `.env`s, and auth collide across
  branches. That fiddliness is most of what the hosted platforms are selling
  relief from.

`para` does the isolation locally, with system containers:

```
       browser                     terminal
       │  https://ws1.<domain>:8443   │
       ▼                              │  para sh ws2
┌──────────────────────────────┐      │
│          host Caddy          │      │
│  TLS + routes for *.<domain> │      │
└──────┬───────────────┬───────┘      │
       │               │              │
┌──────▼──────┐ ┌──────▼──────┐       │
│  para-ws1   │ │  para-ws2   ◀───────┘
│   clone     │ │   clone     │
│   stack     │ │   stack     │
└──────┬──────┘ └──────┬──────┘
       │               │
┌──────▼───────────────▼───────┐
│      para-home-<project>     │
│   mounted at /para/shared    │
└──────────────────────────────┘
```

Each workspace is a **system** container with its own IP. Whatever the project
runs — bare processes, or containers nested inside the container (Docker boots
fine) — binds its usual ports on the workspace's own network, so workspaces
never collide with each other or with the host. Caddy proxies each workspace's
URL to its IP; nothing gets remapped.

The URL is only one door. `para sh` drops a real shell in a workspace's clone —
your dotfiles, a real pty, no web terminal — and `para run` opens a tmux
session there with `claude` already running. Agents work the workspaces the
same way you do.

- **One host Caddy** terminates TLS for the `*.<domain>` wildcard and
  reverse-proxies each workspace's routes to its container IP. It binds `:8443`
  by default; clean `:443` URLs are an opt-in — see
  [Workspace URLs](./urls.md).
- **One Incus container per workspace** (`para-<name>`) holds the clone and
  runs the project's whole stack inside — nested containers included.
- **One shared home volume per project**, attached to every workspace at
  `/para/shared` — authenticate once (git, `gh`, dotfiles) and every workspace
  inherits it.
- **The project's hooks** do all provisioning. Everything project-specific
  lives in the project's `.paraspace/` dir, never in `para` — the
  [hook contract](./hooks.md) is the seam.

Nothing else runs on the host.

## macOS: one extra layer

The same stack, one layer down. `para start` boots a
[Colima](https://github.com/abiosoft/colima) Linux VM with the Incus runtime,
so Incus — and with it the containers and the volume — lives inside the VM.
Caddy still runs on the Mac and reaches container IPs through the VM's network
(Colima's `--network-address`). The `incus` CLI on the host simply points into
the VM; nothing else changes.

## Going deeper

The finer mechanics — self-describing workspaces, machine-global names,
project discovery, where state lives — are in [Internals](./internals.md).
