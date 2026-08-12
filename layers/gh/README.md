# gh

Targets the bundled `void` template. It installs GitHub CLI during
`para image build` and stores its authentication under `$PARA_SHARED/gh`, linked
at `~/.config/gh`.

Set `PARA_GH_AUTH=1` in the project Parafile to let the mod upload the `git`
mod's shared SSH key before the first clone. Successful authorization writes
`$PARA_SHARED/gh/.key-authorized`, so later provisions stay local. Delete that
marker to retry.

```sh
para mod add git gh
para image build
para up feat-x
```

Without the `git` mod nothing opens `git:before`, so no key is authorized. The
shared `~/.config/gh` link is this mod's `provision` hook, so one `gh` login
still covers every workspace of the project.
