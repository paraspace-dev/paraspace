# Contract versioning

The `para`↔project interface is versioned. It covers everything a project's
`.paraspace/` directory depends on:

- the [environment para injects](./hooks.md#the-environment-para-injects),
- the [hook names and semantics](./hooks.md),
- the `~/.paraspace` layout in the guest,
- the [`Parafile` keys](./parafile.md),
- the [project-command](./commands.md#project-commands) mechanism.

`para` implements a contract version, currently **1**. It is always a plain
incrementing integer, never a range, a semver string, or a `>=`. Comparing it
is `=`, and that will not change.

Every bundled template already declares the one it was written against, so
`para init` pins it for you:

```sh
PARA_CONTRACT=1
```

It is an ordinary `Parafile` key, so it reaches your hooks like any other. You
touch it once, when you migrate your own `.paraspace/` to a new contract.

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
`.paraspace/` lands **in** contract 1 rather than bumping it, and neither this
page nor any other keeps a list of what moved. To see what a break was, scaffold
a current template into a scratch directory and diff it against yours:

```sh
para init --force
```

If you want a `.paraspace/` that keeps working without you, pin the version you
have:

```sh
npm i -g paraspace@0.2.0
```

At 1.0 the contract freezes, and anything that breaks a `.paraspace/` bumps the
number instead.
