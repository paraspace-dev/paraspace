# Contract versioning

The `para`↔project interface is versioned. It covers everything a project's
`.paraspace/` directory depends on:

- the [environment para injects](./hooks.md#the-environment-para-injects),
- the [hook names and semantics](./hooks.md),
- the `~/.paraspace` layout in the guest,
- the [`Parafile` keys](./parafile.md),
- the [project-command](./commands.md#project-commands) mechanism.

`para` provides a contract version (`PARA_CONTRACT`, currently **2**) and
injects it into hooks. Declare the one you build against in your Parafile:

```sh
: "${PARA_VERSION:=2}"
```

If they don't match, para **refuses with a clear error** instead of silently
misbehaving — so a globally-updated `para` shared across projects can't quietly
break yours. Declaring nothing works, and `para doctor` suggests adding it.

The rules:

- A **breaking** change to the interface bumps `PARA_CONTRACT`.
- **Additive** changes (a new variable, a new optional key) don't.
- A project bumps `PARA_VERSION` when it migrates its own `.paraspace/`.

## Migrating from contract 1

Contract 2 is a hard break with no compatibility shim. If you have a v1
project, the fastest path is `para init --force` into a scratch directory to
diff against a current template. Otherwise:

| Contract 1 | Contract 2 |
|---|---|
| guest staging dir `~/.para/` | `~/.paraspace/` — same name as the host directory |
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
| `para config-set KEY VALUE` | `para config init`, then edit `para config path` |
| `para run`, `claude`, `web`, `key`, `config-sync` | project commands in `.paraspace/commands/` |
| `para reconcile`, `para install`, `para image-build` | deleted |

New in contract 2 and worth adopting: `PARA_READY_HOST` (wait for guest DNS to
resolve a host your hooks need), `.paraspace/commands/` (your own `para` verbs),
and `para doctor`.

## Why the pin is worth setting

`para` is normally installed globally and shared across every project on the
machine. Without a pin, updating it silently changes the ground under a
project whose hooks were written against an older interface — and the failure
shows up as a broken clone or a stack that won't boot, not as a version error.
With a pin, you get the version error.
