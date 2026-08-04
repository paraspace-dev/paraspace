# Bringing the stack up, and knowing when it's up

`boot` has exactly one contract. **Return zero only once every routed port is
actually listening.** para gates on the container agent, runs your hooks, and
then trusts your exit code, so a `boot` that backgrounds a dev server and
returns immediately produces a workspace that reports ready and serves 502s.
Every pattern below exists to satisfy that one sentence.

Contents: [readiness helpers](#readiness-helpers) ·
[binding](#bind-on-every-interface-not-loopback) ·
[hostnames](#let-the-framework-accept-the-workspaces-hostname) ·
[docker compose](#1-docker-compose) · [system services](#2-system-services-plus-an-app-process)
· [bare processes](#3-bare-processes-no-init-involved) · [k3s](#4-k3s-inside-the-workspace)
· [hybrid](#5-hybrid-services-in-containers-and-the-app-bare) · [seed data](#seed-data-and-migrations)

## Readiness helpers

Add these to `.paraspace/hooks/helpers` once and every boot pattern gets shorter.
`wait_port` is enough for most stacks; use `wait_http` when a service accepts
connections before it can serve (Rails, Django's dev server, anything doing a
first compile).

```sh
# Wait until something is listening on a TCP port. $1 port, $2 seconds (60).
wait_port() {
  command -v ss >/dev/null || die "ss is missing, add iproute2 in image-build"
  local i=0
  while [ "$i" -lt "${2:-60}" ]; do
    ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}

# Wait until a URL answers at all, any status, including 404 and 500. $1 url,
# $2 seconds (120). No `curl -f`: it exits non-zero on >=400, so an app whose /
# is a 404 would look dead for the whole timeout.
wait_http() {
  local i=0
  while [ "$i" -lt "${2:-120}" ]; do
    curl -sS -o /dev/null --max-time 3 "$1" && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}
```

**They return rather than `die`, and that matters.** `die` exits the hook, so a
caller written as `wait_port 3000 || { tail log; }` would never reach the
`tail`. The process is already gone, and the log you most wanted is the one
nobody sees. Returning leaves the decision with the call site:

```sh
wait_port 3000 120 || die "nothing on :3000 after 120s"
wait_port 3000 120 || { tail -50 ~/log/dev.log >&2; die "the dev server never came up"; }
```

`ss` comes from `iproute2`, which `references/bases.md` names per base. Install
it there and the guard above blames the missing package instead of blaming your
app.

A boot hook that starts several things should wait for each of them, and the
routed ones are non-negotiable:

```sh
for r in $PARA_ROUTES; do
  wait_port "${r##*:}" 120 || die "nothing listening on the routed port ${r##*:}"
done
```

That loop is worth writing verbatim in most projects, because it reads the
routes para actually published and so can't drift from the `Parafile`.

## Bind on every interface, not loopback

Caddy runs on the **host** and proxies to the container's bridge IP, so a port
bound on `127.0.0.1` inside the workspace is one it can never reach. The
readiness contract doesn't catch it either, because `ss -ltn "sport = :3000"`
matches a loopback bind, so `wait_port` returns zero, `boot` succeeds, para
publishes the route, and the URL 502s. `wait_http "http://127.0.0.1:3000"` is a
liveness check for the same reason. It proves the app answers, not that Caddy
can reach it.

Most dev servers bind loopback by default. The spellings:

| Stack | Bind |
|---|---|
| Rails | `bin/rails server -b 0.0.0.0` (under `bin/dev`, in `Procfile.dev`) |
| Django | `manage.py runserver 0.0.0.0:8000` |
| Vite | `vite --host` (or `server.host: true`) |
| Next | `next dev -H 0.0.0.0` |
| compose | `ports: "3000:3000"`, never `"127.0.0.1:3000:3000"` |

Then assert the address and not just the port, which is one more line in the
routed-port loop above:

```sh
ss -ltn | grep -qE "(0\.0\.0\.0|\[::\]):${r##*:}\b" ||
  die "routed port ${r##*:} is on loopback only; rebind it on 0.0.0.0 for Caddy"
```

## Let the framework accept the workspace's hostname

`https://<name>.$PARA_DOMAIN` is a Host header the app has never seen, and
frameworks reject unknown hosts by default. Rails 6+ answers 403 "Blocked
hosts", Django 400 "Invalid HTTP_HOST header", Vite 403. The tell is that the
body is the *framework's* own error page, where a routing problem would give you
Caddy's 502 instead. Because it looks like the app, this is the failure most
often declared a success.

| Stack | Setting |
|---|---|
| Rails | `config.hosts << ".#{ENV['PARA_DOMAIN']}"` in `config/environments/development.rb` |
| Django | `ALLOWED_HOSTS = ['.paraspace.dev']`, where a leading dot means every subdomain |
| Vite | `server.allowedHosts: ['.paraspace.dev']` |
| Next | `allowedDevOrigins: ['*.paraspace.dev']` |
| Phoenix | `check_origin: false` in `config/dev.exs` |

`PARA_DOMAIN` is a `Parafile` variable, and hooks and `para sh` both have it in
the environment, so read it from there wherever the config language can. A
hardcoded `paraspace.dev` breaks for the first team that sets its own domain.
Commit the setting to the repo's dev config if the team is adopting para, and
write it from `boot` while you're only proving the adoption works.

## 1. Docker Compose

The cleanest case, and the one the bundled `void-docker-gh` template ships:

```sh
cd "$HOME/$PARA_CLONE_DIR"
docker compose up -d --wait --wait-timeout 300
```

`--wait` blocks until healthchecked services are healthy and plain ones are
running, which satisfies the contract for free, provided your compose file
actually defines healthchecks for the services that matter. If it doesn't, add
`wait_port` calls after it rather than trusting "running".

What this costs in the image is in `image.md` under the docker requirements, and
`references/bases.md` has the per-distro spelling, including the Debian/Ubuntu
equivalent of the Void template's docker block. One thing is worth repeating
because it happens silently. On a btrfs- or ZFS-backed pool, nested Docker falls
back to the `vfs` driver instead of overlayfs, so refuse to publish the image in
that state the way the templates' `image-build` does.

Bind mounts and `network_mode: host` inside a workspace behave normally; ports
bind on the container's own IP, so nothing collides with the host or with other
workspaces. **Don't remap ports** to avoid collisions, since that's the problem
para already solved.

## 2. System services plus an app process

The best fit for "our stack just runs locally", covering PHP with MySQL, Rails
with Postgres, Django with Redis, or a Python service and a queue. **An Incus
system container boots the distro's init**, so on Debian/Ubuntu bases
`systemctl` genuinely works, and the packaged services behave the way they do on
a dev laptop. This is usually simpler *and* faster than adding Docker to the
picture.

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
wait_port 5432 30 || die "postgres never came up"
npm ci && npm run build
sudo systemctl restart myapp        # a unit your image-build installed
wait_port 3000 120 || die "myapp is not listening, see journalctl -u myapp"
```

`boot` runs as `$PARA_USER`, so anything touching systemd needs `sudo`. The
bundled templates grant that user passwordless sudo, which is a template's
choice rather than something para provides. Check it's there before relying on
it.

On Void the equivalent is runit (`ln -sf /etc/sv/postgresql /var/service/`), on
Alpine it's OpenRC (`rc-update add postgresql default`). Neither is worse; they
just aren't systemd.

## 3. Bare processes, no init involved

When there is no service manager and you don't want one, supervise it yourself.
The trap is that para runs `boot` to completion, so anything still attached to
the hook's stdout dies with it:

```sh
cd "$HOME/$PARA_CLONE_DIR"
mkdir -p ~/log
setsid nohup npm run dev >~/log/dev.log 2>&1 < /dev/null &
wait_port 3000 120 || { tail -50 ~/log/dev.log >&2; die "the dev server never came up"; }
```

Three things make this survivable:

- **`setsid` plus redirecting all three streams** detaches the process from the
  hook. Leave it attached and you get one of two bad outcomes: it dies with the
  hook, or it holds the hook's stdout open and `para up` never returns.
- **A log file you can point at.** `tail` it in the failure path, because a boot
  hook that dies without showing why is the worst thing to hand a teammate.
- **Idempotence.** `boot` re-runs on every `up`, so either kill the old process
  first (`pkill -f 'npm run dev' || true`) or check the port before starting.

If more than two processes are involved, install a real supervisor
(`supervisord`, `s6`, or a couple of systemd units) in `image-build`. Writing a
process manager inside a boot hook is a sign the work belongs in the image.

## 4. k3s inside the workspace

It works, since the container already runs nested, but it is the slowest option
to converge and the fiddliest to keep healthy. Take it only when the project's
dev loop genuinely is Kubernetes.

- Install in `image-build`, don't start it there: `curl -sfL https://get.k3s.io |
  INSTALL_K3S_SKIP_START=true sh -`.
- On any pool that isn't overlayfs-capable, k3s needs `--snapshotter=native`,
  and it will be slow.
- Readiness is a rollout rather than a port. Run `kubectl wait
  --for=condition=Ready node --all --timeout=180s`, then `kubectl rollout status
  deploy/<app> --timeout=300s` for each deployment, and only then `wait_port` on
  the NodePort or ingress you routed.
- Point `PARA_ROUTES` at the ingress controller's NodePort. A `kubectl
  port-forward` started in `boot` also works, but a NodePort is far more stable
  across reconverges.
- Budget several minutes for the first boot and pre-pull images into the base
  image the way `PARA_PREPULL_IMAGES` does for Docker.

## 5. Hybrid, services in containers and the app bare

Very common, and para handles it without ceremony. Run the databases in Docker
(or as system services) and the app as a plain process, exactly as people do on
their laptops.

```sh
cd "$HOME/$PARA_CLONE_DIR"
docker compose up -d --wait db redis          # only the infra services
mise install                                   # or nvm/pyenv, per the repo's pin
npm ci
setsid nohup npm run dev >~/log/dev.log 2>&1 </dev/null &
wait_http "http://127.0.0.1:3000" 180 || die "the app never answered, see ~/log/dev.log"
```

As a rule of thumb, put in a container whatever you'd otherwise have to install
system-wide at a pinned version, and run bare whatever you want to edit and
restart constantly.

## Seed data and migrations

Migrations belong in `boot`, since they're part of coming up, and they must be
idempotent, which every framework's migrator already is. Seeding belongs
wherever it's cheapest:

- **A small seed** runs in `boot` behind a sentinel.
- **A large dump** goes on `$PARA_SHARED` once and is restored per workspace at
  boot. A multi-GB download per workspace is the thing to avoid; a multi-GB
  restore per workspace is usually fine and keeps each workspace's database its
  own.

para's own `cookbook.md` has the concrete recipe for fetching a dump from a URL,
so read that rather than re-deriving one. When the dump is instead a file on the
human's machine, any running workspace of the project is a door to the same
volume:

```sh
incus file push seed.dump "para-<ws>/para/shared/seed.dump"    # fastest for gigabytes
para sh <ws> -c 'cat > /para/shared/seed.dump' < seed.dump     # the same door as everything else
```

Both the dump and one restored copy per workspace live on one incus pool, so
check there is room for both before you start. `incus storage info "$PARA_POOL"`
tells you, with the pool name `para doctor` prints.

## Routes

Route only what a human would open. An unrouted port is still reachable from
inside the workspace, and every route is one more Caddy site to keep valid. The
syntax and what an empty list means are in `parafile.md`, in the docs the probe
located. Read it there rather than from a copy that can drift.
