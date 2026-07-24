# para test suite

Real tests for `para`. Two tiers, one entrypoint:

```sh
test/run            # both tiers (e2e is skipped with a note if incus is absent)
test/run --cli      # CLI tier only — no incus, fast, runs in CI
test/run --e2e      # e2e tier only — needs a reachable incus daemon
test/run route      # run only tests whose description contains "route"
```

`npm test`, `npm run test:cli`, and `npm run test:e2e` map to the same.

> **Run the e2e tier locally before you merge.** Only the CLI tier runs in CI
> ([`.github/workflows/test.yml`](../.github/workflows/test.yml)) — the e2e tier
> needs a live incus daemon that GitHub-hosted runners don't have, so **nothing
> automated will catch an e2e regression for you.** Whenever you touch the
> `up`/route/lifecycle/volume mechanism, run `test/run --e2e` (or `test/run`) on
> Linux and confirm it's green before merging a PR or marking it ready for review.
> The e2e tier is **Linux-only** (native incus, or a Linux VM on macOS); on a Mac
> host the CLI tier is all you get. See [Known
> limitations](#known-limitations-of-the-e2e-sandbox).

## What each tier covers

**CLI tier** (`test/cli/`) — no incus. Argument handling, `para --help`, and
`para init` (pure filesystem). This is what runs on every push
([`.github/workflows/test.yml`](../.github/workflows/test.yml)), alongside the
ShellCheck gate ([`bin/lint`](../bin/lint)).

**e2e tier** (`test/e2e/`) — the real mechanism, exercised through actual `para`
commands against a live Incus workspace:

- the routing path — `para up` → the project's hooks → the boot readiness
  contract → Caddy TLS → the container's bridge IP → the app — asserted with a
  real HTTPS request that returns the boot hook's sentinel (`test_workspace`,
  `test_idempotency`). Note this is the *Docker-free* path: the fixture serves
  with busybox `httpd`, so it does **not** exercise para's nested-Docker/compose
  boot (the image contract's core), only the incus/Caddy/hook/volume seams;
- `para sh -c` running as the uid-1000 user, byte-clean, exit-status-propagating;
- the `down` → `up` (resume) → `rm` lifecycle (`test_lifecycle`);
- the per-project shared volume, shared across a project's workspaces
  (`test_shared`).

## The fixture

`test/fixtures/hello/` is the smallest real para project: an Alpine box that
serves a fixed sentinel over HTTP with busybox `httpd`. It is **not** a template
(it never ships in the npm package) and it does **not** use Docker — that keeps
the published image ~5.5 MB and the whole path Docker-free.

The image is built by **`para image-build`**, from the fixture's own
[`.paraspace/image-build.sh`](fixtures/hello/.paraspace/image-build.sh)
(`apk add bash busybox-extras sudo`, an `app:1000` user) on the
`PARA_BASE_IMAGE`/`PARA_IMAGE_BOOTSTRAP` its Parafile declares
(`images:alpine/edge` + `apk add --no-cache bash`), published as the
`alpine-minimal` alias. That's deliberate: the fixture is the non-Void,
Docker-free second consumer, so building it is also the only coverage
`image-build` has — it's what proves the command carries no distro or Docker
assumptions of its own.

But the build is **cached**, and nothing invalidates that cache: an existing
`alpine-minimal` alias is reused as-is. So in steady state most runs skip
`image-build` entirely and prove nothing about it. **Rebuild explicitly with
`PARA_TEST_REBUILD=1 test/run --e2e` whenever you touch the fixture's
`image-build.sh`, its Parafile's base/bootstrap, or `cmd_image_build` itself** —
otherwise you're testing the image you built last time. `--no-build` skips even
the existence check.

## Isolation

Every run is sandboxed so it never touches your real para state:

- throwaway `XDG_STATE_HOME`/`XDG_CONFIG_HOME`/… under a temp dir — its own
  registry, Caddyfile, pidfile and machine config;
- a non-default Caddy port (`9443`), so its Caddy can't collide with a real one;
- an IP band carved from the addresses **actually free** on the incus bridge (the
  registry is sandboxed and empty, but bridge IPs are machine-global — this is
  what stops a run from allocating straight into a live workspace);
- a throwaway `PARA_PROJECT`/volume, and fixed pre-tracked workspace names so
  teardown reclaims everything even if a test aborts.

Teardown removes the run's workspaces, its shared volume, its Caddy, and the temp
tree. The `alpine-minimal` image is left cached. Flags: `--keep` (leave it all
for inspection), `--failfast` (stop at the first failure).

## Known limitations of the e2e sandbox

The isolation is strong but not absolute — a few things are outside what a
throwaway XDG tree can fence off:

- **Caddy's admin port (`:2019`) is not sandboxable.** para's generated Caddyfile
  sets no `admin` directive, so its Caddy binds the default admin endpoint — and
  Caddy binds it with `SO_REUSEPORT`, so a sandbox Caddy and a real para Caddy
  would *both* hold `:2019` and para's admin calls (`caddy reload`/`stop`) would
  be load-balanced across them — an `up` in the test run could reload, or a stop
  could kill, your real Caddy. So `sandbox_e2e` refuses to run while another Caddy
  owns `:2019` and tells you to `para stop` first. Teardown kills the run's own
  Caddy by its pidfile pid (never via the shared admin API). A proper fix (a
  configurable admin endpoint) belongs in para itself.
- **IP allocation is a setup-time snapshot.** The band is carved from what's free
  on the bridge when the run starts (including stopped workspaces' reservations).
  para's own `alloc_ip` never re-consults incus, so starting a *real* `para up` in
  another terminal mid-run can still collide. Don't do that while an e2e run is in
  flight.
- **`para up` requires outbound DNS.** para gates readiness on resolving
  `github.com` inside the guest, so the e2e tier needs working outbound DNS (the
  image build needs the network anyway — the tier isn't offline-capable).
- **The e2e tier is Linux / native-incus only.** It reads the incus bridge
  (`incusbr0`) directly and carves a machine-global IP band, which assumes a
  native Linux incus. para also supports macOS (incus in a colima VM), but the
  e2e tier does not run there — use the CLI tier on macOS. (The image build
  itself is host-agnostic; it builds a Linux container through whatever incus
  the CLI reaches.)

## Writing a test

A test is just a `test_*` bash function dropped into a file under `cli/` or
`e2e/` — no registration, no boilerplate. The harness
([`lib/harness.sh`](lib/harness.sh)) autodiscovers every `test_*` function by
name and runs each in its own subshell; a test **passes when its function returns
zero** and **fails on any non-zero return**. The `assert_*` helpers in
[`lib/assert.sh`](lib/assert.sh) return non-zero on failure, so a bare
`assert_eq …` line is a hard checkpoint. Helper functions that aren't tests must
*not* be named `test_*` (prefix them `_`, like `_ls_state`) or they'll be run as
tests. A few rules keep the suite honest:

- **Pick the right tier.** If it needs no incus — argument handling, `--help`,
  `init`, or a refusal that fires *before* any backend call (name validation,
  contract-version and cross-project-ownership checks) — it belongs in `cli/` so
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
  function's later success — end such lines with `|| return 1`. Use `para_do` for
  mutating para calls (it stays quiet on success and surfaces para's output on
  failure) and `assert_fails` for "para must reject this".
- **Wait on async state with `eventually`, never a fixed `sleep`.** Boot, routing,
  and state transitions are asynchronous; `eventually <secs> <cmd…>` retries until
  the command succeeds or the timeout elapses. For the routing path specifically,
  use `assert_serves <ws>` — it already retries, where a bare `http_get <ws>`
  asks once and will flake if the request follows an `up` (which reloads Caddy).
  `http_get` is for when you need the body itself, after `assert_serves` has
  established the route is live; it curls through the run's Caddy hermetically
  (`--resolve`, para's internal CA).
- **Bind assertions to a specific workspace.** Assert on *this* workspace's `para
  ls` row (`awk '$1==n{print $3}'`), not "does RUNNING appear somewhere" — in a
  shared registry another row can otherwise mask a bad state here.
- **Keep it ShellCheck-clean.** Test files are linted by `bin/lint` (discovered by
  their shebang) exactly like `bin/para`. Run `bin/lint` before you push.

## Layout

```
test/
  run                 entrypoint (tier selection, sandbox, discovery)
  lib/harness.sh      test_* autodiscovery + pass/fail reporting
  lib/assert.sh       assert_*, eventually(), http_get(), assert_serves()
  lib/sandbox.sh      XDG sandbox, free-IP-band picker, teardown
  cli/                CLI-tier tests (no incus)
  e2e/                e2e-tier tests (incus)
  fixtures/hello/     the Alpine HTTP fixture + its image builder
```

Test files are plain bash and are ShellCheck-linted by `bin/lint` like the rest
of the package (discovered by their `#!/usr/bin/env bash` shebang).
