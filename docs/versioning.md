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
: "${PARA_CONTRACT:=1}"
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

## Migrating from the pre-release engine

Contract 1 is the first published contract, so there is nothing to migrate
*from*, unless you used `para` before it was released, in which case the break
is total, with no compatibility shim. The fastest path is `para init --force`
into a scratch directory to diff against a current template. Otherwise:

| Before | Now |
|---|---|
| guest staging dir `~/.para/` | `~/.paraspace/`, the same name as the host directory |
| `PARA_VERSION` (the key a project declared) | `PARA_CONTRACT`, the same name para uses for its own |
| `$PROJECT_ROOT` while the `Parafile` is sourced | `$PARA_PROJECT_DIR`, the same value, and it reaches hooks too |
| `$PARA_ROUTES` comma-separated | space-separated: `for r in $PARA_ROUTES` |
| `parse_routes` / `route_ports` helpers | delete them; `${r##*:}` is the port |
| hooks run as `bash <path>` | still `bash <path>`, with the exec bit and the shebang both ignored |
| `.env` seeded to `~/.para/host.env` | `~/.paraspace/host.env`, pushed only if the file exists |
| `PARA_HOST_ENV` unset/empty/set three-way | defaults to the project's `.env`; used if present |
| unset `PARA_ROUTES` was refused | unset means empty means no HTTP; `para doctor` mentions it |
| para validated routes and domains | `caddy validate` does, before every reload |
| per-project keys refused from the user config | allowed; `para doctor` advises instead |
| `PARA_PREPULL_IMAGES` injected into the image build | gone, so set your own key and read it in `hooks/image-build` |
| image stamped uid/user/contract/incremental | only `user.para.base`, and `para image status` reports when it was built and from what |
| `para start` / `para stop` | `para caddy start\|stop\|status` |
| `para config-set KEY VALUE` | `para config edit`, since the file is hand-edited now |
| `para web`, `key` | project commands in `.paraspace/commands/`, shipped by `void-docker-gh` |
| `para run`, `claude` | gone from the engine and from every template, so write your own, or see [Running coding agents](./agents.md#driving-one) |
| `para reconcile`, `install`, `image-build`, `config-import`, `config-sync` | deleted, since `up` now re-pushes `.paraspace/` every time |

New since then: `PARA_READY_HOST` (wait for guest DNS to resolve a host your
hooks need), `.paraspace/commands/` (your own `para` verbs), `para doctor`, and
`PARA_HOOKS`/`PARA_SKEL` (name the guest dirs instead of rebuilding them out of
`$HOME`). All additive, so contract 1 covers them.

## Changes inside contract 1

Contract 1 is not frozen until 1.0. Until then a break lands **in** it rather
than bumping it. para has one consumer, and publishing a new contract for a
migration nobody has made would be a version number describing nothing. Each one
is listed here, and each is a hand edit to a `.paraspace/` scaffolded before it.

- **`.paraspace/image-build.sh` → `.paraspace/hooks/image-build`.** One rule for
  every hook, `para` runs it by name out of `hooks/`. `git mv` it. The old name
  is not recognized, and nothing reads it. `para image build` says
  `no 'image-build' hook` and names the path it wants instead.
- The builder now gets your **whole `.paraspace/`** at `/opt/.paraspace`, so a
  build hook reads `$PARA_HOOKS` and `$PARA_SKEL` like any other hook, and gets
  no stdin. A build hook that piped its own input, or that ran a package manager
  without `-y`, has to stop.
- **A hook name resolves to more than one script.** para runs your
  `hooks/<name>`, then each `mods/*/hooks/<name>`. See [Hook
  points](./hook-points.md) and [Mods](./mods.md). Nothing changes for a project
  with no `mods/`.
- **A verb resolves to more than one `commands/`**, and `$PARA_MOD_DIR` is new.
  para runs your `commands/<verb>` if you have it, else the one mod that does.
  See [Mods](./mods.md#verbs-a-mod-brings). This is additive: with no `mods/`,
  or with no mod that ships `commands/`, nothing resolves differently.
- **`.paraspace/run-hook` is a name para owns**, alongside `env` and `host.env`.
  para writes its runner there on every push, so a file of yours at that path is
  overwritten.
- **The exec bit no longer matters in `hooks/`**, and para no longer sets it
  there. A hook runs as `bash <the file>` whatever its mode, so a
  `core.fileMode=false` checkout stops breaking a workspace, but a helper *you*
  run by path out of `hooks/` now needs `bash` in front of it, or its own exec
  bit committed. `commands/` is unchanged: a command honours its own shebang,
  so it still needs the bit, and `para init` and `para mod add` both set it.

At 1.0 this section closes and anything that breaks a `.paraspace/` bumps the
number instead.
