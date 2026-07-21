# Plan: `para init <git-url>` — scaffold from a remote template repo

## Goal

Let `para init` accept a git URL (SSH or HTTPS, any forge) in place of a bundled
template name, so people can host and share paraspace templates anywhere (GitHub,
GitLab, Codeberg, self-hosted). This is the ecosystem mechanism for a "zoo" of
configs: publishing a template = pushing a repo whose root looks like one of the
bundled `examples/` (a `.paraspace/` dir plus an optional demo tree).

```
para init git@codeberg.org:user/paraspace-void.git
para init https://gitlab.com/user/paraspace-void.git
para init https://github.com/user/paraspace-void.git#v1.2   # pin a tag/branch
```

## Why a git URL (not `npm create`)

`para` is already an always-installed CLI, so template resolution belongs *in*
the CLI, not in a parallel `npm create @scope/create-*` package per template
(which would fragment the zoo into one published package each and duplicate
`para init`'s copy logic). A git URL is forge-agnostic, needs no publishing
infrastructure, and reuses `cmd_init`'s existing copy loop verbatim. See the repo
README for the authoring convention.

## Decisions (settled)

- **v1 = whole repo is one template.** The repo root holds `.paraspace/` (+ an
  optional demo tree), mirroring `examples/void-docker-gh/`. Monorepo/`repo.git//subdir`
  ("zoo repo" holding many templates) is deliberately deferred.
- **`#ref` pinning is in v1.** A trailing `#<ref>` clones that branch or tag
  (`git clone --depth 1 --branch <ref>`). Full-SHA pinning is a known limitation
  (would need fetch + checkout) — documented, not built.
- **npm-convention resolution (`paraspace-template-*`) is not needed** given the
  git-URL path; may never be added.

## How it fits the existing code (`bin/para`)

`cmd_init` (currently ~line 998) already does everything after `$src` is known:
walks `$src`, skips existing files unless `--force`, skips the template's own
`README.md`, and personalizes the scaffolded `Parafile`'s `PARA_IMAGE`. A git
template's repo root is just another `$src` — `$src/.paraspace` in default mode,
`$src` under `--full` — so the only new work is **resolving a URL into a local
`$src`**, then falling through to the existing loop.

## Design

### 1. Detect git spec vs. bundled name

Bundled names are simple (`void-docker-gh`); git specs always carry characters a
bundled name never does. New helper (near `templates_dir`):

```sh
# True if the arg looks like a git remote (URL, scp-form, or *.git) rather than
# a bundled template name. Forge-agnostic — matches shape, not host.
is_git_spec() {
  case "$1" in
    *://*) return 0 ;;   # https://  ssh://  git://
    *.git) return 0 ;;   # ...repo.git
    *@*:*) return 0 ;;   # git@github.com:user/repo  (scp form)
    *)     return 1 ;;
  esac
}
```

### 2. Reorder `cmd_init` so a URL doesn't require bundled templates

`templates_dir()` is currently required up front and would `die` "no templates
found" even for a URL that needs no bundled examples. New order:

1. parse args (unchanged)
2. `--list` → require `templates_dir`, list bundled, return (bundled-only; unchanged)
3. **if `is_git_spec "$tmpl"` → clone into a temp dir, `src=$tmp`** (new)
4. else → `templates_dir` → `src=$tdir/${tmpl:-void-docker-gh}` (unchanged)
5. **common copy loop from `$src`** (existing code, verbatim)

### 3. The clone step (the ~10 new lines)

```sh
command -v git >/dev/null || die "git not found — needed to init from a URL."
local ref=""
case "$tmpl" in *\#*) ref="${tmpl##*#}"; tmpl="${tmpl%#*}" ;; esac
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git clone --depth 1 ${ref:+--branch "$ref"} -- "$tmpl" "$tmp" \
  || die "git clone failed: $tmpl"
rm -rf "$tmp/.git"   # so --full never walks .git/ into the project
src="$tmp"
[ -d "$src/.paraspace" ] \
  || die "not a paraspace template — repo has no .paraspace/ at its root."
```

Load-bearing details:
- **`rm -rf "$tmp/.git"`** is mandatory — otherwise `--full` (`root=$src`) copies
  the repo's `.git/` into the target.
- **`#ref` split** happens before clone; `--branch` accepts a branch *or* tag.
- **`.paraspace/` sanity check** gives a clear "not a paraspace template" error
  instead of the generic "nothing to scaffold at $root" from the copy loop.
- **`mktemp -d` + `EXIT` trap** cleans up on success and on `die`.

### 4. Cosmetics

- Usage header (currently ~line 69–73) and the inline `die` usage string
  (~line 1005): `para init [<template>|<git-url>] [--list] [--force] [--full]`.
- README: document the URL form, `#ref`, and the template layout ("repo root =
  `.paraspace/` + optional demo tree", i.e. publish a repo shaped like
  `examples/void-docker-gh/`).

## Security

`init` only copies files — no code runs at scaffold time. But the hooks it lays
down (`.paraspace/hooks/`) are shell scripts that run later during `para up`, so a
git template is trust-on-clone. Add one line to the docs: **review
`.paraspace/hooks/` before running `para up`.** No sandboxing — review is the gate,
consistent with the rest of para.

## Edge cases

- `--list` stays bundled-only (a URL + `--list` is meaningless).
- git absent → clear `die` before cloning.
- clone failure (bad URL, missing ref, no network) → `die` with the spec echoed.
- repo missing `.paraspace/` → explicit "not a paraspace template" error.
- `--full` on a clone → `.git/` already stripped, so only real template files copy.
- existing-file skipping and `--force` behave identically to the bundled path
  (same loop).

## Deferred (not in v1)

- Monorepo templates via `repo.git//subdir`.
- Full-commit-SHA pinning (needs fetch + checkout, not `--branch`).
- npm-convention resolution (`paraspace-template-*`).

## Test checklist (manual, on a dev box — para has no CI)

- `para init https://github.com/<you>/<template>.git` into an empty dir → lays
  down `.paraspace/`, personalizes `PARA_IMAGE` to the dir name.
- SSH form `git@github.com:<you>/<template>.git` → same result.
- `#ref` → clones that tag/branch.
- `--full` → demo tree present, no `.git/`.
- Re-run without `--force` → all files "skip (exists)"; with `--force` → overwrites.
- Non-paraspace repo → "not a paraspace template" error, temp dir cleaned up.
- Bundled `para init void-docker-gh` and `para init --list` → unchanged.
