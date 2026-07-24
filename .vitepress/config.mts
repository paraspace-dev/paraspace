import { defineConfig } from 'vitepress'

// Site source is the repo root: `index.md` is the landing page and the
// authoritative `docs/` tree is served as-is at /docs/. Everything else in
// the repo is excluded below.
export default defineConfig({
  title: 'ParaSpace',
  description:
    'Parallel dev workspaces — every task gets a full, isolated copy of your project with its own stack and URL.',
  cleanUrls: true,
  lastUpdated: true,

  srcExclude: ['README.md', 'CLAUDE.md', 'templates/**', 'plans/**', 'test/**'],

  // docs/README.md is the docs index on GitHub and npm; serve it at /docs/.
  rewrites: {
    'docs/README.md': 'docs/index.md',
  },

  sitemap: { hostname: 'https://paraspace.dev' },

  themeConfig: {
    nav: [{ text: 'Docs', link: '/docs/', activeMatch: '^/docs/' }],

    sidebar: {
      '/docs/': [
        { text: 'Overview', link: '/docs/' },
        {
          text: 'Guides',
          items: [
            { text: 'How it works', link: '/docs/how-it-works' },
            { text: 'Project setup', link: '/docs/project-setup' },
            { text: 'Workspace URLs', link: '/docs/urls' },
            { text: 'Git authentication', link: '/docs/git-auth' },
          ],
        },
        {
          text: 'Reference',
          items: [
            { text: 'Commands', link: '/docs/commands' },
            { text: 'The Parafile', link: '/docs/parafile' },
            { text: 'Hooks', link: '/docs/hooks' },
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
