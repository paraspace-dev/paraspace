# para test suite

Real tests for `para`. Two tiers, one entrypoint:

```sh
test/run            # both tiers (e2e is skipped with a note if incus is absent)
test/run --cli      # CLI tier only — no incus, fast, runs in CI
test/run --e2e      # e2e tier only — needs a reachable incus daemon
test/run route      # run only tests whose description contains "route"
```

`npm test`, `npm run test:cli`, and `npm run test:e2e` map to the same.

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
the box ~15 MB and the whole path Docker-free.

`para image-build` is deliberately not used: it hardwires a Void base + a
docker-overlay check, so it can't build a tiny Docker-free Alpine image.
[`build-image.sh`](fixtures/hello/build-image.sh) does the equivalent with plain
incus — `apk add bash busybox-extras sudo`, an `app:1000` user — and publishes it
as the `alpine-minimal` alias. The e2e setup builds it once (cached across runs;
`--no-build` reuses it, `build-image.sh --force` rebuilds).

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
  e2e tier does not run there — use the CLI tier on macOS. (`build-image.sh` is
  host-agnostic; it builds a Linux container through whatever incus the CLI
  reaches.)

## Layout

```
test/
  run                 entrypoint (tier selection, sandbox, discovery)
  lib/harness.sh      test_* autodiscovery + pass/fail reporting
  lib/assert.sh       assert_*, eventually(), http_get()
  lib/sandbox.sh      XDG sandbox, free-IP-band picker, teardown
  cli/                CLI-tier tests (no incus)
  e2e/                e2e-tier tests (incus)
  fixtures/hello/     the Alpine HTTP fixture + its image builder
```

Test files are plain bash and are ShellCheck-linted by `bin/lint` like the rest
of the package (discovered by their `#!/usr/bin/env bash` shebang).
