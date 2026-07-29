---
name: paraspace-setup
description: >-
  Set up ParaSpace for a project — write the `.paraspace/` directory (a Parafile
  plus provision/boot/image-build hooks) that turns a repo into parallel Incus
  dev workspaces, then build the image and prove `para up <name>` actually boots
  and serves. Use this whenever para, paraspace, `.paraspace/`, a Parafile,
  `para up`, `para init` or `para image build` come up; whenever someone wants
  isolated per-branch or per-agent dev environments, a workspace per task with
  its own database and URL, or several coding agents running side by side
  without stepping on each other; and whenever someone asks how to get an
  existing stack — docker compose, a provision script, a devcontainer, a Coder
  template, k3s, or services that just run locally — working inside a para
  workspace. Applies to any stack: git or no VCS, Docker or bare processes, any
  Linux base image.
---

# Adopting ParaSpace in a project

`para` gives a project parallel dev workspaces: one unprivileged Incus system
container per task, each with its own copy of the code, its own stack, its own
database, and its own `https://<name>.<domain>` URL.

The engine bakes in **nothing** about how a project is provisioned. Adoption is
therefore one directory — `.paraspace/` — that answers four questions about how
this project comes up. Your job is to answer them from evidence already in the
repo, write hooks that read like the rest of that repo, and then prove it boots.

## Orient before you write anything

Start with the survey — read-only, and it answers most of what you'd otherwise
guess about this machine and this repo:

```sh
bash <this skill's dir>/scripts/para-probe    # run it from the project root
```

Then read the docs **shipped with the installed para**, not your memory of them.
The `.paraspace/` contract is versioned, and those docs are the version that
matches the `para` on this box. Whichever of these resolves:

```sh
ls "$(dirname "$(readlink -f "$(command -v para)")")/../docs"   # follows the bin symlink
ls "$(npm root -g)/paraspace/docs"                             # global npm install
```

Failing both, the same pages are at <https://paraspace.dev/docs/>.

| Before you | Read |
|---|---|
| write a `Parafile` | `parafile.md` |
| write `provision` or `boot` | `hooks.md` |
| write `image-build` | `image.md` |
| add a `para <verb>` | `commands.md` |
| debug a failing `up` | `troubleshooting.md` |

Read the two bundled templates too — they sit beside `docs/` in the same
package, they are the reference for what a good `.paraspace/` looks like, and
you will be starting from one of them rather than from a blank file.

If para isn't installed: `npm i -g paraspace`. If the machine isn't ready for
containers at all, you can still do everything except the last phase — say so
and keep going, don't stall.

## The four questions

Everything in `.paraspace/` falls out of these. Answer them from the repo, ask
the human only what the repo can't tell you.

| # | Question | Decides | Detail |
|---|---|---|---|
| 1 | How does the code get into a workspace? | `PARA_ORIGIN`, the clone step in `provision`, maybe a host-side seed verb | `references/ingestion.md` |
| 2 | What brings the stack up, and how do you know it's up? | `boot`, `PARA_ROUTES` | `references/stacks.md` |
| 3 | What must be installed for that to work? | `PARA_IMAGE_BASE`, `PARA_IMAGE_BOOTSTRAP`, `image-build` | `references/bases.md` |
| 4 | What is shared across workspaces vs. private to each? | `provision`, `$PARA_SHARED` | below |

Question 4 has a short answer that is right most of the time: **credentials,
dotfiles and big immutable caches are shared; everything the app writes is
private.** One authenticated home per project (`$PARA_SHARED`, the volume every
workspace of the project mounts at `/para/shared`) is what makes `para up` cheap
after the first one. A per-workspace database is the entire point — never put
live app state on the shared volume. A multi-GB seed dump *is* shared, and each
workspace restores from it at boot.

## Workflow

### 1. Read the evidence

Most repos already describe their own provisioning somewhere. Find it before
asking anyone anything — `references/evidence.md` maps each artifact
(`docker-compose.yml`, `Dockerfile`, `devcontainer.json`, a Coder `main.tf`,
CI workflows, `Procfile`, `mise.toml`, `provision.sh`, README) to the part of
`.paraspace/` it answers.

Then ask the human only the gaps, in one round — typically: which port is the
app you'd open in a browser, what's needed to log in locally, and whether there
is seed data.

### 2. Say the plan back, with its cost

Before touching anything, state the four answers in a few lines, plus what
adoption will cost on this machine, because some of it is measured in minutes:

- `para image build` takes **several minutes** the first time, and images are
  **per-arch** — built on the machine that runs them.
- Workspace names are **machine-global**, so `api` is a bad name and
  `myapp-api` is a good one.
- Each workspace is a full container with a full copy of the stack. Disk is the
  real limit on how many run at once.

Get a yes before the first `para image build`. Everything up to that point is
files in their repo, which they can read; past it you're spending minutes of
their machine.

