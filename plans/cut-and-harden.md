# Phase -1: cut and harden `bin/para` (in bash)

Status: planned. This supersedes-for-now the TypeScript port plan (PR #10):
an adversarial review of that plan concluded ~85% of `bin/para`'s hard content
is domain-essential (it would port 1:1, gaining nothing from types), that the
highest-value fixes are deliverable in bash in days rather than at the end of
a multi-week port, and that porting now would **ossify boundary violations**
that pre-launch is the cheapest moment to cut. So: shrink the surface to the
one worth having, kill the dominant bug class, and add the missing test tier —
all in bash. The port stays on the shelf with an explicit trigger (end of this
doc).

Everything here is contract-neutral or additive: `PARA_CONTRACT` stays 1.
Per CLAUDE.md, every PR carries its docs updates and versioning.md Decisions
entries in the same change.

## A. Cut (the surface that shouldn't exist)

### A1. Remove `para install` + XDG template staging

`cmd_install` (bin/para:1741-1760) and the `~/.local/share/paraspace` staging
it feeds. The npm funnel (`npm i -g paraspace`) is already what README /
getting-started document; the zero-toolchain copy-a-file audience this served
is tiny pre-launch and the verb carries a stale-copies-in-the-wild update
problem. Checkout users: run `bin/para` directly or `npm link`.
Docs: drop the commands.md row; versioning.md entry (command surface is not
contract).

### A2. Remove the `image-build` deprecated alias

bin/para:2233. A deprecation alias for zero external consumers. Its
test (`test_image_build_alias_is_still_accepted`) goes with it.

### A3. `stack_images` → a Parafile key (the compose/Dockerfile knowledge)

`stack_images` (bin/para:1554-1563) parses `docker-compose.yml` `image:` lines
and `Dockerfile` `FROM`s at the project root — compose knowledge hardcoded in
the tool whose one rule is that it holds none. Two consumers: the image-build
pre-pull (bin/para:1857) and the drift hash (`image_src_sha`, bin/para:316).

Replace with an **optional** Parafile key, `PARA_IMAGE_PREPULL` — a
CSV/whitespace list, same liberal parsing as `PARA_ROUTES`. Unset/empty = no
pre-pull (para assumes nothing about your stack). `image_src_sha` hashes the
resolved value instead of parsing the repo, so the drift signal is preserved.
`templates/void-docker-gh` declares its demo image; and because the Parafile
is sourced bash, a project that *wants* the old derive-from-compose behavior
puts the one-liner in its own Parafile — the policy moves to the consumer,
which is the whole point. Additive key: no contract bump. Docs: parafile.md
(optional-keys section), image.md (pre-pull paragraph), template Parafiles.

### A4. Genericize `cmd_config_sync`

bin/para:1524-1548 hardcodes one template's skel layout — `zshrc`, `tmux/`,
`claude/`, `nvim/`, and `chmod +x /para/shared/claude/statusline.sh` (para
knowing a project's statusline path is the clearest boundary breach in the
file). Generic replacement, same UX:

- iterate the top-level entries of `$PROJECT_ROOT/.paraspace/skel/` and
  `incus file push -r` each to `/para/shared/`;
- restore exec bits generically: `find skel -type f -perm -u+x` host-side,
  `chmod +x` the corresponding guest paths (incus push drops mode);
- chown what was pushed.

The "never touches user state" property holds by construction (it only pushes
skel entries). Behavior for the bundled templates is identical. Docs:
commands.md row rewording.

### A5. `cmd_key`: stop hardcoding the hooks' key path

bin/para:1424-1430 reads `/para/shared/ssh/id_ed25519.pub` — a path the
*template's hooks* create; para "never runs git" yet knows their layout.
**Decision needed** (recommendation first):

1. **Recommended:** optional Parafile key `PARA_PUBKEY` (guest path). Unset →
   the verb dies with "your project's hooks own auth — set PARA_PUBKEY in
   .paraspace/Parafile". Bundled templates set it. Verb keeps working
   everywhere it works today; the layout knowledge moves to its owner.
2. Cut the verb; the templates' provision hooks already print the key and
   pause. (Loses the standalone re-print convenience documented in
   git-auth.md.)

### A6. `cmd_claude` / `cmd_run`: move the session policy behind a key

bin/para:1371-1422. The PTY mechanics (`su --pty` SIGWINCH forwarding, the
TERM-fallback guard) are hard-won mechanism and stay. The *policy* — that the
session is `claude --name <ws>`, that tmux window 1 is claude and window 2 is
`sh` — is one user's workflow baked into the generic tool.
**Decision needed** (recommendation first):

1. **Recommended:** keep one verb, redefined: `para run <name>` runs the
   project's declared session — a new optional Parafile key (e.g.
   `PARA_RUN`, a guest command line run in `~/$PARA_CLONE_DIR` through the
   existing pty dance; unset → a login shell there, i.e. today's `para sh`
   landing spot). `cmd_claude` is cut; `templates/void-jchook` declares the
   tmux+claude session as its `PARA_RUN`, so the author's daily workflow is
   one template key, not tool code. Additive key; docs: commands.md,
   parafile.md, hooks.md (the key is forwarded like all keys).
