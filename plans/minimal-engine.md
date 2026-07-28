# The minimal engine: a total rewrite of `bin/para`

Status: **engine landed.** `bin/para` *is* the rewrite (1,080 lines, from
2,244); the old script is gone from the tree and lives on in git history. The
bundled templates and the e2e fixture are on contract 1, both test tiers are
green (32 tests), and `bin/lint` is clean. **Remaining: the docs** — every page
under `docs/` still describes the pre-rewrite interface (`para stop`,
`config-set`, `web`, `key`, `reconcile`, the registry, `~/.para`), which is step 3 below and the
subject of `plans/docs-rewrite.md`.

**Supersedes** `plans/cut-and-harden.md` (PR #11), `plans/ts-port.md` (PR #10),
and `plans/go-rewrite.md`. Decisions, made: **bash**, rewritten from an empty
file; **the contract redesigned freely** and left at `PARA_CONTRACT` **1**,
since nothing is released yet — a pre-release iteration doesn't earn a version
number; **no compatibility with what came before**.

## The goal

`para` is glue over `incus` and `caddy`. The code should read like it. The
2,244-line `bin/para` reads like a compliance document: every command carries a
paragraph explaining the bash it needed, every config key carries a guard
against a way it could be misused, and the same three ideas are spelled four
different ways.

The target is **habitability, not line count** — the line count is a symptom.
Held to four rules:

1. **No bash gymnastics.** If a line needs a warning comment about bash, write
   the line that doesn't need one. Nothing gets explained by a paragraph.
2. **Inheritance, not enforcement.** Config resolves by ordinary bash rules.
   No denylists, no `declare -p` probing, no "did they set it or leave it
   unset" archaeology. A user who puts a nonsense value in their config gets
   nonsense; `para doctor` is where we tell them so.
3. **One way to do each thing.** One door into a workspace, one env-forwarding
   rule, one place that knows about TTYs, one place that knows about Caddy.
4. **Simplicity beats features.** When a feature costs a mechanism, the feature
   goes. Several do below.

Line budget falls out at **~950** (from 2,244), but the real gates are: **no
function longer than ~30 lines, no comment longer than ~3 lines.** A comment
that wants to be longer is a docs page with a one-line pointer.

## Six structural decisions

Each one deletes a *category* of code, not a few lines. Guards mostly evaporate
here rather than being cut — they existed because a data structure was fragile,
and the structure changes.

### 1. Incus is the database. Delete the registry.

Verified on incus 6.22: `incus list` takes **config keys and device keys as
columns**, and config keys as **filters**.

```
$ incus list 'user.para.project=madi' -f csv \
    -c 'n,s,user.para.project,user.para.routes,user.para.domain,devices:eth0.ipv4.address'
para-ws2,STOPPED,madi,9000 api:3000 pgweb:8081,madisonai.dev,10.120.251.200
```

One call, ~17 ms, correct for stopped instances (the device column is the
*configured* static IP), scoped by project *by incus*, no bash filtering. The
container already had to be self-describing for `reconcile` to work — so make
the stamp the only record and delete everything that mirrored it.

**Deletes:** `$XDG_STATE_HOME/para/workspaces` and every reader/writer of it
(`ip_of`, `project_of`, `registry_remove`, `first_running_ct`, the awk one-liners
in `web`/`ls`, the mktemp-rewrite dance); the `-` sentinels; every "an empty
field would shift every reader's parse" guard; the whitespace-in-stamp guard;
the registry-vs-container double ownership check; **`para reconcile` entirely**
(it exists only to repair drift between two copies of one fact). `alloc_ip`
reads the addresses actually in use on the bridge (`--all-projects`) instead of
para's own bookkeeping — which is strictly more correct, and lets
`test/lib/sandbox.sh` drop its ~50-line IP-band carving too.

**Costs:** `para ls` needs incus reachable. Fine — everything else does.
Routes are stamped **space-separated** so no CSV field can contain a comma and
parsing stays `IFS=, read -r`.

### 2. Config is two sourced bash files. That is the whole precedence story.

```sh
PARA_PROJECT_DIR="${PARA_PROJECT_DIR:-$(find_project_root || true)}"
parafile="$PARA_PROJECT_DIR/.paraspace/Parafile"

[ -f "$PARA_CONFIG" ] && . "$PARA_CONFIG"     # ~/.config/para/config — your box
[ -f "$parafile" ]    && . "$parafile"        # .paraspace/Parafile — the project
: "${PARA_DOMAIN:=paraspace.dev}"             # …engine defaults, last
```

Both files are sourced bash using **one idiom**, the one the Parafile already
uses:

- `: "${PARA_X:=value}"` — "here's a value, unless the environment has one."
- `PARA_X=value` — "I insist," which is a legitimate thing for a project to say.

That is the entire model: **environment > whichever file is sourced first >
the other file > engine defaults.** User config first (your box outranks a
project on box-shaped keys), Parafile second, defaults last. No code implements
any of it.

**Deletes:** the `parafile_only_key` denylist and its warning path; the
`printf -v` hand-rolled loader; `ROUTES_DECLARED` and the `declare -p`
array-detection dance; the set-vs-unset probing on `PARA_HOST_ENV`; the
load-time regex validation of `PARA_CLONE_DIR` / `PARA_CLONE_BRANCH` /
`PARA_PROJECT`; `validate_domain` and its on-write / on-use split; the
`usage_full` special-casing of unresolvable values. Roughly 180 lines of
guards, gone, and the remaining ones are gone for *structural* reasons — see
decisions 3 and 4.

Kept: `validate_name` for workspace names (one regex, one message — the most
typed input, and it becomes a DNS label). Everything else, incus rejects loudly
and clearly on its own.

### 3. Every "your box is misconfigured" check moves to `para doctor`.

~200 lines of preflight — colima version, cgroup-v1-inside-/sys/fs/cgroup,
`getcap cap_net_bind_service`, `idmapped_mounts`, OpenZFS ≥ 2.2, pool driver,
dir-pool-on-btrfs see-through — is real, hard-won domain knowledge sitting in
the hot path of every `up`. It moves, verbatim in spirit, into one command that
exists to say what's wrong. `para doctor` also absorbs:

- resolved config introspection (deleting that section of `--help`),
- wildcard DNS actually resolving to 127.0.0.1 (a new check, and a common
  first-run failure),
- "your user config sets `PARA_PROJECT` box-wide, which is probably wrong" —
  **the denylist, re-expressed as advice instead of enforcement.**

`up` keeps only what it can't proceed without: incus reachable, image exists,
pool exists (die with the exact `incus storage create` line). And `ensure_pool`
stops **mutating** — no more auto-switching `PARA_POOL` to `para-dir` and
writing it into the user's config file behind their back. It warns; doctor
explains; the user decides.

One line replaces the rest: on a failed `up`, print *"if this looks like a host
problem, run `para doctor`."*

### 4. One door into a workspace, and it holds all the terminal knowledge.

Every guest execution — `para sh`, hooks, and (via `para sh`) project commands
— goes through one function. See "Terminal semantics" below; this is the part
of the old file that is **most** worth preserving and the part currently
duplicated across `wexec`, `wexec_tty`, `cmd_sh`, `cmd_claude` and `cmd_run`
with four subtly different spellings.

The guest script stops being spliced together host-side. Everything the guest
needs is already in the guest, in `~/.paraspace/env`:

```sh
guest_prelude='
  . ~/.paraspace/env
  infocmp "${TERM:-}" >/dev/null 2>&1 || export TERM=xterm-256color
  cd "$HOME/$PARA_CLONE_DIR" 2>/dev/null || cd "$HOME"
'
```

Nothing is interpolated except the user's own command, appended verbatim. The
`'…'"$var"'…'` quoting sandwiches disappear — and with them the injection
surface that `PARA_CLONE_DIR`'s validation regex existed to cover.

### 5. One env-forwarding rule, everywhere.

**Every `PARA_*` variable in scope is forwarded to anything para runs on your
behalf** — guest hooks, project commands, and the image-build payload.

```sh
# The one way para hands its context to anything it runs for you.
para_env() { local v; for v in "${!PARA_@}"; do printf 'export %s=%q\n' "$v" "${!v}"; done; }
```

Written to `~/.paraspace/env` for the guest, prepended to the payload on stdin
for `image build` (`{ para_env; cat "$payload"; } | incus exec … -- bash -s`),
and for host-side project commands it's the one-liner `export "${!PARA_@}"`.

**Deletes:** the `--env PARA_USER --env PARA_UID --env PARA_GID` special cases
in image build; the array-skip guard in the forwarder; and — the good part —
**`stack_images()` and the whole `PARA_PREPULL` concept.** para no longer parses
`docker-compose.yml` and `Dockerfile` (madi policy that never belonged here),
and doesn't replace it with a key either: a project that pre-pulls images sets
`PARA_PREPULL` in its Parafile and reads it in its own `image-build.sh`. **The
engine never learns the key exists.** That is the generic-mechanism boundary
working as designed.

### 6. Let `caddy validate` be the validator.

`caddy validate --config … --adapter caddyfile` runs before every reload, and
its failure is surfaced instead of swallowed (a known bug fix). Once it does,
`parse_routes`' ~70 lines — port range 1–65535, leading zeros, DNS-label shape,
within-workspace host collisions — and `gen_caddyfile`'s cross-row duplicate
guard are re-implementations of a check Caddy does better, whose only reason for
existing was that a bad value used to *corrupt the registry*. There is no
registry. Route handling becomes:

```sh
# Routes may be written with commas, spaces, tabs or newlines. Canonical form is
# lowercase, space-separated — what para stamps and what `for r in $PARA_ROUTES` reads.
normalize_routes() { printf '%s' "$1" | tr 'A-Z,\t\n' 'a-z   '; }
```

Input spelling stays as forgiving as it is today (commas are the readable
choice for a short list; newlines for a long one); only the canonical form
changes. No squeeze or trim: every consumer word-splits anyway. Deliberately a
string transform rather than an `IFS=$', \t\n'` split — the split form needs
`set -f` and an IFS save/restore around it, which is exactly the paragraph
(`PARA_ROUTES="30*"` resolving against your `$PWD`) this rewrite is trying not
to have.

A bad route now fails at `caddy validate`, loudly, naming the site, with nothing
written.

## Terminal semantics: the things that must not be lost

`para claude` took real debugging. All of it survives, in one function, stated
once:

| What | Why |
|---|---|
| `su -` — never `incus exec --user` | `su` runs initgroups, so supplementary groups load (`docker`, without which the stack hits permission-denied on the socket) |
| `su --pty` on the interactive path | with `-c`, plain `su` stays the terminal's foreground process and drops SIGWINCH; the TUI never repaints on resize (stuck-small claude, misplaced cursor). `--pty` proxies the tty and forwards resizes |
| `incus exec -t` only when **stdin and stdout are both** TTYs; explicit `-T` otherwise | a pty echoes NULs and translates `\n`→`\r\n`; forcing `-t` on stdin alone corrupts `para sh x -c … \| tee`, `> file`, and `$(…)`. Bare auto-mode ignores `PARA_NONINTERACTIVE`, so be explicit in both directions |
| `infocmp "$TERM" \|\| export TERM=xterm-256color`, in the guest | a host `$TERM` (ghostty) with no terminfo in the container hard-fails tmux/claude; otherwise pass the native terminal through untouched |
| `exec` at the end | the workspace command's exit status becomes para's |
| `-s /bin/bash` for `-c` | deterministic semantics regardless of the image's login shell; hooks are run **by path** so their own shebang decides |

New, documented consequence: `su --pty` is util-linux `su`. **busybox `su` (Alpine)
has no `--pty`**, so an interactive `para sh` on a busybox image fails loudly.
That's an image requirement (`docs/image.md`), not something the engine papers
over. The e2e fixture is unaffected — it runs non-interactive.

## Project commands: `.paraspace/commands/<verb>`

The one new primitive, and the one that lets policy leave the engine.

```
para <verb> [args…]
  engine verb                      -> engine (engine always wins)
  .paraspace/commands/<verb>       -> exec it, on the HOST, with every PARA_*
                                      exported, args passed through verbatim
  otherwise                        -> unknown command
```

Host-side, with the user's tty, so interactive flows work naturally. Also
exported: `PARA_BIN` (this script's path, so a command can call back reliably)
and `PARA_PROJECT_DIR`. Workspace resolution is the command's business — para
passes args through untouched.

Because `para sh` owns the terminal semantics, the commands that used to be
hardcoded engine verbs are now one-liners a template ships:

```sh
#!/usr/bin/env bash
# summary: claude in the workspace clone
exec "$PARA_BIN" sh "$1" -c "exec claude --name $1"
```

```sh
#!/usr/bin/env bash
# summary: tmux session — claude in window 1, a shell in window 2
exec "$PARA_BIN" sh "$1" -c '
  tmux has-session -t '"$1"' 2>/dev/null && exec tmux attach -t '"$1"'
  tmux new-session -d -s '"$1"' -n claude "claude --name '"$1"'"
  tmux new-window  -t '"$1"': -n sh
  exec tmux attach -t '"$1"'
'
```

- **`--help`** lists discovered commands under `PROJECT COMMANDS`, with the
  `# summary:` line if the file has one, name-only if not.
- **Completion** gets them from `para commands` (bare names, one per line, the
  sister of `para ls --names`), and offers workspace names at position 2 for any
  non-engine verb — the right default with zero configuration.
- **Security**: they run with your privileges, like any script in a repo you
  cloned. Engine verbs shadow them so a template can't silently redefine
  `para up`; everything discovered is listed in `--help` so nothing runs
  invisibly. `para doctor` flags a command that shadows an engine verb.

## Hooks, simplified

Two guest hooks, unchanged in spirit: **`provision`** (idempotent, before boot)
and **`boot`** (readiness contract). Simplifications:

- **Guest staging dir `~/.para` → `~/.paraspace`.** Host `.paraspace/` pushes to
  guest `~/.paraspace/` — same name, same content, one concept instead of two.
  Hooks live at `~/.paraspace/hooks/<name>`, skel at `~/.paraspace/skel`, the
  seeded env at `~/.paraspace/host.env`, para's context at `~/.paraspace/env`.
- **`PARA_ROUTES` is space-separated** in the injected env, so a hook writes
  `for r in $PARA_ROUTES` and the templates' `parse_routes` / `route_ports`
  helpers **delete themselves**.
- **`PARA_HOST_ENV`** loses its set-but-missing / unset-means-default / empty-
  means-nothing three-way. Default `$PROJECT_ROOT/.env`; push it if it exists;
  otherwise don't. Three lines.
- **The push is one command**, not a hooks/skel/env/chmod sequence with a
  conditional.
- Hooks are **executed by path** (their shebang decides), not `bash <path>`.

Everything else about hooks is deleted *from the engine* rather than changed:
there is no third hook class. Host-side behavior is a project command.

## The command surface

**Engine keeps** — mechanism only:

| Verb | |
|---|---|
| `up` / `down` / `rm` | incus lifecycle, IP allocation, volume attach, stamp, hooks, Caddy |
| `ls [--all] [--names]` | one incus query, formatted |
| `sh <name> [-c …]` | the one door into a workspace |
| `caddy start\|stop\|status` | the host side of the glue (was `para start`/`stop`) |
| `image build\|status\|rm` | the publish/swap choreography is engine-grade |
| `config init\|path` | seed / locate the user config (see below) |
| `init [<template>]` | file copy |
| `doctor` | everything that used to be inline preflight |
| `commands` | project-command names (completion + `--help` feeder) |
| `completions <shell>` | generated from the verb table + discovered commands |
| `--help` / `--version` | ~45 lines, not 160 |

**Offloaded to `.paraspace/commands/`** (templates ship them; nothing is lost
for a project that wants them): `claude`, `run`, `key`, `web`, `config-sync`.

**Deleted outright**: `reconcile` (decision 1), `config-set` and the
auto-persist path (decision 3), `config-import` (it was `incus file push` sugar
— a project command if anyone wants it), `install` (npm is the funnel),
`image-build` (the deprecated alias), `stack_images` (decision 5).

### `para config init | path`

The user config is hand-edited sourced bash now, so the engine's job is to help
you find it and start it — not to write it for you.

- **`config path`** prints `$XDG_CONFIG_HOME/para/config`. That's the whole
  command, and it makes `$EDITOR "$(para config path)"` the documented way to
  edit it (no `config edit` verb needed).
- **`config init`** seeds it, refusing to clobber without `--force`. No bundled
  asset and no drift, because it's **generated from para's own resolved
  values** — which also makes the box-level knob list exist in exactly one
  place:

```sh
{ echo '# para user config — sourced bash. ":=" yields to the environment,'
  echo '# a plain assignment insists. Uncomment what you want to change.'
  for k in PARA_DOMAIN PARA_HTTPS_PORT PARA_POOL PARA_BRIDGE PARA_IP_LO PARA_IP_HI; do
    printf '# : "${%s:=%s}"\n' "$k" "${!k}"
  done
} > "$PARA_CONFIG"
```

`para doctor` prints the resolved values and the path, so the two commands
compose with the one place that diagnoses.

**Kept from the old interface** because they're proven: the Parafile as sourced bash;
blanket `PARA_*` forwarding; `/para/shared` and the `security.shifted` volume;
container stamps; contract pinning (a project targeting another one gets a
clear refusal).

**Image-build details that survive verbatim** — the domain knowledge, not the
prose: force-stop before publish (init-agnostic), publish from a **snapshot**
(the dir-pool lstat race), publish to a temp alias then swap with the
`published` latch (never destroy the working image first), EXIT/INT traps that
tear the builder down, background `incus exec … & wait` so Ctrl-C works, `-q`
when stderr isn't a TTY, `PARA_IMAGE_BOOTSTRAP` via `sh -c` before the payload.
Dropped: the `user.para.uid` / `user.para.user` / `user.para.contract` /
`user.para.incremental` stamps and the `up`-time drift refusal built on them
(doctor's job). Kept: `user.para.src_sha` and `image status`'s drift report —
both dropped since, for `user.para.base` ([mods.md](./mods.md#drift-detection-goes-away)).

## Line budget

| Section | est. |
|---|---|
| header + config load (defaults, two sourced files, derived keys) | 70 |
| helpers (log/warn/die/need/interactive/validate_name/url/para_env) | 60 |
| incus queries (list/get/ct_name/alloc_ip/stamp) | 70 |
| caddy (generate/validate/start/stop/reload) | 90 |
| `ws_exec` + `sh` | 45 |
| hooks (push + run) | 45 |
| `up` / `down` / `rm` | 110 |
| `ls` | 35 |
| `image build` / `status` / `rm` | 130 |
| `init` | 60 |
| `doctor` | 110 |
| dispatch + project commands + help + completions | 130 |
| **total** | **~955** |

A section over budget is the review signal that policy is creeping back.

## Decisions taken

1. **`start`/`stop` → `caddy start|stop|status`.** `para stop` sat one word from
   `para down` and meant something unrelated. `up` still starts Caddy
   automatically; macOS colima autostart moves to `doctor`/`up`.
2. **`config-set` → `config init` + `config path`.** Nothing writes the config
   automatically any more (decision 3), so the engine seeds and locates it and
   otherwise stays out of the way.
3. **`PARA_ROUTES` canonical form is space-separated**, input spelling
   unchanged (commas, spaces, tabs, newlines all separate entries).

## Still open

- **`web` and `key` leave the engine.** Recommend yes — they're a template's
  `xdg-open` and a template's key path, and they make the two best demos of the
  new mechanism, so the default template ships them. `para ls` prints the URL
  either way. Say no and they stay as engine verbs (~15 lines each, now that
  there are no route sentinels to interrogate).

## As built

What writing it settled, beyond the design above:

- **`PARA_READY_HOST`** (new, optional Parafile key). The old engine blocked on
  `getent hosts github.com` before every hook — a hardcoded external host, i.e.
  project policy in the engine. Now `up` waits for the incus agent, and waits
  for DNS only if the project names a host it depends on. The clone-based
  templates declare `github.com`; the Alpine fixture declares its package
  mirror.
- **`PARA_CADDY_ADMIN`** (new, optional). Caddy's default admin endpoint
  (`localhost:2019`) is shared by every Caddy on the box via `SO_REUSEPORT`, so
  a `caddy reload` could land on someone else's server. Setting this emits an
  `admin` directive in the generated Caddyfile. The e2e sandbox uses it, which
  deleted its "refuse to run while another Caddy owns :2019" preflight — the
  tier now runs happily beside a real para Caddy.
- **`caddy stop` is a `kill` on the pidfile**, not an admin-API call, for the
  same ambiguity reason. SIGTERM is a graceful shutdown for Caddy.
- **`MIN_INCUS` + a capability probe in `doctor`.** para needs config keys and
  device keys as `incus list` columns; an incus too old rejects the column
  (exit 1, independent of how many instances exist), so the probe decides and
  the version only shapes the message — a distro may backport, and the number
  alone would then lie in both directions. No semver parser: `version_ge` is
  `sort -V`, which is also the only thing that gets `6.9 < 6.22` right.
- **`doctor` does not inherit `set -e`.** Every check reads something that may
  be missing, so a failed probe used to abort the report at the first bad line —
  exactly when the rest of it matters most. One `set +e` in `cmd_doctor`.
- **`rm` and `down` converge instead of erroring.** `rm` of an absent workspace
  warns and succeeds (teardown scripts depend on it); `down` of a stopped one
  warns and succeeds. `up` was already convergent.
- **`ls` columns are NAME STATE IP PROJECT URL** — state second, since it's what
  you scan for.
- **`image build` lost `-q`/`-v`** (it auto-quiets when stderr isn't a TTY, the
  only case that mattered) and lost the `user.para.uid`/`user`/`contract`/
  `incremental` stamps with the `up`-time drift refusal built on them.
  `-i/--from-current` and the `user.para.src_sha` drift report stay — the drift
  report has since been dropped. Its config checks now run before it touches the
  daemon.
- **Templates ship the offloaded verbs**: `void-docker-gh` carries
  `commands/web` and `commands/key`. Both are one-liners over `para sh`, because
  that is where the terminal handling lives. (`commands/claude` and
  `commands/run` went with `void-jchook` when
  [mods](./mods.md) replaced it — v1 mods ship no `commands/`, so they live in
  `docs/agents.md` as snippets to copy.) Templates no longer bake
  `PARA_PROJECT` — the engine derives it from the directory name.
- **The Caddyfile is machine-wide by construction.** It's generated from incus,
  so it lists every para workspace on the box regardless of which project (or
  which sandbox) generated it. Recorded in `test/README.md`.
- **Interactive `para sh` is not e2e-coverable** and never was: `su --pty` is
  util-linux, the Alpine fixture has busybox. Unchanged from the old engine —
  same flags, same limitation — now documented rather than incidental.

### Bugs the rewrite's own test runs caught

Worth keeping as evidence that the e2e tier earns its keep: the image builder
leaked after a *successful* build (the EXIT trap was cleared before the delete);
`alloc_ip` compared whole lines against an incus column that annotates addresses
as `10.0.0.5 (eth0)`, so it would have handed a live workspace's IP to a new
one; `<<-EOF` silently flattened the generated Caddyfile; and route
canonicalization left the fixture's multi-line value as `"   8080   api:8080 "`.

## Migration (one branch, staged, suite-green at the end)

1. ~~**Write the engine**~~ **done.** `bin/para2` beside the old one, driven by
   `PARA=bin/para2 test/run --e2e`. The fixture gained
   `.paraspace/commands/hello` (asserted by `test_project_commands_extend_para`)
   and moved to the new contract, so the *old* `bin/para` refused it — which was
   the version handshake working as designed. **No unit tier** — a reversal of
   the earlier plan: the CLI tier already runs the real binary, and a source
   guard plus a third tier is machinery this engine doesn't need.
   *Next:* the CLI tier still targets the old surface (route/domain validation,
   `config-set`, `web`, registry readers) and needs its rewrite — roughly half
   of its 371 lines test behavior the rewrite deliberately deletes.
2. **Migrate the bundled templates**: `commands/` files, `hooks/helpers` loses
   `parse_routes`/`route_ports`, `~/.para` → `~/.paraspace`, `PARA_CONTRACT=1`.
3. **Docs pass**: `parafile.md` (precedence section shrinks to a paragraph),
   `hooks.md`, new `commands.md` section for project commands, `image.md` (the
   `su --pty` image requirement), `versioning.md`'s contract-2 entry with the
   v1→v2 migration, `internals.md` (no registry), CLAUDE.md's line counts.
4. **Migrate madi** (repo-root `.paraspace/`, including its own
   `commands/claude` and `commands/run`) in the same change that swaps
   `bin/para2` → `bin/para` and deletes the old script.

Gates: `bin/lint` (add `check-set-e-suppressed`, `check-extra-masked-returns`,
`add-default-case`, plus `shfmt`) from the first commit — the new file is
written under the rules, not graded against them later; CLI tier in CI; full
e2e locally including one `PARA_TEST_REBUILD=1` run and a real `void-docker-gh`
boot before the swap.

## Risks

- **The contract break is total** — mitigated by owning every consumer and
  migrating them in the same change. Nothing is released, so `PARA_CONTRACT`
  stays at 1; a project targeting a different one fails loudly.
- **A rewrite can drop invisible behavior** — mitigated by treating the old
  file's domain comments as the checklist (they are the spec of the invisible
  behavior), and by the "terminal semantics" and "image-build details" tables
  above being explicit inventories rather than a promise to remember.
- **Fewer guards means uglier failures for the misconfigured.** Accepted
  deliberately: `para doctor` is the answer, and it's a better one, because it
  runs when you're looking for answers instead of when you're trying to work.
- **`para ls` now requires incus.** Accepted.
- **Policy creep back into the engine** — the section budget is the tripwire,
  and project commands remove the excuse ("just one more verb").
