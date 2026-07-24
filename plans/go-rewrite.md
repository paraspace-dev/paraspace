# Plan: rewrite `para` in Go

## Goal

Rewrite the `para` CLI from its current ~1400-line bash script (`bin/para`) into
a Go binary, driven by three compounding wins that all point the same way:

1. **Typed Incus interactions.** Incus ships a first-party Go client
   (`github.com/lxc/incus/v6/client`). Every `incus exec | launch | file push`
   we currently shell out to and text-parse — including the quoting hell of
   pushing commands through a guest `su -c` re-parse — becomes a typed API call
   against an `InstanceServer`.
2. **Code-aware completions for free.** Define the command tree once; generate
   shell completions from it, including *dynamic* ones that call back into the
   binary at TAB time to list live workspaces.
3. **Native startup.** A static binary starts in ~1–3ms vs ~10ms (bun) / ~40ms
   (node).

The insight that makes this a single decision rather than three trade-offs:
**dynamic completions invoke the binary on every TAB**, so #2 and #3 are the same
requirement — "code-aware completions" only feel instant on a fast-starting
native binary; a node/bun process spawned per-keystroke never will. That settles
*native*. And #1 — the Incus Go client having no equal in Rust — settles *Go*.
Absent the Incus tie-in, Go-vs-Rust would be a real debate; the client library
ends it.

## Contract breakage is free right now — bank it

madi is the **only** consumer, and we own it (plus the three `examples/`). There is
no published `paraspace` user base yet. So this is the cheapest it will ever be to
fix anything wrong with the `.paraspace/` interface — **do the redesigns now, before
there are users to migrate.** `PARA_CONTRACT` resets cleanly to **1** for the Go era.

This does *not* abandon the engine/contract separation — that architecture is still
right. It means "preserve the contract verbatim" is a convenience, not a constraint:
keep the parts that are already good, and **deliberately break the parts that aren't**,
updating madi + the examples in the same pass.

## The architecture: engine vs contract (still the principle)

The split that makes the rewrite lower-risk than it looks:

- **Hooks stay bash, unchanged.** `hooks/` (+ `image-build.sh`) run *inside the
  guest*, orchestrating git/docker/xbps — shell is the right tool there, and Lua/Go
  would just be `os.execute` soup. Keeping them byte-for-byte identical is where the
  de-risking lives: the Go engine reimplements what *runs* the hooks, not the hooks
  themselves. The injected `PARA_*` env, hook names/semantics, and `~/.para` layout
  carry over. See the README contract section and
  `docs/plans/2026-07-14-para-project-seam.md`.
- **Config gets redesigned** — the one part of the contract we deliberately break,
  because it was bash *only because para was bash* (see "Config format" below).
- **Ship side-by-side until parity.** The Go binary and the bash script coexist; we
  retire `bin/para` only once the Go version reaches command parity (see phases). No
  flag day — madi and the examples move to the new config format in the same pass.

## Decisions (settled)

- **Language: Go.** Chosen *for* the Incus client library and the mockable
  `InstanceServer` interface (which finally gives us real unit tests instead of
  "the test suite is ShellCheck"). Static binary, trivial cross-compile, sub-5ms
  start.
- **CLI framework: Cobra.** The project's headline features are (a) live,
  code-aware completions and (b) painless distribution — and Cobra is the
  strongest at both. Its `__complete` dynamic-completion protocol is the mature,
  battle-tested one (kubectl, gh, docker); it generates bash/zsh/fish/powershell
  from one definition; and goreleaser has native hooks for its completions + man
  pages. Kong was considered and is terser (struct-tag definitions), but its
  dynamic completion (kongplete/posener-complete) is less polished and its
  ecosystem smaller — and terseness is not what this tool optimizes for.
  - *Cost & mitigation:* Cobra command trees are boilerplate-y. Keep one command
    per file (`internal/cmd/sh.go`, …), group related flags into structs, and
    factor shared setup (backend connect, workspace resolution) into helpers so
    each `cmd_*` stays thin.
- **Config format: TOML manifest.** Replaces the sourced-bash `Parafile`. Full
  reasoning + the bash escape hatch in "Config format" and "Escaping to bash" below.
- **Completions ship as `para completion {bash,zsh,fish,powershell}`**, sourced
  the same way as the fzf integration we already seed (`source <(para completion
  zsh)`). Dynamic completions for workspace-arg commands call the Incus API to
  list live workspaces, so they never drift from reality.