2. Keep both verbs as-is and write the exception down in CLAUDE.md ("para
   ships opinionated session verbs"). Honest, but the exception will be cited
   as precedent by the next boundary breach.

Cuts total: ~250-350 lines removed or moved to consumers, and every currently
known violation of the generic-mechanism rule is gone.

## B. Harden (kill the bug classes where they live)

### B1. Registry → KEY=VALUE per workspace (the big one)

The flat positional file (`name ip routes domain project`, `-` sentinels) was
PR #9's dominant bug source (three field-shift guards, whitespace quarantine,
sentinel plumbing). New layout:

```
$PARA_STATE_DIR/workspaces.d/<name>   # ip=… routes=… domain=… project=…
```

- ~10 read/write sites move behind two helpers (`ws_get`, `ws_put`):
  `ip_of`:553, `project_of`:558, `registry_remove`:569, `cmd_up`:1101/1125,
  `cmd_reconcile`:1197-1261, `cmd_ls`:1283-1316, `cmd_web`:1440-1441,
  `first_running_ct`:1507, `gen_caddyfile`:825-868.
- Empty routes are just `routes=` — the `-` sentinels and every positional
  guard get deleted. (`reconcile` still translates `-` from old *container
  stamps* forever.)
- One-way migration on first write: convert the flat file, keep it as
  `workspaces.migrated`. Atomic per-workspace writes (tmp + mv).
- Tests: `a_registry_row`/`forget_registry_row` (test/lib/project.sh:141-153)
  write the new format; e2e tier asserts through para commands and is
  format-agnostic. Registry is host-internal state, not contract
  (docs/internals.md paragraph updates).

### B2. Source guard + a unit tier

Replace the bare `main "$@"` (bin/para:2244) with
`[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"` so the test harness can
source `bin/para` and call pure helpers directly. New `test/unit/` tier in
`test/run` (CI, no incus): `parse_routes`, `route_host`, `has_apex_route`,
`validate_domain`, `version_ge`, `image_src_sha`, and `gen_caddyfile` against
fixture registries — the fiddly string logic that today is only reachable
through the fenced CLI tier.

### B3. Restructure load-time execution

bin/para:54-283 runs at file load, before `log/warn/die` exist — the file
apologizes for the ordering twice (:60-61, :226-227). Wrap it as
`load_config()` called from `main()` after helper definitions. Kills the
one structural complaint about the bash that a function can fix, makes B2's
sourcing clean (sourcing stops executing config load as a side effect), and
positions `config-dump` (B4).

### B4. `para config-dump` + golden matrix tests

A hidden verb printing the resolved config: sorted `KEY=VALUE` for every
`PARA_*`, plus `ROUTES_DECLARED` and `PROJECT_ROOT`. CLI-tier golden tests
drive it across the precedence matrix (env set/empty/unset × user config
present/absent × Parafile variants, denylist warnings included) — the
precedence table in docs/parafile.md becomes executable. Standing support
tool ("paste your config-dump") and, if the port ever fires, the ready-made
cross-implementation differ.

### B5. The three known bug fixes

- `caddy_reload` (bin/para:902) stops swallowing errors: `caddy validate
  --config … --adapter caddyfile` on the generated file, surfaced reload
  failures. The failure mode "workspace reported ready while serving nothing,
  next cold start breaks every workspace" dies at the source.
- `route_host` (bin/para:385-389) lowercases the whole host, closing the
  case-blind gap in the cross-row duplicate-site guard (bin/para:854).
- `cmd_web`'s dead `${wdomain:-$PARA_DOMAIN}` fallback (bin/para:1451-1452)
  → plain `$wdomain`.

### B6. Lint upgrades

`.shellcheckrc`: `enable=check-set-e-suppressed,check-extra-masked-returns,add-default-case`
— the first one mechanically flags the `set -e` AND-OR shape at
sync_project (bin/para:941) that PR #9 noticed and left; fix the instances it
finds. Add `shfmt -d` to `bin/lint` and CI. This is the honest ceiling of
bash static analysis; B2 is what covers the rest.

## Sequencing (five PRs, each gated on lint + CLI tier in CI + e2e locally)

| PR | Contents | Notes |
|---|---|---|
| 1 | A1 + A2 (pure removals) + B5 (bug fixes) + B6 (lint) | small, immediate value |
| 2 | A3 (`PARA_IMAGE_PREPULL`) + A4 (generic config-sync) | template + docs updates ride along |
| 3 | A5 + A6 per the decisions above | the two decision points — confirm before this PR |
| 4 | B3 (`load_config()`) + B2 (source guard + unit tier) + B4 (config-dump + golden tests) | structure first, then the tests that exploit it |
| 5 | B1 (registry rewrite + migration) | last: it lands on a smaller, better-tested script |

Estimate: ~1-2 weeks total. Nothing here blocks on anything outside the repo.

## The port trigger (recorded so it isn't relitigated)

`plans/ts-port.md` (PR #10) stays shelved, not dead — its execution planning
is sound if the premise ever holds. Port when **any one** of:

1. a committed roadmap item bash structurally can't serve (REST-over-socket
   incus client, plugin API, JSON output surface);
2. external contributors exist and bash friction shows up in real issues/PRs;
3. ≥2 **shipped** (not review-caught) bash-semantics bugs after B1+B2 land.

If it fires, Phase -1 has already shrunk the surface the port must carry, and
B4's config-dump is the cross-implementation differ the port plan required.
