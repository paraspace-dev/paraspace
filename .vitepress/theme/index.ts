import { h } from 'vue'
// theme-without-fonts is the default theme minus its bundled Inter. The body
// and code faces are declared in custom.css instead, so shipping Inter as well
// would be ~50KB of font nobody renders.
import DefaultTheme from 'vitepress/theme-without-fonts'
import Sky from './Sky.vue'
import TerminalDemo from './TerminalDemo.vue'
import './custom.css'

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      // `layout-top` renders above the navbar in the DOM, which is what lets the
      // sky bleed behind it. The layer is absolutely positioned, so it claims no
      // space and needs no --vp-layout-top-height.
      'layout-top': () => h(Sky),
      'home-hero-image': () => h(TerminalDemo),
    })
  },
}
