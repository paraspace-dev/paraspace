---
name: paraspace-setup
description: >-
  Adopt ParaSpace (`para`) in a project by writing the `.paraspace/` directory
  (a Parafile plus provision/boot/image-build hooks) that turns a repo into
  parallel Incus dev workspaces, then building the image and proving
  `para up <name>` actually boots and serves. Use whenever para, paraspace,
  `.paraspace/`, a Parafile, `para up`, `para init`, `para image build`,
  `para doctor` or `PARA_ROUTES` come up; when someone wants one isolated
  container per branch, per task or per coding agent, each with its own database
  and `https://<name>.<domain>` URL; or when they ask how to get an existing
  stack (compose, a provision script, a devcontainer, bare processes, k3s)
  running inside a para workspace. Any stack, any Linux base, git or no VCS. Not
  for plain Docker, compose or devcontainer work with no para involved, not for
  Coder, Codespaces or git-worktree setups, and not for running a one-off
  command in a sandbox.
---

# Adopting ParaSpace in a project

`para` gives a project parallel dev workspaces: one unprivileged Incus system
container per task, each with its own copy of the code, its own stack, its own
database, and its own `https://<name>.<domain>` URL.

The engine bakes in **nothing** about how a project is provisioned. Adoption is
therefore one directory, `.paraspace/`, answering four questions about how this
project comes up. Your job is to answer them from evidence already in the repo,
write hooks that read like the rest of that repo, and then prove it boots.

## Four rules that come first

These decide whether this run is safe.

1. **Everything you change lives in this repo.** Machine-level changes belong to
   the human, including `npm i -g`, `incus admin init`, `usermod`, `setcap`,
   `caddy trust`, `umount`, `colima start`, `incus storage create` and
   `para config edit`. Print the exact command, say what it changes, wait. So
   does `para caddy stop`, because **one host Caddy serves every workspace of
   every project on the box**, so stopping it drops URLs for repos you never
   opened. Any `para up` reloads it anyway.
2. **You have no terminal, so nothing can prompt.** A hook only prompts when
   para has a tty at both ends, and a tool call has neither, so `pause` returns
   instantly and `gh auth login` is skipped. That's why the first `up` on a
   private repo fails at the clone, and
   [`references/ingestion.md`](references/ingestion.md) has the three-command
   loop that works instead. Also use `para sh <ws> -c '…'`, since a bare
   `para sh` is an interactive shell you can't drive.
3. **Take a workspace name nothing else on the box is using.** Names are
   machine-global, and `para up` on an existing name of the *same* project
   announces that it is reconverging and then does it, without asking, re-running
   provision and boot over whatever a human has in flight. `para rm` then
   force-deletes with no confirmation. Run `para ls -a --names` first, pick
   something you can't collide with, and never `rm` a name you didn't create in
   this session. Valid names are lowercase letters, digits and hyphens, starting
   with a letter, 31 max. **Delete no state you didn't create either**, which
   rules out `para image rm`, `para down` and `incus delete -f` on someone else's
   workspace, and above all
   `incus storage volume delete <pool> para-home-<slug>`. That last one
   destroys the project's one authenticated home
   for every workspace and every teammate on the box. `para rm` spares it on
   purpose, and nothing recreates its keys.
4. **The project's identity is a directory name.** `PARA_PROJECT` defaults to the
   slugified name of the checkout dir, and both the daemon-global image alias and
   the `para-home-<slug>` volume follow from it. Adopting `~/work/api` while
   `~/side/api` is already adopted therefore republishes *that* project's image
   and mounts its `/para/shared`, handing you its ssh key, its `gh` token, a
   `.seeded` file that makes provision skip seeding, and a `para ls` that lists
   its workspaces as yours for `para rm` to destroy. **para refuses none of
   this.** Its guards catch only a *different* project stamp, and here the stamp
   is identical, so rule 3's listing won't reveal it either. Before the first
   `para image build`, check the slug is free with the read-only `incus image
   list` and `incus storage volume list <pool>`, and pin
   `: "${PARA_PROJECT:=acme-api}"` in the `Parafile` if it isn't.

## Orient

Start with the survey. It's read-only, it runs `para doctor` for you, and it
answers most of what you'd otherwise guess about this machine and this repo.

```sh
bash "${CLAUDE_SKILL_DIR}/scripts/para-probe"
```

