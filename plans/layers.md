# Layers

Replace the scaffold-and-vendor model (templates copied by `para init`, mods
copied by `para mod add`) with an ordered list of **layers**. A layer is any
directory shaped like `hooks/ skel/ commands/`, plus an optional `configure`.
Templates, bundled mods, third-party mods, and the project's own hooks all
become layers, and both old words retire. The one kind distinction left is
positional, a layer under a `base/` directory is a base.

The project side of the contract becomes three names under `.paraspace/`:

```
.paraspace/
  env       # PARA_* vars, sourced bash (replaces the Parafile)
  stack     # the layer list, one path per line, in composition order
  layers/   # the project's own layers
    project/
```

A `stack` for a typical node project:

```
node_modules/paraspace/layers/base/void
node_modules/paraspace/layers/docker
node_modules/paraspace/layers/git
.paraspace/layers/project
```

## Why

- **Pinning.** Vendored copies go stale and re-adding discards local edits.
  When the layers live under `node_modules/`, the project's lockfile answers
  "which layer code provisioned this workspace", and updating is `npm update`.
- **Order.** Hook and skel resolution between mods is currently an unordered
  glob, documented as "no promised order". The stack makes order explicit and
  deterministic, which also settles skel conflicts (later layer wins per file).
- **Unification.** With explicit order, a template was only ever "the layer
  that goes first". One concept replaces two, and the project's own hooks stop
  being a special case. `.paraspace/layers/` is the project's own layer root,
  the same shape this package and every plugin ship, and every project-owned
  layer lives there, whether scaffolded (`project`), stubbed fresh, or copied
  out of a package to customize.
- **No syntax to break.** The stack is a flat file a script can edit with
  `echo` and `grep`. An earlier draft kept the list in the Parafile as a
  `PARA_LAYERS` block and needed a canonical format spec plus a refusal path
  for hand-edited bash; the stack file is that format with the bash deleted.
- **Less churn.** Consumers stop committing mod shell they didn't write.

## The two files

`env` replaces the Parafile, a rename with the format unchanged. It stays
sourced bash; the engine is bash, so sourcing is the mechanism, and the only
write the engine ever makes to it is the set-if-unset helper appending a
declaration. Every var is `PARA_*` and every var forwards into the guest,
`PARA_CONTRACT` included, so the name says exactly what the file is. A fresh
project's entire `env` is `PARA_CONTRACT=1`.

`stack` is one directory path per line, resolved against the project root,
composed top to bottom. Blank lines and `#` comments are ignored. `add` edits
it by inserting or removing whole lines, and is a no-op when the trimmed line
it would write is already present. The syntax is intentionally minimal, so
nothing needs a bash parser, but the engine normalizes entries and requires
each path to exist.

Two entries are the same layer when their trimmed lines are equal as strings.
Resolution dies on duplicate lines just as it does on missing paths. para
never canonicalizes paths, so two spellings that reach the same directory are
two entries and a user error; the resolved chain printed by `para doctor`
makes that visible.

The engine loads the normalized list, comments and blanks dropped, leading
and trailing whitespace trimmed, one path per line, order preserved, into
`PARA_STACK`, which forwards like any other `PARA_*` var. Hooks and guest
sessions inspect the composition at runtime by reading it. The runner takes
its order from the indexed layer directories rather than from `PARA_STACK`.
`PARA_STACK` is derived from the file on every invocation; a declaration in
`env` cannot override it.

## The one resolution rule

Each stack line is a directory path resolved against the project root, and it
must exist. Existence-checking is the entire runtime mechanism. para never
knows about npm; `node_modules/paraspace/layers/base/void` is just a
directory, so a git submodule, a mise checkout, or a plain copy under
`.paraspace/layers/` works identically. No search paths, no bare-name lookup,
no shadowing rules.

Resolution happens once, up front, before any operation touches anything. A
missing entry dies listing every missing path at once and naming the likely
fix (`npm install`, or the typo). `para doctor` prints the resolved chain in
order.

## Add-time shorthand, plugins, and discovery

Shorthand exists only at `add` time, and its output is always the explicit
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
the full path. When paraspace is not under `node_modules/`, add says so and
the user writes full paths.

`paraspace-plugin-*` is the ecosystem convention, on the `eslint-plugin-*`
pattern. A **plugin** is an npm package shipping a `layers/` directory, the
same shape this package and `.paraspace/` carry; the vendor name is the
package name minus the prefix, and the rest of the package is the author's to
organize. The two words stay distinct in every doc: a plugin is the
distribution unit, a layer is what the engine composes. npm enforces none of
this, so `@paraspace/*` (register the scope) is where enforceably-official
separate packages would live, and bare `paraspace-*` stays clear by request
rather than mechanism. Scoped `@paraspace/*` packages do not participate in
vendor-name shorthand; a full path reaches them. Publishing against this
makes the layer shape and hook semantics contract surface in the full
`PARA_CONTRACT` sense; one docs page tells an author how to publish a plugin.

