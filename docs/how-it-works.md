# How it works

`para` composes four pieces: one host Caddy, one Incus container per workspace, a
shared home volume per project, and the project's own hooks. Nothing else runs
on the host.

Incus containers are **system** containers, so Docker runs inside each
workspace: the compose stack boots unchanged — same compose file, same ports —
on the workspace's own network. Every workspace can bind `:3000` without
colliding, and Caddy proxies each workspace's URL to its container IP, so all
of them stay reachable with no remapped ports and no per-branch overrides.

```
       browser
       │  https://ws1.<domain>:8443
       ▼
┌──────────────────────────────┐
│          host Caddy          │   terminates TLS for *.<domain>
└──────┬───────────────┬───────┘   proxies each route → container IP
       │               │
┌──────▼──────┐ ┌──────▼──────┐
│  para-ws1   │ │  para-ws2   │   one Incus system container per
│   clone     │ │   clone     │   workspace — the project's stack
│   stack     │ │   stack     │   (Docker and all) runs inside
└──────┬──────┘ └──────┬──────┘
       │               │
┌──────▼───────────────▼───────┐
│      para-home-<project>     │   one shared home volume per project
│   mounted at /para/shared    │   (auth, dotfiles — seeded once)
└──────────────────────────────┘
```

- **One host Caddy** terminates TLS for the `*.<domain>` wildcard and
  reverse-proxies each workspace's routes to its container IP. It binds `:8443`
  by default; clean `:443` URLs are an opt-in — see
  [Workspace URLs](./urls.md).
- **One Incus container per workspace** (`para-<name>`) holds the clone and
  runs the project's whole stack inside, Docker included.
- **One shared home volume per project**, attached to every workspace at
  `/para/shared` — authenticate once (git, `gh`, dotfiles) and every workspace
  inherits it.
- **The project's hooks** do all provisioning. Everything project-specific
  lives in the project's `.paraspace/` dir, never in `para` — the
  [hook contract](./hooks.md) is the seam.

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
