# Git authentication

Workspaces clone and push over SSH, so the git host must trust this machine's
key. `para` uses **one `para` key per machine** (`para-<hostname>`), individually
revocable — never your host keys.

## First run

The provision hook (in the default template) generates the key on the first
`up` of a project's shared volume, prints it, and **pauses** so you can
authorize it:

1. Copy the printed key, add it at your git host (e.g.
   [github.com/settings/keys](https://github.com/settings/keys)).
2. Press Enter to let the clone proceed.

`para up` is idempotent, so if a first clone fails with
`Permission denied (publickey)`, authorize the key and re-run.

The templates ship a [project command](./commands.md#project-commands) that
re-prints the key any time:

```sh
para key
```

## Letting `gh` do it

Set `PARA_GH_AUTH=1` in the default template's `Parafile` and its hook takes a
`gh auth login` path instead, uploading the key for you — handy for private
repos.

Because the key lives on the
[shared volume](./internals.md#the-shared-home-volume), every
workspace of the project inherits it — you authorize once per machine, not per
workspace.

That cuts both ways, and it's worth deciding deliberately: anything running in
a workspace, [an agent included](./agents.md#let-the-agent-off-the-leash), can
push wherever this key is authorized. A deploy key scoped to the one repository
is the tighter choice; an account-wide key is the convenient one.
