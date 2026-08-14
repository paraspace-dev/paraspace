# docker

Targets the bundled `base/void` layer. It installs Docker and Compose, enables
the runit service, adds the workspace user to the Docker group, and refuses an
Incus storage pool that leaves nested Docker on the slow `vfs` driver.

```sh
para add docker
para image build
```

When the layer is added, its host-side `configure` runs
[`docker compose config --format json`](https://docs.docker.com/reference/cli/docker/compose/config/)
from the project root. This uses Compose's normal project
discovery, including standard filenames, `.env`, and `COMPOSE_FILE`, and sees
the fully interpolated, merged model. Node.js and Docker Compose are optional:
if either is missing, Compose cannot resolve the project, or its JSON is
malformed, installation still succeeds with a warning and no env edit.

Configuration proposes two additive settings:

- `PARA_PREPULL_IMAGES` contains deduplicated explicit service `image` values.
  Build-only services do not contribute generated names.
- `PARA_ROUTES` contains fixed published TCP ports that Caddy can reach. One
  usable port becomes the apex. Several become DNS-safe service subdomains;
  services with several ports also use the port name or published port.

UDP, random or ranged published ports, loopback-only bindings, and explicitly
non-HTTP application protocols are skipped. If service/port normalization
would create an invalid or duplicate hostname, routes are left unchanged
instead of guessed. Existing declarations always win independently, even an
empty declaration such as `PARA_ROUTES=""`; edit .paraspace/env before or after
adding the layer for a manual override. Re-adding the layer reruns inspection but
does not duplicate declarations.

During boot it runs `docker compose up -d --wait --wait-timeout 300` when the
clone contains a Compose file. To run something once the stack is answering,
add `hooks/boot:after` to a layer. `para` runs this hook point after every
layer's `boot` hook on every boot, whether or not this layer found a Compose
file. See [hook points](https://paraspace.dev/docs/hook-points).

Routes are ordinary Caddy-to-workspace-port mappings and do not otherwise
depend on Docker.

Set `PARA_PREPULL_IMAGES` in the project's .paraspace/env to a space-separated list of
images to bake into the workspace image. Nested Docker needs an Incus `dir`
pool, or another pool backed by ext4, so it can use overlayfs.

The image hook ends by opening the `docker:after` [hook
point](https://paraspace.dev/docs/hook-points), so a `hooks/docker:after` of
yours installs into an image where the daemon already answers. It also leaves
`/etc/paraspace/points/docker` in the image, which a `provision` hook can test
when it must refuse rather than proceed without Docker.