- **Distribution moves to goreleaser + Homebrew.** Cross-compile darwin/linux ×
  amd64/arm64, generate completions + man pages as release artifacts, and
  auto-update a Homebrew tap. `brew install paraspace` (or `go install`) replaces
  the npm `paraspace` + shell-install dance. The npm package gets a final
  deprecation release pointing at the new install path.
- **`para sh` (and friends) with no workspace arg → interactive picker.** One
  `resolveWorkspace(arg)` helper, used by every workspace-arg command (`sh`,
  `web`, `stop`, `rm`, `claude`):
  1. arg given → use it;
  2. exactly one workspace exists → use it silently;
  3. TTY + `fzf` on PATH → fzf-pick, with `--preview` rendering `para info <name>`
     (status, IP, routes, branch, URL — we already have all of it);
  4. else → print the list and exit non-zero.
  fzf is detected, never depended on. A built-in TUI picker (bubbletea/huh) is a
  possible later fallback, explicitly out of scope for v1.

## Config format: TOML manifest (decided)

The `Parafile` was sourced bash *only because the engine was bash* — sourcing was
free. In a Go engine that reason dies, and bash config actively costs: a
subprocess-eval hack, side effects, silent-typo failure (`PARA_ROTES=` → empty; the
current code even comments on this footgun), and nothing but bash can read it. Config
and hooks are different jobs — config *describes*, hooks *do* (cf. `Cargo.toml`/
`build.rs`, `package.json`/scripts) — so we split them cleanly.

- **`.paraspace/config.toml`** (name TBD — could retain the `Parafile` brand) — a
  declarative manifest, typed-unmarshalled into a Go struct with real "unknown key"
  errors and validation:

  ```toml
  project   = "madi"        # defaults to the directory name
  image     = "madi-dev"    # defaults to project
  # origin  = "…"           # omit → engine derives it from `git remote get-url origin`
  domain    = "madisonai.dev"
  clone_dir = "madi"
  routes    = ["9000", "api:3000", "pgweb:8081"]
  volume    = "para-home"
  ```

