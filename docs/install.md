# Install ParaSpace

Install [Node.js](https://nodejs.org/) first. It includes `npm`, which installs
`para`.

```sh
npm i -g paraspace
para --version
```

You install `para` globally once, but inside a project the project's copy runs.
When `paraspace` is installed under the project's `node_modules` (or a workspace
root above it), `para` hands the invocation to that copy, which keeps workspaces
on the version the project's lockfile pins rather than whatever this machine
has. In a project that pins none, the commands that depend on the project warn
and run the global copy. Pinning is part of
[Add ParaSpace to a project](./project-setup.md).

`para which` prints the file that would answer, without executing anything from
the checkout, so you can inspect a fresh clone's para before the first verb
hands off to it. One verb never hands off: `para completions` always answers
from the copy you invoked, so sourcing it from a shell rc stays quiet in any
directory.

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
[How it works](./how-it-works.md#macos-adds-a-vm).

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