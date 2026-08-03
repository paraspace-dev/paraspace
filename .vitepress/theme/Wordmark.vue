<script setup>
/**
 * PARASPACE, drawn rather than typeset.
 *
 * One arch and one stem width build the whole alphabet. The arch is a
 * semicircle of radius 30.5 on a 78x100 body, stroked at 17. P is that arch
 * closed at the bar, A is the same arch with both legs run to the baseline, R
 * is P with a leg, and C is the arch twice, over the top and under the bottom,
 * with 22 units of stem down the spine between them. S turns on the same 30.5
 * half-width, so every curve on the page, including the two lenses behind this,
 * is struck from the same radius.
 *
 * Stroked, not filled. Butt caps land the terminals flush on the baseline and
 * the right edge, and round joins give the E its corners for free.
 *
 * One place that isn't enough. R's leg is a diagonal, and a butt cap on a
 * diagonal is cut square to the stroke, which leaves a stub hanging off the
 * end rather than a foot standing on the line. The leg runs at 45 degrees
 * straight through the baseline and the wordmark is clipped there instead, so
 * the ground does the cutting.
 */
const GLYPHS = {
  p: 'M8.5 100V39a30.5 30.5 0 0 1 61 0v29H8.5',
  a: 'M8.5 100V39a30.5 30.5 0 0 1 61 0v61M8.5 68h61',
  r: 'M8.5 100V39a30.5 30.5 0 0 1 61 0v29H8.5M34 68l36 36',
  s: 'M69.5 29.25a30.5 20.75 0 1 0-30.5 20.75 30.5 20.75 0 1 1-30.5 20.75',
  c: 'M69.5 39a30.5 30.5 0 0 0-61 0v22a30.5 30.5 0 0 0 61 0',
  e: 'M78 8.5H8.5V91.5H78M8.5 50H56',
}

/* Every body is 78 wide on a 100 advance, so the wordmark sets solid and the
   tracking is one number rather than a per-pair judgement. */
const LETTERS = [...'paraspace'].map((ch, i) => ({ d: GLYPHS[ch], x: i * 100 }))

const WIDTH = LETTERS[LETTERS.length - 1].x + 78
</script>

<template>
  <svg
    class="wordmark"
    :viewBox="`-3 -3 ${WIDTH + 6} 106`"
    role="img"
    aria-label="ParaSpace"
    preserveAspectRatio="xMidYMid meet"
  >
    <defs>
      <!-- Lit from above by the lenses: bone at the cap line cooling toward the
           baseline. Stops come from CSS so the print half can reverse them. -->
      <linearGradient id="pv-ink" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="100">
        <stop class="s1" offset="0%" />
        <stop class="s2" offset="100%" />
      </linearGradient>

      <!-- The baseline, as a hard edge. Every other terminal already stops on
           it; this is what lets R's leg run through and be cut flush. -->
      <clipPath id="pv-baseline">
        <rect x="-40" y="-40" width="2000" height="140" />
      </clipPath>

      <g id="pv-word" clip-path="url(#pv-baseline)">
        <path v-for="(l, i) in LETTERS" :key="i" :d="l.d" :transform="`translate(${l.x} 0)`" />
      </g>
    </defs>

    <!-- Misregistration: on the CRT it's RGB fringing, on the print it's a
         plate that landed 2 units off. Same offset, and the theme picks the
         inks. Drawn behind the wordmark, so only the overhang shows. -->
    <use class="fringe f1" href="#pv-word" x="-2" />
    <use class="fringe f2" href="#pv-word" x="2" />
    <use class="face" href="#pv-word" />
  </svg>
</template>

<style scoped>
.wordmark {
  display: block;
  width: 100%;
  overflow: visible;
}

.face,
.fringe {
  fill: none;
  stroke-width: 17;
  stroke-linecap: butt;
  stroke-linejoin: round;
}

.face {
  stroke: url(#pv-ink);
}

.s1 {
  stop-color: var(--pv-ink-1);
}

.s2 {
  stop-color: var(--pv-ink-2);
}

.fringe {
  opacity: 0.5;
}

.f1 {
  stroke: var(--pv-fringe-1);
}

.f2 {
  stroke: var(--pv-fringe-2);
}
</style>