- **The engine owns the one real derivation.** Every actual Parafile computed exactly
  one value — `origin` from the git remote. Make that a documented default in Go and
  the entire turing-complete-config justification vanishes for the common case (you
  can't yet name a second computed value you need).
- **Env vars still win** over the file (unchanged), layered in Go.
- **Hooks stay bash.** Unaffected.

*Considered and set aside: embedded Lua* (gopher-lua, in-process). It would be
config-as-safe-code — turing-complete, sandboxed, typed table → Go struct, and nicely
coherent with the Lua nvim config in `skel/` — and it strictly beats sourced-bash for
a Go host. But it's a third language for ~8 values that don't currently compute. The
`{sh=…}` form + bash overlay below recover the escape-valve without it. Revisit if
config ever genuinely needs to *compute* (per-branch images, conditional routes).

## Escaping to bash (the future turing-complete hatch)

We don't lose config-as-code — we **demote it from mandatory to optional override**,
so the declarative base stays clean and full shell power is one file away. Two tiers,
in the spirit of mutt's `` set x = `cmd` `` / ``source `cmd` `` backtick escapes
(neither is needed for v1 — the `origin` default covers the only known computed value
— but the design is fixed now so the hatch exists when a second one appears):

1. **Per-value command substitution — a typed TOML form, not string magic.** A field
   that accepts either a literal or a `{ sh = "…" }` table runs the command and uses
   its trimmed stdout:

   ```toml
   origin = { sh = "git remote get-url origin" }
   image  = { sh = "echo madi-$(git branch --show-current)" }
   ```

   A custom `StringOrShell` type implements the TOML unmarshal (plain string →
   literal; `{sh=…}` → `bash -c`, trim stdout). Explicit, greppable, and *only the
   fields that opt in are ever executed* — no turning every string into an injection
   site.

2. **A full bash overlay — the real escape.** An optional `.paraspace/config.sh` that
   para sources *after* the TOML; any `PARA_*` it exports overrides the manifest. This
   is the old sourced-`Parafile`, kept — but demoted to an opt-in override layer, so
   you drop to turing-complete bash only when you genuinely must, and the 90% case
   never sees it. (mutt's ``source `cmd``, generalized.)

**Precedence, low → high:** engine defaults → `config.toml` (incl. `{sh=…}`) →
`config.sh` overlay → real environment variables.

## Also reconsider now (breakage is free)

Cheap to decide in this same pass, before there are users:

- **The `PARA_*` env surface** injected into hooks — audit/rename/trim while the
  contract is resetting to 1.
- **`image-build.sh` as just another hook** (`hooks/image-build`?) rather than a
  special top-level file.
- **The config file's name/location** — `.paraspace/config.toml` vs retaining the
  `Parafile` brand for recognition.

## Deferred / optional

- **Caddy admin API.** We could POST config to `:2019/config` instead of
  regenerating a Caddyfile + reload. Cleaner, but the file+reload path is simpler
  to reason about and debug — keep it for now, revisit later.
- **Built-in picker** (no-fzf TUI) — deferred (see above).
- **Full-SHA template pinning, zoo/subdir templates** — unrelated to this
  rewrite; tracked in `plans/init-from-git-url.md`.

## Architecture sketch

```
paraspace/                       (its own repo — see "Repository" below)
  cmd/para/main.go             thin entrypoint → internal/cli
  internal/
    cli/            root.go, completion wiring
    cmd/            one file per command (up, sh, ls, rm, image-build, …)
    incus/          InstanceServer wrapper: connect (local socket / colima
                    remote), launch, exec (interactive + batch), file push/pull,
                    state, list. The one place the client lib is touched.
    config/         load config.toml (+ defaults, {sh=} exec, optional config.sh
                    overlay, env override); user config; registry
    caddy/          Caddyfile gen + reload (admin API optional later)
    hook/           run a .paraspace/hooks/<name> inside a workspace with the
                    injected PARA_* env (unchanged contract)
    workspace/      resolveWorkspace() + the fzf picker
  .goreleaser.yaml
```

The `incus` package is the crux: it wraps the client behind an interface so the
rest of the tool is testable without a live daemon.

## The hard parts (call these out, port them last)

- **Interactive `sh`/`exec` over websockets.** `InstanceServer.ExecInstance` with
  an `InstanceExecArgs` control handler for stdin/stdout + window-resize is the
  fiddliest port (the `incus` CLI itself does exactly this, so there's a
  reference). Batch exec (used by hooks) is easy; the interactive TTY path is the
  work.
- **`image-build`.** Launches a pristine `images:voidlinux` container with
  `security.nesting=true`, streams the `image-build.sh` payload in, publishes the
  result. Multiple client calls + streaming; the second-highest-effort command.
- **macOS/colima remote connection.** On macOS the daemon runs in the colima VM,
  so the client connects to a *remote* Incus (URL + client cert — the same config
  the `incus` CLI already stores). One connection-setup edge case to get right in
  `internal/incus/connect`.

## Testing

- **Unit:** `InstanceServer` is an interface → mock it. Config loading (TOML
  unmarshal + defaults + `{sh=}` exec + overlay/env precedence), Caddyfile
  generation, `resolveWorkspace` logic, registry parsing — all unit-testable, which
  the bash version never was.
- **Integration:** run the real binary against a real Incus in CI (Linux runner
  with incus installed) for lifecycle smoke tests.
- **Example hooks stay ShellCheck-linted** — `bin/lint` (or its successor) keeps
  gating the `examples/` bash, since those don't change.

## Phased sequencing (parity milestones, not a big bang)

1. **Skeleton** — Go module, Cobra root, `internal/incus` connect (local +
   colima), TOML config loading (defaults + env precedence), `para completion`
   wired up. Prove the Incus connection with a trivial call.
2. **Read-only commands** — `ls`, `info`, `key`, `web`. Validates output parity
   and the client wiring at low risk. Land dynamic completion for workspace args
   here (it needs `ls`).
3. **Lifecycle** — `up`, `stop`, `rm`, `image-build`. The meat, including hook
   execution and the pristine-container image build.
4. **Interactive** — `sh`, `exec`, `claude` (the websocket/TTY work) + the fzf
   `resolveWorkspace` picker.
5. **Routing + cutover** — Caddy gen/reload, `config-sync`/`config-set`, remaining
   commands. At parity: goreleaser release, deprecate npm, retire `bin/para`.

## Repository

paraspace extracts to **its own repo before execution begins** — the immediate next
step after this plan lands, and ahead of Phase 1. It is already a self-contained,
MIT-licensed unit that knows nothing about madi (see `packages/paraspace/CLAUDE.md`);
extraction just makes that real. madi becomes a downstream consumer that pins a
released `para`.

## Open questions (decide before/at extraction)

- **Go module path** — `github.com/<owner>/paraspace`? Binary stays `para`.
- **Extraction mechanics** — `git filter-repo` to preserve `packages/paraspace/`
  history, vs a clean-start repo. (Leaning: preserve history.)
- **Does the bash `para` live on in the new repo** during the port (side-by-side,
  as the plan assumes) or do we branch/tag it and start Go on `main`? (Leaning:
  keep it on `main` until Phase 5 parity, so the tool is never broken.)
