/**
 * Gruvbox syntax themes for Shiki.
 *
 * VitePress defaults to github-light/github-dark, which colors shell command
 * words indigo — a hue this site owns nowhere else, so every code block read as
 * a visitor. Shiki bundles no gruvbox, so these are the two palettes the rest of
 * the theme already uses (see theme/custom.css), mapped onto TextMate scopes:
 * red keywords, green commands and strings, blue variables, yellow types, gray
 * comments. Backgrounds are set by `--vp-code-block-bg`, not from here, so the
 * `colors` entries below only matter as Shiki's required defaults.
 *
 * Palette reference: https://github.com/morhetz/gruvbox
 */

import type { ThemeRegistrationRaw } from 'shiki'

type Palette = {
  fg: string
  bg: string
  gray: string
  red: string
  green: string
  yellow: string
  blue: string
  purple: string
  orange: string
}

/* Light uses the darker end of each gruvbox hue: the code block sits on a pale
   gray, not on gruvbox's cream, so the normal-contrast variants are too faint. */
const light: Palette = {
  fg: '#3c3836',
  bg: '#fbf1c7',
  gray: '#7c6f64',
  red: '#9d0006',
  green: '#79740e',
  yellow: '#b57614',
  blue: '#076678',
  purple: '#8f3f71',
  orange: '#af3a03',
}

const dark: Palette = {
  fg: '#ebdbb2',
  bg: '#282828',
  gray: '#928374',
  red: '#fb4934',
  green: '#b8bb26',
  yellow: '#fabd2f',
  blue: '#83a598',
  purple: '#d3869b',
  orange: '#fe8019',
}

function theme(name: string, type: 'light' | 'dark', p: Palette): ThemeRegistrationRaw {
  return {
    name,
    type,
    colors: {
      'editor.foreground': p.fg,
      'editor.background': p.bg,
    },
    settings: [
      { settings: { foreground: p.fg, background: p.bg } },
      {
        scope: ['comment', 'punctuation.definition.comment', 'string.comment'],
        settings: { foreground: p.gray, fontStyle: 'italic' },
      },
      {
        scope: [
          'keyword',
          'keyword.control',
          'storage',
          'storage.type',
          'storage.modifier',
          'entity.name.tag',
          'variable.language',
        ],
        settings: { foreground: p.red },
      },
      {
        scope: [
          'string',
          'string.quoted',
          'string.template',
          'entity.name.function',
          'support.function',
          'meta.function-call.identifier',
        ],
        settings: { foreground: p.green },
      },
      {
        /* A shell argument is scoped `string.unquoted.argument`, but on this
           site those tokens are the workspace names and paths — the nouns a
           reader scans for, and where the prose link color comes from. They
           read as identifiers, so they take the identifier blue rather than
           the string green the scope name would suggest. */
        scope: [
          'variable',
          'variable.other',
          'meta.definition.variable',
          'punctuation.definition.variable',
          'support.property-name',
          'meta.object-literal.key',
          'string.unquoted.argument',
        ],
        settings: { foreground: p.blue },
      },
      {
        scope: [
          'entity.name.type',
          'entity.name.class',
          'support.type',
          'support.class',
          'entity.other.attribute-name',
        ],
        settings: { foreground: p.yellow },
      },
      {
        scope: ['constant.numeric', 'constant.language', 'constant.character.escape'],
        settings: { foreground: p.purple },
      },
      {
        /* Shell flags and operators: the warm accent, so `-g` and `|` stay
           legible without competing with the command word. */
        scope: ['constant.other.option', 'keyword.operator'],
        settings: { foreground: p.orange },
      },
    ],
  }
}

export const gruvboxLight = theme('gruvbox-light', 'light', light)
export const gruvboxDark = theme('gruvbox-dark', 'dark', dark)