### 3. Scaffold, then edit

Never hand-write a `Parafile` from memory — it will drift from the contract this
para version pins. Scaffold, then edit the result:

```sh
para init void-docker-gh   # the stack is docker compose
para init void-minimal     # anything else
para init --list           # see what this para ships
```

`para init` skips files that already exist, so it is safe in a repo that has
some of a `.paraspace/` already. Adapt in this order — `Parafile`, then
`image-build`, then `provision`, then `boot` — because each one constrains the
next.

Two things worth checking before you write a hook: whether a bundled **mod**
already does the piece you're about to write (`para mod add --list`), and
whether the recipe you want is already in `cookbook.md` (gh auth, dotfiles,
seeding a database, several ports, monorepos, extra verbs).

### 4. Build, boot, iterate

```sh
para image build           # minutes
para up myapp-check        # clone → provision → boot → routes
para ls                    # state, IP, URL
```

Name the throwaway workspace after the project — names are machine-global, so
`check` or `test` will collide with somebody else's workspace eventually.

`para up` is idempotent and reconverges: **fix the hook, re-run `up`** is the
normal loop, and you should expect to go around it two or three times. While
tuning `image-build`, `para image build -i` layers onto the current image and
skips the bootstrap — much faster — but do one clean build before you call it
done.

Read a hook failure top-down: the first `error:` line is where it actually
broke, and the `stack:` beside it is the path para took to get there. Everything
below it is the unwind. `references/machine.md` maps the failures you'll
actually hit to their fixes.

Tear it down once it's green (`para rm myapp-check`); the shared volume — and
with it the authentication you just did — survives, which is the point.

### 5. Hand off

Commit `.paraspace/` — it's plumbing every teammate and every agent then gets
for free. Tell the human the three commands their colleagues will run
(`para image build`, `para up <name>`, `para sh <name>`), which of the
scaffolded verbs you kept, and anything you deliberately left out.

## Writing hooks that fit

Hooks are bash run inside the workspace, and they end up living in someone
else's repo forever. Match that repo's conventions, and para's:

- **`set -euo pipefail` and `. "$PARA_HOOKS/helpers"`** at the top. The helpers
  give you `stage`/`info`/`warn`/`die` and `interactive`/`pause`; use them
  instead of raw `echo`, so output reads the same as every other para project.
- **Idempotent, because `provision` and `boot` re-run on every `up`.** Guard
  expensive work with a sentinel beside the thing it guards, not with a flag
  someone has to remember.
- **`boot` returns zero only when every routed port is actually listening.**
  This is the contract para cannot check for you, and breaking it is the single
  most common reason a workspace comes up and its URL 502s.
- **Errors point somewhere** — name the fix in the `die`, not just the symptom.
- **Prefer changing the shape over adding a guard**, keep functions to a screen,
  skip bash arrays (they don't survive para's env forwarding, and empty ones
  trip `set -u` on macOS's bash 3.2), and keep comments to *why*, three lines
  max.
- Run `shellcheck -x .paraspace/hooks/*` if it's available. para's own CI lints
  every hook it ships, and yours should pass the same bar.

Two traps specific to hooks, both of which produce silent wrongness rather than
an error:

- **Within one `provision`, files cross between hooks but the environment does
  not.** A `/etc/profile.d/x.sh` written by one hook takes effect on the *next*
  thing para runs, not on the hook beside it.
- **Only scalars reach hooks.** `PARA_PORTS=(3000 3001)` arrives as `3000`, with
  no warning. Pass a delimited string and split it, the way `PARA_ROUTES` does.

## Staying inside the boundary

para is a generic mechanism, like `docker compose`. If the answer to a problem
seems to be "para should know about my framework", it isn't — the answer is a
hook, a `PARA_*` variable of your own (any `PARA_FOO` you invent is forwarded to
every hook), or a project command in `.paraspace/commands/`. Adding a verb is a
five-line executable, and it runs on the host with your tty.

The same boundary applies to what you tell the user: `para claude` is a file a
mod ships, not something the engine provides.

## References

Read the one you need; they don't need to be read together.

| File | When |
|---|---|
| `references/evidence.md` | reading a repo to work out how it comes up |
| `references/ingestion.md` | question 1 — git, private repos, no VCS at all |
| `references/stacks.md` | question 2 — compose, bare processes, systemd, k3s, readiness |
| `references/bases.md` | question 3 — choosing a base image and writing `image-build` |
| `references/machine.md` | the host (Linux vs macOS/Colima), and failure → fix |

`scripts/para-probe` prints the machine and repo survey the first phase needs.

Optional accelerator: if the **context7** MCP server is available, use it for
docs on the *project's own* stack (framework, database, package manager) while
writing `image-build` and `boot`. Don't use it for para or Incus — the shipped
`docs/` are authoritative for para, and `references/machine.md` carries the
Incus behavior that actually bites here. Nothing in this skill requires it.
