import { h } from 'vue'
import DefaultTheme from 'vitepress/theme'
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
