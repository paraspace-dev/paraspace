<script setup>
/**
 * PARASPACE, drawn rather than typeset.
 *
 * One arch and one stem width build the whole alphabet. The arch is a
 * semicircle of radius 30.5 on a 78x100 body, stroked at 17: P is that arch
 * closed at the bar, A is the same arch with both legs run to the baseline, and
 * R is P with a leg. S and C are arcs of the same family, so every curve on the
 * page — including the two lenses behind this — comes off one circle.
 *
 * Stroked, not filled: butt caps land the terminals flush on the baseline and
 * the right edge, and round joins give the E its corners for free.
 */
const GLYPHS = {
  p: 'M8.5 100V39a30.5 30.5 0 0 1 61 0v29H8.5',
  a: 'M8.5 100V39a30.5 30.5 0 0 1 61 0v61M8.5 68h61',
  r: 'M8.5 100V39a30.5 30.5 0 0 1 61 0v29H8.5M36 68l33.5 26',
  s: 'M69.5 29.25a30.5 20.75 0 1 0-30.5 20.75 30.5 20.75 0 1 1-30.5 20.75',
  c: 'M56.5 16a30.5 41.5 0 1 0 0 68',
  e: 'M78 8.5H8.5V91.5H78M8.5 50H56',
}

/* Every body is 78 wide on a 100 advance, so the wordmark sets solid and the
   tracking is one number rather than a per-pair judgement. C is the exception:
   it's open on its right, so it carries air no other letter does and gives
   back 13 units. */
const LETTERS = []
let pen = 0
for (const ch of 'paraspace') {
  LETTERS.push({ d: GLYPHS[ch], x: pen })
  pen += ch === 'c' ? 87 : 100
}

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

      <g id="pv-word">
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