`${CLAUDE_SKILL_DIR}` is this skill's own directory, and every path here is
relative to it. If your harness leaves it unexpanded, look beside this `SKILL.md`.

Among other things the probe prints the `docs` and `templates` paths of the
**installed para**. Read those, not your memory of them. The `.paraspace/`
contract is versioned, and that copy is the version matching the `para` on this
box. Failing that, the same pages are at <https://paraspace.dev/docs/>.

| Before you | Read |
|---|---|
| write a `Parafile` | `parafile.md` |
| write `provision` or `boot` | `hooks.md` |
| write `image-build` | `image.md` |
| add a `para <verb>` | `commands.md` |
| slot a hook into the middle of another | `hook-points.md` |
| touch a `.paraspace/` somebody else wrote | `versioning.md` |
| debug a failing `up` | `troubleshooting.md` |

Read the two bundled templates too. They sit beside `docs/` in the same package,
they are the reference for what a good `.paraspace/` looks like, and you will be
starting from one of them rather than from a blank file.

If para isn't installed: `npm i -g paraspace`. If the machine isn't ready for
containers at all, you can still do everything except the last phase. Say so and
keep going rather than stalling.

## The four questions

Everything in `.paraspace/` falls out of these. Answer them from the repo, ask
the human only what the repo can't tell you.

| # | Question | Decides | Detail |
|---|---|---|---|
| 1 | How does the code get into a workspace? | `PARA_ORIGIN`, the clone step in `provision`, maybe a host-side seed verb | `references/ingestion.md` |
| 2 | What brings the stack up, and how do you know it's up? | `boot`, `PARA_ROUTES` | `references/stacks.md` |
| 3 | What must be installed for that to work? | `PARA_IMAGE_BASE`, `PARA_IMAGE_BOOTSTRAP`, `image-build` | `references/bases.md` |
| 4 | What is shared across workspaces vs. private to each? | `provision`, `$PARA_SHARED` | below |

Question 4 usually has the same answer. **Credentials, dotfiles and big
immutable caches are shared; everything the app writes is private.** One
authenticated home per project (`$PARA_SHARED`, the volume every workspace of
the project mounts at `/para/shared`) is what makes `para up` cheap after the
first one. A per-workspace database is the entire point, so never put live app
state on the shared volume. A multi-GB seed dump does belong there, and each
workspace restores from it at boot.

## Workflow

### 1. Read the evidence

Most repos already describe their own provisioning somewhere. Find it before
asking anyone anything. `references/evidence.md` maps each artifact
(`docker-compose.yml`, `Dockerfile`, `devcontainer.json`, a Coder `main.tf`,
CI workflows, `Procfile`, `mise.toml`, `provision.sh`, README) to the part of
`.paraspace/` it answers.

Look for a root `.env` too. `PARA_HOST_ENV` defaults to it, so the first
`para up` pushes it into every workspace and every agent in one. Point it at a
dev-only file if it holds more than an agent should see. Invent no secret values,
and echo none of theirs.

Then ask the human only the gaps, in one round. Usually that's which port is the
app you'd open in a browser, what's needed to log in locally, and whether there
is seed data.

### 2. Say the plan back, with its cost

Before touching anything, state the four answers in a few lines, plus what
adoption will cost on this machine, because some of it is measured in minutes:

- `para image build` takes **several minutes** the first time, and images are
  **per-arch**, built on the machine that runs them.
- Workspace names and the project slug are both **machine-global** (rules 3 and
  4), so `api` is a bad workspace name and `myapp-api` is a good one.
- Each workspace is a full container with a full copy of the stack. Disk is the
  real limit on how many run at once.

Get a yes before the first `para image build`: everything up to it is files in their
repo, which they can read; past it you're spending minutes of their machine.

### 3. Scaffold, then edit

Never hand-write a `Parafile` from memory, because it will drift from the
contract this para version pins. Scaffold from the directory you mean to be the
project root, since `para init` writes into `$PWD` and para finds a project by
walking *up* from `$PWD`, so a stray second `.paraspace/` deeper in the tree
wins. Then edit the result:

```sh
para init void-docker-gh   # code arrives by `git clone`, which covers most projects
para init void-minimal     # only when nothing is cloned (a pushed tree, a bare box)
para init --list           # see what this para ships
```

