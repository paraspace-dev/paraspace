# Mods

A template is a **starting point** for your project's ParaSpace configuration.
Mods allow you to augment the base template with optional or custom behavior.

## Adding a mod

When you want your dotfiles, or a credential helper, or a language runtime in a
project that already has a `.paraspace/`, you add or create a mod.

```sh
para mod add --list         # list the built-in mods
para mod add git docker gh  # add one or several at once
para image build            # if the mod fills image-build
para up feat-x
```

The mod lands in your project's `.paraspace/mods` directory.

> [!WARN]
> Mods may run configuration code when you add them. 3rd party mods should be
> reviewed before adding.

Configuration is additive: a script may add a missing `Parafile` declaration,
but one already there always wins, including an explicit empty value.

Adding the same mod again **replaces** the directory. So, to update a mod, you
can simply add it again.

> [!NOTE]
> `para mod add` installs only built-in mods. Git URLs are planned but not
> supported yet.

## Create your own mod

```sh
para mod init <name>
```

This stubs all the main hooks into `.paraspace/mods/<name>`.

## What's in one

A mod is a directory shaped like `.paraspace/`:

```
.paraspace/mods/dotfiles/
  README.md
  configure                         # optional, bundled mods only
  hooks/{provision,image-build}
  skel/{zshrc,nvim,tmux,claude,claude.json,bin}
  commands/{claude,run}
```

`para up` pushes your whole `.paraspace/` into the workspace, including mods
and their hooks.

A mod never has its own `Parafile`. Its optional root-level `configure` is a
host script, not a sourced config file; it may use
`set_parafile_var_if_not_set` to propose values in the project's Parafile.

## Custom verbs

A mod's `commands/<verb>` becomes `para <verb>`. See
[Commands](./commands.md#project-commands) for what a command is, and note that
they run on your host rather than in a workspace.

`para --help` names the mod each verb came from, and marks a verb that can't run.
`para doctor` can help you diagnose any naming collisions.

## Hooks

`provision`, `boot` and `image-build` run every time. para runs each name
through the project's hook first, then each mod's, in [no promised
order](./hook-points.md#filling-one).

Mods can define custom [hook points](./hook-points.md). This lets other mods
plug-into key points in the execution flow. For example:

```sh
"$PARA_RUN_HOOK" deploy:before
```

