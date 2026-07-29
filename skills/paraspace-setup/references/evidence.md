# Reading a repo for how it comes up

Almost every project already encodes its own provisioning somewhere — CI, a
container build, an infra template, a setup script, or a README section someone
wrote for the last new hire. Adoption is mostly **translation**, not invention.
Find the source, translate it, and confirm only the gaps with a human.

`scripts/para-probe` lists the candidates. This page says what each one proves.

## The map

| Artifact | What it tells you | Lands in |
|---|---|---|
| `docker-compose.yml` | the whole stack, its ports, its images, its env | `boot` (one line), `PARA_ROUTES`, `PARA_PREPULL_IMAGES` |
| `Dockerfile` | the package list and base distro someone already chose | `image-build`, `PARA_IMAGE_BASE` |
| `.devcontainer/devcontainer.json` | `image`/`features` → packages; `postCreateCommand` → provision; `forwardPorts` → routes | all four |
| Coder / Terraform `main.tf` | `coder_agent.startup_script` is a provision + boot hook already written; `coder_script` blocks and modules list the tooling | `provision`, `boot`, `image-build` |
| `.github/workflows/*.yml` | `services:` = what the app needs running; `setup-node`/`setup-python`/etc. = pinned runtime versions; the test job = a working headless bring-up | `image-build`, `boot` |
| `Procfile`, `foreman`/`overmind` config | every process that must be running, by name | `boot` |
| `mise.toml`, `.tool-versions`, `.nvmrc`, `.python-version` | exact runtime versions — honor them, don't round to the distro's | `image-build` |
| `flake.nix`, `shell.nix` | the full dependency closure, including system libs people forget | `image-build` |
| Ansible playbooks, `Vagrantfile`, `provision.sh`, `bootstrap.sh` | literally a provision hook in another language | `image-build` + `provision` |
| `Makefile` / `Taskfile.yml` (`setup`, `dev`, `bootstrap` targets) | the commands the team actually types | `provision`, `boot` |
| `.env.example` | what the app needs to be handed, and which values are secret | `PARA_HOST_ENV`, the `.env` step in `provision` |
| k8s manifests, Helm chart, `skaffold.yaml` | a k3s-in-workspace stack, or a compose translation | `boot`, `image-build` |
| `README.md` "Getting started" / `CONTRIBUTING.md` | the human's own answer, usually the fastest read | everything |

## How to read each one

**Split by lifetime, not by source.** The same information gets divided by a
single question: *does it change per workspace?* Package installs, runtime
toolchains and pre-pulled images are the same in every workspace → `image-build`,
paid once. Clones, credentials, `.env` rendering and database seeding differ per
workspace → `provision`, paid every `up`. Starting things → `boot`.

**A Dockerfile is a package list, not a plan.** Take its `apt-get install` line
and its base-image choice; ignore its layering, its `COPY`, its `USER` and its
`CMD`. A para workspace is a system container that boots an init and holds the
whole stack — it is much closer to a small VM than to an app container.

**CI is the most trustworthy source you have**, because it demonstrably works
headless. `services:` blocks name the databases and their versions; the setup
steps name the runtime versions; the test command is a bring-up you can copy.
What CI won't tell you is anything about the interactive dev loop — hot reload,
seed data, an admin login.

**A Coder template is the closest cousin.** `startup_script` maps almost
line-for-line onto `provision` + `boot`; its parameters are `PARA_*` variables;
its modules (code-server, dotfiles, an agent CLI) are `image-build` packages or a
para mod. The one thing that does not carry over is the cloud plumbing.

**Compose is the easy case, and it is worth checking whether it's true.** If a
`docker-compose.yml` covers the whole stack, question 2 is one line and question
3 is "docker, nesting, overlayfs". Confirm it isn't a partial file that assumes
the app itself runs on the host — that's the hybrid case in
`references/stacks.md`.

## What the repo won't tell you

Ask these in one round, after you've read everything else:

1. **Which port would you open in a browser?** (becomes the apex route; other
   ports become subdomain routes or nothing)
2. **What does a fresh checkout need to be usable — migrations, seed data, a
   test login?**
3. **Which secrets are needed to boot at all**, and where do they come from
   today? (a `.env` on their machine → `PARA_HOST_ENV`; a vault → a hook)
4. **Is the repo private, and on which host?** (decides the auth path in
   `references/ingestion.md`)
5. **Anything heavy that shouldn't be downloaded per workspace** — model
   weights, a big npm/composer cache, container images.

Then say the four answers back before you start writing.
