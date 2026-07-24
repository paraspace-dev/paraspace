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
  republished the other's. Additive in practice: every scaffolded Parafile
  declared the key explicitly, and `para init` no longer has to rewrite it.
- **Per-project keys are refused from the user config.** `PARA_PROJECT`,
  `PARA_IMAGE`, `PARA_BASE_IMAGE`, `PARA_IMAGE_BOOTSTRAP`, `PARA_VERSION`,
  `PARA_ORIGIN`, `PARA_CLONE_DIR` and `PARA_VOLUME` are now ignored in
  `~/.config/para/config` (with a warning) and rejected by `para config-set`: a
  box-wide value applied them to every project, and one global `PARA_PROJECT`
  collapsed every project's ownership and shared volume onto a single name. The
  environment is unaffected, and the config namespace stays open to every other
  `PARA_*`. Not a `Parafile`-key change — the keys and their meanings are
  identical — so no bump.
- **The image records the workspace user it baked** (`user.para.user`,
  `user.para.uid`), and `para up` refuses an image whose baked ids don't match
  `PARA_UID`/`PARA_GID`. Additive provenance, degrading to "not stamped" on older
  images; it turns a documented footgun (override without rebuild → chowns onto a
  uid with no passwd entry) into an up-front error.
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
