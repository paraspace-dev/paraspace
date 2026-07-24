# Contract versioning

The `para`↔project interface — the
[injected environment](./hooks.md#the-environment-para-injects), the `~/.para`
layout, the [hook names and semantics](./hooks.md), and the
[`Parafile` keys](./parafile.md) — is versioned.

`para` provides a contract version (`PARA_CONTRACT`, currently **1**) and injects
it into hooks. If your Parafile declares `PARA_VERSION` and it doesn't match,
`para` **refuses with a clear error** instead of silently misbehaving — so
updating a global `para` shared across projects can't quietly break yours.

The rules:

- A **breaking** change to the interface bumps `PARA_CONTRACT`.
- **Additive** changes (a new variable, a new optional key) don't.
- A project sets `PARA_VERSION` to whatever `para` it builds against, and bumps
  it when it migrates its hooks.

## Decisions

Interface changes that were made *without* a bump, and why — so the constant
staying at 1 stays explicable:

- **`para image-build` became `para image build`, plus `status`/`rm`.** The base
  image is a distinct, shared, occasional artifact, so its verbs moved under a
  `para image <sub>` namespace, and `para image status`/`para image rm` were
  added. Additive, not breaking: `para image-build` stays as a deprecated alias,
  the injected env / hook names / `Parafile` keys are untouched, and the new
  provenance properties (`user.para.*`) degrade to "unknown" on older images. So
  `PARA_CONTRACT` stayed at 1.
- **`PARA_BASE_IMAGE` became required for `para image build`.** `image build`
  used to hardcode a Void base; it now refuses unless the
  [`Parafile`](./parafile.md#para_base_image) names a base image. Under the rules
  above that is breaking — an existing Parafile without the key stops building —
  but it landed pre-launch, at zero external consumers, so `PARA_CONTRACT` stayed
  at 1 rather than burning a version on a migration nobody had to perform.
- **`PARA_ROUTES` lost its `8080` default and gained an empty spelling.** An
  unset `PARA_ROUTES` used to fall back to port 8080 — baked-in project policy —
  and an explicitly empty one was refused, which made a workspace with no HTTP
  routes inexpressible. Now `PARA_ROUTES=()` is legal and publishes no site,
  while an *unset* key is refused (empty is a decision, unset is an oversight).
  Breaking for a Parafile that relied on the 8080 fallback; landed pre-launch, so
  `PARA_CONTRACT` stayed at 1. The registry's routes field records `-` for a
  route-less workspace, since it's positional and can't be empty.
- **`PARA_IMAGE` now defaults to `$PARA_PROJECT`** instead of the fixed
  `para-dev`. Incus image aliases are daemon-global, so the old default put two
  projects that both left the key unset on one image — and a build in either
  republished the other's. Breaking on the same terms as `PARA_BASE_IMAGE`
  above: a `Parafile` that omitted the key and relied on the `para-dev` alias
  now resolves to a different image (`para up` says the image isn't built; the
  old `para-dev` image is left on disk). Pre-launch, zero external consumers, so
  `PARA_CONTRACT` stayed at 1 rather than burning a version. `para init` no
  longer rewrites the key, and the bundled templates no longer declare it.
- **Per-project keys are refused from the user config.** `PARA_PROJECT`,
  `PARA_IMAGE`, `PARA_BASE_IMAGE`, `PARA_IMAGE_BOOTSTRAP`, `PARA_VERSION`,
  `PARA_ORIGIN`, `PARA_CLONE_DIR`, `PARA_VOLUME` and `PARA_ROUTES` are now
  ignored in `~/.config/para/config` (with a warning) and rejected by
  `para config-set`: a box-wide value applied them to every project, and one
  global `PARA_PROJECT` collapsed every project's ownership and shared volume
  onto a single name. The environment is unaffected, and the config namespace
  stays open to every other `PARA_*`.

  This **narrows the injected hook environment**, which the contract covers: a
  hook that read one of these from a machine-wide user config now sees nothing.
  Breaking under the rules, and excused the same way as the two entries above —
  pre-launch, no external consumers — not because the keys themselves are
  unchanged. `PARA_DOMAIN` is deliberately **not** on the list despite being
  project config: a personal wildcard domain is a reasonable box-wide setting,
  and workspace names are unique per machine, so a shared domain can't collide.
- **The image records the `PARA_UID`/`PARA_GID` it was built with**
  (`user.para.uid`, plus `user.para.user` for display), and `para up` refuses to
  launch when they no longer match the configured ids. The guarantee is
  deliberately narrow — it compares para's build-time config against para's
  current config, and is **not** a claim about what `image-build.sh` actually
  created, since para assumes nothing about the payload. It catches the case
  that bites (config moved, image didn't). Additive provenance, degrading to
  "not stamped" on older images.
- **`PARA_USER`/`PARA_UID`/`PARA_GID` became `Parafile` keys.** They were
  defaulted before the `Parafile` was sourced, so a `Parafile` declaring them
  with the usual `: "${PARA_UID:=…}"` idiom was silently ignored — the value was
  already set, so the assignment never fired. They're now defaulted alongside
  `PARA_IMAGE`, after the `Parafile`, which is where the image they describe is
  configured. The defaults, the injected env, and "a real env var wins" are all
  unchanged; what used to be ignored now takes effect. One narrow edge is
  technically breaking: a `Parafile` that *read* one of these at source time
  (e.g. `PARA_VOLUME="para-home-$PARA_USER"`) used to see the pre-applied default
  and now trips `set -u` with "unbound variable", since the default no longer
  exists yet when the `Parafile` runs. That just makes them behave like every
  other project key (`PARA_DOMAIN`, `PARA_IMAGE`, `PARA_CLONE_DIR` are all
  defaulted after the `Parafile` and fail the same way) — a `Parafile` should
  *declare* the keys it owns, not read para's defaults for them — and no bundled
  template or fixture does this, so `PARA_CONTRACT` stayed at 1.