**Pick by how the code arrives, not by whether the stack is Docker.** The piece
of `void-docker-gh` worth keeping even for a stack with no containers in it is
its `provision`, which handles shared-volume seeding, one ssh key per project,
key authorization and `.env`. You're replacing its `boot` and `image-build`
either way. `void-minimal` has no clone step at all.

Adapt in the order `Parafile`, `image-build`, `provision`, `boot`, because each
one constrains the next. And know what you scaffolded. **The template ships
working demo values where you might expect placeholders that fail loudly.**
`PARA_ORIGIN` points at `jchook/docker-caddy` and `PARA_ROUTES` at `8080`. Miss
the routes and you get a 502; miss the origin and the workspace cleanly boots
somebody else's project. Where the Parafile sits in the repo it clones, derive
it instead:

```sh
: "${PARA_ORIGIN:=$(git -C "$PARA_PROJECT_DIR" remote get-url origin)}"
```

If the repo already has a `.paraspace/`, **don't scaffold over it.** `para init`
skips files that exist, but it still *adds* every file the template has and the
project doesn't, so you get a `commands/key`, a `skel/zshrc` or a `hooks/helpers`
somebody chose not to have, each carrying the template's Void-and-`gh`
assumptions. Read what's there instead (`Parafile`, every `hooks/*`, and every
`mods/*/hooks/*`, since para runs the project's hook *and* each mod's for the
same name) and edit in place.

Two things worth checking before you write a hook: whether a bundled **mod** already
does the piece you're about to write (`para mod add --list`), and whether the recipe
is already in `cookbook.md` (gh auth, dotfiles, seeding a database, several ports,
monorepos, extra verbs). Then read **Writing hooks that fit** below: its two traps
fail silently, and `boot`'s readiness contract is the one para can't check for you.

### 4. Build, boot, iterate

```sh
para doctor                # again, since anything you handed the human may have landed
para ls -a --names         # rule 3: a free name (rule 4's slug checks are separate)
para image build           # minutes
para up myapp-setup-check  # launch → volume → push .paraspace/ → provision → boot → routes
```

The probe already ran doctor once. Run it again here because this is the first
step that costs real minutes, and a host `✗` you reported in step 2 may have
been fixed while you were writing hooks. A blocker that is still there is worth
saying again before you spend the build, not after.

The last line of `para up` prints **every** URL the workspace publishes. Take the
host and port from there, exactly as printed, rather than from `para ls`, which
shows only the apex URL, shows none at all for a subdomain-only route, and shows
it for a stopped workspace too. Then ask for each one, with `-k` for para's own
CA and `-S` because `-s` alone hides the error:

```sh
curl -skS -m 10 -o /tmp/body -w '%{http_code}\n' "$url"   # then read /tmp/body
```

**A URL is a Caddy site, not a stack that answers**, and the reply tells you
which you got. No reply at all means retry once, because the first request to a
hostname Caddy has not served before pays for its certificate, then check
`para caddy status`. A **502** means Caddy has the route and the port isn't
answering from outside, so read the *address* in `para sh <ws> -c 'ss -ltn'`,
since a `127.0.0.1` bind is more often the bug than the port number is. A 502
that persists means `boot` returned zero too early. A **403 or 400 on the
framework's own error page** is host authorization rather than routing, which
`references/stacks.md` covers. **A 200 that isn't this project's app** belongs to
a neighbour, since every workspace shares the wildcard domain. With
`PARA_ROUTES=""` there is nothing to curl, so prove it with `ss -ltn` and the
stack's own health command.

If `para image status` shows an image already exists, say so before rebuilding.
The build replaces it for the whole project, so anything the human's current
image has that your `image-build` doesn't is gone from their next `para up`.

`para up` is idempotent and reconverges, so **fix the hook, re-run `up`** is the
normal loop, and you should expect to go around it two or three times. While
tuning `image-build`, `para image build -i` layers onto the current image and
skips the bootstrap, which is much faster, but do one clean build before you
call it done.

Read a hook failure top-down. The first `error:` line is where it actually
broke, the `stack:` beside it is the path para took to get there, and everything
below is the unwind. `hook-points.md` reads a nested trace, and explains why a
hook missing `set -e` reports a ready workspace with the error sitting in the
scrollback. `troubleshooting.md` explains most of what `para doctor` reports. For
the rest, the platform you're on and where to look when the workspace itself is
broken, see `references/machine.md`.

