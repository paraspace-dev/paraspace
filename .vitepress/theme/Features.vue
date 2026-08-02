<script setup>
/**
 * The six things para gives you, alternating down the page.
 *
 * Each one sits in a lens — the same primitive the hero is built from (see
 * .pv-lens in custom.css) — and takes the hue of the hero circle on its side:
 * blue on the left, green on the right. The two circles separate on load and
 * then walk down the page, which is the whole reason the section reads as part
 * of the poster rather than a list underneath it.
 *
 * There is no rule or spine connecting them. These six aren't a sequence, and a
 * connector would claim they were; the glows overlap instead.
 */
import { onMounted, ref } from 'vue'

const ROWS = [
  {
    key: 'planet',
    title: 'Sandboxed',
    body: 'Set your coding agent to YOLO mode and enjoy peace of mind. Each workspace runs in an unprivileged system container — boot is fast, memory and compute are shared, and you can run containerized stacks inside it. Run a dozen at once and none of them can see another\'s branch, database, or half-finished edits.',
  },
  {
    key: 'key',
    title: 'Authenticate once',
    body: 'Run <code>gh auth login</code> in one workspace and every workspace on the project is authenticated — including the one you create next week, and after a reboot. One revocable key per project, and never your host\'s.',
  },
  {
    key: 'sputnik',
    title: 'Workspace subdomains',
    body: '<code>https://fix-login.paraspace.dev</code> the moment it\'s up — no DNS to set up; local TLS &amp; CA trust is automatic. Your stack keeps its usual ports, so hot reload and WebSockets need no configuration.',
  },
  {
    key: 'rocket',
    title: 'Thin wrapper',
    body: 'It\'s just bash. Your project has total control over virtually every aspect of the parallel workspace lifecycle, from building the image and booting the stack, to custom verbs and execution hooks.',
  },
  {
    key: 'console',
    title: 'A real terminal',
    body: 'No iframes, no web terminal. <code>para sh</code> is a real pty on your own machine, so tmux, Neovim and Claude Code behave well and support custom dotfiles per box. Each workspace feels like an extension of your normal environment.',
  },
]

const root = ref(null)

/*
 * The reveal is added by script and only ever by script: without it every row
 * is already in its finished state, so a reader with no JS — or one who asked
 * for less motion — gets the page rather than six empty gaps.
 */
onMounted(() => {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return

  root.value.classList.add('js')
  const io = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue
        entry.target.classList.add('in')
        io.unobserve(entry.target)
      }
    },
    { rootMargin: '0px 0px -12% 0px', threshold: 0.15 },
  )
  for (const row of root.value.querySelectorAll('.row')) io.observe(row)
})
</script>

<template>
  <section ref="root" class="features">
    <!--
      One sheet of drawings. Every icon is built from the circles and arcs the
      wordmark is, so the page is drawn by one hand; the gradient runs blue to
      green, so each icon holds both lenses whichever one it's sitting in.
    -->
    <svg class="defs" width="0" height="0" aria-hidden="true">
      <defs>
        <linearGradient id="pv-i-grad" x1="0" y1="0" x2="1" y2="1">
          <stop class="g1" offset="0%" />
          <stop class="g2" offset="100%" />
        </linearGradient>

        <mask id="pv-m-planet">
          <rect width="64" height="64" fill="#fff" />
          <path d="M16.5 34a13.5 13.5 0 0 1 27 0Z" fill="#000" />
        </mask>

        <g id="pv-i-planet">
          <circle cx="30" cy="34" r="13.5" />
          <path class="soft" d="M20 43.5A13.5 13.5 0 0 0 39.5 24.5" />
          <g mask="url(#pv-m-planet)">
            <ellipse cx="30" cy="34" rx="24.5" ry="8" transform="rotate(-17 30 34)" />
          </g>
          <circle class="lit" cx="52" cy="14" r="1.8" />
          <path class="soft" d="M50 22.5v4M48 24.5h4" />
        </g>

        <g id="pv-i-key">
          <circle cx="32" cy="17.5" r="9.5" />
          <circle cx="32" cy="17.5" r="3.4" />
          <path d="M32 27v27M32 40.5h8.5M32 47.5h6" />
        </g>

        <g id="pv-i-sputnik">
          <circle cx="28" cy="27" r="9" />
          <path d="M22 33.5 12 47M34 33.5 44 47M25 35.5 21 50M31 35.5 35 50" />
          <path class="soft" d="M44.5 15.5a15 15 0 0 1 0 15" />
          <path class="softer" d="M50 11a22 22 0 0 1 0 24" />
        </g>

        <g id="pv-i-rocket">
          <path
            d="M32 7c6.2 6.4 9.5 14.6 9.5 22.8 0 6-1.4 11.4-3 15.7H25.5c-1.6-4.3-3-9.7-3-15.7C22.5 21.6 25.8 13.4 32 7z"
          />
          <circle cx="32" cy="26" r="4.6" />
          <path
            d="M22.8 32.6c-4.3 2.4-6.6 6.7-6.6 11.9l6.3-3.4M41.2 32.6c4.3 2.4 6.6 6.7 6.6 11.9l-6.3-3.4"
          />
          <path class="soft" d="M28.5 50.5 32 57l3.5-6.5" />
        </g>

        <g id="pv-i-console">
          <rect x="8.5" y="13" width="47" height="31" rx="4.5" />
          <path d="M17.5 25.5 23 30l-5.5 4.5M27.5 34.5h10" />
          <path d="M32 44v6.5M22 50.5h20" />
        </g>
      </defs>
    </svg>

    <article v-for="(row, i) in ROWS" :key="row.key" class="row" :class="{ flip: i % 2 === 1 }">
      <div class="art">
        <span class="wash" />
        <div class="lens pv-lens">
          <span class="core" />
          <svg class="ico" viewBox="0 0 64 64" aria-hidden="true">
            <use :href="`#pv-i-${row.key}`" />
          </svg>
        </div>
      </div>
      <div class="copy">
        <h2>{{ row.title }}</h2>
        <!-- eslint-disable-next-line vue/no-v-html -- our own copy, no user input -->
        <p v-html="row.body" />
      </div>
    </article>
  </section>
