<!-- Pre-deslop original of docs/install.md, extracted from 9cd9ad7^ (AI-written, later fixed by the deslop pass in 9cd9ad7). -->
# Install ParaSpace

ParaSpace runs workspaces on your machine with
[Incus](https://linuxcontainers.org/incus/) and routes their URLs through
Caddy, so both have to be on the host before `para` is useful.

## Install `para`

```sh
npm i -g paraspace
para --version
```

## Install the host dependencies

### macOS

Install Caddy, Colima, and Incus with [Homebrew](https://brew.sh/):

```sh
brew install caddy colima incus
```

Colima provides the Linux VM that Incus runs in. That VM is reserved once for
the machine, not once per workspace. See
[How it works](./how-it-works.md#macos-adds-one-layer).

### Linux

Install [Caddy](https://caddyserver.com/docs/install) and
[Incus](https://linuxcontainers.org/incus/docs/main/tutorial/first_steps/)
using the instructions for your distribution.

## Check the machine

```sh
para doctor
```

`para doctor` checks the host configuration and prints the fix for anything
still outstanding. Rerun it until it reports that the machine is ready, and see
[Troubleshooting](./troubleshooting.md) when a check keeps failing.

Workspace URLs are served over HTTPS from Caddy's own local CA. Caddy usually
installs that CA's root itself the first time it issues a certificate, but
[Workspace URLs](./urls.md#trusting-the-certificate) covers the case where your
browser still distrusts them.

## Next

Your host is ready.

- [Use a ParaSpace project](./using-a-project.md) when the repository already
  contains `.paraspace/`.
- [Add ParaSpace to a project](./project-setup.md) when you are setting up your
  own repository.
