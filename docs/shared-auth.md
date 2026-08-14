# Shared authentication

Every workspace of a project mounts the same volume at `/para/shared`. Whatever
your provision hook links out of it, every workspace inherits, so you sign in
once per project instead of once per workspace.

That covers anything with a credential on disk: your VCS, `gh` or `glab`, an
agent CLI's session, an npm or PyPI token, or a cloud CLI profile.

## How it works

`para` only supplies the volume. Deciding *what* is shared is the provision
hook's job, and it's usually a handful of symlinks:

```sh
# .paraspace/layers/project/hooks/provision
mkdir -p "$PARA_SHARED/git/ssh" "$PARA_SHARED/gh"
ln -sfn "$PARA_SHARED/gh"             ~/.config/gh     # gh login
ln -sfn "$PARA_SHARED/claude"         ~/.claude        # agent session
ln -sfn "$PARA_SHARED/git/gitconfig"  ~/.gitconfig
ln -sfn "$PARA_SHARED/git/ssh/id_ed25519" ~/.ssh/id_ed25519
```

The volume is [per project](./internals.md#the-shared-home-volume) by default.
You can point several projects at one `PARA_VOLUME` to share across them.

Recipes for the common ones are in the [Cookbook](./cookbook.md).

## Version control over SSH

Workspaces clone and push over the network, so your host has to trust a key.
The bundled `git` layer generates **one key per project**, on that project's
shared volume and labelled `para-<project>-<hostname>`, so you can grant it only
what this project needs and revoke it without touching anything else.

Nothing about this is git-specific. A Mercurial, Fossil or Subversion project
wants the same thing: a key on the shared volume, and whatever config file that
tool reads linked into `$HOME`.

### First run

Add the `git` layer to your project:

```sh
para add git
```

During the project's first `para up`, the layer generates a fresh key, prints
it, and **pauses** so you can authorize it:

1. Copy the printed key and add it at your host (e.g.
   [github.com/settings/keys](https://github.com/settings/keys)).
2. Press Enter to let the clone proceed.

`para up` is idempotent, so if a first clone fails with
`Permission denied (publickey)`, authorize the key and re-run.

The `git` layer also ships a [project command](./commands.md#project-commands)
that re-prints it. It is a file in the layer's `commands/`, rather than a
`para` built-in:

```sh
para key
```

### Login with `gh`

Add the `gh` layer to guide you through the `gh login` flow during the
project's first `para up`:

```sh
para add gh
```

Workspaces can then use `gh` to open pull requests and anything else the CLI
does.
