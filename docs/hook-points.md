# Hook points

Your `provision` hook clones the repo. Now you need an ssh config, a credential
helper, or an `insteadOf` rewrite to an internal mirror in place **before** it
does — and you'd rather not paste that into the middle of a hook you already
have, especially if it came from someone else.

Open a point where the ordering matters:

```sh
# .paraspace/hooks/provision — the line just before you clone
"$PARA_RUN_HOOK" clone:before
```

Anything named `clone:before` now runs at exactly that moment. para never learns
the name — you invent it and you place it.

## Filling one

Write the file. There is nothing to register:

```sh
cat > .paraspace/hooks/clone:before <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git config --global url."git@github.com:".insteadOf https://github.com/
EOF
```

More than one file can answer to a name — yours runs first, then any that came
with a vendored component. **They run in no particular order**, so write each so
it doesn't care what else filled the same point.

## Naming

Use `<subject>:before` and `<subject>:after` around the thing itself, so that
listing `hooks/` groups them by subject:

```
clone:after   clone:before   provision
```

`provision`, `boot` and `image-build` are para's names. Every other name in
`hooks/` is yours.

## Passing things is the part that bites

A point is for slotting in *behavior*, not for handing over data — the hooks it
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
  somewhere else — wrong files, no error.
