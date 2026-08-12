# Writing rules for ParaSpace prose

These rules govern all human-facing prose in this repository, including
`README.md`, `docs/`, code comments, and CLI output. They are hard rules, not
suggestions.

## Write documentation that completes a task

Documentation pages serve developers who know the shell and git but have never
read the `para` source. A reader should be able to complete the page's task
from the page. Use a published-spec register that is plain and confident,
never marketing or internal notes.

- Write for the reader's job, not the code's shape. If a paragraph's
  grammatical subject is `para`, try rewriting it with the reader as the
  subject and keep that version if it survives.
- Describe behavior and the rationale needed to use it correctly. Do not
  narrate design history or the decision process. Keep that material in
  plans, which are working notes and are never linked from documentation.
- Show the command on `README.md` and `docs/` pages. A page earns its keep
  with the line a reader can paste.
- One page owns each fact, including its default. That page states the
  default. Other pages link to it instead of repeating it.
- Explain costs and constraints on the page where they affect the reader.
- During 0.x, rename concepts in every page in the same change. Do not add
  migration notes, deprecation shims, or historical naming prose.
- Keep pages under about 150 lines. Every `##` heading names a task or a
  thing, never a mechanism.
- Errors and CLI messages point to a fix, `para doctor`, or the relevant doc.
  Show the diagnostic command when it helps the reader act:

  ```sh
  para doctor
  ```

## Describe layers without assigning policy to the engine

A workspace is provisioned by an ordered stack of layers. A layer is a
directory shaped like `hooks/`, `skel/`, and `commands/`, with an optional
`configure` script.

Consumers configure their workspace under `.paraspace/`:

- `env` contains sourced Bash and `PARA_*` variables.
- `stack` contains one layer path per line. Layers compose from top to bottom,
  and a later layer wins for each file.
- `layers/` contains layers owned by the project.

This package ships layers under `node_modules/paraspace/layers/`: `base/void`,
`docker`, `dotfiles`, `gh`, and `git`.

`para` is a thin generic mechanism. It does not prescribe how a workspace is
provisioned, and layer content is not engine behavior. When an example depends
on a shipped layer, name that layer. For example, `para claude` is a command
shipped by the `dotfiles` layer, not an engine verb.

## Match the surface

Documentation pages use the audience and register above. Code comments are
domain specification, no more than three lines, and explain why rather than
what. CLI messages use the same voice with more direct wording and name the
fix, `para doctor`, or the relevant doc.

## Keep the style direct

- M-dashes are banned.
- Avoid colons as emphasis pivots in running prose. Use them when they do
  structural work, such as introducing commands or steps, `Related: ...`
  labels, and CLI-message labels.
- Banned words: barrel, seam, load-bearing, quietly, delve.
- Cut filler. Do not use throat-clearing openers, emphasis crutches, business
  jargon, or meta-commentary.
- Do not use binary contrasts, negative listings, dramatic fragmentation,
  self-posed rhetorical questions, or anaphora and tricolon abuse.
- Prefer active constructions with named actors. Write "The team fixed it,"
  not "the complaint becomes a fix."
- Do not stack short punchy fragments for manufactured emphasis or write
  listicles disguised as prose.
- Keep Markdown plain GitHub-flavored so pages read correctly on GitHub, npm,
  and the VitePress site alike.
