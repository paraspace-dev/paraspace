# Contract versioning

The `para`↔project interface is versioned. It covers everything a project's
`.paraspace/` directory depends on:

- the [environment para injects](./hooks.md#the-environment-para-injects),
- the [hook names and semantics](./hooks.md),
- the `~/.paraspace` layout in the guest,
- the [env file keys](./env.md),
- the [`.paraspace/stack` file format](./layers.md),
- the [project-command](./commands.md#project-commands) mechanism,
- bundled layer entry points and `$PARA_HELPERS` functions.

`para` implements a contract version, currently **1**. It is always a plain
incrementing integer, never a range, a semver string, or a `>=`. Comparing it
is `=`, and that will not change.

`para init` writes the pin into the scaffolded env file:

```sh
PARA_CONTRACT=1
```

It is an ordinary env key, so it reaches your hooks like any other. You touch
it once, when you migrate your own `.paraspace/` to a new contract.

If the two don't match, para **refuses with a clear error** instead of silently
misbehaving, so a globally-updated `para` shared across projects can't break
yours without saying so. Declaring nothing works, and `para doctor` suggests
adding it.

The rules:

- A **breaking** change to the interface bumps `PARA_CONTRACT` by one.
- **Additive** changes (a new variable, a new optional key) don't.
- A project bumps its own `PARA_CONTRACT` when it migrates its `.paraspace/`.
- There is no range syntax and no compatibility window: one integer, compared
  for equality.

## Before 1.0

`para` is 0.x and contract 1 is not frozen. A change that breaks a
`.paraspace/` lands **in** contract 1 rather than bumping it, and there is no
migration log of those breaking changes.

Bundled layer code lives under `node_modules/paraspace/` and is pinned by the
project's lockfile. A project that declares `paraspace` as a devDependency keeps
working until it chooses to update. To see what changed in the bundled layers
between two versions, run:

```sh
npm diff --diff=paraspace@0.2.0 --diff=paraspace@0.3.0
```

Pinning the global CLI still works too:

```sh
npm i -g paraspace@0.2.0
```

The global CLI version should match the version pinned by the project's
lockfile.

At 1.0 the contract freezes, and anything that breaks a `.paraspace/` bumps the
number instead.
