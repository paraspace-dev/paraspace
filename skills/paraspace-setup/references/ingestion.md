# Getting the code into a workspace

A workspace has none of your host mounted — that isolation is the whole point,
and it's why an agent can be let off the leash inside one. So the code arrives
one of two ways: the workspace **pulls** it (a clone, over the network), or the
host **pushes** it (a project command, from outside). Everything below is a
variation on those two.

## 1. Git with a remote — the default

The bundled `void-docker-gh` template already does this: `PARA_ORIGIN` in the
`Parafile`, a clone in `provision`, and one ssh key on the shared volume so you
authenticate once per project rather than once per workspace.

Worth knowing:

- **`PARA_ORIGIN` and `PARA_CLONE_BRANCH` are project variables, not engine
  ones.** para forwards them and never acts on them; your `provision` hook is
  what reads them. That also means `PARA_CLONE_BRANCH=release-2 para up hotfix`
  works as a one-off if your hook honors it.
- **The clone can race guest DNS.** Set `PARA_READY_HOST` to your git host
  (`github.com`) and para blocks until the guest resolves it.
- **A repo the Parafile lives in can derive its own origin**, which is one less
  thing to keep in sync:
  ```sh
  : "${PARA_ORIGIN:=$(git -C "$PARA_PROJECT_DIR" remote get-url origin)}"
  ```
- **Large repos:** `git clone --filter=blob:none` gives full history with a
  fraction of the transfer, and it stays a normal repo (unlike `--depth 1`,
  which breaks `git log main..` and some tooling). Per-workspace clone time is
  paid on every `para up` of a new workspace, so this matters more here than on
  a laptop.

### Private repos

The template prints the workspace's public key and waits for you to authorize
it, and with `PARA_GH_AUTH=1` it has `gh` upload it for you. For other hosts:

- **GitLab / Bitbucket / Gitea** — same flow, no CLI: print the key, pause,
  human pastes it into the host's SSH-keys page. The key lives on the shared
  volume, so this happens once per project per machine.
- **A deploy key** is the tighter option when the workspace shouldn't be able to
  push everywhere the human can. Generate it on the shared volume, register it
  read-only on the one repo.
- **HTTPS + token** when ssh is blocked: put the token in the host `.env`
  (`PARA_HOST_ENV` pushes it to `~/.paraspace/host.env`), and have `provision`
  configure a credential helper from it. Never bake a token into the image —
  the image is shared by every workspace and outlives them.
- **Internal mirrors / ssh config / `insteadOf`** need to be in place *before*
  the clone. Open a hook point rather than editing the middle of the clone hook:
  `"$PARA_RUN_HOOK" clone:before`.

Remember the shared volume holds a key that can push wherever it's authorized,
and every workspace of the project — and every agent in one — has it. Scope it
to what you're comfortable with.

## 2. Git with no usable remote (local-only, or an unreachable host)

Push a bundle from the host. It's a single file, it carries full history, and it
goes through the same door as everything else:

```sh
#!/usr/bin/env bash
# summary: seed a workspace from the local repo (no remote needed)
set -euo pipefail
git -C "$PARA_PROJECT_DIR" bundle create - --all \
  | "$PARA_BIN" sh "$1" -c 'cat > /tmp/repo.bundle'
"$PARA_BIN" sh "$1" -c "
  git clone /tmp/repo.bundle \$HOME/$PARA_CLONE_DIR &&
  git -C \$HOME/$PARA_CLONE_DIR remote remove origin
"
```

Save as `.paraspace/commands/seed`, `chmod +x`, and `para seed ws1` works. Two
notes: the clone's `origin` points at the bundle file, so remove or repoint it;
and `para sh -c` is byte-clean when its stdin isn't a terminal, which is exactly
what makes piping a bundle through it safe.

Then have `provision` skip cloning when `~/$PARA_CLONE_DIR/.git` already exists,
so `para up` stays idempotent and the seed isn't fought over.

## 3. No VCS at all, or uncommitted work you need

Send the working tree as a tar. This is the answer for a directory that was
never a repo, for Mercurial/SVN/Fossil trees you'd rather not install a client
for, and for "I need my uncommitted changes in there":

```sh
#!/usr/bin/env bash
# summary: copy the host working tree into a workspace (a seed, not a sync)
set -euo pipefail
tar -C "$PARA_PROJECT_DIR" --exclude-vcs --exclude node_modules -cz . \
  | "$PARA_BIN" sh "$1" -c "mkdir -p \$HOME/$PARA_CLONE_DIR && tar -xz -C \$HOME/$PARA_CLONE_DIR"
```

**Say plainly that this is a seed, not a sync.** Nothing propagates afterwards
in either direction; re-running it overwrites files that changed inside the
workspace. If a project lives on this path, the honest advice is that it will
work better once the code is in *some* VCS, even a local-only one — then §2
applies and history comes with it.

For a real non-git VCS, the clean version is to install the client in
`image-build` and clone in `provision` exactly as git does — `hg clone`,
`svn checkout`, `fossil open` are all fine inside a workspace, and they get the
same idempotence guard.

## 4. What about mounting the host directory in?

Incus can attach a host path (`incus config device add para-<ws> src disk
source=… path=…`), and people ask for it. It is almost always the wrong move
here:

- every workspace then edits the **same** files, which deletes the isolation
  that makes parallel workspaces and off-leash agents safe;
- unprivileged containers need idmapped mounts for the uids to line up, so it
  fails or produces root-owned files on exactly the setups that are already
  fragile;
- `para rm` no longer resets anything.

If someone wants edits on the host to appear inside, the better answers are: run
the editor inside the workspace (`para sh`), or push with the command in §3 when
they want a fresh copy. Reserve the mount for genuinely shared read-only assets,
and say what it costs when you use it.

## 5. Monorepos

Two shapes, and they're both in para's own `cookbook.md` — read it rather than
inventing a third. Briefly: one `.paraspace/` per app (each gets its own project
identity, image and workspaces), or one `.paraspace/` at the root with a
`PARA_*` variable selecting which app a workspace boots. The first is right when
the apps have different stacks; the second when they share one.
