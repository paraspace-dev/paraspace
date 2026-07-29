# Bringing the stack up, and knowing when it's up

`boot` has one contract: **return zero only once every routed port is actually
listening.** para gates on the container agent, runs your hooks, and then trusts
your exit code — so a `boot` that backgrounds a dev server and returns
immediately produces a workspace that reports ready and serves 502s. Every
pattern below is really a pattern for satisfying that one sentence.

Contents: [readiness helpers](#readiness-helpers) ·
[docker compose](#1-docker-compose) · [system services](#2-system-services-plus-an-app-process)
· [bare processes](#3-bare-processes-no-init-involved) · [k3s](#4-k3s-inside-the-workspace)
· [hybrid](#5-hybrid-services-in-containers-app-bare) · [seed data](#seed-data-and-migrations)

## Readiness helpers

Add these to `.paraspace/hooks/helpers` once and every boot pattern gets shorter.
`wait_port` is enough for most stacks; use `wait_http` when a service accepts
connections before it can serve (Rails, Django's dev server, anything doing a
first compile).

```sh
# Wait until something is listening on a TCP port. $1 port, $2 seconds (60).
wait_port() {
  local i=0
  while [ "$i" -lt "${2:-60}" ]; do
    ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN && return 0
    sleep 1; i=$((i + 1))
  done
  die "nothing is listening on :$1 after ${2:-60}s — check the service log"
}

# Wait until a URL answers with any HTTP status. $1 url, $2 seconds (120).
wait_http() {
  local i=0
  while [ "$i" -lt "${2:-120}" ]; do
    curl -fsS -o /dev/null --max-time 3 "$1" && return 0
    sleep 1; i=$((i + 1))
  done
  die "$1 never answered after ${2:-120}s — check the service log"
}
```

`ss` comes from `iproute2` (Debian/Ubuntu), `iproute2` (Alpine), `iproute2`
(Void) — add it in `image-build` or the helper silently never succeeds.

A boot hook that starts several things should wait for each of them, and the
routed ones are non-negotiable:

```sh
for r in $PARA_ROUTES; do wait_port "${r##*:}" 120; done
```

That loop is worth writing verbatim in most projects: it reads the routes para
actually published, so it can't drift from the `Parafile`.

## 1. Docker Compose

The cleanest case, and the one the bundled `void-docker-gh` template ships:

```sh
cd "$HOME/$PARA_CLONE_DIR"
docker compose up -d --wait --wait-timeout 300
```

`--wait` blocks until healthchecked services are healthy and plain ones are
running, which satisfies the contract for free — provided your compose file
actually defines healthchecks for the services that matter. If it doesn't, add
`wait_port` calls after it rather than trusting "running".

What this costs in the image (`references/bases.md` has the per-distro spelling):
docker, the workspace user in the `docker` group, `security.nesting` (para sets
this), and a storage driver that resolves to **overlayfs**. On a btrfs- or
ZFS-backed Incus pool, nested Docker silently falls back to the `vfs` driver and
everything becomes punishingly slow — the templates' `image-build` refuses to
publish an image in that state, and yours should too.

Bind mounts and `network_mode: host` inside a workspace behave normally; ports
bind on the container's own IP, so nothing collides with the host or with other
workspaces. **Don't remap ports** to avoid collisions — that's the problem para
already solved.

## 2. System services plus an app process

The best fit for "our stack just runs locally" — PHP + MySQL, Rails + Postgres,
Django + Redis, a Python service with a queue. **An Incus system container boots
the distro's init**, so on Debian/Ubuntu bases `systemctl` genuinely works, and
the packaged services behave the way they do on a dev laptop. This is usually
simpler *and* faster than adding Docker to the picture.

In `image-build` (as root, no tty):

```sh
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql redis-server nginx
systemctl enable postgresql redis-server nginx
```

Enabling at build time means every workspace has them running before `boot`. In
`boot`, start only what's project-specific and then wait:

```sh
cd "$HOME/$PARA_CLONE_DIR"
sudo systemctl is-active --quiet postgresql || sudo systemctl start postgresql
wait_port 5432 30
npm ci && npm run build
sudo systemctl restart myapp        # a unit your image-build installed
wait_port 3000 120
```

`boot` runs as `$PARA_USER`, so anything touching systemd needs `sudo` — the
bundled templates grant that user passwordless sudo, which is a template's
choice and not something para provides. Check it's there before relying on it.

On Void the equivalent is runit (`ln -sf /etc/sv/postgresql /var/service/`), on
Alpine it's OpenRC (`rc-update add postgresql default`). Neither is worse; they
just aren't systemd.

## 3. Bare processes, no init involved

When there is no service manager and you don't want one, supervise it yourself.
The trap is that para runs `boot` to completion — anything still attached to the
hook's stdout dies with it:

```sh
cd "$HOME/$PARA_CLONE_DIR"
mkdir -p ~/log
setsid nohup npm run dev >~/log/dev.log 2>&1 < /dev/null &
wait_port 3000 120 || { tail -50 ~/log/dev.log >&2; exit 1; }
```

Three things make this survivable:

- **`setsid` + redirecting all three streams** detaches the process from the
  hook. Without it the process is killed when the hook exits, and the symptom is
  a URL that works for one second.
- **A log file you can point at.** `tail` it in the failure path — a boot hook
  that dies without showing why is the worst thing to hand a teammate.
- **Idempotence.** `boot` re-runs on every `up`, so either kill the old process
  first (`pkill -f 'npm run dev' || true`) or check the port before starting.

If more than two processes are involved, install a real supervisor
(`supervisord`, `s6`, or a couple of systemd units) in `image-build`. Writing a
process manager inside a boot hook is a sign the work belongs in the image.

## 4. k3s inside the workspace

Workable — the container already runs nested — but it is the slowest option to
converge and the fiddliest to keep healthy. Take it only when the project's dev
loop genuinely is Kubernetes.

- Install in `image-build`, don't start it there: `curl -sfL https://get.k3s.io |
  INSTALL_K3S_SKIP_START=true sh -`.
- On any pool that isn't overlayfs-capable, k3s needs `--snapshotter=native`,
  and it will be slow.
- Readiness is a rollout, not a port: `kubectl wait --for=condition=Ready
  node --all --timeout=180s`, then `kubectl rollout status deploy/<app>
  --timeout=300s` for each deployment, and only then `wait_port` on the
  NodePort or ingress you routed.
- Point `PARA_ROUTES` at the ingress controller's NodePort (or a
  `kubectl port-forward` you start in `boot` — but a NodePort is far more
  stable across reconverges).
- Budget several minutes for the first boot and pre-pull images into the base
  image the way `PARA_PREPULL_IMAGES` does for Docker.

## 5. Hybrid: services in containers, app bare

Very common, and para handles it without ceremony: run the databases in Docker
(or as system services) and the app as a plain process, exactly as people do on
their laptops.

```sh
cd "$HOME/$PARA_CLONE_DIR"
docker compose up -d --wait db redis          # only the infra services
mise install                                   # or nvm/pyenv, per the repo's pin
npm ci
setsid nohup npm run dev >~/log/dev.log 2>&1 </dev/null &
wait_http "http://127.0.0.1:3000" 180
```

The rule of thumb: put in a container whatever you'd otherwise have to install
system-wide at a pinned version; run bare whatever you want to edit and restart
constantly.

## Seed data and migrations

Migrations belong in `boot` (they're part of coming up, and they must be
idempotent — every framework's migrator already is). Seeding belongs wherever
it's cheapest:

- **small** — run the seed command in `boot` behind a sentinel.
- **large dump** — put the dump on `$PARA_SHARED` once, restore per workspace at
  boot. A multi-GB download per workspace is the thing to avoid; a multi-GB
  restore per workspace is usually fine and keeps each workspace's database its
  own.

para's own `cookbook.md` has the concrete recipe — read it rather than
re-deriving one.

## Routes

`PARA_ROUTES` is a list of `[sub:]port`; a bare port is the workspace apex.
Route only what a human would open — an internal port with no route is still
reachable from inside the workspace, and every route is a Caddy site para has to
keep valid. A workspace that serves nothing (a worker, a consumer) declares
`PARA_ROUTES=""` deliberately, and `para ls` then shows no URL.
