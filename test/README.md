# para test suite

Real tests for `para`. Two tiers, one entrypoint:

```sh
test/run            # both tiers (e2e is skipped with a note if incus is absent)
test/run --cli      # CLI tier only — no incus, fast, runs in CI
test/run --e2e      # e2e tier only — needs a reachable incus daemon
test/run routing    # run only tests whose description contains "routing"
```

`npm test`, `npm run test:cli`, and `npm run test:e2e` map to the same.

## What each tier covers

**CLI tier** (`test/cli/`) — no incus. Argument handling, `para --help`, and
`para init` (pure filesystem). This is what runs on every push
([`.github/workflows/test.yml`](../.github/workflows/test.yml)), alongside the
ShellCheck gate ([`bin/lint`](../bin/lint)).

**e2e tier** (`test/e2e/`) — the real mechanism, exercised through actual `para`
commands against a live Incus workspace:

- `para up` → the project's hooks → the boot readiness contract → Caddy TLS →
  the container's bridge IP → the app, asserted with a real HTTPS request that
  returns the boot hook's sentinel (`test_workspace`, `test_idempotency`);
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
