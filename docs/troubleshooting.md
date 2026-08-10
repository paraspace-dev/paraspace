# Troubleshooting

## Start with `para doctor`

Everything `para` knows about how a machine can be misconfigured lives in one
command, so the commands you use every day don't carry it:

```
$ para doctor

config
    user config        /home/you/.config/para/config
    state              /home/you/.local/state/para
    project dir        /home/you/src/myapp
    PARA_PROJECT_NAME  myapp
    PARA_IMAGE_NAME    myapp
    PARA_DOMAIN        paraspace.dev
    PARA_ROUTES        8080
    PARA_POOL          default
    PARA_VOLUME        para-home-myapp
    Caddy port         8443

host
  ✓ caddy present
  ✓ para Caddy running on :443
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

`✓` passed, `!` is advice, and `✗` is a failure that exits non-zero. The
`config` block is also the answer to "what did para actually resolve", so check
it whenever a setting doesn't seem to be taking effect.

## The host

### Your Incus is too old

> ✗ incus 6.2 cannot select device columns, which is how para reads workspace
> state. Upgrade to 6.22 or newer (Ubuntu's repos ship 6.2)

para has no registry. It asks Incus for each workspace's project, routes and IP
as query columns, which needs **Incus ≥ 6.22**. Distro repos lag, so install
from [the Incus package
repositories](https://linuxcontainers.org/incus/docs/main/installing/).

### Containers won't start at all

> ✗ cgroup-v1 mounted inside /sys/fs/cgroup (…). No container will start until
> you unmount it: sudo umount -l …

A named cgroup-v1 hierarchy mounted under `/sys/fs/cgroup` makes LXC fail every
container start with a cryptic `Failed to create cgroup at_mnt`. Unmount it, and
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

> ! pool 'default' is btrfs-backed, so nested Docker falls back to vfs

Nested Docker can't use overlayfs on a btrfs or ZFS-backed Incus pool, so it
falls back to the `vfs` driver, which copies the whole filesystem per layer.
Put para on a `dir` pool over ext4/xfs:

```sh
incus storage create para-dir dir source=/path/on/ext4
```

Then set `PARA_POOL` in your [user config](./parafile.md#user-config-not-parafile).

### The workspace is up but the URL doesn't load

> ✗ *.paraspace.dev does not resolve to 127.0.0.1, so workspace URLs will not
> load (docs/urls.md)

The wildcard has to point at your machine. The default `paraspace.dev` already
does; a custom `PARA_DOMAIN` needs a wildcard record of your own. See
[Workspace URLs](./urls.md#using-your-own-domain).

If DNS is fine, check Caddy is actually up (`para caddy status`) and that the
browser trusts its CA. A first-run `caddy trust` covers most browsers, and
[Workspace URLs](./urls.md#trusting-the-certificate) covers the rest.

### Caddy can't bind `:443`

> ✗ caddy cannot bind :443 unprivileged. Run sudo setcap …

Non-root can't bind below 1024 on Linux. Grant the capability (re-apply after
every `caddy` upgrade), or stay on the default `:8443`:

```sh
sudo setcap cap_net_bind_service=+ep "$(readlink -f "$(command -v caddy)")"
```

### macOS: `incus daemon unreachable`

Incus runs inside a Colima VM there. `colima start --runtime incus`, then
re-run.

## The project

### `no image 'myapp'. Build it with: para image build`

The base image is per-project and per-arch, and it isn't built for you. Run
`para image build`, which takes several minutes the first time. See
[The image contract](./image.md).

### `Permission denied (publickey)` during the first `up`

The machine's para key isn't authorized at your git host yet. `para up` is
idempotent, so authorize it and re-run. See [Shared
authentication](./shared-auth.md).

### `up` succeeds but the URL returns 502

Caddy is proxying to a port nothing is listening on. Almost always a `boot` hook
that returned zero before its services were actually up. The
[readiness contract](./hooks.md#boot) requires that it return only once every
routed service is listening (`docker compose up -d --wait` does that for a
Compose stack; anything else needs its own wait). Check from inside:

```sh
para sh <name> -c 'ss -ltnp'
```

### `this project targets para contract N, but this para provides 1`

A globally-updated `para` met a project pinned to an older contract, and refused
rather than misbehaving. See [Contract versioning](./versioning.md).

### `para sh -c` fails on a minimal image

Running `para sh <ws> -c '<cmd>'` from a terminal uses `su --pty`, which is
util-linux; busybox's `su` (plain Alpine) doesn't have it. That's an
[image requirement](./image.md#what-the-image-must-have). A bare `para sh`, and
`-c` with its output piped or redirected, use plain `su -` and work anywhere.

## Still stuck

`incus info --show-log para-<name>` shows why a container refused to start, and
the generated Caddyfile is at `${XDG_STATE_HOME:-~/.local/state}/para/Caddyfile`
if you want to see exactly what para asked Caddy to serve.
