# Hook points

A hook can run a point of its own — a name para has never heard of, filled by
your other hooks and, once you vendor one, by a mod. It is how a project makes
its own provisioning extensible without para learning anything about it.

Open one from anywhere in one of your hooks:

```sh
"$PARA_RUN_HOOK" clone:before
```

para invokes `provision`, `boot` and `image-build`; every other name in that
vocabulary is yours. Spell them `<subject>:before` / `<subject>:after`, so a
listing sorts by subject first and moment second.

Any name resolves to **every owner that has a hook by that name** — your
`hooks/<name>` first, then each `mods/*/hooks/<name>`, with no promise about
order among the latter. `mods/` is how a vendored component fills the same points
your own hooks do; until you have one, a name resolves to your file or to
nothing.

Three sharp edges:

- **Only exported variables reach a point.** It runs as a new process, so a
  plain `repo_url=…` set three lines above the call is unset inside the hooks it
  runs. Better than exporting it: pass nothing — a point is for filling in
  behavior, not for handing over arguments.
- **Don't re-source `~/.paraspace/env`.** It holds the *project's* values, so a
  hook that re-sources it mid-run rewinds `$PARA_HOOKS` to the project's — wrong
  file, no error.
- **The context does not survive `su -`/`sudo`**, which reset the environment. A
  build hook installing as another user needs
  `su - "$PARA_USER" -c 'PARA_SKEL=… …'`.

