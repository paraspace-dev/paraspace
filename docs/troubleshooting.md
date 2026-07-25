# Troubleshooting

## Start with `para doctor`

Everything `para` knows about how a machine can be misconfigured lives in one
command, so the commands you use every day don't carry it:

```
$ para doctor

config
    user config   /home/you/.config/para/config
    state         /home/you/.local/state/para
    project dir   /home/you/src/myapp
    PARA_PROJECT  myapp
    PARA_IMAGE    myapp
    PARA_DOMAIN   paraspace.dev
    PARA_ROUTES   8080
    PARA_POOL     default
    PARA_VOLUME   para-home-myapp
    Caddy port    8443

host
  ✓ caddy present
  ✓ para Caddy running on :8443
  ✓ *.paraspace.dev resolves to 127.0.0.1

incus
  ✓ incus 6.22
  ✓ pool 'default' (dir)
  ✓ bridge 'incusbr0' up

project
  ✓ Parafile targets contract 1
  ✓ routes: 8080
  ✓ image 'myapp' exists
```

`✓` passed, `!` is advice, `✗` is a failure — and any `✗` exits non-zero. The
`config` block is also the answer to "what did para actually resolve," which is
worth checking whenever a setting doesn't seem to be taking effect.

## The host

### Your Incus is too old

> ✗ incus 6.2 cannot select device columns, which is how para reads workspace
> state — upgrade to 6.22 or newer

para has no registry: it asks Incus for each workspace's project, routes and IP
as query columns, which needs **Incus ≥ 6.22**. Distro repos lag (Ubuntu ships
6.2), so install from
[the Incus package repositories](https://linuxcontainers.org/incus/docs/main/installing/)
or from Zabbly.

### Containers won't start at all

> ✗ cgroup-v1 mounted inside /sys/fs/cgroup (…)

A named cgroup-v1 hierarchy mounted under `/sys/fs/cgroup` makes LXC fail every
container start with a cryptic `Failed to create cgroup at_mnt`. Unmount it —
doctor prints the exact path:

```sh
sudo umount -l /sys/fs/cgroup/<name>
```

### A workspace dies mid-boot on the shared volume

> ✗ this kernel cannot do idmapped mounts …
> ! OpenZFS 2.1 is older than 2.2 …

The shared volume attaches to many unprivileged containers at once, which needs
either `shiftfs` or idmapped mounts. Without them a workspace fails with
`Required idmapping abilities not available`. Kernel ≥ 5.12 (≥ 5.15 on btrfs),
and OpenZFS ≥ 2.2 if the pool is on ZFS.

### Everything inside the workspace is slow

> ! pool 'default' is btrfs-backed — nested Docker falls back to vfs

The slowest failure para has, and it's silent: nested Docker can't use overlayfs
on a btrfs or ZFS-backed Incus pool, so it falls back to the `vfs` driver, which
copies the whole filesystem per layer. Put para on a `dir` pool over ext4/xfs:

```sh
incus storage create para-dir dir source=/path/on/ext4
```

Then set `PARA_POOL` in your [user config](./parafile.md#user-config-not-parafile).

### The workspace is up but the URL doesn't load

> ✗ *.paraspace.dev does not resolve to 127.0.0.1

The wildcard has to point at your machine. The default `paraspace.dev` already
does; a custom `PARA_DOMAIN` needs a wildcard record of your own — see
[Workspace URLs](./urls.md#using-your-own-domain).

If DNS is fine, check Caddy is actually up (`para caddy status`) and that the
browser trusts its CA — a first-run `caddy trust` covers most browsers, and
[Workspace URLs](./urls.md#trusting-the-certificate) covers the rest.

### Caddy can't bind `:443`

> ✗ caddy cannot bind :443 unprivileged — sudo setcap …

Non-root can't bind below 1024 on Linux. Grant the capability (re-apply after
every `caddy` upgrade), or stay on the default `:8443`:

```sh
sudo setcap cap_net_bind_service=+ep "$(readlink -f "$(command -v caddy)")"
```

### macOS: `incus daemon unreachable`

Incus runs inside a Colima VM there. `colima start --runtime incus`, then
re-run.

## The project

### `no image 'myapp' — para image build`

The base image is per-project and per-arch, and it isn't built for you. Run
`para image build` — several minutes the first time. See
[The image contract](./image.md).

### `Permission denied (publickey)` during the first `up`

The machine's para key isn't authorized at your git host yet. `para up` is
idempotent, so authorize it and re-run — [Git authentication](./git-auth.md).

### `up` succeeds but the URL returns 502

Caddy is proxying to a port nothing is listening on. Almost always a `boot` hook
that returned zero before its services were actually up: the
[readiness contract](./hooks.md#boot) is that it returns only once every routed
service is listening (`docker compose up -d --wait`). Check from inside:

```sh
para sh <name> -c 'ss -ltnp'
```

### `this project targets para contract N, but this para provides 2`

A globally-updated `para` met a project pinned to an older contract, and refused
rather than misbehaving. See [Contract versioning](./versioning.md).

### An interactive `para sh` fails on a minimal image

`para sh` uses `su --pty`, which is util-linux. A busybox `su` (plain Alpine)
doesn't have it. That's an [image requirement](./image.md#what-the-image-must-have);
non-interactive `para sh -c …` still works.

## Still stuck

`incus info --show-log para-<name>` shows why a container refused to start, and
the generated Caddyfile is at `${XDG_STATE_HOME:-~/.local/state}/para/Caddyfile`
if you want to see exactly what para asked Caddy to serve.
