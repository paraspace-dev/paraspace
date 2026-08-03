# The machine

> **You don't run these.** Everything on this page changes the machine rather
> than the repo you were asked to work in, which covers `npm i -g`,
> `incus admin init`, `usermod`, `setcap`, `caddy trust`, `umount`,
> `colima start`, `incus storage create` and `para config edit`. Print the exact
> command, say what it changes, and let the human run it. Be especially careful
> with `para config edit`, which rewrites the *user-global* config and so
> applies to every para project on the box.

`para doctor` is where everything para knows about a misconfigured machine
lives, and `troubleshooting.md` is where each of its checks is explained and
fixed. **Run doctor, read that page, and when it disagrees with anything here,
it wins.** This page is only the part neither can know: which platform you're
on, and where to look when the workspace itself is broken.

## Linux hosts

Incus runs natively, so the containers, the storage pool and the bridge are all
on this kernel, and Caddy is a host process. If the probe says Incus is missing,
first-time setup is:

```sh
# Incus >= 6.22, from the Incus repos rather than the distro's, which lag:
#   https://linuxcontainers.org/incus/docs/main/installing/
incus admin init --minimal
sudo usermod -aG incus-admin "$USER"   # `_incus-admin` on some distros; check `getent group`
```

`para doctor` then covers the rest, including pool driver, kernel idmapping,
cgroups and Caddy's bind capability, with the fix printed beside each failure.

Doctor can only *warn* about one judgment call. A btrfs- or ZFS-backed pool
makes nested Docker fall back to the `vfs` storage driver. Nothing errors,
everything is just punishingly slow. If the project's stack is Docker, treat
that warning as a blocker and get the human onto a dir/ext4 pool before you
build an image on top of it.

## macOS hosts

Incus runs inside a Colima VM, so the architecture is the same one layer down.
The containers, the images and the storage pool live **inside the VM**, the
`incus` CLI on the Mac points into it, and Caddy still runs on the Mac and
reaches container IPs through the VM's network.

```sh
brew install caddy colima incus
colima start --runtime incus --network-address   # see `colima start --help` for sizing
```

What changes in practice, none of which is in the shipped docs:

- **Colima must be running** before any `para` command that touches Incus.
  `incus daemon unreachable` almost always means it isn't.
- **`--network-address`** is what makes the VM's containers reachable from Caddy
  on the Mac. Without it, URLs don't load even though `para ls` looks right.
- **Size the VM for the whole stack, not one workspace.** Every workspace, every
  image and every Docker layer shares the VM's disk, and image builds are
  usually the first thing to run out of room.
- **Images are per-arch**, so on Apple Silicon you're on arm64. A base image or
  a container image with no arm64 build fails here and works on a colleague's
  x86 box.
- **The storage-driver advice above is about the VM's pool**, not APFS.
- **`colima stop` stops every workspace**, and `para up` brings one back.
- `:443` binds without `setcap` here, so port-less URLs are just the config
  change.

## When a workspace is broken

```sh
incus info --show-log para-<ws>      # why the container refused to start
incus exec para-<ws> -- bash         # a ROOT shell, bypassing para and $PARA_USER
para sh <ws> -c 'ss -ltnp'           # what is actually listening
para ls --all                        # every workspace on the machine, any project
```

Reach for `incus exec … -- bash` when the workspace user, its login shell, or
the shared volume is the thing that's broken. It depends on none of them, which
is exactly why `para sh` can't help you there.

Two failure modes produce silent wrongness rather than an error, so they aren't
in doctor's list:

- **A tool you added to `image-build` isn't there.** Nothing tracks image drift;
  rebuild.
- **A variable a hook exported isn't set in the next hook.** The environment
  doesn't cross between hooks, so pass it through a file (`/etc/profile.d/`,
  `$HOME`, `$PARA_SHARED`). `hooks.md` has the table of which file to pick.