</template>

<style scoped>
.features {
  position: relative;
  margin: 0 auto;
  padding: 0 24px;
  max-width: 900px;

  /* Lens diameter; the wash is sized off it so the two stay in proportion. */
  --d: clamp(132px, 16vw, 180px);
}

.defs {
  position: absolute;
}

.row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  align-items: center;
  gap: 48px;
}

/* Far enough apart that each lens belongs to the paragraph beside it and not to
   the one below; the wash is what keeps them from reading as separate. */
.row + .row {
  margin-top: 104px;
}

.art {
  position: relative;
  display: flex;
  justify-content: flex-end;
}

.row.flip .art {
  justify-content: flex-start;
}

/*
 * What ties the rows together. The lens throws light a lens-width or so; this
 * throws it three, faintly enough to be a wash rather than a second glow, so
 * one row's light reaches the next and the section reads as one lit column
 * instead of six lamps. It's first in the row, so it paints behind the lens
 * without a negative z-index that would drop it behind the poster's sheet.
 */
.wash {
  position: absolute;
  top: 50%;
  left: 50%;
  width: calc(var(--d) * 3.1);
  height: calc(var(--d) * 3.1);
  margin: calc(var(--d) * -1.55);
  border-radius: 50%;
  pointer-events: none;
  background: radial-gradient(
    circle at 50% 50%,
    color-mix(in srgb, var(--c) calc(var(--pv-d) * 9%), transparent) 0%,
    color-mix(in srgb, var(--c) calc(var(--pv-d) * 4%), transparent) 44%,
    transparent 76%
  );
}

.row.flip .art {
  order: 2;
}

/* Blue on the left, green on the right — whichever hero circle that side came
   from. The small lens turns the poster's dials down; at 150px the poster's
   bloom would swallow the icon. */
.row {
  --c: var(--pv-lens-a);
}

.row.flip {
  --c: var(--pv-lens-b);
}

.lens {
  --pv-fade: 0.4;
  --pv-rim: 2px;
  --pv-blur: 1.7px;
  --pv-glow: 26px;
  --pv-cast: 34px;
  --pv-crown-y: 5px;

  position: relative;
  width: var(--d);
  height: var(--d);
}

/* The warm core: the underglow from the hero, pooled behind each icon so the
   glyph is lit rather than painted. */
.core {
  position: absolute;
  inset: 20%;
  border-radius: 50%;
  background: radial-gradient(
    circle at 50% 52%,
    color-mix(in srgb, var(--pv-under) calc(var(--pv-d) * 20%), transparent),
    transparent 72%
  );
}

.ico {
  position: absolute;
  top: 21%;
  left: 21%;
  width: 58%;
  height: 58%;
  overflow: visible;
  fill: none;
  stroke: url(#pv-i-grad);
  stroke-width: 2.6;
  stroke-linecap: round;
  stroke-linejoin: round;
}

.g1 {
  stop-color: var(--pv-lens-a);
}

.g2 {
  stop-color: var(--pv-lens-b);
}

/* Secondary detail — a terminator, a highlight, a far signal arc — reads as
   depth at full strength and as clutter. */
.ico :deep(.soft) {
  opacity: 0.55;
}

.ico :deep(.softer) {
  opacity: 0.32;
}

.ico :deep(.lit) {
  fill: url(#pv-i-grad);
  stroke: none;
}

.copy h2 {
  margin: 0;
  font-size: 23px;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--vp-c-text-1);
}

.copy p {
  margin: 12px 0 0;
  max-width: 46ch;
  font-size: 16px;
  line-height: 1.65;
  color: var(--vp-c-text-2);
}

.copy :deep(code) {
  border-radius: 4px;
  padding: 3px 6px;
  font-family: var(--vp-font-family-mono);
  font-size: 0.875em;
  color: var(--vp-code-color);
  background-color: var(--vp-code-bg);
}

/* ---- Reveal ------------------------------------------------------------- */

/*
 * Each row arrives from its own side: the lens travels further than the copy,
 * so the light leads and the words follow it in.
 */
.js .row .art,
.js .row .copy {
  opacity: 0;
  transition:
    opacity 0.75s ease,
    transform 0.75s cubic-bezier(0.16, 0.84, 0.28, 1);
}

.js .row .art {
  transform: translateX(-38px);
}

.js .row.flip .art {
  transform: translateX(38px);
}

.js .row .copy {
  transform: translateY(20px);
  transition-delay: 0.12s;
}

.js .row.in .art,
.js .row.in .copy {
  opacity: 1;
  transform: none;
}

/* ---- Narrow ------------------------------------------------------------- */

@media (max-width: 767px) {
  .row {
    grid-template-columns: 1fr;
    justify-items: center;
    gap: 20px;
    text-align: center;
  }

  /* The zigzag has nowhere to go in one column, so every row reads the same way
     down and the alternating hue carries the rhythm on its own. */
  .row.flip .art {
    order: 0;
  }

  .art,
  .row.flip .art {
    justify-content: center;
  }

  .row + .row {
    margin-top: 56px;
  }

  .copy p {
    margin-inline: auto;
  }

  .js .row .art,
  .js .row.flip .art {
    transform: translateY(24px);
  }
}
</style>
