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
