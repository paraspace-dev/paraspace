return {
  {
    "mason-org/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    opts = {},
  },

  -- Make lua_ls actually useful in this config: dynamically loads neovim
  -- runtime types and plugin source paths into lua_ls's workspace based on
  -- `require` calls. Without this, lua_ls completes basic Lua only, with no
  -- vim.api.*, no plugin types, no go-to-def into plugin source.
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        -- vim.uv types
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
        -- lazy.nvim plugin spec types
        "lazy.nvim",
      },
    },
  },

  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
      "mason-org/mason.nvim",
      "neovim/nvim-lspconfig",
    },
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      -- Per-server config (deep-merged on top of nvim-lspconfig defaults).
      vim.lsp.config("ts_ls", {
        init_options = { hostInfo = "neovim" },
        settings = {
          typescript = { format = { semicolons = "insert" } },
        },
      })

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
            diagnostics = { globals = { "vim" } },
          },
        },
      })

      -- Server set trimmed to this project's stack. Dropped vs. source:
      -- rust_analyzer, intelephense (php), pyright, gopls. Mason installs these
      -- on first launch into the shared /para/shared/nvim-data volume (para
      -- shares nvim rather than baking it), so it's a one-time cost per machine.
      require("mason-lspconfig").setup({
        ensure_installed = {
          "ts_ls",
          "marksman",
          "lua_ls",
          "bashls",
          "jsonls",
          "yamlls",
          "cssls",
          "html",
        },
        automatic_enable = true,
      })

      -- Diagnostic display
      vim.diagnostic.config({
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        virtual_text = { spacing = 2, prefix = "●" },
        float = { border = "rounded", source = true },
      })

      -- LSP keymaps (only set when an LSP attaches to a buffer)
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("lsp_attach", { clear = true }),
        callback = function(ev)
          local buf = ev.buf
          local map = function(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, desc = desc })
          end

          -- Navigation: route through fzf-lua so multi-result lists open in
          -- a picker with preview (and Enter jumps). `jump1 = true` in the
          -- fzf-lua opts makes single results jump straight there.
          local fzf = function(m) return function() require("fzf-lua")[m]() end end
          map("n", "gd", fzf("lsp_definitions"), "Go to definition")
          map("n", "gy", fzf("lsp_typedefs"), "Go to type definition")
          map("n", "gi", fzf("lsp_implementations"), "Go to implementation")
          map("n", "gr", fzf("lsp_references"), "References")
          map("n", "K", vim.lsp.buf.hover, "Hover docs")

          -- Diagnostics (`<C-j>`/`<C-k>` and `[g`/`]g`)
          local function diag_jump(count)
            return function() vim.diagnostic.jump({ count = count, float = false }) end
          end
          map("n", "[g", diag_jump(-1), "Prev diagnostic")
          map("n", "]g", diag_jump(1), "Next diagnostic")
          map("n", "<C-k>", diag_jump(-1), "Prev diagnostic")
          map("n", "<C-j>", diag_jump(1), "Next diagnostic")

          -- Show full diagnostic(s) for the current line in a float. Press once
          -- to peek; press again to focus the float (then move/select/yank to copy).
          map("n", ",d", function() vim.diagnostic.open_float(nil, { scope = "line" }) end, "Line diagnostics")

          -- Refactor / fix
          map("n", ",rn", vim.lsp.buf.rename, "Rename symbol")
          map({ "n", "v", "x" }, ",a", vim.lsp.buf.code_action, "Code action")
          map("n", ",ac", vim.lsp.buf.code_action, "Code action (buffer)")
          map("n", ",qf", function()
            vim.lsp.buf.code_action({
              filter = function(a) return a.isPreferred end,
              apply = true,
            })
          end, "Quick fix")
          map("n", ",cl", vim.lsp.codelens.run, "Run codelens")

          -- Formatting (kept under `,f`; <leader>p still routes to conform.format below)
          map({ "n", "x" }, ",f", function() vim.lsp.buf.format({ async = true }) end, "Format")

          -- Highlight matching symbol on CursorHold (replaces coc highlight)
          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          if client and client.server_capabilities.documentHighlightProvider then
            local hl_grp = vim.api.nvim_create_augroup("lsp_highlight_" .. buf, { clear = true })
            vim.api.nvim_create_autocmd("CursorHold", {
              group = hl_grp, buffer = buf, callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd("CursorMoved", {
              group = hl_grp, buffer = buf, callback = vim.lsp.buf.clear_references,
            })
          end
        end,
      })
    end,
  },

  -- Formatter (replaces vim-prettier; <leader>p hits prettier/gofmt/rustfmt/etc)
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      { "<leader>p", function() require("conform").format({ async = true, lsp_format = "fallback" }) end, mode = { "n", "v" }, desc = "Format buffer" },
    },
    opts = {
      formatters_by_ft = {
        javascript = { "prettier" },
        javascriptreact = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
        html = { "prettier" },
        json = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        lua = { "stylua" },
        sh = { "shfmt" },
      },
    },
  },
}
