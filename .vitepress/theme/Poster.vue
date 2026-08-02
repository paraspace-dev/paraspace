<script setup>
/**
 * The landing page's first screen: two lenses overlapping like a Venn, the
 * wordmark sitting on the intersection, and a warm bed of light underneath.
 *
 * The diagram is the product. Two workspaces on one machine share the host,
 * the kernel and the project's credentials — that's the overlap — and share
 * nothing else, which is the two crescents. The lenses separate out of a single
 * circle on load for the same reason.
 *
 * Colors and blend mode come from custom.css, because the two themes are two
 * different physics: dark is light combining on a CRT, light is ink
 * overprinting on paper.
 */
import Wordmark from './Wordmark.vue'
</script>

<template>
  <div class="poster">
    <div class="field" aria-hidden="true">
      <div class="under" />
      <div class="lens a pv-lens" />
      <div class="lens b pv-lens" />
      <div class="grain" />
      <div class="vignette" />
    </div>

    <div class="inner">
      <h1 class="mark"><Wordmark /></h1>
      <p class="billing">Parallel dev workspaces on your machine</p>
      <p class="lede">
        Every task gets a full, isolated copy of your project — its own clone, its own stack, its
        own https URL. Run coding agents in parallel without collisions.
      </p>
      <div class="actions">
        <a class="para-btn brand" href="/docs/getting-started">Get started</a>
        <a class="para-btn alt" href="/docs/why">Why ParaSpace</a>
      </div>
      <p class="hosts">
        <span>fix-login.paraspace.dev</span>
        <span>add-billing.paraspace.dev</span>
        <span>try-bun.paraspace.dev</span>
      </p>
    </div>
  </div>
</template>

<style scoped>
/*
 * .VPContent already pads the page down by the navbar's height, so the poster
 * pulls back up through it: the sheet then starts at the top of the page and
 * bleeds behind the (transparent) bar, and .inner puts the height back before
 * the copy starts. Without this the hero sat a navbar too low and the paper
 * began below one.
 */
.poster {
  position: relative;
  margin-top: calc(var(--vp-nav-height) * -1);
}

/* The sheet everything above the fold is printed on. Full-bleed without 100vw:
   .VPHome is the page's full width already, and its own overflow-x rule keeps
   the lenses from opening a right gutter. It runs past the terminal and into
   the feature rows, then dissolves — a sheet that ended on a line would read as
   a band pasted onto the page. */
