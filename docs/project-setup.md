# Add ParaSpace to a project

This guide adds ParaSpace to a repository you maintain. Finish
[Install ParaSpace](./install.md) first, so that `para doctor` reports your
machine is ready.

## Scaffold `.paraspace/`

From the repository root, run:

```sh
para init
```

That copies the default `void-docker-gh` template into a new `.paraspace/`
directory. To pick another one:

```sh
para init --list
para init <template>
```

`para init` skips files that already exist, so you can run it in a repository
that already has application code or an earlier ParaSpace setup. The generated
`Parafile` pins the [contract version](./versioning.md) it was written for.

## Configure the project

The scaffold runs as-is, but it still describes the template's project rather
than yours. Four files carry almost everything you need to change.

### 1. Set the repository and routes

Edit `.paraspace/Parafile`. At minimum:

- point `PARA_ORIGIN` at your Git repository;
- set `PARA_IMAGE_BASE` to the incus image `para image build` starts from, and
  `PARA_IMAGE_BOOTSTRAP` to a line that installs bash when the base lacks it;
- give `PARA_ROUTES` one entry per service port that should get a URL.

```sh
: "${PARA_ORIGIN:=git@github.com:acme/example.git}"
: "${PARA_IMAGE_BASE:=images:debian/13}"
PARA_ROUTES="${PARA_ROUTES-3000,db:8081}"
```

That serves the workspace apex from port 3000 and `db.<name>.<domain>` from
port 8081. Write your values with the idioms the template uses, so a one-off
`PARA_ROUTES="3000" para up ws` still wins.

See the [Parafile reference](./parafile.md) for every setting.

### 2. Build the base image

Edit `.paraspace/hooks/image-build`, which names the packages, tools, and
workspace user baked into the project's image. Stable dependencies belong here
rather than in a hook that reruns on every start. See
[The image contract](./image.md).

### 3. Provision each workspace

Edit `.paraspace/hooks/provision`, which runs before the project boots. It
usually prepares the shared home volume, configures authentication, copies
files out of `skel/`, renders `.env`, and does any one-time setup. The default
template handles the common case and expects you to edit it in place.

### 4. Start the stack

Edit `.paraspace/hooks/boot`, which starts the application stack. It must
return zero only once every routed service is listening. See
[Hooks](./hooks.md).

## Build and launch

```sh
para image build
```

The first build usually takes several minutes. Images are per project and per
architecture, then reused until their source changes.

```sh
para up my-feature
```

`para up` creates the workspace, runs your hooks, and configures its routes.
Cloning the repository is one of the things `hooks/provision` does, which is
why `void-minimal` produces a workspace with no clone at all.

Enter it and list its URLs:

```sh
para sh my-feature
para ls
```

On a fresh machine the first launch may pause after printing an SSH public
key. Add it to your Git host, then run `para up my-feature` again. See
[Shared authentication](./shared-auth.md).

## Iterate on the setup

`para up` is idempotent. Run it against an existing or stopped workspace and it
restarts and reconverges that workspace instead of failing, which makes the
setup loop:

```sh
# edit a hook or the Parafile
para up my-feature
```

Once a workspace boots, commit `.paraspace/` so every contributor and coding
agent gets the same environment. It is setup-once project infrastructure like
`.github/`, and para finds it by walking up from the working directory.

## What is in `.paraspace/`

| Entry       | Read by                                | Purpose                                                            |
| ----------- | -------------------------------------- | ------------------------------------------------------------------ |
| `Parafile`  | `para` on the host                     | Project settings and the [contract version](./versioning.md)       |
| `hooks/`    | The workspace and image builder        | Image creation, provisioning, boot, and supporting scripts         |
| `skel/`     | Your hooks                             | Seed files such as dotfiles and configuration                      |
| `commands/` | `para` on the host                     | Project-specific [`para` commands](./commands.md#project-commands) |
| `mods/`     | The host, workspace, and image builder | Vendored reusable components added with `para mod add`             |

To go further with any of them:

- declare your own `PARA_*` knobs, which reach every hook and command
  ([Custom Parafile variables](./parafile.md#your-own-vars));
- drop an executable in `commands/` to add a `para` verb of your own
  ([Project commands](./commands.md#project-commands));
- run `para mod add` for setup you would rather vendor than maintain, such as
  dotfiles or a credential helper ([Mods](./mods.md)).

## Templates

`para init` copies one of two runnable starting points, and you own the copy
afterward. `void-docker-gh` is the default, a small Docker-based project
demonstrating routes, GitHub authentication, and the `key` and `web` project
commands. `void-minimal` installs and runs nothing, for when you would rather
assemble the environment yourself. Each has its own README in the repository's
[`templates/` directory](https://github.com/paraspace-dev/paraspace/tree/main/templates).

## Next

[Running coding agents](./agents.md) covers the parallel-development workflow.
[The Cookbook](./cookbook.md) covers database seeding, authentication,
dotfiles, image pre-pulling, monorepos, and custom commands.
[Use a ParaSpace project](./using-a-project.md) is the shorter daily loop
contributors follow once setup is done.
