# Hook points

Your `provision` hook clones the repo. To put an SSH config, credential helper,
or `insteadOf` rewrite in place before it runs, add a `provision:before` hook to
a layer:

```sh
cat > .paraspace/layers/project/hooks/provision:before <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git config --global url."git@github.com:".insteadOf https://github.com/
EOF
```

There is nothing to register. When para runs a plain hook name such as
`provision`, it runs that name's `:before` point first, then every layer's
plain hook in stack order, with the top layer first, then its `:after` point.

This applies to every plain hook name, including para's `provision`, `boot`, and
`image-build` hooks, and names that hooks open with `"$PARA_RUN_HOOK"`. A
failing `provision:before` stops the run before any layer's `provision` hook
executes.

## Opening a finer point

Use an explicit point when the whole hook is too broad. For example, open
`clone:before` on the line immediately before a clone:

```sh
# .paraspace/layers/project/hooks/provision
"$PARA_RUN_HOOK" clone:before
```

Anything named `clone:before` runs at exactly that moment. para never learns the
name. You invent it and you place it.

Write the file in any layer that should fill the point:

```sh
cat > .paraspace/layers/project/hooks/clone:before <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git config --global url."git@github.com:".insteadOf https://github.com/
EOF
```

More than one layer can answer to a name. A hook name runs from every layer in
the stack that defines it, in stack order, with the top layer first. Write each
one so it doesn't care what else filled the point. That keeps it portable
between projects with different layer stacks. This is how every hook name
resolves, `provision` and `boot` included.

An unfilled point runs nothing and prints nothing. A plain hook name with no
implementation prints a note instead:

```text
==> hook: provision (none)
```

Points are optional. A plain name left unfilled is usually worth noticing.

## Naming

`:before` and `:after` are the suffixes para runs automatically around every
plain hook name. Use `<subject>:before` and `<subject>:after` around the thing
itself, so that listing a layer's `hooks/` directory groups them by subject:

```text
clone:after   clone:before   provision
```

Names ending in `:before` or `:after` are terminal. `provision:before` does not
also run `provision:before:before` and `provision:before:after`.

`provision`, `boot`, and `image-build` are para's names. Every other name in
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
  su - "$PARA_USER" -c "PARA_LAYER_DIR=$PARA_LAYER_DIR install-my-dotfiles"
  ```

- **Don't re-source `~/.paraspace/env`** to get para's variables "back". It
  does not carry the per-hook values, so doing that mid-run strips the running
  hook's own context: `$PARA_LAYER_DIR` vanishes and `$PARA_HOOK_CHAIN` resets
  the cycle guard. Wrong files, no error.

## Reading a failure

Once points nest, "which hook failed" stops being obvious, so para reports at
every level as hook files open points and fail under `set -e`:

```text
error: hook failed (exit 7): project/hooks/keys:setup
  chain: provision > clone:before > keys:setup
error: hook failed (exit 7): project/hooks/clone:before
  chain: provision > clone:before
error: hook failed (exit 7): project/hooks/provision
```

Read it top down. **The first line is where it actually broke**, and the
`chain:` beside it is the route para took to get there. Everything under it is
the unwind. Automatic points appear in the chain just like points a hook opens
explicitly.

When an automatic point such as `provision:before` fails, it reports one error
line with its chain. No enclosing `provision` error follows because no
`provision` hook file failed:

```text
error: hook failed (exit 7): project/hooks/provision:before
  chain: provision > provision:before
```

The exit status is the failing hook's own, carried up untouched, so `exit 7`
reaches you as 7. A hook that opens no point fails in a single line, with no
chain.

**Your hook needs `set -e` for any of that to fire.** `"$PARA_RUN_HOOK" …` exits
non-zero when something it ran failed, but a hook that doesn't stop on error
carries on past it and can still exit 0, and then `para up` reports a ready
workspace with the error sitting in your scrollback. Every hook stub `para init`
writes opens with `set -euo pipefail`. Start yours there too.

A point that ends up invoking itself is refused rather than left to recurse:

```text
error: hook cycle: provision > clone:before > provision
```

Calling the same point twice in a row is not a cycle, and runs twice. For
example, explicitly opening `boot:after` runs it during the `boot` hook, then
para runs its automatic `boot:after` point after every layer's `boot` has
finished.
