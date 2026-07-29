# The machine, and what goes wrong on it

`para doctor` is where everything para knows about a misconfigured machine
lives. **Run it and read it before diagnosing anything yourself** — re-deriving
its checks by hand is slower and drifts from what para actually accepts. This
page is for the parts doctor can't know: which platform you're on, and what to
do about each thing it reports.

## Linux — Incus runs natively

The container, the storage pool and the bridge are all on this kernel; Caddy is
a host process. Setup, if the probe says something is missing:

```sh
# Incus >= 6.22 is required (para reads workspace state as device columns).
# Distro repos lag badly — Ubuntu ships 6.2. Install from the Incus repos:
#   https://linuxcontainers.org/incus/docs/main/installing/
incus admin init --minimal          # first time only
sudo usermod -aG incus-admin "$USER" # then log out and back in
```

Two host-level facts decide whether nested workloads are fast or unusable:

- **The storage pool's driver.** Nested Docker cannot use overlayfs on a btrfs-
  or ZFS-backed pool and silently falls back to `vfs`, which copies the whole
  filesystem per layer. This is the slowest failure para has and it never
  errors. Fix it once with a dir pool on ext4/xfs, then point para at it:
  ```sh
  incus storage create para-dir dir source=/path/on/ext4
  para config edit          # set PARA_POOL=para-dir
  ```
- **Kernel + idmapped mounts.** The shared volume attaches to many unprivileged
  containers at once, which needs idmapped mounts (kernel ≥ 5.12, ≥ 5.15 on
  btrfs) or shiftfs, and OpenZFS ≥ 2.2 if the pool is on ZFS. Without it a
  workspace dies mid-boot with `Required idmapping abilities not available`.

For port-less URLs, Caddy needs the bind capability, re-applied after every
caddy upgrade:

```sh
sudo setcap cap_net_bind_service=+ep "$(readlink -f "$(command -v caddy)")"
```

## macOS — Incus runs inside a Colima VM

Same architecture, one layer down. The containers, the images and the storage
pool live **inside the VM**; the `incus` CLI on the Mac points into it; Caddy
still runs on the Mac and reaches container IPs through the VM's network. So:

```sh
brew install caddy colima incus
colima start --runtime incus --network-address   # check `colima start --help` for sizing flags
```

What changes in practice:

- **Colima must be running** before any `para` command that touches Incus;
  `incus daemon unreachable` almost always means it isn't.
- **`--network-address`** is what makes the VM's containers reachable from
  Caddy on the Mac. Without it URLs won't load even though `para ls` looks fine.
- **Size the VM for the whole stack, not for one workspace.** Every workspace,
  every image and every Docker layer is on the VM's disk. Image builds are the
  usual first thing to run out of room.
- **Images are per-arch:** on Apple Silicon you're building and running arm64,
  so a base image or a container image with no arm64 build will fail here and
  work on a colleague's x86 box.
- **The storage-driver advice above applies to the VM's pool**, not to APFS on
  the Mac.
- **`colima stop` stops every workspace**; they come back with `para up`.
- `:443` binds without `setcap` on macOS, so the port-less-URL setup is just the
  config change.

## Failure → cause → fix

Read a hook failure top-down: the first `error:` line is where it broke, the
`stack:` beside it is how para got there, and everything below is the unwind.

| What you see | What it is | What to do |
|---|---|---|
| `no image 'x' — para image build` | the per-project image isn't built on this machine/arch | `para image build` (minutes) |
| `this project targets para contract N…` | the repo's `.paraspace/` and this `para` disagree | update `para`, or pin the project to the contract it targets |
| `Permission denied (publickey)` during the first `up` | the workspace's key isn't authorized at the git host yet | authorize it, then re-run `para up` — it's idempotent |
| `up` succeeds, URL returns **502** | `boot` returned zero before the routed port was listening | fix the readiness gate (`references/stacks.md`); confirm with `para sh <ws> -c 'ss -ltnp'` |
| URL doesn't resolve or shows a cert warning | wildcard DNS, or Caddy's CA isn't trusted | `para doctor` for the DNS check; `caddy trust` once per machine |
| `Required idmapping abilities not available` | kernel/ZFS too old for the shared volume | see the kernel note above |
| `Failed to create cgroup at_mnt` | a named cgroup-v1 hierarchy is mounted under `/sys/fs/cgroup` | `sudo umount -l /sys/fs/cgroup/<name>` (doctor prints the path) |
| everything inside the workspace is slow | nested Docker fell back to the `vfs` driver | move to a dir/ext4 pool, rebuild the image |
| `para sh <ws> -c …` fails on a minimal image | busybox `su` has no `--pty` | install util-linux's `su` in `image-build` |
| a hook can't find a variable it exported earlier | the environment doesn't cross between hooks | pass it through a file — `/etc/profile.d/`, `$HOME`, or `$PARA_SHARED` |
| a tool you added to `image-build` isn't there | nothing tracks image drift | rebuild (`para image build -i` while iterating) |

## Escape hatches when a workspace is broken

```sh
incus info --show-log para-<ws>      # why the container refused to start
incus exec para-<ws> -- bash         # a ROOT shell, bypassing para and $PARA_USER
para sh <ws> -c 'ss -ltnp'           # what is actually listening
para ls --all                        # every workspace on the machine, any project
```

`incus exec … -- bash` is the one to reach for when the workspace user, its
shell, or the shared volume is the thing that's broken — it doesn't depend on
any of them. The generated Caddyfile is at
`${XDG_STATE_HOME:-~/.local/state}/para/Caddyfile` when you want to see exactly
what para asked Caddy to serve.

Workspace names are **machine-global**, so `api` collides across projects on one
box. Name them after the task, prefixed by the project when there's any doubt.
