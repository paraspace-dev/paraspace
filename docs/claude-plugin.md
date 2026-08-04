# The Claude Code plugin

ParaSpace ships a [Claude Code](https://claude.com/claude-code) plugin that
adopts `para` into a project for you. It reads how your repo already comes up,
from its compose file, `Dockerfile`, CI workflow, devcontainer, Coder template
or provision script, writes the `.paraspace/`, and iterates until `para up`
produces a workspace that really boots and serves.

You end up with the same files and the same contract as
[Project setup](./project-setup.md) describes, and you review the diff like any
other change.

## Install

```
/plugin marketplace add paraspace-dev/paraspace
/plugin install paraspace@paraspace
```

`/plugin uninstall paraspace` removes it.

The skill also installs on its own, through the community
[`skills`](https://github.com/vercel-labs/skills) CLI, a third-party tool rather
than an Anthropic one. It finds this skill through the repo's
`.claude-plugin/marketplace.json` and copies the directory (`SKILL.md`,
`references/`, `scripts/`) into `.claude/skills/paraspace-setup/`.

```sh
npx skills add paraspace-dev/paraspace
npx skills add -g paraspace-dev/paraspace   # user-level, for every project
```

That is the route for an agent that isn't Claude Code. What such an agent does
with a directory of markdown and one shell script is up to it.

Using `para` never requires the plugin, and nothing it writes depends on it
afterward. The `.paraspace/` it produces is ordinary files you own.

## Use it

From your project root, ask for what you want:

```
set this project up for para
```

What it then does, in order:

1. Surveys the machine, checking platform, Incus, Caddy, the storage driver,
   and `para doctor`. On macOS it knows Incus lives in a Colima VM.
2. Reads your repo for how the stack is provisioned today, then asks you only
   what the repo can't answer. Which port you'd open in a browser, what a fresh
   checkout needs before it's usable, which secrets it takes to boot.
3. Says the plan back with what it will cost, and waits for a yes before
   spending minutes on an image build.
4. Scaffolds with `para init` and adapts the result. It edits a template rather
   than inventing a `Parafile`, so what lands targets the
   [contract](./versioning.md) your `para` provides.
5. Builds and boots, reads the failures, fixes the hooks, and goes around again
   until a workspace serves. Then it tears the throwaway workspace down.

Point it at a repo that already has a `.paraspace/` and it reads what's there
and amends in place instead of overwriting.

## What it's good for

The `para init` default covers a git repo with a Docker Compose stack, and the
[templates](./project-setup.md#templates) are the two shapes it ships. The
plugin earns its keep on everything else:

- stacks that just run locally, PHP with MySQL or Rails with Postgres, where
  the workspace runs them as system services rather than in containers;
- a base image that isn't Void, chosen to match what your project already
  targets;
- code that arrives without a git remote, or without git at all;
- k3s, or a hybrid where the databases are containers and the app is a plain
  process;
- the [readiness contract](./hooks.md#boot) for stacks that aren't
  `docker compose --wait`. People get that wrong by hand more than anything
  else, and it's why a workspace comes up and its URL 502s.

## What it costs

Once you approve the build, expect minutes. The boot loop usually runs two or
three times on top of the image build itself.

It runs `para` for real, so it builds an image, creates a workspace, and
removes that workspace when it's done. It asks before any of that.

Review stays with you. Hooks run inside your workspaces and a project command
runs on your host with your privileges, so read the `.paraspace/` diff before
you commit it, the same as any other generated code.

## What it won't do

It won't change `para` itself. If your project seems to need the engine to know
something about it, the answer is a hook, [a `PARA_*` variable of your
own](./parafile.md#your-own-vars), or a [project
command](./commands.md#project-commands). The plugin stays on that side of the
line, and so should any change it suggests.

It also can't finish on a machine that isn't ready for containers. It will
still write and explain the `.paraspace/`, then hand you the `para doctor`
failures to fix. See [Troubleshooting](./troubleshooting.md).
