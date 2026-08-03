# Hook points

Your `provision` hook clones the repo. Now you need an ssh config, a credential
helper, or an `insteadOf` rewrite to an internal mirror in place **before** it
does, and you'd rather not paste that into the middle of a hook you already
have, especially if it came from someone else.

Open a point where the ordering matters:

```sh
# .paraspace/hooks/provision, the line just before you clone
"$PARA_RUN_HOOK" clone:before
```

Anything named `clone:before` now runs at exactly that moment. para never learns
the name. You invent it and you place it.

## Filling one

Write the file. There is nothing to register:

```sh
cat > .paraspace/hooks/clone:before <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git config --global url."git@github.com:".insteadOf https://github.com/
EOF
```

More than one file can answer to a name. `hooks/<name>` runs first, then that
same name under each [mod](./mods.md)'s `hooks/`. **Mods run in no particular
order**, so write each one so it doesn't care what else filled the point. This
is how every hook name resolves, `provision` and `boot` included.

## Naming

Use `<subject>:before` and `<subject>:after` around the thing itself, so that
listing `hooks/` groups them by subject:

```
clone:after   clone:before   provision
```

`provision`, `boot` and `image-build` are para's names. Every other name in
`hooks/` is yours.

## Passing things is the part that bites

A point is for slotting in *behavior*, not for handing over data. The hooks it
runs are separate processes, so:

- **Ordinary variables don't travel.** A `repo_url=…` three lines above the call
  is unset inside the hooks it runs. Export it if you must, but needing to is
  usually a sign the value belongs in a file both sides read.
- **`su -` and `sudo` wipe para's environment.** A hook that installs something
  as another user has to carry what it needs across:

  ```sh
  su - "$PARA_USER" -c "PARA_SKEL=$PARA_SKEL install-my-dotfiles"
  ```

- **Don't re-source `~/.paraspace/env`** to get para's variables "back". It
  holds your project's values, so doing that mid-run silently repoints
  `$PARA_HOOKS` at your `hooks/` even when the hook reading it came from
  somewhere else. Wrong files, no error.

## Reading a failure

Once points nest, "which hook failed" stops being obvious, so para reports at
every level as it unwinds:

```
error: hook failed (exit 7): hooks/keys:setup
  stack: provision > clone:before > keys:setup
error: hook failed (exit 7): hooks/clone:before
  stack: provision > clone:before
error: hook failed (exit 7): hooks/provision
```

Read it top down. **The first line is where it actually broke**, and the
`stack:` beside it is the route para took to get there. Everything under it is
the unwind. The exit status is the failing hook's own, carried up untouched, so
`exit 7` reaches you as 7. A hook that opens no point fails in a single line,
with no stack.

**Your hook needs `set -e` for any of that to fire.** `"$PARA_RUN_HOOK" …` exits
non-zero when something it ran failed, but a hook that doesn't stop on error
carries on past it and can still exit 0, and then `para up` reports a ready
workspace with the error sitting in your scrollback. Every bundled template
opens with `set -euo pipefail`. Start yours there too.

A point that ends up invoking itself is refused rather than left to recurse:

```
error: hook cycle: provision > clone:before > provision
```

Calling the same point twice in a row is not a cycle, and runs twice.
