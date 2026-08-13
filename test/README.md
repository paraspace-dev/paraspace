# para test suite

Real tests for `para`. Two tiers, one entrypoint:

```sh
test/run            # both tiers (e2e is skipped with a note if incus is absent)
test/run --cli      # CLI tier only. No incus, fast, runs in CI
test/run --e2e      # e2e tier only. Needs a reachable incus daemon
test/run route      # only tests whose description matches the regex "route"
test/run '^image build'      # …so anchors and alternation work too
```

A description is the test's function name with `test_` dropped and underscores
as spaces, so it is only ever letters, digits and spaces, and a plain word behaves
as the substring match it looks like.

`npm test`, `npm run test:cli`, and `npm run test:e2e` map to the same.

> **Run the e2e tier locally before you merge.** Only the CLI tier runs in CI
> ([`.github/workflows/test.yml`](../.github/workflows/test.yml)), and the e2e tier
> needs a live incus daemon that GitHub-hosted runners don't have, so **nothing
> automated will catch an e2e regression for you.** Whenever you touch the
> `up`/route/lifecycle/volume mechanism, run `test/run --e2e` (or `test/run`) on
> Linux and confirm it's green before merging a PR or marking it ready for review.
> The e2e tier is **Linux-only** (native incus, or a Linux VM on macOS); on a Mac
> host the CLI tier is all you get. See [Known
> limitations](#known-limitations-of-the-e2e-sandbox).

## What each tier covers

**CLI tier** (`test/cli/`) needs no incus. Argument handling, `para --help`, and
`para init`/`para add` (pure filesystem). This is what runs on every push
([`.github/workflows/test.yml`](../.github/workflows/test.yml)), alongside the
ShellCheck gate ([`bin/lint`](../bin/lint)).

**e2e tier** (`test/e2e/`) is the real mechanism, exercised through actual `para`
commands against a live Incus workspace:

- the routing path (`para up` → the project's hooks → the boot readiness
  contract → Caddy TLS → the container's bridge IP → the app), asserted with a
  real HTTPS request that returns the boot hook's sentinel (`test_workspace`,
  `test_idempotency`). Note this is the *Docker-free* path: the fixture serves
  with busybox `httpd`, so it does **not** exercise para's nested-Docker/compose
  boot (the image contract's core), only the incus, Caddy, hook and volume
  contracts;
- `para sh -c` running as the workspace user (`$PARA_USER`/`$PARA_UID`, pinned by
  the sandbox), byte-clean, exit-status-propagating;
- the `down` → `up` (resume) → `rm` lifecycle (`test_lifecycle`);
- the per-project shared volume, shared across a project's workspaces
  (`test_shared`).

## The fixture

`test/fixtures/hello/` is the smallest real para project: an Alpine box that
serves a fixed sentinel over HTTP with busybox `httpd`. It is **not bundled
content** (it never ships in the npm package) and it does **not** use Docker,
which keeps the published image ~5.5 MB and the whole path Docker-free.

The image is built by **`para image build`**, from the fixture's own
[`.paraspace/layers/project/hooks/image-build`](fixtures/hello/.paraspace/layers/project/hooks/image-build)
(`apk add bash busybox-extras sudo`, plus a `$PARA_USER` user) on the
`PARA_IMAGE_BASE`/`PARA_IMAGE_BOOTSTRAP` its
[`.paraspace/env`](fixtures/hello/.paraspace/env) declares
(`images:alpine/edge` + `apk add --no-cache bash`), published as the
`alpine-minimal` alias. That's deliberate: the fixture is the non-Void,
Docker-free second consumer, so building it is also the only coverage
`para image build` has, and it proves the command carries no distro or Docker
assumptions of its own.

But the build is **cached**, and nothing invalidates that cache: an existing
`alpine-minimal` alias is reused as-is. So in steady state most runs skip
`para image build` entirely and prove nothing about it. **Rebuild explicitly with
`PARA_TEST_REBUILD=1 test/run --e2e` whenever you touch the fixture's
`hooks/image-build`, its env file's base/bootstrap, or `cmd_image_build` itself.**
Otherwise you're testing the image you built last time. `--no-build` skips even
the existence check.

The fixture also ships **one extra layer**, `.paraspace/layers/e2e-mod/`, listed
in [`.paraspace/stack`](fixtures/hello/.paraspace/stack) before the project layer,
rather than creating it at test time, because `PARA_PROJECT_DIR` points at the
tracked fixture, so a test that scaffolded one would dirty the working tree and
fail on a second run. Layers and their order are described in
[`docs/layers.md`](../docs/layers.md). It fills `provision`, `image-build`, and
`boot`, opens a `fixture:before` point the project layer fills too, and adds a
`commands/` verb. That gives the tier coverage of a provider-owned point, one
layer filling another's point, and a non-project-layer boot hook. Its
`image-build` half is baked into the cached image, so it is one more reason
`PARA_TEST_REBUILD=1` matters.

## Isolation

Every run is sandboxed so it never touches your real para state:

- throwaway `XDG_STATE_HOME`/`XDG_CONFIG_HOME`/… under a temp dir, with its own
  Caddyfile, pidfile and user config;
- a non-default Caddy port (`9443`), so its Caddy can't collide with a real one,
  and its own Caddy **admin** endpoint (`PARA_CADDY_ADMIN`, `:19443`) so a
  `caddy reload` from the run can never land on your real para Caddy;
- a throwaway `PARA_PROJECT_NAME`/volume, and fixed pre-tracked workspace names
  so teardown reclaims everything even if a test aborts;
- **the para identity and image keys inherited from your shell are unset**
  (`PARA_VOLUME`, `PARA_PROJECT_NAME`, `PARA_PROJECT_DIR`, `PARA_IMAGE_NAME`,
  `PARA_IMAGE_BASE`, `PARA_IMAGE_BOOTSTRAP`). Both halves matter: teardown
  deletes `PARA_VOLUME`, and an inherited `PARA_IMAGE_NAME` would make a
  `PARA_TEST_REBUILD=1` run publish the fixture payload over *your* image alias.

Teardown removes the run's workspaces (via `para rm`, backstopped by a direct
`incus delete` in case the run died before registering), its shared volume (swept
across every storage pool, guarded to the run-unique `para-home-paratest-*`
name), its Caddy, and the temp tree. The `alpine-minimal` image is left cached.
Ctrl-C is trapped so an interrupted run still tears down. Flags: `--keep` (leave
it all for inspection), `--failfast` (stop at the first failure).

## Known limitations of the e2e sandbox

The isolation is strong but not absolute, and a few things are outside what a
throwaway XDG tree can fence off:

- **The Caddyfile is machine-wide.** para reads the workspace list from incus
  rather than from a registry of its own, so the run's Caddyfile also carries
  *your* workspaces' hostnames. Harmless, since they are served on the run's own
  port and admin endpoint, but don't write a test that asserts the Caddyfile contains
  nothing else.
- **Storage pools are shared with your real para, deliberately.** The sandbox
  does *not* pin `PARA_POOL`, so a run exercises the pool you actually use.
  That is safe because isolation here is by *name*: containers are
  `para-<run-unique>`, the volume is `para-home-paratest-$$`, teardown is guarded
  to those, and para has no pool-level destructive operation. `PARA_POOL` is
  inherited from your environment, unlike the identity and image keys the sandbox
  unsets.
- **`para up` requires outbound DNS**, because the fixture declares
  `PARA_READY_HOST` and its image build installs from the network. The tier isn't
  offline-capable.
- **The e2e tier is Linux / native-incus only.** It reads the incus bridge
  (`incusbr0`) directly, which assumes a native Linux incus. para also supports
  macOS (incus in a colima VM), but the e2e tier does not run there, so use the CLI
  tier on macOS. (The image build itself is host-agnostic; it builds a Linux
  container through whatever incus the CLI reaches.)
- **Interactive `para sh` is not covered.** A pty path needs util-linux `su
  --pty`, and the Alpine fixture ships busybox. Exercise it by hand against a
  real project whose image ships util-linux, such as the bundled `base/void`
  layer's.

## Writing a test

A test is just a `test_*` bash function dropped into a file under `cli/` or
`e2e/`, with no registration and no boilerplate. The harness
([`lib/harness.sh`](lib/harness.sh)) autodiscovers every `test_*` function by
name and runs each in its own subshell; a test **passes when its function returns
zero** and **fails on any non-zero return**. The `assert_*` helpers in
[`lib/assert.sh`](lib/assert.sh) return non-zero on failure, so a bare
`assert_eq …` line is a hard checkpoint. Helper functions that aren't tests must
*not* be named `test_*` (prefix them `_`, like `_ls_state`) or they'll be run as
tests. A few rules keep the suite honest:

- **Pick the right tier.** If it needs no incus (argument handling, `--help`,
  `init`, or a refusal that fires *before* any backend call, such as name
  validation and the contract-version and cross-project-ownership checks) it
  belongs in `cli/` so
  CI actually runs it. Anything that boots a workspace goes in `e2e/`.
- **Write order-independent tests.** Execution order is **not** guaranteed: the
  harness runs functions in `declare -F` (alphabetical-by-name) order, not file or
  source order. Never assume one test ran before another. Read-only e2e tests
  share the primary workspace (`$PARA_WS`, brought up once by [`run`](run)) and
  must not disturb it; any test that mutates lifecycle state gets its own
  workspace (`$PARA_WS2`/`$PARA_WS3`, pre-tracked for teardown) and cleans up
  after itself.
- **Check every step's exit status.** The harness deliberately does *not* run
  tests under `set -e` (they routinely run commands expected to fail). So a
  non-final assert whose result you don't check is silently masked by the
  function's later success, so end such lines with `|| return 1`. Use `para_do` for
  mutating para calls (it stays quiet on success and surfaces para's output on
  failure) and `assert_fails` for "para must reject this".
- **Wait on async state with `eventually`, never a fixed `sleep`.** Boot, routing,
  and state transitions are asynchronous; `eventually <secs> <cmd…>` retries until
  the command succeeds or the timeout elapses. For the routing path specifically,
  use `assert_serves <ws>`, which already retries, where a bare `http_get <ws>`
  asks once and will flake if the request follows an `up` (which reloads Caddy).
  `http_get` is for when you need the body itself, after `assert_serves` has
  established the route is live; it curls through the run's Caddy hermetically
  (`--resolve`, para's internal CA).
- **Bind assertions to a specific workspace.** Assert on *this* workspace's `para
  ls` row (`awk '$1==n{print $3}'`), not "does RUNNING appear somewhere": in a
  shared registry another row can otherwise mask a bad state here.
- **Keep it ShellCheck-clean.** Test files are linted by `bin/lint` (discovered by
  their shebang) exactly like `bin/para`. Run `bin/lint` before you push.

## Layout

```
test/
  run                 entrypoint (tier selection, sandbox, discovery)
  lib/harness.sh      test_* autodiscovery + pass/fail reporting
  lib/assert.sh       assert_*, eventually(), http_get(), assert_serves()
  lib/sandbox.sh      XDG sandbox (dirs, Caddy port + admin endpoint), teardown
  lib/project.sh      throwaway projects, project commands, stub backends
  cli/                CLI-tier tests (no incus)
  e2e/                e2e-tier tests (incus)
  fixtures/hello/     the Alpine HTTP fixture + its image builder
```

Test files are plain bash and are ShellCheck-linted by `bin/lint` like the rest
of the package (discovered by their `#!/usr/bin/env bash` shebang).