Leave the workspace up until the human has seen the URL answer, then tell them
the command that removes it (`para rm myapp-setup-check`). Tearing it down the
moment it goes green throws away the only evidence you have, and they can't
check a workspace that no longer exists. Either way the shared volume survives,
and with it the authentication you just did, which is the point.

### 5. Hand off

Commit `.paraspace/`. It's plumbing every teammate and every agent then gets for
free. **Nothing in it is a secret.** The `Parafile` and every hook are committed
*and* pushed into every workspace, so real values belong in the host-side file
that `PARA_HOST_ENV` names (step 1). para pushes that file into the workspace,
where the same variable names the pushed copy. Check `.gitignore` covers it.

Tell the human the three commands their colleagues run (`para image build`,
`para up <name>`, `para sh <name>`), which scaffolded verbs you kept, and what
you left out.

## Writing hooks that fit

Hooks are bash run inside the workspace, and they end up living in someone
else's repo forever. Match that repo's conventions, and para's:

- **`set -euo pipefail`, then `. "$PARA_HOOKS/helpers"`** where a `helpers`
  exists. That file is something the *templates* ship rather than something para
  provides, so a hand-written `.paraspace/` may have none and the source line
  would kill the hook on line two. It gives you `stage`/`info`/`warn`/`die` and
  `interactive`/`pause`; use them over raw `echo` so output reads like every
  other para project.
- **Idempotent, because `provision` and `boot` re-run on every `up`.** Guard
  expensive work with a sentinel beside the thing it guards, not with a flag
  someone has to remember.
- **`boot` returns zero only when every routed port is listening and the process
  listening is the one this run started.** This is the contract para cannot
  check for you, and breaking it is the single most common reason a workspace
  comes up and its URL 502s. The second half matters because `boot` re-runs on
  every `up`: kill the old process, relaunch at once, then poll the port, and a
  slow exit means your new process died on an address already in use while the
  poll passed against the old one, still serving the previous code. Wait for the
  old listener to go, then check the pid you started is alive.
- **Errors point somewhere.** Name the fix in the `die`, not just the symptom.
- **Prefer changing the shape over adding a guard**, keep functions to a screen,
  and keep comments to *why*, three lines max.
- **`shellcheck -x .paraspace/hooks/*` if it's available**, plus the two things
  it needs before it tells you anything useful. shellcheck can't expand
  `$PARA_HOOKS`, so the `helpers` source line reports SC1091 until either the
  hook carries `# shellcheck source=.paraspace/hooks/helpers` or the project
  root gets a `.shellcheckrc` holding `source-path=SCRIPTDIR`. And a guest
  script single-quoted on purpose (below) reports SC2016, which para's own code
  answers with an annotated disable rather than by changing the quoting:
  `# shellcheck disable=SC2016  # the guest expands this, not us`. Get those two
  in place first. Otherwise a correct hook fails the check, and the tempting
  next move is to "fix" code that was already right.

Two traps specific to hooks, both of which produce silent wrongness rather than
an error:

- **Within one `provision`, files cross between hooks but the environment does
  not.** A `/etc/profile.d/x.sh` written by one hook takes effect on the *next*
  thing para runs, not on the hook beside it.
- **`PARA_*` values are scalars only.** `PARA_PORTS=(3000 3001)` arrives as
  `3000`, silently. Pass a delimited string and split it, the way `PARA_ROUTES`
  does. Arrays *inside* a hook are fine, and both templates use them.

If a problem looks like "para should know about my framework", it isn't. The
answer is a hook, a `PARA_*` variable of your own (any `PARA_FOO` you invent is
forwarded to every hook), or a project command in `.paraspace/commands/`, a
five-line executable that runs on the host and becomes `para <verb>`.

## References

| File | When |
|---|---|
| `references/evidence.md` | reading a repo to work out how it comes up |
| `references/ingestion.md` | question 1 (git, private repos, no VCS at all) |
| `references/stacks.md` | question 2 (compose, bare processes, systemd, k3s, readiness) |
| `references/bases.md` | question 3 (choosing a base image and writing `image-build`) |
| `references/machine.md` | the host (Linux vs macOS/Colima) and debugging a broken workspace |

If the **context7** MCP server happens to be available, it's worth using for the
*project's own* stack while writing `image-build` and `boot`. For para itself,
the shipped `docs/` are authoritative.
