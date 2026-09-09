# How it works

`para` uses [Incus] to run containers and [Caddy] to route workspace URLs.
The project's `.paraspace/` directory defines the environment inside each
workspace.

See [Why ParaSpace](./why.md) for the reasons behind this design.

## The shape

```
       browser                     terminal
       │  https://ws1.<domain>        │
       ▼                          para sh ws2
┌──────────────────────────────┐      │
│          host Caddy          │      │
│  TLS + routes for *.<domain> │      │
└──────┬───────────────┬───────┘      │
       │               │              │
┌──────▼──────┐ ┌──────▼──────┐       │
│  para-ws1   │ │  para-ws2   ◀───────┘
│   clone     │ │   clone     │
│  services   │ │  services   │
└──────┬──────┘ └──────┬──────┘
       │               │
┌──────▼───────────────▼───────┐
│      para-home-<project>     │
│   mounted at /para/shared    │
└──────────────────────────────┘
```

Each workspace is an unprivileged Incus **system** container with a static IP on
the Incus bridge. Whatever the project runs inside (bare processes or nested
containers) binds its usual ports on that IP, so workspaces never collide with
each other or with the host, and nothing gets remapped.

Open the workspace URL in a browser or use `para sh` to enter its shell.

## The pieces

- Caddy runs on the host, terminates TLS for the `*.<domain>` wildcard, and
  reverse-proxies each workspace's routes to its container IP. `para` generates
  its configuration from Incus metadata for all projects on the machine.
  See [Workspace URLs](./urls.md).
- One Incus container per workspace (`para-<name>`) holds the clone and
  runs the project's services, including nested containers.
- One shared home volume per project attaches to every workspace of that
  project at `/para/shared`. Authenticate once (git, `gh`, dotfiles) and every
  workspace of the project inherits it.
- The project's hooks do all the provisioning. Hooks live in an ordered list
  of layers. The project's `.paraspace/` directory holds the env file, the
  stack file that lists layers in order, and the project's own layers. Layers
  added from the paraspace package or a plugin resolve under `node_modules/`.
  Nothing project-specific lives in `para` itself. See the [hook
  contract](./hooks.md) and [Layers](./layers.md).

There is no ParaSpace daemon or database. `para` stores workspace identity
in Incus container metadata.
`para up` starts what it needs, including Caddy. Besides the Incus daemon, that
Caddy is the only para-related process on your host.

## macOS adds a VM

On macOS, Incus runs inside a [Colima](https://github.com/abiosoft/colima)
Linux VM, so the containers and the shared volume live in the VM. Caddy still
runs on the Mac and reaches container IPs through the VM's network (Colima's
`--network-address`). The `incus` CLI on the host points into the VM; nothing
else changes.

## Going deeper

- [Internals](./internals.md) covers self-describing workspaces, the shared
  volume, machine-global names, and where state lives.
- [Commands](./commands.md) covers the full surface, and how a project adds
  verbs of its own.

[Incus]: https://linuxcontainers.org/incus/
[Caddy]: https://caddyserver.com/
