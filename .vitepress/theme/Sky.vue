<script setup>
/**
 * Full-bleed sky behind the top of the landing page. Two different skies, not
 * one recolored: dark mode is a nebula in deep space (drifting blooms, a
 * procedural filament layer, a starfield), light mode is a late-afternoon
 * daytime sky (aqua overhead warming toward the horizon, high thin cloud, and
 * the moon with Venus beside it — the two things you can actually pick out in
 * daylight). Mounted in the `layout-top` slot so it sits behind the navbar as
 * well as the hero, and painted at z-index -1 so page content stays above it.
 */
import { computed } from 'vue'
import { useData } from 'vitepress'

const { frontmatter } = useData()
const isHome = computed(() => frontmatter.value.layout === 'home')

/* Deterministic PRNG (mulberry32): the SSR pass and the client hydration must
   agree on every star position, so Math.random() is out. */
function mulberry32(a) {
  return () => {
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/* Real starfields aren't monochrome. Mostly warm white, a few cool, and a
   couple of gold/rose ones that land in the gruvbox ramp. */
const TINTS = [
  ['#f6eeda', 0.6],
  ['#cfe0ff', 0.22],
  ['#fabd2f', 0.11],
  ['#d3869b', 0.07],
]

function tintFor(u) {
  let acc = 0
  for (const [color, weight] of TINTS) {
    acc += weight
    if (u <= acc) return color
  }
  return TINTS[0][0]
}

const STARS = (() => {
  const rand = mulberry32(0x5eed17)
  const stars = []
  for (let i = 0; i < 96; i++) {
    /* Cubed skew: a lot of faint pinpricks, a handful of bright anchors —
       a flat size distribution reads as scattered confetti. */
    const mag = rand() ** 3
    const size = 1 + mag * 2.2
    stars.push({
      key: i,
      twinkles: rand() < 0.34,
      bright: size > 2.4,
      style: {
        '--x': `${(rand() * 100).toFixed(2)}%`,
        /* Squared toward 0: denser overhead, thinning into the page. */
        '--y': `${(rand() ** 1.6 * 100).toFixed(2)}%`,
        '--sz': `${size.toFixed(2)}px`,
        '--o': (0.34 + mag * 0.52).toFixed(2),
        '--tint': tintFor(rand()),
        '--dur': `${(4 + rand() * 5).toFixed(1)}s`,
        /* Negative delay: stars start mid-cycle, so nothing fades in together. */
        '--delay': `${(rand() * -9).toFixed(1)}s`,
      },
    })
  }
  return stars
})()
</script>

<template>
  <div v-if="isHome" class="sky" aria-hidden="true">
    <!-- ---- Night: nebula ------------------------------------------------ -->
    <div class="night">
      <div class="wash" />

      <div class="bloom b1" />
      <div class="bloom b2" />
      <div class="bloom b3" />
      <div class="bloom b4" />
      <div class="bloom b5" />

      <!--
        Filaments: fractal noise, desaturated and gamma-crushed so only the
        crests survive, used as a luminance mask over a plum/magenta/teal
        gradient. The viewBox stretches to the layer, which smears the noise
        horizontally on wide screens — that's where the wave comes from.
      -->
      <svg class="filaments" viewBox="0 0 1200 700" preserveAspectRatio="none">
        <defs>
          <filter
            id="para-neb-noise"
            x="0"
            y="0"
            width="100%"
            height="100%"
            color-interpolation-filters="sRGB"
          >
            <feTurbulence
              type="fractalNoise"
              baseFrequency="0.0055 0.014"
              numOctaves="4"
              seed="17"
            />
            <feColorMatrix type="saturate" values="0" />
            <feComponentTransfer>
              <feFuncR type="gamma" exponent="3.4" amplitude="1.7" />
              <feFuncG type="gamma" exponent="3.4" amplitude="1.7" />
              <feFuncB type="gamma" exponent="3.4" amplitude="1.7" />
              <feFuncA type="table" tableValues="1 1" />
            </feComponentTransfer>
          </filter>

          <mask id="para-neb-mask" maskUnits="userSpaceOnUse" x="0" y="0" width="1200" height="700">
            <rect width="1200" height="700" filter="url(#para-neb-noise)" />
          </mask>

          <!-- Stop colors come from CSS so the theme can swap them; `var()` is
               not allowed in a presentation attribute, hence the classes. -->
          <linearGradient id="para-neb-hue" x1="0" y1="0" x2="1" y2="1">
            <stop class="f1" offset="0%" />
            <stop class="f2" offset="46%" />
            <stop class="f3" offset="100%" />
          </linearGradient>
        </defs>

        <rect width="1200" height="700" fill="url(#para-neb-hue)" mask="url(#para-neb-mask)" />
      </svg>

      <div class="stars">
        <i
          v-for="star in STARS"
          :key="star.key"
          :class="{ tw: star.twinkles, bright: star.bright }"
          :style="star.style"
        />
      </div>
    </div>

    <!-- ---- Day: late afternoon ------------------------------------------ -->
    <div class="day">
      <div class="daylight" />

      <!-- The daytime moon: washed out rather than luminous — it's barely
           brighter than the sky around it, which is why you have to look. -->
      <div class="moon">
        <span class="mare m1" />
        <span class="mare m2" />
        <span class="mare m3" />
      </div>

      <!-- Venus holds steady where a star would scintillate, so it gets a
           clean glow and no twinkle. -->
      <div class="venus" />

      <!--
        The cumulus deck. Its silhouette is built from layered radial gradients
        (percentages, so it reflows with the viewport) and then run through a
        turbulence displacement filter, which is what turns smooth arcs into a
        billowed cloud edge. Towers highest behind the headline and fall away to
        the right so the terminal keeps its patch of sky; solid white by the
        time the feature cards begin, so they rest on it like a horizon.
      -->
      <div class="nimbus" />

      <svg class="defs" width="0" height="0" aria-hidden="true">
        <!--
          Two displacement passes, because one only ever yields wobbly ovals: a
          coarse, low-frequency pass deforms the puff cluster into big irregular
          masses, then a finer pass breaks those edges into cauliflower. That
          hierarchy — large forms made of small ones — is what reads as cumulus.
        -->
        <filter
          id="para-puff"
          x="-25%"
          y="-25%"
          width="150%"
          height="150%"
          color-interpolation-filters="sRGB"
        >
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.0035"
            numOctaves="4"
            seed="5"
            result="coarse"
          />
          <feDisplacementMap
            in="SourceGraphic"
            in2="coarse"
            scale="70"
            xChannelSelector="R"
            yChannelSelector="G"
            result="d1"
          />
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.014"
            numOctaves="3"
            seed="11"
            result="fine"
          />
          <feDisplacementMap
            in="d1"
            in2="fine"
            scale="24"
            xChannelSelector="R"
            yChannelSelector="G"
          />
        </filter>

        <!-- Displacement is measured in px, so the desktop scale would tear a
             phone-width cloud apart. Same recipe, proportionate amplitude. -->
        <filter
          id="para-puff-sm"
          x="-25%"
          y="-25%"
          width="150%"
          height="150%"
          color-interpolation-filters="sRGB"
        >
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.008"
            numOctaves="4"
            seed="5"
            result="coarse"
          />
          <feDisplacementMap
            in="SourceGraphic"
            in2="coarse"
            scale="28"
            xChannelSelector="R"
            yChannelSelector="G"
            result="d1"
          />
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.03"
            numOctaves="3"
            seed="11"
            result="fine"
          />
          <feDisplacementMap
            in="d1"
            in2="fine"
            scale="8"
            xChannelSelector="R"
            yChannelSelector="G"
          />
        </filter>
      </svg>
    </div>
  </div>
</template>

<style scoped>
.sky {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  z-index: -1;
  height: clamp(760px, 100vh + 300px, 1220px);
  overflow: hidden;
  pointer-events: none;
}

.night,
.day {
  position: absolute;
  inset: 0;
}

/* One sky at a time. */
.night {
  display: none;
}

.dark .day {
  display: none;
}

.dark .night {
  display: block;
}

/* ======================================================================== */
/* Night: nebula                                                            */
/* ======================================================================== */

.wash {
  position: absolute;
  inset: 0;
  background: linear-gradient(180deg, rgba(21, 15, 28, 0.96), rgba(21, 15, 28, 0) 72%);
}

/* ---- Blooms ------------------------------------------------------------ */

/* Soft-edged radial gradients need no blur filter of their own, which keeps
   the drift animation transform-only (composited, never repainted). */
.bloom {
  position: absolute;
  border-radius: 50%;
  background: radial-gradient(
    closest-side,
    color-mix(in srgb, var(--c) var(--a), transparent),
    transparent 74%
  );
  animation: drift var(--dur) ease-in-out var(--delay, 0s) infinite alternate;
  will-change: transform;
}

.b1 {
  --c: var(--neb-gas-1);
  --a: 42%;
  --dur: 94s;
  top: -22%;
  left: -14%;
  width: 74%;
  height: 96%;
}

.b2 {
  --c: var(--neb-gas-2);
  --a: 34%;
  --dur: 78s;
  --delay: -12s;
  top: -8%;
  left: 50%;
  width: 62%;
  height: 78%;
}

.b3 {
  --c: var(--neb-gas-3);
  --a: 24%;
  --dur: 110s;
  --delay: -30s;
  top: 26%;
  left: -18%;
  width: 52%;
  height: 62%;
}

/* Gas 4 sits where the terminal does, so the brand orange reads as the
   nebula's warm core rather than a stray highlight. */
.b4 {
  --c: var(--neb-gas-4);
  --a: 20%;
  --dur: 68s;
  --delay: -22s;
  top: -14%;
  left: 68%;
  width: 38%;
  height: 44%;
}

/* Low and wide: the faint mass the feature cards float in. */
.b5 {
  --c: var(--neb-gas-1);
  --a: 20%;
  --dur: 120s;
  --delay: -46s;
  top: 58%;
  left: 2%;
  width: 96%;
  height: 52%;
}

@keyframes drift {
  from { transform: translate3d(0, 0, 0) scale(1); }
  to { transform: translate3d(2.5%, -1.5%, 0) scale(1.08); }
}

/* ---- Filaments --------------------------------------------------------- */

.filaments {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  opacity: 0.5;
  /* A touch of blur turns crisp noise crests into glowing gas. */
  filter: blur(3px);
  mask-image: linear-gradient(180deg, transparent, #000 14%, #000 46%, transparent 92%);
}

.f1 { stop-color: var(--neb-fil-1); }
.f2 { stop-color: var(--neb-fil-2); }
.f3 { stop-color: var(--neb-fil-3); }

/* ---- Stars ------------------------------------------------------------- */

.stars {
  position: absolute;
  inset: 0;
  mask-image: linear-gradient(180deg, #000 54%, transparent 94%);
}

.stars i {
  position: absolute;
  top: var(--y);
  left: var(--x);
  width: var(--sz);
  height: var(--sz);
  border-radius: 50%;
  background: var(--tint);
  opacity: var(--o);
}

.stars i.bright {
  box-shadow: 0 0 6px 1px color-mix(in srgb, var(--tint) 45%, transparent);
}

.stars i.tw {
  animation: twinkle var(--dur) ease-in-out var(--delay) infinite;
}

/* Small amplitude, long period: scintillation you notice on the second look,
   not a string of fairy lights. */
@keyframes twinkle {
  0%,
  100% {
    opacity: calc(var(--o) * 0.45);
    transform: scale(0.9);
  }
  50% {
    opacity: var(--o);
    transform: scale(1);
  }
}

/* Same field at phone width is a crowd; drop every other star. */
@media (max-width: 640px) {
  .stars i:nth-child(2n) {
    display: none;
  }
}

/* ======================================================================== */
/* Day: late afternoon                                                      */
/* ======================================================================== */

/* Deeper overhead, paling as it drops — the actual vertical structure of an
   afternoon sky, which is what keeps it from reading as a flat tinted band. It
   only has to carry the strip above the cloud deck, so it clears out early. */
.daylight {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    180deg,
    var(--sky-high) 0%,
    var(--sky-mid) 22%,
    var(--sky-low) 42%,
    transparent 58%
  );
}

/* ---- The cumulus deck -------------------------------------------------- */

.nimbus {
  position: absolute;
  inset: 0;
  /* Cool throughout: bright lit crowns, a blue-gray shadowed body, then paling
     haze into the white the cards sit on. No warm cast — sunlit cumulus against
     blue reads white-to-slate, and any cream turns it into a sunset. */
  background: linear-gradient(
    180deg,
    #ffffff 0%,
    #f6fbfd 12%,
    #dde9f0 25%,
    #e9f2f7 34%,
    #f7fbfc 46%,
    #ffffff 60%
  );
  /*
   * The silhouette: a cluster of overlapping puffs rather than a handful of big
   * ellipses, so the displacement has small forms to break up as well as large.
   * It towers on the left, crests above the headline, and steps down to the
   * right past the terminal — and the solid base means sky only ever shows
   * above the contour, never beside or below it.
   */
  /* Near-solid puffs with only a thin soft rim, packed so neighbours overlap by
     roughly half. Soft-edged puffs never fuse — they stay legible as separate
     ovals no matter how many you add. Solid ones union into one mass and let the
     displacement supply the irregular contour, which is the whole point. */
  mask-image:
    /* crown */
    radial-gradient(7% 5% at 23% 12%, #000 80%, transparent 94%),
    radial-gradient(7% 5% at 30% 11.5%, #000 80%, transparent 94%),
    /* second tier */
    radial-gradient(8.5% 5.5% at 16% 17%, #000 80%, transparent 94%),
    radial-gradient(8.5% 5.5% at 25% 16%, #000 80%, transparent 94%),
    radial-gradient(8.5% 5.5% at 34% 17.5%, #000 80%, transparent 94%),
    /* third tier */
    radial-gradient(9.5% 6% at 10% 22%, #000 80%, transparent 94%),
    radial-gradient(9.5% 6% at 20% 21%, #000 80%, transparent 94%),
    radial-gradient(9.5% 6% at 30% 22%, #000 80%, transparent 94%),
    radial-gradient(9.5% 6% at 40% 23.5%, #000 80%, transparent 94%),
    /* widening base of the tower */
    radial-gradient(10% 6% at 5% 27%, #000 80%, transparent 94%),
    radial-gradient(10% 6% at 16% 26.5%, #000 80%, transparent 94%),
    radial-gradient(10% 6% at 27% 27.5%, #000 80%, transparent 94%),
    radial-gradient(10% 6% at 38% 28.5%, #000 80%, transparent 94%),
    radial-gradient(10% 6% at 49% 30%, #000 80%, transparent 94%),
    /* shoulder riding the slope down past the terminal */
    radial-gradient(11% 5.5% at 60% 33.5%, #000 80%, transparent 94%),
    radial-gradient(11% 5.5% at 71% 36%, #000 80%, transparent 94%),
    radial-gradient(11% 5.5% at 82% 39%, #000 80%, transparent 94%),
    radial-gradient(11% 5.5% at 93% 41.5%, #000 80%, transparent 94%),
    /* The base is sloped, not level: a horizontal boundary would fill in the
       right-hand sky the shoulder is supposed to leave open. */
    linear-gradient(197deg, transparent 28%, #000 36%);
  /* Displace, then soften just enough — a cumulus edge is crisp but not vector. */
  filter: url(#para-puff) blur(1.1px);
}

/* Shadowed undersides, tucked below each billow cluster and following the
   contour down to the right. The parent's mask clips these to the silhouette so
   they only ever darken cloud, never sky — without them the deck is a flat
   cut-out with no volume. */
.nimbus::before {
  content: '';
  position: absolute;
  inset: 0;
  background:
    radial-gradient(6% 3% at 25% 14%, rgba(126, 156, 176, 0.42), transparent 72%),
    radial-gradient(7% 3.5% at 19% 19%, rgba(126, 156, 176, 0.48), transparent 72%),
    radial-gradient(7% 3.5% at 29% 19.5%, rgba(126, 156, 176, 0.44), transparent 72%),
    radial-gradient(8% 4% at 13% 24%, rgba(126, 156, 176, 0.52), transparent 72%),
    radial-gradient(8% 4% at 25% 25%, rgba(126, 156, 176, 0.5), transparent 72%),
    radial-gradient(8% 4% at 37% 26%, rgba(126, 156, 176, 0.46), transparent 74%),
    radial-gradient(9% 4% at 50% 33%, rgba(126, 156, 176, 0.4), transparent 74%),
    radial-gradient(9% 4% at 64% 37%, rgba(126, 156, 176, 0.34), transparent 74%),
    radial-gradient(9% 3.5% at 78% 41%, rgba(126, 156, 176, 0.3), transparent 76%),
    radial-gradient(9% 3.5% at 91% 44%, rgba(126, 156, 176, 0.26), transparent 76%);
}

/* No displacement support → smooth arcs, which still read as cloud. */
@supports not (filter: url(#para-puff)) {
  .nimbus {
    filter: blur(2px);
  }
}

.defs {
  position: absolute;
}

/* ---- The moon ---------------------------------------------------------- */

/* Both sit in the band between the navbar and the headline — the only sky that
   stays clear at every desktop width, since by 1024px the hero's terminal column
   reaches within 64px of the right edge — and the deepest part of the gradient,
   where a pale moon reads best. Horizontally they sit left of the terminal
   rather than above its top corner, which is what they were crowding. */
.moon {
  position: absolute;
  top: 7%;
  right: 54%;
  width: 46px;
  height: 46px;
  border-radius: 50%;
  /* Waxing gibbous: the terminator is soft shading toward the lower left
     rather than a hard bite, since a daytime moon has no contrast to spare. */
  background: radial-gradient(circle at 68% 32%, var(--moon-lit) 52%, var(--moon-dim) 92%);
  /* Barely any bloom: the daytime moon is dimmer than the sky it sits in, so a
     halo would turn it into a lamp. Just enough to soften the limb. */
  box-shadow: 0 0 5px 1px color-mix(in srgb, #fff 26%, transparent);
  opacity: 0.9;
}

/* Maria: faint, irregular, low-contrast — enough to say "moon" without
   turning into a cartoon. */
.mare {
  position: absolute;
  border-radius: 50%;
  background: var(--moon-mare);
  opacity: 0.36;
  filter: blur(2px);
}

.m1 {
  top: 22%;
  left: 30%;
  width: 34%;
  height: 27%;
}

.m2 {
  top: 52%;
  left: 52%;
  width: 24%;
  height: 20%;
}

.m3 {
  top: 40%;
  left: 20%;
  width: 17%;
  height: 15%;
}

/* ---- Venus ------------------------------------------------------------- */

.venus {
  position: absolute;
  /* Clear of the terminal's topmost ghost frame, so it reads as sky rather than a
     speck on the chrome. */
  top: 10.5%;
  right: 47%;
  width: 4px;
  height: 4px;
  border-radius: 50%;
  background: var(--venus-core);
  box-shadow:
    0 0 4px 1.5px color-mix(in srgb, var(--venus-core) 70%, transparent),
    0 0 12px 4px color-mix(in srgb, var(--venus-core) 30%, transparent);
}

/* Below 960px the hero stacks and the terminal drops under the copy, so the
   right side of the sky opens up — move the pair over rather than letting the
   headline run through them. */
/*
 * Stacked layout. The copy runs unbroken from the wordmark down to the buttons,
 * so there's no gap to land the cloud tops in — put them above the wordmark
 * instead and let every line sit on white. The sky narrows to a strip, with the
 * moon just clearing the crests, which is the same reading as the desktop
 * composition rather than a different one.
 */
@media (max-width: 959px) {
  /* The strip here is only the gap between the navbar and the wordmark, so the
     pair sits high enough to overlap the nav's own band and has to dodge its
     controls. In absolute px the empty stretch differs with width — the search
     box is an icon on a phone and a full field by 768px — but as a percentage
     the clear zone is roughly 38%–74% at both ends, so that's what these are
     anchored to. */
  .moon {
    top: 2.8%;
    right: 45%;
    width: 38px;
    height: 38px;
  }

  .venus {
    top: 6%;
    right: 30%;
  }

  /* Same contour gesture compressed into the strip above the wordmark. The
     puffs are wide relative to their spacing — at this width the desktop
     proportions leave them barely touching, which reads as a row of bubbles
     rather than a cloud. */
  .nimbus {
    mask-image:
      radial-gradient(16% 5% at 4% 13%, #000 80%, transparent 94%),
      radial-gradient(16% 5% at 15% 12%, #000 80%, transparent 94%),
      radial-gradient(16% 5% at 26% 12.5%, #000 80%, transparent 94%),
      radial-gradient(16% 5% at 37% 13%, #000 80%, transparent 94%),
      radial-gradient(16% 5% at 48% 13.5%, #000 80%, transparent 94%),
      radial-gradient(16% 5% at 59% 14%, #000 80%, transparent 94%),
      radial-gradient(16% 5% at 70% 14.5%, #000 80%, transparent 94%),
      radial-gradient(16% 5% at 81% 15%, #000 80%, transparent 94%),
      radial-gradient(16% 5% at 92% 15.5%, #000 80%, transparent 94%),
      linear-gradient(180deg, transparent 15%, #000 20%);
    filter: url(#para-puff-sm) blur(0.8px);
  }

  /* The valleys move up with the crests. */
  .nimbus::before {
    background:
      radial-gradient(14% 3% at 20% 16%, rgba(126, 156, 176, 0.42), transparent 74%),
      radial-gradient(14% 3% at 50% 17.5%, rgba(126, 156, 176, 0.36), transparent 74%),
      radial-gradient(14% 3% at 80% 19%, rgba(126, 156, 176, 0.3), transparent 74%);
  }
}

/* ======================================================================== */

@media (prefers-reduced-motion: reduce) {
  .bloom,
  .stars i.tw {
    animation: none;
  }
}
</style>
