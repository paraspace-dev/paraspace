# Shared authentication

Every workspace of a project mounts the same volume at `/para/shared`. Whatever
your provision hook links out of it, every workspace inherits, so you sign in
once per project instead of once per workspace, and workspaces you create next
month are already signed in.

That covers anything with a credential on disk: your VCS, `gh` or `glab`, an
agent CLI's session, an npm or PyPI token, a cloud CLI's profile.

## How it works

`para` only supplies the volume. Deciding *what* is shared is the provision
hook's job, and it's usually a handful of symlinks:

```sh
# .paraspace/hooks/provision
mkdir -p "$PARA_SHARED/git/ssh" "$PARA_SHARED/gh"
ln -sfn "$PARA_SHARED/gh"             ~/.config/gh     # gh login
ln -sfn "$PARA_SHARED/claude"         ~/.claude        # agent session
ln -sfn "$PARA_SHARED/git/gitconfig"  ~/.gitconfig
ln -sfn "$PARA_SHARED/git/ssh/id_ed25519" ~/.ssh/id_ed25519
```

Link the directory a tool keeps its state in, and that tool is authenticated in
every workspace of the project. The volume is
[per project](./internals.md#the-shared-home-volume) by default; point several
projects at one `PARA_VOLUME` to share across them.

Recipes for the common ones are in the [Cookbook](./cookbook.md).

## Version control over SSH

Workspaces clone and push over the network, so your host has to trust a key.
The bundled `git` mod generates **one key per project**, on that project's
shared volume and labelled `para-<hostname>`. It is individually
revocable, and it is never one of your host keys.

Nothing about this is git-specific. A Mercurial, Fossil or Subversion project
wants the same thing: a key on the shared volume, and whatever config file that
tool reads linked into `$HOME`.

### First run

On the first `up` of a project's shared volume, the `git` hook generates
the key, prints it, and **pauses** so you can authorize it:

1. Copy the printed key and add it at your host (e.g.
   [github.com/settings/keys](https://github.com/settings/keys)).
2. Press Enter to let the clone proceed.

`para up` is idempotent, so if a first clone fails with
`Permission denied (publickey)`, authorize the key and re-run.

The `git` mod also ships a [project command](./commands.md#project-commands)
that re-prints it, a file in the mod's `commands/` rather than a `para`
built-in:

```sh
para key
```

### Letting `gh` do it

Vendor `git` and `gh`, then set `PARA_GH_AUTH=1` in the project's `Parafile`.
The `gh` mod uploads the shared key before `git` clones, which is useful for
private repositories. It records success on the shared volume, so later
provisions make no GitHub request. The [Cookbook](./cookbook.md#authenticate-gh-during-provisioning)
shows the underlying commands.

## What sharing costs

One credential store reachable by every workspace means anything running in
one, [an agent included](./agents.md#let-the-agent-off-the-leash), can use
every credential you put there. It can push wherever that key is authorized,
and call whatever API those tokens allow.

Two ways to keep that in proportion:

- **Scope the key, not the sharing.** A deploy key limited to the one
  repository is the tighter choice; an account-wide key is the convenient one.
- **Split the volume.** `PARA_VOLUME` is per project by default precisely so
  one project's credentials aren't in another's workspaces. Give a project
  handling something sensitive its own, and don't point it at a shared name.
