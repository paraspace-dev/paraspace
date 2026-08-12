# Layers

Replace the scaffold-and-vendor model (templates copied by `para init`, mods
copied by `para mod add`) with an ordered list of **layers** declared in the
Parafile. A layer is any directory shaped like `hooks/ skel/ commands/`, plus
an optional `configure`. Templates, bundled mods, third-party mods, and the
project's own hooks all become layers, and both old words retire. The one
kind distinction left is positional, a layer under a `base/` directory is a
base.

```sh
PARA_LAYERS="
  node_modules/paraspace/layers/base/void
  node_modules/paraspace/layers/docker
  node_modules/paraspace/layers/git
  .paraspace/project
"
```

## Why

- **Pinning.** Vendored copies go stale and re-adding discards local edits.
  When the layers live under `node_modules/`, the project's lockfile answers
  "which layer code provisioned this workspace", and updating is `npm update`.
- **Order.** Hook and skel resolution between mods is currently an unordered
  glob, documented as "no promised order". The list makes order explicit and
  deterministic, which also settles skel conflicts (later layer wins per file).
- **Unification.** With explicit order, a template was only ever "the layer
  that goes first". One concept replaces two, and the project's own hooks stop
  being a special case. `.paraspace/` is the project's own layer root, and
  every project-owned layer lives there, whether scaffolded (`project`),
  stubbed fresh, or copied out of a package to customize.
- **Less churn.** Consumers stop committing mod shell they didn't write.

## The one resolution rule

Each `PARA_LAYERS` entry is a directory path resolved against the project
root, and it must exist. That is the entire mechanism. para never knows about
npm; `node_modules/paraspace/layers/base/void` is just a directory, so a git
submodule, a mise checkout, or a plain vendored copy under `.paraspace/` works
identically. No search paths, no bare-name lookup, no shadowing rules.

`add` owns the `PARA_LAYERS` block, and a canonical format is what makes the
rewrite tractable. Scaffolding writes one full relative path per line, both
delimiters on their own lines, no variables or interpolation, and the rewrite
function only touches a block matching that shape. The Parafile is sourced
bash, so a hand-edited block with a `$p` prefix var still runs fine; `add`
just refuses to rewrite it and says to edit `PARA_LAYERS` by hand. No bash
parser, one format, one clean refusal.

Resolution happens once, up front, before any operation touches anything. A
missing entry dies listing every missing path at once and naming the likely
fix (`npm install`, or the typo). `para doctor` prints the resolved chain in
order.

