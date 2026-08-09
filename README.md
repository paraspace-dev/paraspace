# ParaSpace

[![npm version](https://img.shields.io/npm/v/paraspace.svg)](https://www.npmjs.com/package/paraspace)
[![test](https://github.com/paraspace-dev/paraspace/actions/workflows/test.yml/badge.svg)](https://github.com/paraspace-dev/paraspace/actions/workflows/test.yml)
[![lint](https://github.com/paraspace-dev/paraspace/actions/workflows/lint.yml/badge.svg)](https://github.com/paraspace-dev/paraspace/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/npm/l/paraspace.svg)](./LICENSE)

`para` runs any number of full, isolated copies of your project side by side on
your own machine. Each workspace is an unprivileged [Incus] system container
with its own clone, its own stack, and its own `https://<name>.<domain>` URL, so
several coding agents (or you) can build, run and break things in parallel
without colliding.

## Documentation

📖 **[Documentation](https://paraspace.dev/docs/)**

- [Install ParaSpace](./docs/install.md)
- [Why ParaSpace](./docs/why.md) · [Prior art](./docs/prior-art.md)
- [Use a ParaSpace project](./docs/using-a-project.md)
- [How it works](./docs/how-it-works.md) ·
  [Running coding agents](./docs/agents.md)
- [Project setup](./docs/project-setup.md) · [Cookbook](./docs/cookbook.md)
- [Commands](./docs/commands.md) · [The Parafile](./docs/parafile.md) ·
  [Hooks](./docs/hooks.md) · [Mods](./docs/mods.md) ·
  [The image contract](./docs/image.md) ·
  [Contract versioning](./docs/versioning.md)
- [Troubleshooting](./docs/troubleshooting.md)

## Contributing

PRs are welcome! Please follow the [house style](./CLAUDE.md#house-style).

`bin/lint` and `test/run` run in CI. The e2e tier is not run in CI, so run it
locally before merging anything touching `up`, routes or lifecycle. See
[`test/README.md`](./test/README.md).

`npm run site` previews the VitePress docs; `npm run site:build` checks for
dead links.

## License

[MIT](./LICENSE)

[Incus]: https://linuxcontainers.org/incus/
