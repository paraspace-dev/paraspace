# Plan: project-scoped workspace names

**Status: deferred.** The container-name half is small and would delete more
code than it adds. But it only *works* if the URL is scoped too, and every way
of doing that makes the default URL longer for everyone — including people with
one project, who get nothing back. Written down so the next person asking
"why are names machine-global?" gets the whole answer instead of re-deriving it.

## Goal

Let `ws1` exist in project A and project B at the same time. Today the second
`para up ws1` refuses (`bin/para:492`) because a container name is global to the
machine.

## Why it's coherent with the rest of the design

Every other per-project identifier is already scoped: the shared volume is
`para-home-<project>` (`bin/para:112`), the image alias is `<project>`
(`bin/para:111`), the image builder is `para-image-build-<project>`
(`bin/para:772`). The container name is the holdout, and the machine-global rule
in [`docs/internals.md`](../docs/internals.md) exists because of it.

## The container-name change (the easy half)

Keep `para-` as a fixed lead and make it `para-<project>-<name>`. Not
`<project>-<name>`: the fixed prefix is what lets `ws_list` (`bin/para:207`) see
*every* workspace on the box with `^para-` — `caddy_sites` is machine-wide by
design — and it's the fence `test/lib/sandbox.sh:121` guards teardown on. It
also sidesteps incus's "must not start with a digit" rule, so a directory named
`2024-app` still yields a legal name.

Eleven sites touch `CT_PREFIX`. Only two parse it back into a workspace name —
`caddy_sites` (`bin/para:366`) and `cmd_ls` (`bin/para:610`) — and both already
have `project` in hand from the CSV row, so `${name#"$CT_PREFIX$project-"}` is
unambiguous even though both halves can contain hyphens.

**It's a net deletion.** The project-mismatch guards in `up`, `down` and `rm`
(`bin/para:492`, `:550`, `:573`) and the `PARA_PROJECT=x para down <name>`
escape hatch all go away — you can't name another project's container, so there
is nothing to refuse.

**It adds one guard: length.** Incus caps instance names at 63 characters
(letters, digits, dashes; no leading digit). Today's budget is `para-` + a name
of at most 31 = 36. `PARA_PROJECT` is a slug of a directory basename and is
unbounded, so it would need a cap — which is the kind of check the house style
says to design away, and there isn't an obvious shape that does.

## Why it doesn't work alone: the URL is the other global namespace

`<name>.$PARA_DOMAIN` is global too, and it's the one people actually collide
on. `caddy_sites` builds one machine-wide Caddyfile from every para container,
so two projects each running `ws1` on the default `paraspace.dev` both emit
`https://ws1.paraspace.dev:8443`, `caddy validate` rejects the duplicate site
address, and `caddy_sync` dies.

That trades a good failure for a bad one:

- **Today:** `up` dies before anything is created, and names the owning project.
- **After:** `up` dies at the *end* — container launched, volume attached,
  `provision` and `boot` already run.
- **And it's a cross-project denial.** While both containers exist, every
  `caddy_sync` on the machine fails, so project A's next `para up` breaks too.
  (Nothing already serving goes down: `caddy_sync` validates `$CADDYFILE.new`
  before the `mv`, and reload keeps the old file. But nobody can converge.)

So the container rename is only half a feature. The URL has to be scoped in the
same change.

## Options for scoping the URL

1. **Per-project `PARA_DOMAIN`** — works today, zero engine change. Project A
   sets `a.paraspace.dev`, project B `b.paraspace.dev`. Rejected as the *only*
   answer: someone who doesn't set it gets the late failure above, which is
   strictly worse than what they have now.
2. **Move the ownership check from the name to the URL** — `up` pre-computes the
   hosts this workspace would claim and refuses if another project already
   publishes one, keeping the good up-front error. Rejected: it re-adds the
   cross-row duplicate guard that [`minimal-engine.md`](./minimal-engine.md) §6
   deliberately deleted in favor of `caddy validate`.
3. **Default `PARA_DOMAIN` to `$PARA_PROJECT.paraspace.dev`** — the best of the
   three, and the reason this plan is shelved rather than adopted. No new
   Parafile key and no new URL-shape concept; anyone who sets `PARA_DOMAIN`
   explicitly is unaffected (the templates only ship it commented out). It's a
   one-line move: the default at `bin/para:86` goes down into the identity block
   at `bin/para:107-113`, since it now reads `PARA_PROJECT`.

   DNS and TLS are both fine with the extra label — verified that
   `*.paraspace.dev` synthesizes at any depth (`ws1.projecta.paraspace.dev` and
   `a.b.c.paraspace.dev` both resolve to `127.0.0.1`), and Caddy's internal CA
   issues per-site certs, so a three-deep subdomain route
   (`api.ws1.myapp.paraspace.dev`) needs nothing special.

   **The cost, and the reason to stop here: `https://ws1.myapp.paraspace.dev:8443`
   is a lot to type and read**, and every single-project user pays it to solve a
   problem they don't have.

## What it would break

- Existing `para-<name>` containers go invisible to the new engine — `incus
  rename` or a one-shot migration. Since they break anyway, the domain change
  should ride along: one migration, not two.
- `templates/void-jchook/.paraspace/skel/claude/statusline.sh:11` and the zshrc
  prompts derive the workspace from the hostname with `${ws#para-}`, so they'd
  start showing `projecta-ws1`. Template policy, not engine contract — and they
  should arguably read `PARA_NAME` instead.
- Docs stating the current shape: [`internals.md`](../docs/internals.md)
  ("Workspace names are machine-global"),
  [`how-it-works.md`](../docs/how-it-works.md),
  [`urls.md`](../docs/urls.md).

**Additive, not a `PARA_CONTRACT` bump.** Container naming isn't in the
versioned seam (injected env, hook names and semantics, the `~/.paraspace`
layout, the `Parafile` keys), and `PARA_NAME` stays the short name either way.

## What would change the verdict

Someone hitting the collision for real — the same workspace vocabulary
(`ws1`, `fix`, `spike`) across several projects on one machine, often enough
that renaming is a tax. At that point option 3 is the design; the URL length is
the price, and it's worth paying for the person who has the problem.
