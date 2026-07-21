# How it works

para composes four pieces: one host Caddy, one Incus container per workspace, a
shared home volume per project, and the project's own hooks. Nothing else runs
on the host.

## One host Caddy

`para start` brings up a single para-owned Caddy that terminates TLS for the
`*.<domain>` wildcard and reverse-proxies each workspace's routes to its
container IP. Routes are recorded **per workspace** (from that workspace's own
project), so several projects with different routes coexist correctly.

Caddy binds `:8443` by default (any user can); port-less URLs on `:443` are an
opt-in — see [Workspace URLs](./urls.md).

## The shared home volume

Each project gets one Incus custom volume (`security.shifted=true`), attached
to every workspace of that project at `/para/shared`. The project's provision
hook seeds and symlinks it (dotfiles, Claude/gh/ssh/nvim auth), so you
authenticate once and every workspace inherits it.

The volume is **per-project by default** (`para-home-<project>`); point several
projects at one `PARA_VOLUME` to share auth across them.

## Provisioning is the project's

para launches the container, attaches the volume, waits for it to be ready,
syncs the project's `.paraspace/` dir into it, and runs the project's hooks.
Everything domain-specific (git, gh, dotfiles, `.env`, boot) lives in
`.paraspace/hooks/`, never in para. The [hook contract](./hooks.md) is the seam.

## Workspaces are self-describing

Each `para-<name>` container records its own identity — owning project, routes,
domain — in its Incus config at `up` time. Two things follow:

- `para up` refuses to adopt a container owned by another project, even if the
  registry lost the row.
- The registry is a rebuildable cache: `para reconcile` regenerates it
  wholesale from the containers (recover after a wipe, or a restore onto a new
  box).

## Workspace names are machine-global

A name maps to one `para-<name>` container, so `sh`/`web`/`rm`/`run` address it
by bare name from anywhere with no ambiguity. `para up <name>` refuses a name
already owned by another project (it names the owner) rather than adopting its
container — pick a distinct name.

## Project discovery

para finds your project by walking up from `$PWD` for a `.paraspace/` dir, the
way git and compose find theirs. Only `up`, `image-build`, and `config-sync`
must run inside a project; everything else (`ls`, `sh`, `down`, `rm`, `web`,
`key` — and `init`, which creates the `.paraspace/` dir) works from anywhere.
`para ls` scopes to the current project (`--all` for every project's).

## Where state lives

| What | Where |
|---|---|
| Machine config (`PARA_*` overrides; env wins) | `~/.config/para/config` |
| Generated Caddyfile | `${XDG_STATE_HOME:-~/.local/state}/para/Caddyfile` |
| Workspace registry (rebuildable — see above) | `${XDG_STATE_HOME:-~/.local/state}/para/workspaces` |
| Shared home volume | Incus volume `para-home-<project>` |

para writes `PARA_POOL` to the machine config itself when the default Incus
pool is btrfs/zfs-backed — nested Docker needs a `dir` pool on Linux, and para
creates one. `para config-set KEY VALUE` persists any other override.
