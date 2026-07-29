# The Claude Code plugin

ParaSpace ships a [Claude Code](https://claude.com/claude-code) plugin that
adopts `para` into a project for you. It reads how your repo already comes up —
compose file, `Dockerfile`, CI workflow, devcontainer, Coder template, provision
script — writes the `.paraspace/`, and then iterates until `para up` produces a
workspace that really boots and serves.

It is the automated version of [Project setup](./project-setup.md): same files,
same contract, and you review the diff like any other change.

## Install

```
/plugin marketplace add paraspace-dev/paraspace
/plugin install paraspace@paraspace
```

`/plugin uninstall paraspace` removes it. Nothing about the plugin is required
to use `para`, and nothing it writes depends on it afterwards — the
`.paraspace/` it produces is ordinary files you own.

## Use it

From your project root, ask for what you want:

```
set this project up for para
```

What it then does, in order:

1. **Surveys the machine** — platform, Incus, Caddy, storage driver, and
   `para doctor`. On macOS it knows Incus lives in a Colima VM.
2. **Reads your repo** for how the stack is provisioned today, and asks you only
   what the repo can't answer — which port you'd open in a browser, what a fresh
   checkout needs to be usable, which secrets it takes to boot.
3. **Says the plan back**, with what it will cost, and waits for a yes before
   spending minutes on an image build.
4. **Scaffolds with `para init`** and adapts the result — it edits a template
   rather than inventing a `Parafile`, so what lands targets the
   [contract](./versioning.md) your `para` provides.
5. **Builds and boots**, reads the failures, fixes the hooks, and goes around
   again until a workspace serves. Then it tears the throwaway workspace down.

It works on a repo that already has a `.paraspace/` too — it reads what's there
and amends in place rather than overwriting.

## What it's good for

The `para init` default covers a git repo with a Docker Compose stack (the
[templates](./project-setup.md#templates) are the two shapes it ships). The
plugin is for everything else:

- stacks that just run locally — PHP + MySQL, Rails + Postgres, a Python service
  and a queue — where the workspace runs them as system services rather than in
  containers;
- a base image that isn't Void, chosen to match what your project already
  targets;
- code that arrives without a git remote, or without git at all;
- k3s, or a hybrid where the databases are containers and the app is a plain
  process;
- the [readiness contract](./hooks.md#boot) for stacks that aren't
  `docker compose --wait` — the part people most often get wrong by hand, and
  the reason a workspace comes up and its URL 502s.

## What it costs

- **Minutes, once you approve the build.** The boot loop usually runs two or
  three times on top of the image build.
- **Your machine's state.** It runs `para` for real: builds an image, creates a
  workspace, and removes that workspace when it's done. It asks first.
- **Review is still yours.** Hooks run inside your workspaces and a project
  command runs on your host with your privileges. Read the `.paraspace/` diff
  before you commit it, the same as any generated code.

## What it won't do

It won't change `para` itself. If your project seems to need the engine to know
something about it, the answer is a hook, [a `PARA_*` variable of your
own](./parafile.md#your-own-vars), or a [project
command](./commands.md#project-commands) — the plugin stays on that side of the
line, and so should any change it suggests.

It also can't finish on a machine that isn't ready for containers. It will still
write and explain the `.paraspace/`, then hand you the `para doctor` failures to
fix — see [Troubleshooting](./troubleshooting.md).