Discovery has exactly three kinds of root, `.paraspace/layers/`, this
package's `layers/`, and each installed plugin's `layers/`. Installed plugins
are enumerated only by the glob `node_modules/paraspace-plugin-*/layers/`;
that is the entire discovery mechanism for installed plugins. Because the
glob sees only packages the project already installed, the trust surface is
npm's own and falls under the existing review warning for third-party layers.
All three are literally the same shape, a `layers/` directory holding nothing
but layers, so the listing needs no exclusion rules. Runtime resolution never
discovers; add-time discovery supports vendor-name expansion and the `--list`
catalog.

`para add --list` indexes the bundled catalog, installed plugins, and the
project's own `.paraspace/layers/` in one flat sorted list, names exactly as
`add` accepts them, added layers checked rather than hidden, so the flagless
list answers both "what can I add" and "what do I have":

```
✔ .paraspace/layers/project
  .paraspace/layers/base/custom-base
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
  default base; given names it writes a minimal `env` if needed
  (`PARA_CONTRACT=1`), stubs `.paraspace/layers/project/`, inserts any new
  stack lines before the project layer (shorthand resolved to explicit
  paths), and reruns the configure chain. Bare `para init` after a hand edit
  of the stack converges too. `--list` shows the index above. `--new <name>`
  stubs `.paraspace/layers/<name>` and inserts it before the project layer.
  The template copy machinery, the "the Parafile is yours, the template's
  isn't" carve-out, and the `-f` refresh semantics all delete.
- The `mod` command group deletes entirely. `para mod add` is subsumed by
  init, `para mod init` by `--new`, and customizing a package layer is copying
  its directory into `.paraspace/layers/` and pointing the stack line at the
  copy.
- `para up` pushes each resolved layer into
  `~/.paraspace/layers/NN-<name>/` in the guest, where `NN` is the layer's
  two-digit stack index. The project layer is included, replacing the single
  `.paraspace/` push. Lexical order matches stack order, so the runner keeps
  a plain glob for hooks. This changes the guest `~/.paraspace` layout.
  Contract territory, but we are in 0.x, so it lands as one change with no
  shims.
- Command verbs resolve across layers in stack order, with the later layer's
  verb winning. This is the same conflict rule used for skel files, and
  `commands.md` documents it once.

## `configure` gets an explicit moment

Layers may propose `env` values, such as the docker mod deriving `PARA_ROUTES`
from a compose model. That must never run during `para up`, or a routine
command mutates a committed file. `configure` runs in stack order at `para
init`, and because existing declarations win, including explicit empty values,
the chain is idempotent. Init can therefore rerun it wholesale on every
invocation rather than tracking which layers are "new".

The failure model for this chain remains an open decision. Direct writes
through the engine's set-if-unset helper, today
`set_parafile_var_if_not_set` and renamed with the file, reuse its centralized
existing-declaration check but leave earlier proposals applied to the
committed file if a later layer fails. Alternatively, the helper can buffer
writes to a proposals file that `add` merges only after the chain exits
cleanly. That makes the chain transactional and provides dry-run behavior for
free, at the cost of a second moving part.

## Repo restructure

`templates/void/.paraspace/` moves to `layers/base/void/` and `mods/*` moves
to `layers/*`, so this package, every plugin, and `.paraspace/layers/` all
present one layer-root shape. A base is by convention the first layer and the
one that establishes the image, bootstrap, and user, and exactly one docs
page says so.

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
- "Stack" already means the thing a workspace runs in README and `why.md`
  prose. Reword the running-services sense wherever the two would meet on a
  page; one word, one meaning per page.

## Docs affected

`parafile.md` becomes `env.md` (rename, format unchanged, precedence
unchanged, `PARA_STACK` documented as derived), `mods.md` deletes and
`layers.md` owns layers, the stack file, and resolution, `image.md` and
`hooks.md`/`hook-points.md` (guest layout, order is now promised),
`commands.md` (verb resolution), `how-it-works.md`, CLAUDE.md's contract
paragraph, `versioning.md` untouched (contract stays 1), plus `para
init`/`--help` text and the README funnel. A new page covers authoring and
publishing a `paraspace-plugin-*` plugin. Same-change rule applies; nothing
names the old spelling.
