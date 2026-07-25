# Internals

The finer mechanics behind [How it works](./how-it-works.md). None of this is
required to use `para` — it explains behavior you'll observe.

## Incus is the database

There is no para registry. Each `para-<name>` container records its own
identity — owning project, routes, domain — in its Incus config at `up` time,
and its IP in its `eth0` device. One `incus list` returns all of it as columns,
so para keeps no second copy and can't drift from one.

Two consequences:

- **`para ls` needs Incus reachable.** Everything else does too, so this costs
  nothing in practice.
- **The generated Caddyfile is machine-wide by construction.** It's built from
  Incus, so it lists every para workspace on the box regardless of which
  project generated it. That's what makes one Caddy correct across projects.

## The shared home volume

Each project gets one Incus custom volume (`security.shifted=true`, which is
what lets one volume attach to many unprivileged containers with correctly
shifted ownership), mounted in every workspace of that project at
`/para/shared`. Your provision hook decides what goes on it.

It is **per-project by default** (`para-home-<project>`); point several projects
at one `PARA_VOLUME` to share auth across them. `para rm` never touches it.

## Workspace names are machine-global

A name maps to one `para-<name>` container, so `sh`/`rm`/`down` address it by
bare name from anywhere with no ambiguity. `para up <name>` refuses a name
already owned by another project — and names the owner — rather than adopting
its container.

## Project discovery

[Finding the `.paraspace/` directory](./project-setup.md) is only a file
lookup: a project's *identity* is `PARA_PROJECT`, so moving or renaming the
checkout never orphans its workspaces.

## Where state lives

| What | Where |
|---|---|
| User config | `${XDG_CONFIG_HOME:-~/.config}/para/config` |
| Generated Caddyfile | `${XDG_STATE_HOME:-~/.local/state}/para/Caddyfile` |
| Caddy pidfile | `${XDG_STATE_HOME:-~/.local/state}/para/caddy.pid` |
| Workspace identity | the container's own Incus config |
| Shared home volume | Incus volume `para-home-<project>` |

para never changes your config behind your back. It seeds the file from a
commented template the first time you run `para config edit`, and after that
it's yours.
