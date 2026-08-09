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

- [Install ParaSpace](https://paraspace.dev/docs/install)
- [Why ParaSpace](https://paraspace.dev/docs/why) ·
  [Prior art](https://paraspace.dev/docs/prior-art)
- [Use a ParaSpace project](https://paraspace.dev/docs/using-a-project)
- [How it works](https://paraspace.dev/docs/how-it-works) ·
  [Running coding agents](https://paraspace.dev/docs/agents)
- [Project setup](https://paraspace.dev/docs/project-setup) ·
  [Cookbook](https://paraspace.dev/docs/cookbook)
- [Commands](https://paraspace.dev/docs/commands) · [The Parafile](https://paraspace.dev/docs/parafile) ·
  [Hooks](https://paraspace.dev/docs/hooks) · [Mods](https://paraspace.dev/docs/mods) · [The image
  contract](https://paraspace.dev/docs/image) · [Contract versioning](https://paraspace.dev/docs/versioning)
- [Troubleshooting](https://paraspace.dev/docs/troubleshooting)

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
