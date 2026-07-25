<template>
  <div class="para-hero">
    <div class="space" aria-hidden="true">
      <span class="orbit"><span class="sat" /></span>
    </div>

    <!-- Parallel-universe ghosts of the terminal -->
    <div class="ghost g2" aria-hidden="true" />
    <div class="ghost g1" aria-hidden="true" />

    <div
      class="term"
      role="img"
      aria-label="Terminal session: para up launches isolated workspaces ws1 and ws2, each served at its own https URL"
    >
      <div class="term-bar">
        <span class="dot red" /><span class="dot yellow" /><span class="dot green" />
        <span class="term-title">para</span>
      </div>
      <div class="term-body">
        <div class="line cmd c1"><span class="typed">para up ws1</span></div>
        <div class="line out" style="--d: 1.5s"><span class="ok">✓</span> container launched</div>
        <div class="line out" style="--d: 2s"><span class="ok">✓</span> cloned + provisioned</div>
        <div class="line out" style="--d: 2.5s"><span class="arrow">→</span> <span class="url">https://ws1.paraspace.dev</span></div>
        <div class="line cmd c2"><span class="typed">para up ws2</span></div>
        <div class="line out" style="--d: 4.6s"><span class="ok">✓</span> container launched</div>
        <div class="line out" style="--d: 5.1s"><span class="arrow">→</span> <span class="url">https://ws2.paraspace.dev</span></div>
        <div class="line cmd c3" style="--d: 5.7s"><span class="cursor" /></div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Gruvbox dark-hard terminal, identical in light and dark page themes. */
.para-hero {
  --gb-bg: #1d2021;
  --gb-bg-soft: #282828;
  --gb-fg: #ebdbb2;
  --gb-gray: #928374;
  --gb-orange: #fe8019;
  --gb-yellow: #fabd2f;
  --gb-green: #b8bb26;
  --gb-aqua: #8ec07c;
  --gb-red: #fb4934;

  position: relative;
  width: 100%;
  max-width: 440px;
  margin: 0 auto;
  padding: 28px 0 0 28px;
}

/* The page nebula supplies the ambient color now; this is just the warm bloom
   that lifts the terminal off it. */
.para-hero::before {
  content: '';
  position: absolute;
  inset: -6%;
  background: radial-gradient(closest-side at 45% 55%, rgba(254, 128, 25, 0.2), transparent 72%);
  filter: blur(38px);
  pointer-events: none;
}

/* ---- Space dressing ---------------------------------------------------- */

.space {
  position: absolute;
  inset: -12%;
  pointer-events: none;
}

/* Mission-diagram orbit: dashed ellipse + a small satellite tracing it. The
   starfield belongs to the page nebula (Nebula.vue) — a second, denser field
   clustered on the terminal read as a smudge. */
.orbit {
  position: absolute;
  inset: 6% -4%;
  border: 1px dashed color-mix(in srgb, var(--gb-gray) 45%, transparent);
  border-radius: 50%;
  transform: rotate(-14deg);
}

.sat {
  position: absolute;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--gb-aqua);
  box-shadow: 0 0 8px 1px color-mix(in srgb, var(--gb-aqua) 60%, transparent);
  offset-path: ellipse(50% 50% at 50% 50%);
  animation: orbit 26s linear infinite;
}

/*
 * Bright-aqua glows nicely against the nebula, but on the daytime sky it lands
 * within ~1.2:1 of the aqua behind it and disappears — and so would the brand
 * orange, at almost the same luminance. The orbit crosses both mid-aqua sky and
 * white cloud, so no single bright tint covers the range: light mode uses a dark
 * marker, which is what an object silhouetted against a bright sky looks like
 * anyway, with a thin light rim so it keeps an edge on either backdrop. The glow
 * goes too, since a bloom on a bright sky reads as fuzz rather than light.
 */
html:not(.dark) .sat {
  background: #3c3836;
  box-shadow: 0 0 0 1.5px rgba(255, 255, 255, 0.6);
}

/* No offset-path support → keep the ring, skip the satellite. */
@supports not (offset-path: ellipse(50% 50% at 50% 50%)) {
  .sat { display: none; }
}

@keyframes orbit {
  from { offset-distance: 0%; }
  to { offset-distance: 100%; }
}

/* ---- Parallel-universe terminal stack ---------------------------------- */

.ghost,
.term {
  border-radius: 10px;
  background: var(--gb-bg);
  border: 1px solid color-mix(in srgb, var(--gb-gray) 35%, transparent);
}

.ghost {
  position: absolute;
  inset: 0 28px 28px 0;
}
.ghost.g1 { transform: translate(14px, -14px); opacity: 0.45; }
.ghost.g2 { transform: translate(28px, -28px); opacity: 0.2; }

/* Against the daytime sky the dark ghosts read as gray smudges rather than
   dimmer terminals, so they pull back. */
html:not(.dark) .ghost.g1 { opacity: 0.28; }
html:not(.dark) .ghost.g2 { opacity: 0.12; }

.term {
  position: relative;
  overflow: hidden;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.35);
}

.term-bar {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 10px 14px;
  background: var(--gb-bg-soft);
  border-bottom: 1px solid color-mix(in srgb, var(--gb-gray) 25%, transparent);
}

.dot { width: 11px; height: 11px; border-radius: 50%; opacity: 0.8; }
.dot.red { background: var(--gb-red); }
.dot.yellow { background: var(--gb-yellow); }
.dot.green { background: var(--gb-green); }

.term-title {
  margin-left: 8px;
  font-family: var(--vp-font-family-mono);
  font-size: 11px;
  color: var(--gb-gray);
}

.term-body {
  padding: 16px 18px 18px;
  font-family: var(--vp-font-family-mono);
  font-size: 13px;
  line-height: 1.9;
  color: var(--gb-fg);
  text-align: left;
}

.line {
  opacity: 0;
  white-space: nowrap;
  animation: appear 0.01s linear var(--d, 0s) forwards;
}

.cmd::before {
  content: '$ ';
  color: var(--gb-orange);
  font-weight: 700;
}

/* Typed commands: width reveal in character steps. */
.typed {
  display: inline-block;
  overflow: hidden;
  white-space: nowrap;
  vertical-align: bottom;
  width: 0;
}
.c1 { --d: 0.3s; }
.c1 .typed { animation: typing 1s steps(11, end) 0.3s forwards; }
.c2 { --d: 3.4s; }
.c2 .typed { animation: typing 1s steps(11, end) 3.4s forwards; }

@keyframes typing {
  from { width: 0; }
  to { width: 11ch; }
}

@keyframes appear {
  to { opacity: 1; }
}

.ok { color: var(--gb-green); }
.arrow { color: var(--gb-yellow); }
.url { color: var(--gb-aqua); text-decoration: underline; text-underline-offset: 3px; }

.cursor {
  display: inline-block;
  width: 8px;
  height: 1.1em;
  vertical-align: text-bottom;
  background: var(--gb-fg);
  animation: blink 1.1s step-end infinite;
}

@keyframes blink {
  50% { opacity: 0; }
}

/* ---- Motion preferences ------------------------------------------------ */

@media (prefers-reduced-motion: reduce) {
  .line { animation: none; opacity: 1; }
  .typed { animation: none; width: 11ch; }
  .sat { animation: none; }
  .cursor { animation: none; }
}
</style>