.field {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: var(--pv-field-h);
  overflow: hidden;
  pointer-events: none;
  background: var(--pv-paper);
  -webkit-mask-image: linear-gradient(180deg, #000 46%, transparent 92%);
  mask-image: linear-gradient(180deg, #000 46%, transparent 92%);
}

/* ---- The lenses -------------------------------------------------------- */

/*
 * Placement, blend and motion only — the halo and the glass come from .pv-lens
 * in custom.css, which the feature rows use too.
 */
.lens {
  position: absolute;
  top: var(--pv-eye);
  left: 50%;
  width: var(--pv-lens-d);
  height: var(--pv-lens-d);
  margin: calc(var(--pv-lens-d) / -2);
  mix-blend-mode: var(--pv-blend);
  transform: translateX(var(--dx));
  animation:
    split 1.5s cubic-bezier(0.16, 0.84, 0.28, 1) both,
    breathe var(--dur) ease-in-out 1.5s infinite alternate;
}

/*
 * The two lenses are one rule mirrored, so everything that differs between them
 * is a value rather than a second copy: --dx puts their centers 0.72 diameters
 * apart (enough overlap to read as one shared region, not so much that either
 * loses its own crescent), --dx-drift is where each wanders, and the two --dur
 * are coprime enough never to fall into step.
 */
.a {
  --c: var(--pv-lens-a);
  --dx: -36%;
  --dx-drift: -37.5%;
  --dur: 48s;
}

.b {
  --c: var(--pv-lens-b);
  --dx: 36%;
  --dx-drift: 37.5%;
  --dur: 61s;
}

/* One circle becomes two: para in one gesture. */
@keyframes split {
  from {
    transform: translateX(0) scale(0.84);
    opacity: 0;
  }
  to {
    transform: translateX(var(--dx)) scale(1);
    opacity: 1;
  }
}

@keyframes breathe {
  from { transform: translateX(var(--dx)) scale(1); }
  to { transform: translateX(var(--dx-drift)) scale(1.05); }
}

/* ---- Underglow, grain, vignette ---------------------------------------- */

/* The warm bed the Venn sits in — low, wide, and centered under the
   intersection, so the page has one light source and it's the overlap. */
.under {
  position: absolute;
  top: calc(var(--pv-eye) + var(--pv-lens-d) * 0.18);
  left: 50%;
  width: calc(var(--pv-lens-d) * 2.1);
  height: calc(var(--pv-lens-d) * 0.9);
  margin-left: calc(var(--pv-lens-d) * -1.05);
  border-radius: 50%;
  mix-blend-mode: var(--pv-blend);
  background: radial-gradient(
    closest-side,
    color-mix(in srgb, var(--pv-under) 34%, transparent),
    transparent 76%
  );
  animation: rise 1.9s ease-out both;
}

@keyframes rise {
  from { opacity: 0; }
  to { opacity: 1; }
}

/* Film grain, static. The animated kind is a repaint every frame and reads as
   a shader demo rather than an emulsion. */
.grain {
  position: absolute;
  inset: 0;
  opacity: var(--pv-grain);
  mix-blend-mode: var(--pv-grain-blend);
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='180' height='180'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.82' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='180' height='180' filter='url(%23n)'/%3E%3C/svg%3E");
}

/* Edge burn around the poster only — it reaches as far as the composition
   does, not as far as the sheet does. */
.vignette {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: var(--pv-burn-h);
  background: radial-gradient(130% 88% at 50% 26%, transparent 56%, var(--pv-edge) 100%);
  /* A radial can't come back to transparent at the bottom of its own box, so
     the burn is faded out the same way the sheet is. */
  -webkit-mask-image: linear-gradient(180deg, #000 58%, transparent 100%);
  mask-image: linear-gradient(180deg, #000 58%, transparent 100%);
}

/* ---- The copy ----------------------------------------------------------- */

.inner {
  position: relative;
  padding: calc(var(--vp-nav-height) + var(--pv-hero-top)) 24px 0;
  margin: 0 auto;
  max-width: 940px;
  text-align: center;
}

.mark {
  margin: 0 auto;
  max-width: 880px;
  /* The wordmark's own glow, and the only place a filter is allowed near the
     lenses — it would otherwise trap their blend inside a stacking context. */
  filter: drop-shadow(0 0 34px color-mix(in srgb, var(--pv-halo) 45%, transparent));
  animation: lift 1s ease-out 0.5s both;
}

/* Poster billing: the one line of tracked caps on the page, so it stays the
   subtitle and never becomes a texture. It sits on the lenses, where the tracking
   that makes it a poster line also makes it the hardest thing here to read — so
   it carries the weight and contrast the rest of the caption doesn't need. */
.billing {
  margin: 28px 0 0;
  font-size: 14px;
  font-weight: 600;
  letter-spacing: 0.26em;
  text-indent: 0.26em;
  text-transform: uppercase;
  color: var(--pv-sub);
  /* The same halo the wordmark carries, at a fraction of its reach — enough to
     lift the line off whichever lens it is crossing, not enough to notice as
     an effect. It does almost nothing on the print pass, which is correct: pale
     ink on pale paper has nothing to glow against. */
  text-shadow: 0 0 14px color-mix(in srgb, var(--pv-halo) 45%, transparent);
  animation: lift 1s ease-out 0.66s both;
}

.lede {
  margin: 22px auto 0;
  max-width: 54ch;
  font-size: 17px;
  line-height: 1.6;
  color: var(--pv-lede);
  animation: lift 1s ease-out 0.78s both;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 12px;
  margin-top: 32px;
  animation: lift 1s ease-out 0.9s both;
}

/* What you get, in the product's own artifacts: three tasks, three machines,
   three URLs. It's the credit block at the bottom of the one-sheet. */
.hosts {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 6px 22px;
  margin: 44px 0 0;
  font-family: var(--vp-font-family-mono);
  font-size: 12px;
  color: var(--pv-muted);
  animation: lift 1s ease-out 1.05s both;
}

.hosts span + span::before {
  content: '·';
  margin-right: 22px;
  opacity: 0.55;
}

@keyframes lift {
  from {
    opacity: 0;
    transform: translateY(14px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}

/* ---- Narrow ------------------------------------------------------------- */

@media (max-width: 767px) {
  .billing {
    font-size: 12px;
    letter-spacing: 0.2em;
    text-indent: 0.2em;
  }

  .lede {
    font-size: 15px;
  }

  /* The three hosts stack into a column rather than wrapping mid-list. */
  .hosts {
    flex-direction: column;
    gap: 4px;
  }

  .hosts span + span::before {
    content: none;
  }
}

@media (prefers-reduced-motion: reduce) {
  .lens,
  .under,
  .mark,
  .billing,
  .lede,
  .actions,
  .hosts {
    animation: none;
  }
}
</style>
