import { h } from 'vue'
// theme-without-fonts is the default theme minus its bundled Inter. The body
// and code faces are declared in custom.css instead, so shipping Inter as well
// would be ~50KB of font nobody renders.
import DefaultTheme from 'vitepress/theme-without-fonts'
import Poster from './Poster.vue'
import Features from './Features.vue'
import TerminalDemo from './TerminalDemo.vue'
import './custom.css'

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      // The landing page has no `hero` in its frontmatter, so the default one
      // doesn't render and the poster stands in its place — it owns the whole
      // first screen, background included. The terminal follows it: the poster
      // says what para is, the terminal shows the commands, and the rows say
      // what you get. The default feature grid never renders: the landing page
      // has no `features` in its frontmatter either.
      'home-hero-before': () => h(Poster),
      'home-hero-after': () => h(TerminalDemo),
      'home-features-before': () => h(Features),
    })
  },
}
