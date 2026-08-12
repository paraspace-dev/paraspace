# git

Targets the bundled `void` template. It installs Git and OpenSSH during
`para image build`, then seeds a project-wide identity and SSH key under
`$PARA_SHARED/git/` and clones `$PARA_ORIGIN` into `~/$PARA_CLONE_DIR` during
provision.

```sh
para mod add git
para image build
para up feat-x
```

The mod claims `~/.gitconfig`, `~/.ssh/id_ed25519`,
`~/.ssh/id_ed25519.pub`, and `~/.config/para/clone-dir`. It copies the host
project's `.env` into the clone when `$PARA_HOST_ENV` exists. The `para key`
command prints the shared public key through a running workspace.

The mod opens `git:before` before checking or cloning the checkout on every
provision. The bundled `gh` mod uses that point to converge its shared config
and optionally authorize the key once.
