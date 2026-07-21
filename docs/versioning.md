# Contract versioning

The para↔project interface — the
[injected environment](./hooks.md#the-environment-para-injects), the `~/.para`
layout, the [hook names and semantics](./hooks.md), and the
[`Parafile` keys](./parafile.md) — is versioned.

para provides a contract version (`PARA_CONTRACT`, currently **1**) and injects
it into hooks. If your Parafile declares `PARA_VERSION` and it doesn't match,
para **refuses with a clear error** instead of silently misbehaving — so
updating a global `para` shared across projects can't quietly break yours.

The rules:

- A **breaking** change to the interface bumps `PARA_CONTRACT`.
- **Additive** changes (a new variable, a new optional key) don't.
- A project sets `PARA_VERSION` to whatever para it builds against, and bumps
  it when it migrates its hooks.
