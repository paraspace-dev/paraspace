# docker

Targets the bundled `void` template. It installs Docker and Compose, enables
the runit service, adds the workspace user to the Docker group, and refuses an
Incus storage pool that leaves nested Docker on the slow `vfs` driver.

```sh
para mod add docker
para image build
```

During boot it runs `docker compose up -d --wait --wait-timeout 300` when the
clone contains a Compose file. The bundled demo listens on port 8080, which is
why the `void` Parafile starts with `PARA_ROUTES=8080`. Routes are ordinary
Caddy-to-workspace-port mappings and do not otherwise depend on Docker.

Set `PARA_PREPULL_IMAGES` in the project Parafile to a space-separated list of
images to bake into the workspace image. Nested Docker needs an Incus `dir`
pool, or another pool backed by ext4, so it can use overlayfs.

The image hook ends by opening the `docker:after` [hook
point](https://paraspace.dev/docs/hook-points), so a `hooks/docker:after` of
yours installs into an image where the daemon already answers. It also leaves
`/etc/paraspace/points/docker` in the image, which a `provision` hook can test
when it must refuse rather than proceed without Docker.
