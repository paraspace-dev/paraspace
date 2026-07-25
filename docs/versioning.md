# Contract versioning

The `para`↔project interface is versioned. It covers everything a project's
`.paraspace/` directory depends on:

- the [environment para injects](./hooks.md#the-environment-para-injects),
- the [hook names and semantics](./hooks.md),
- the `~/.paraspace` layout in the guest,
- the [`Parafile` keys](./parafile.md),
- the [project-command](./commands.md#project-commands) mechanism.

`para` implements a contract version, currently **1**. Declare the one your
`.paraspace/` was built against in your Parafile:

```sh
: "${PARA_CONTRACT:=1}"
```

It is an ordinary `Parafile` key, so it reaches your hooks like any other.

If the two don't match, para **refuses with a clear error** instead of silently
misbehaving — so a globally-updated `para` shared across projects can't quietly
break yours. Declaring nothing works, and `para doctor` suggests adding it.

The rules:

- A **breaking** change to the interface bumps `PARA_CONTRACT`.
- **Additive** changes (a new variable, a new optional key) don't.
- A project bumps its own `PARA_CONTRACT` when it migrates its `.paraspace/`.

## Migrating from the pre-release engine

Contract 1 is the first published contract, so there is nothing to migrate
*from* unless you used `para` before it was released — in which case the break
is total, with no compatibility shim. The fastest path is `para init --force`
into a scratch directory to diff against a current template. Otherwise:

| Before | Now |
|---|---|
| guest staging dir `~/.para/` | `~/.paraspace/` — same name as the host directory |
| `PARA_VERSION` (the key a project declared) | `PARA_CONTRACT` — the same name para uses for its own |
| `$PROJECT_ROOT` while the `Parafile` is sourced | `$PARA_PROJECT_DIR` — same value, and it reaches hooks too |
| `$PARA_ROUTES` comma-separated | space-separated: `for r in $PARA_ROUTES` |
| `parse_routes` / `route_ports` helpers | delete them; `${r##*:}` is the port |
| hooks run as `bash <path>` | run by path — the shebang decides, so keep it executable |
| `.env` seeded to `~/.para/host.env` | `~/.paraspace/host.env`, pushed only if the file exists |
| `PARA_HOST_ENV` unset/empty/set three-way | defaults to the project's `.env`; used if present |
| unset `PARA_ROUTES` was refused | unset means empty means no HTTP; `para doctor` mentions it |
| para validated routes and domains | `caddy validate` does, before every reload |
| per-project keys refused from the user config | allowed; `para doctor` advises instead |
| `PARA_PREPULL_IMAGES` injected into the image build | gone — set your own key and read it in `image-build.sh` |
| image stamped uid/user/contract/incremental | only `user.para.src_sha` |
| `para start` / `para stop` | `para caddy start\|stop\|status` |
| `para config-set KEY VALUE` | `para config edit` — the file is hand-edited now |
| `para run`, `claude`, `web`, `key` | project commands in `.paraspace/commands/` |
| `para reconcile`, `install`, `image-build`, `config-import`, `config-sync` | deleted — `up` now re-pushes `.paraspace/` every time |

New since then: `PARA_READY_HOST` (wait for guest DNS to resolve a host your
hooks need), `.paraspace/commands/` (your own `para` verbs), and `para doctor`.
