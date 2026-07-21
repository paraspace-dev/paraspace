return {
  -- Snippet engine — LuaSnip + the converted UltiSnips snippets.
  -- Kept lazy so its plugin/luasnip.lua doesn't auto-source before our config
  -- runs (causes a `loaded_fts` nil error during BufWinEnter at startup).
  -- blink.cmp pulls it in on InsertEnter via the dependency below.
  {
    "L3MON4D3/LuaSnip",
    version = "v2.*",
    build = "make install_jsregexp",
    lazy = true,
    config = function()
      local ls = require("luasnip")
      ls.config.set_config({
        history = true,
        updateevents = "TextChanged,TextChangedI",
        enable_autosnippets = false,
      })
      require("luasnip.loaders.from_lua").load({
        paths = vim.fn.stdpath("config") .. "/snippets",
      })
    end,
  },

  -- Completion
  {
    "saghen/blink.cmp",
    version = "1.*",
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = { "L3MON4D3/LuaSnip" },
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      keymap = {
        preset = "default",
        -- Tab/S-Tab cycle the menu; <CR> accepts. <C-Space> manual trigger.
        ["<Tab>"] = { "select_next", "fallback" },
        ["<S-Tab>"] = { "select_prev", "fallback" },
        ["<CR>"] = { "accept", "fallback" },
        ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
        -- <C-j>/<C-k> for snippet jumps (matches old UltiSnips muscle memory)
        ["<C-j>"] = { "snippet_forward", "fallback" },
        ["<C-k>"] = { "snippet_backward", "fallback" },
      },
      snippets = { preset = "luasnip" },
      appearance = { nerd_font_variant = "mono" },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        ghost_text = { enabled = false },
        -- Traditional pum behavior: first item highlighted on open, navigate
        -- with arrows/<C-n>/<C-p>, accept with <CR>. `auto_insert = false`
        -- keeps text out of the buffer until you actually accept.
        list = { selection = { preselect = true, auto_insert = false } },
      },
      sources = {
        default = { "lazydev", "lsp", "path", "snippets", "buffer" },
        providers = {
          lazydev = {
            name = "LazyDev",
            module = "lazydev.integrations.blink",
            -- High score so module-name completions in `require('...')` win
            -- over generic LSP suggestions for the same prefix.
            score_offset = 100,
          },
        },
      },
      cmdline = { enabled = false },
      fuzzy = { implementation = "prefer_rust_with_warning" },
      signature = { enabled = true },
    },
    opts_extend = { "sources.default" },
  },
}
