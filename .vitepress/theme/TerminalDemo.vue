<template>
  <div class="para-hero">
    <!-- ws2 and ws3, one color plate each -->
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
/* Gruvbox dark-hard terminal under the CRT poster; gruvbox light under the
   print one — see the light override below the palette. */
.para-hero {
  --gb-bg: #1d2021;
  --gb-bg-soft: #282828;
  --gb-fg: #ebdbb2;
  --gb-gray: #928374;
  --gb-yellow: #fabd2f;
  --gb-green: #b8bb26;
  --gb-aqua: #8ec07c;
  --gb-red: #fb4934;
  /* The stack behind the terminal: one pane filled, one drawn. */
  --gb-ghost-fill: color-mix(in srgb, var(--gb-bg) 52%, transparent);
  --gb-ghost-line: color-mix(in srgb, var(--gb-gray) 48%, transparent);
  --gb-ghost-line-far: color-mix(in srgb, var(--gb-gray) 34%, transparent);

  position: relative;
  width: 100%;
  max-width: 440px;
  margin: 0 auto;
  /* Headroom for the stack, on the two sides it actually travels: two layers
     up and to the right at 14px each. Keep this in step with .ghost's inset
     and the translate below — the three together are what make the offsets
     land on one diagonal. */
  padding: 28px 28px 0 0;
}

/*
 * The print pass runs the whole terminal on gruvbox light. These are the same
 * inks the code blocks further down the page are highlighted with (see
 * .vitepress/shiki-gruvbox.ts) — a command in the hero and the same command in
 * Quick start are then literally the same color, which is the argument for
 * doing this at all. It also settles the stack: the ghost plates derive their
 * fill and line from --gb-bg and --gb-gray, so they turn to paper and pencil
 * on their own, with no separate light-mode treatment to keep in sync.
 */
html:not(.dark) .para-hero {
  --gb-bg: #fbf1c7;
  --gb-bg-soft: #ebdbb2;
  --gb-fg: #3c3836;
  --gb-gray: #7c6f64;
  --gb-yellow: #b57614;
  --gb-green: #79740e;
  --gb-aqua: #427b86;
  --gb-red: #9d0006;
}

/* The warm bloom that lifts the terminal off the page. */
.para-hero::before {
  content: '';
  position: absolute;
  inset: -6%;
  background: radial-gradient(closest-side at 45% 55%, rgba(250, 189, 47, 0.18), transparent 72%);
  filter: blur(38px);
  pointer-events: none;
}

/* ---- Parallel-universe terminal stack ---------------------------------- */

/*
 * ws2 and ws3, receding behind the front window. Three dimmed copies of the
 * same pane just read as a smudge, so the stack changes state as it goes back
 * instead of only changing opacity: the near one is a translucent pane, the far
 * one is a drawn outline with nothing inside it. Solid, glass, line — the way a
 * mission diagram renders the thing itself, the thing behind it, and the thing
 * that's only a plan. It also fixes the daylight problem the dimming had, since
 * a hairline can't smudge a bright sky the way a dark pane does.
 */
.ghost,
.term {
  border-radius: 10px;
}

.term {
  background: var(--gb-bg);
  border: 1px solid color-mix(in srgb, var(--gb-gray) 35%, transparent);
}

/* Sits exactly on the terminal to start with, so the only thing separating the
   layers is the translate — an even 14px up and right, one step per layer. */
.ghost {
  position: absolute;
  inset: 28px 28px 0 0;
}

.ghost.g1 {
  background: var(--gb-ghost-fill);
  border: 1px solid var(--gb-ghost-line);
  transform: translate(14px, -14px);
}

.ghost.g2 {
  background: none;
  border: 1px solid var(--gb-ghost-line-far);
  transform: translate(28px, -28px);
}


.term {
  position: relative;
  overflow: hidden;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.35);
}

/* A dark terminal needed a heavy shadow to lift off the nebula. A cream one
   needs only enough to sit above the cloud, or it reads as soot. */
html:not(.dark) .term {
  box-shadow: 0 10px 28px -14px rgba(60, 56, 54, 0.45);
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

/* The prompt is the terminal's own chrome rather than a token the code blocks
   below also render, so it takes the site's gold and leaves the nine inks it
   shares with them untouched. */
.cmd::before {
  content: '$ ';
  color: var(--gb-yellow);
  /* 600, not 700: that's the bold cut of Plex Mono the page loads, and asking
     for a weight no loaded face has leaves the choice to each engine's font
     matching — some pick the 600, some smear a synthetic bold over it. */
  font-weight: 600;
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
  .cursor { animation: none; }
}
</style>
