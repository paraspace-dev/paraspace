return {
  -- Tim Pope essentials still worth keeping
  { "tpope/vim-repeat", event = "VeryLazy" },
  { "tpope/vim-sleuth", event = { "BufReadPre", "BufNewFile" } },
  { "tpope/vim-abolish", event = "VeryLazy" },
  { "tpope/vim-eunuch", cmd = { "Move", "Rename", "Delete", "Mkdir", "SudoEdit", "SudoWrite", "Chmod" } },
  { "pbrisbin/vim-mkdir", event = "BufWritePre" },
  { "tommcdo/vim-exchange", keys = { { "cx", mode = { "n", "x" } }, "cxx", "cxc" } },
  -- Auto-save session into Session.vim when one is active. Must load eagerly:
  -- Obsession's autosave lives in `BufEnter`/`VimLeavePre` autocmds registered
  -- by plugin/obsession.vim. Lazy-loading on `cmd = { "Obsess" }` means those
  -- autocmds never get installed when nvim starts via `nvim -S Session.vim`,
  -- so the session file silently stops updating.
  { "tpope/vim-obsession", lazy = false },
  { "editorconfig/editorconfig-vim", event = { "BufReadPre", "BufNewFile" } },

  -- mini.*, small and focused and well-maintained
  {
    "echasnovski/mini.surround",
    version = "*",
    event = "VeryLazy",
    -- Remapped from mini.surround's native `sa`/`sd`/`sr`/`sf`/`sh` to
    -- vim-surround's `ys`/`ds`/`cs` for muscle-memory continuity.
    --
    -- The native scheme is genuinely cleaner, with one `s` prefix, mnemonic
    -- second letter, plus `sf`/`sh` (find / highlight) and `<char>l`/`<char>n`
    -- suffixes for last/next match. We give that up because adopting it
    -- means clobbering `s` (substitute char), and the alternative for `s`
    -- alone (`vc`) is one extra keystroke. (For single-char replace, `r<char>`
    -- is already shorter than `s<char><esc>`, so no loss there.)
    --
    -- Aspirational: migrate to defaults eventually. When ready, set the
    -- mappings table to `{}`, add `vim.keymap.set({'n','x'}, 's', '<Nop>')`
    -- to suppress the timeout-fallback to native `s`, and delete the visual
    -- `S` and `yss` shims below.
    opts = {
      mappings = {
        add = "ys",
        delete = "ds",
        find = "",
        find_left = "",
        highlight = "",
        replace = "cs",
        update_n_lines = "",
        suffix_last = "l",
        suffix_next = "n",
      },
      search_method = "cover_or_next",
    },
    config = function(_, opts)
      require("mini.surround").setup(opts)
      -- Visual mode: `S"` to surround selection (matches vim-surround)
      vim.keymap.set("x", "S", [[:<C-u>lua MiniSurround.add('visual')<CR>]],
        { silent = true, desc = "Surround selection" })
      -- `yss"` → surround the whole line
      vim.keymap.set("n", "yss", "ys_", { remap = true, desc = "Surround line" })
    end,
  },

  {
    "echasnovski/mini.ai",
    version = "*",
    event = "VeryLazy",
    config = function()
      local ai = require("mini.ai")
      ai.setup({
        custom_textobjects = {
          -- ae = entire buffer
          e = function()
            local last = vim.fn.line("$")
            return {
              from = { line = 1, col = 1 },
              to = { line = last, col = math.max(1, #vim.fn.getline(last)) },
            }
          end,
          -- au = URL under cursor (greedy WORD match for http(s)/ftp/file/etc.)
          u = function()
            local line = vim.fn.getline(".")
            local col = vim.fn.col(".")
            local pat = "[%w%-_~%.%+]+://[%w%-_~%.%+/%?%#%[%]@!%$&'%(%)%*%+,;=:%%]+"
            local s, e = 1, 0
            while true do
              local ns, ne = string.find(line, pat, e + 1)
              if not ns then break end
              if ns <= col and ne >= col then s, e = ns, ne; break end
              s, e = ns, ne
              if ns > col then break end
            end
            if e == 0 then return nil end
            return {
              from = { line = vim.fn.line("."), col = s },
              to   = { line = vim.fn.line("."), col = e },
            }
          end,
        },
      })
    end,
  },

  -- EasyAlign on `ga`
  {
    "junegunn/vim-easy-align",
    keys = {
      { "ga", "<Plug>(EasyAlign)", mode = { "n", "x" } },
    },
  },

  -- Image paste in markdown, replaces clipboard-image.nvim
  {
    "HakonHarnes/img-clip.nvim",
    event = "VeryLazy",
    keys = {
      { ",p", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
    },
    opts = {
      default = {
        dir_path = "img",
        relative_to_current_file = true,
        prompt_for_file_name = true,
      },
    },
  },
}
