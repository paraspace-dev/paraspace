return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    lazy = false,
    config = function()
      require("nvim-treesitter").setup()

      -- Parser set trimmed to this project's stack (Bun/TS + Docker + docs).
      -- Dropped vs. the source config: go/gomod/gosum, php/phpdoc, python, rust.
      local installed = {
        "bash", "c", "css", "dockerfile",
        "html", "javascript", "json", "jsonc", "just", "lua", "luadoc",
        "make", "markdown", "markdown_inline",
        "regex", "scss", "sql", "toml", "tsx", "typescript",
        "vim", "vimdoc", "yaml",
      }

      -- Only install missing parsers (network call), no version pinning.
      local to_install = vim.tbl_filter(function(lang)
        return not pcall(vim.treesitter.language.add, lang)
      end, installed)
      if #to_install > 0 then
        require("nvim-treesitter").install(to_install)
      end

      -- Highlights + indent on by default for all installed parsers.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          local ft = args.match
          local lang = vim.treesitter.language.get_lang(ft) or ft
          if pcall(vim.treesitter.start, args.buf, lang) then
            vim.bo[args.buf].indentexpr =
              "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- Better matchpair behaviour (replaces vim-matchup integration with TS)
  {
    "andymass/vim-matchup",
    event = "BufReadPost",
    init = function()
      vim.g.matchup_matchparen_offscreen = { method = "popup" }
    end,
  },
}
