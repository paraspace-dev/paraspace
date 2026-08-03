import { defineConfig } from 'vitepress'
import { gruvboxDark, gruvboxLight } from './shiki-gruvbox'

// Site source is the repo root: `index.md` is the landing page and the
// authoritative `docs/` tree is served as-is at /docs/. Everything else in
// the repo is excluded below.
export default defineConfig({
  title: 'ParaSpace',
  description:
    'Parallel dev workspaces. Every task gets a full, isolated copy of your project with its own stack and URL.',
  cleanUrls: true,
  lastUpdated: true,

  // The two faces the first screen actually paints: the body sans and the mono
  // the poster's host list is set in. Preloaded so neither swaps under the
  // reader, and the rest of Plex Mono's weights can wait for the stylesheet. The
  // wordmark needs no font at all; it's drawn (see theme/Wordmark.vue). Fonts
  // are fetched in CORS mode even same-origin, hence the crossorigin attribute.
  head: (
    [
      '/fonts/ibm-plex-sans-latin-var.woff2',
      '/fonts/ibm-plex-mono-latin-400.woff2',
    ] as const
  ).map((href) => [
    'link',
    { rel: 'preload', href, as: 'font', type: 'font/woff2', crossorigin: '' },
  ]),

  srcExclude: [
    'README.md',
    'CLAUDE.md',
    'templates/**',
    'mods/**',
    'plans/**',
    'test/**',
  ],

  // docs/README.md is the docs index on GitHub and npm; serve it at /docs/.
  rewrites: {
    'docs/README.md': 'docs/index.md',
  },

  sitemap: { hostname: 'https://paraspace.dev' },

  markdown: {
    theme: { light: gruvboxLight, dark: gruvboxDark },
  },

  themeConfig: {
    nav: [{ text: 'Docs', link: '/docs/', activeMatch: '^/docs/' }],

    sidebar: {
      '/docs/': [
        {
          text: 'Start here',
          items: [
            { text: 'Overview', link: '/docs/' },
            { text: 'Why ParaSpace', link: '/docs/why' },
            { text: 'Getting started', link: '/docs/getting-started' },
            { text: 'How it works', link: '/docs/how-it-works' },
            { text: 'Prior art', link: '/docs/prior-art' },
          ],
        },
        {
          text: 'Guides',
          items: [
            { text: 'Running coding agents', link: '/docs/agents' },
            { text: 'Project setup', link: '/docs/project-setup' },
            { text: 'Cookbook', link: '/docs/cookbook' },
            { text: 'Workspace URLs', link: '/docs/urls' },
            { text: 'Shared authentication', link: '/docs/shared-auth' },
            { text: 'Troubleshooting', link: '/docs/troubleshooting' },
          ],
        },
        {
          text: 'Reference',
          items: [
            { text: 'Commands', link: '/docs/commands' },
            { text: 'The Parafile', link: '/docs/parafile' },
            { text: 'Hooks', link: '/docs/hooks' },
            { text: 'Hook points', link: '/docs/hook-points' },
            { text: 'Mods', link: '/docs/mods' },
            { text: 'The image contract', link: '/docs/image' },
            { text: 'Contract versioning', link: '/docs/versioning' },
            { text: 'Internals', link: '/docs/internals' },
          ],
        },
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/paraspace-dev/paraspace' },
    ],

    search: { provider: 'local' },

    editLink: {
      pattern: 'https://github.com/paraspace-dev/paraspace/edit/main/:path',
      text: 'Edit this page on GitHub',
    },

    footer: {
      message: 'Released under the MIT License.',
    },
  },
})
