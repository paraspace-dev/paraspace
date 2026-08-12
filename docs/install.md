# Install ParaSpace

Install [Node.js](https://nodejs.org/) first. It includes `npm`, which installs
`para`.

```sh
npm i -g paraspace
para --version
```

## Install the host dependencies

ParaSpace needs Incus and Caddy on the host.

### macOS

Install Caddy, Colima, and Incus with [Homebrew](https://brew.sh/), then start
the Colima VM with the Incus runtime:

```sh
brew install caddy colima incus
colima start --runtime incus
```

Colima provides the Linux VM where Incus runs. See
[How it works](./how-it-works.md#macos-adds-one-layer).

### Linux

Install [Caddy](https://caddyserver.com/docs/install) and
[Incus](https://linuxcontainers.org/incus/docs/main/tutorial/first_steps/)
using the instructions for your distribution.

## Check the machine

```sh
para doctor
```

`para doctor` reports checks for the configuration, host, Incus, and project.
For each failed check, it prints the command to run or points to the document
that covers the fix. Run the printed fix, then run `para doctor` again until
every check passes. If the Incus daemon has not been initialized on Linux, the
report directs you to run:

```sh
incus admin init
```

See [Troubleshooting](./troubleshooting.md) when a check keeps failing.

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