# How it works

`para` is glue over two things you can already run: [Incus] for the containers
and [Caddy] for the URLs. This page is the mental model — what exists on your
machine once workspaces are up, and which part owns what.

For the argument about *why* this shape, see [Why ParaSpace](./why.md).

## The shape

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

Each workspace is an unprivileged Incus **system** container with a static IP on
the Incus bridge. Whatever the project runs inside — bare processes or nested
containers — binds its usual ports on that IP, so workspaces never collide with
each other or with the host, and nothing gets remapped.

There are two doors into a workspace: its URL, and `para sh`.

## The pieces

- **One host Caddy** terminates TLS for the `*.<domain>` wildcard and
  reverse-proxies each workspace's routes to its container IP. It is generated
  from Incus, so a single Caddy is correct across every project on the machine
  — see [Workspace URLs](./urls.md).
- **One Incus container per workspace** (`para-<name>`), holding the clone and
  running the project's whole stack inside, nested containers included.
- **One shared home volume per project**, attached to every workspace of that
  project at `/para/shared`. Authenticate once (git, `gh`, dotfiles) and every
  workspace of the project inherits it.
- **The project's hooks do all the provisioning.** Everything project-specific
  lives in the project's `.paraspace/` directory, never in `para` — see the
  [hook contract](./hooks.md).

There is no para daemon and no para database: a workspace records its own
identity on its container, so `incus` is the only thing that has to remember
anything. `para up` starts what it needs, including Caddy.

Nothing else runs on the host.

## macOS: one extra layer

The same stack, one layer down. Incus runs inside a
[Colima](https://github.com/abiosoft/colima) Linux VM, so the containers and
the shared volume live in the VM. Caddy still runs on the Mac and reaches
container IPs through the VM's network (Colima's `--network-address`). The
`incus` CLI on the host points into the VM; nothing else changes.

## Going deeper

- [Internals](./internals.md) — self-describing workspaces, machine-global
  names, project discovery, where state lives.
- [Commands](./commands.md) — the full surface, and how a project adds verbs
  of its own.

[Incus]: https://linuxcontainers.org/incus/
[Caddy]: https://caddyserver.com/