Shorthand exists only at init time, and its output is always the explicit
path, so the runtime never sees a bare name and nothing can shadow a layer
after the fact. Three sugar forms, no more, and the first two are one
expansion against different roots. A bundled name expands under this
package's `layers/` (`docker` means `node_modules/paraspace/layers/docker`,
and `base/void` follows the same rule), so an npm install can never change
what a bundled name means. A vendor name expands under the plugin's
`layers/`, so `acme/mod-a` means
`node_modules/paraspace-plugin-acme/layers/mod-a`. Anything else is a path,
tried literally and then under `node_modules/`. A name matching more than one
of these dies naming each candidate (a project's real `vendor/name` directory
can collide with a plugin's layer), and the fix the error names is writing
the full path. When paraspace is not under `node_modules/`, init says so and
the user writes full paths.

`paraspace-plugin-*` is the ecosystem convention, on the `eslint-plugin-*`
pattern. A **plugin** is an npm package shipping a `layers/` directory, the
same shape this package ships and `.paraspace/` mirrors; the vendor name is
the package name minus the prefix, and the rest of the package is the
author's to organize. The two words stay distinct in every doc: a plugin is
the distribution unit, a layer is what the engine composes. npm enforces none
of this, so `@paraspace/*` (register the scope) is where enforceably-official
separate packages would live, and bare `paraspace-*` stays clear by request
rather than mechanism. The plugin glob only ever sees packages the project
already installed, so the trust surface is npm's own, covered by the existing
review warning for third-party layers. Publishing against this makes the
layer shape and hook semantics contract surface in the full `PARA_CONTRACT`
sense; one docs page tells an author how to publish a plugin.

Discovery has exactly three kinds of root, `.paraspace/`, this package's
`layers/`, and each installed plugin's `layers/`. A layer root holds nothing
but layers, so the listing needs no exclusion rules, and resolution never
discovers at all, it only expands.

`para add --list` indexes the bundled catalog, installed plugins, and the
project's own `.paraspace/` in one flat sorted list, names exactly as `add`
accepts them, added layers checked rather than hidden, so the flagless list
answers both "what can I add" and "what do I have":

```
✔ .paraspace/project
  .paraspace/base/custom-base
  acme/base/debian13
  acme/mod-a
✔ acme/mod-b
✔ base/void
✔ docker
  dotfiles
✔ gh
```

## What changes in the engine

- `para init` and `para add` are one convergent verb with two names, a single
  handler and a single help entry (`init` reads right on day one, `add` reads
  right ever after). With no arguments in a fresh directory it scaffolds the
  default base; given names it writes a minimal Parafile if needed
  (`PARA_CONTRACT` plus the `PARA_LAYERS` block, shorthand resolved to
  explicit paths), stubs `.paraspace/project/`, inserts any new layers
  before the project layer, and reruns the configure chain. Bare `para init`
  after a hand edit of `PARA_LAYERS` converges too. `--list` shows the index
  above. `--new <name>` stubs `.paraspace/<name>` and appends it. The
  template copy machinery, the "the Parafile is yours, the template's isn't"
  carve-out, and the `-f` refresh semantics all delete.
- The `mod` command group deletes entirely. `para mod add` is subsumed by
  init, `para mod init` by `--new`, and customizing a package layer is copying
  its directory into `.paraspace/` and pointing the list entry at the copy.
- `para up` pushes each resolved layer into the guest in list order, project
  layer included, replacing the single `.paraspace/` push. The runner iterates
  the same order for hooks; it receives the resolved list rather than globbing.
  This changes the guest `~/.paraspace` layout. Contract territory, but we are
  in 0.x, so it lands as one change with no shims.
- Command verbs resolve across layers in list order. The current
  collision-refusal can stay or become last-wins; decide during implementation
  and document once.

## `configure` gets an explicit moment

Layers may propose Parafile values (the docker mod deriving `PARA_ROUTES` from
a compose model). That must never run during `para up`, or a routine command
mutates a committed file. `configure` runs in layer order at `para init`, and
because existing declarations win (including explicit empty values) the chain
is idempotent, which is what lets init rerun it wholesale on every invocation
rather than tracking which layers are "new". Writes go through the engine's
`set_parafile_var_if_not_set` helper, which already centralizes the
existing-declaration check; buffering its writes to a proposals file that
`add` merges after a clean exit (transactional apply, dry-run for free) is an
implementation option, not a commitment.

## Repo restructure

`templates/void/.paraspace/` moves to `layers/base/void/` and `mods/*` moves
to `layers/*`, so this package, every plugin, and `.paraspace/` all present
one layer-root shape. A base is by convention the first layer and the one
that establishes the image, bootstrap, and user, and exactly one docs page
says so.

The `base/` path component is also how a base is recognized. The runtime
composes every layer identically, but `para doctor` reads the resolved chain
and warns when it contains no base or more than one, since either usually
means a broken image contract.

## Costs

- A fresh clone gains a prerequisite. `.paraspace/` is no longer
  self-contained; layers under `node_modules/` need `npm install` first. The
  resolution error carries the reader to the fix.
- Hoisted monorepo `node_modules` means the path differs per project
  (`../../node_modules/...`). Ship without walk-up cleverness; add it only if
  real projects hit this enough to earn a second rule.
- Non-npm projects either carry a one-dependency `package.json` or vendor
  their layers by path. Both work by construction.

## Docs affected

`parafile.md` (new var, precedence unchanged), `mods.md` (becomes the layers
page), `image.md` and `hooks.md`/`hook-points.md` (guest layout, order is now
promised), `commands.md` (verb resolution), `how-it-works.md`, `versioning.md`
untouched (contract stays 1), plus `para init`/`--help` text and the README
funnel. A new page covers authoring and publishing a `paraspace-plugin-*`
plugin. Same-change rule applies; nothing names the old spelling.
