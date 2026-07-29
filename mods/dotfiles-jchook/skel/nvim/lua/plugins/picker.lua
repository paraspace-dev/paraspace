return {
  -- Filetype icons used by fzf-lua, oil, and anything else that can render
  -- them. Shared dep — keep it in one place.
  { "nvim-tree/nvim-web-devicons", lazy = true },

  {
    "ibhagwan/fzf-lua",
    cmd = { "FzfLua" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    -- Lazy-route vim.ui.select through fzf-lua. First call loads the plugin
    -- and registers the real handler; subsequent calls hit fzf-lua directly.
    -- Affects code actions, multi-server rename, and any other ui.select site.
    init = function()
      vim.ui.select = function(items, opts, on_choice)
        require("fzf-lua").register_ui_select()
        vim.ui.select(items, opts, on_choice)
      end
    end,
    keys = {
      -- <C-p>: fuzzy file find with proximity-sort relative to current buffer.
      -- For proximity to "stick" while you type:
      --   * `fd | proximity-sort` provides the input in proximity order.
      --   * `--scheme=default --tiebreak=index` makes input order win ties
      --     (overrides fzf-lua's default `--scheme=path`).
      --   * `_fzf_nth_devicons=false` disables fzf-lua's default `--nth=-1..`,
      --     which scopes scoring to the basename (after the icon delimiter)
      --     and varies scores across files enough to defeat the tiebreak.
      --     Icons still render — this only affects what fzf scores against.
      {
        "<C-p>",
        function()
          local cur = vim.fn.expand("%")
          -- proximity-sort is a Rust tool and isn't installed on the para
          -- image; fall back to a plain fd listing when it's absent so <C-p>
          -- still works (just without proximity ordering).
          local has_prox = vim.fn.executable("proximity-sort") == 1
          -- An explicit `cmd` bypasses `fd_opts` entirely, and fzf-lua still
          -- appends `--hidden` for its <A-h> toggle — so the excludes have to
          -- be repeated here or <C-p> lists the whole .git tree.
          local base = "fd -t f --exclude .git --exclude .jj --strip-cwd-prefix"
          local cmd = (cur == "" or cur == nil or not has_prox)
            and base
            or string.format(
              "%s | proximity-sort %s", base, vim.fn.shellescape(cur))
          require("fzf-lua").files({
            cmd = cmd,
            _fzf_nth_devicons = false,
            fzf_opts = {
              ["--scheme"] = "default",
              ["--tiebreak"] = "index",
              ["--nth"] = false,
              ["--delimiter"] = false,
            },
          })
        end,
        desc = "Find files (proximity-sorted)",
      },

      -- Buffers / history / tags
      { "<leader>;", function() require("fzf-lua").buffers() end, desc = "Buffers" },
      { "<leader>r", function() require("fzf-lua").command_history() end, desc = "Command history" },
      { "<leader>t", function() require("fzf-lua").lsp_workspace_symbols() end, desc = "Workspace symbols" },

      -- File outline (preserves <space>o → outline)
      { "<leader>o", function() require("fzf-lua").lsp_document_symbols() end, desc = "Document outline" },

      -- All diagnostics (preserves <space>a)
      { "<leader>a", function() require("fzf-lua").diagnostics_workspace() end, desc = "Workspace diagnostics" },

      -- Live grep with preview (preserves <leader>f → :Ripgrep)
      { "<leader>f", function() require("fzf-lua").live_grep_native() end, desc = "Ripgrep (live)" },
    },
    opts = {
      "default",
      winopts = {
        height = 0.85,
        width = 0.90,
        preview = { default = "bat", layout = "flex" },
      },
      keymap = {
        builtin = {
          ["<C-d>"] = "preview-page-down",
          ["<C-u>"] = "preview-page-up",
        },
      },
      files = {
        prompt = "Files❯ ",
        fd_opts = "--color=never --hidden --type f --type l --exclude .git --strip-cwd-prefix",
      },
      grep = {
        prompt = "Rg❯ ",
        rg_opts = "--column --line-number --no-heading --color=always --smart-case",
      },
      lsp = {
        jump1 = true,
        code_actions = {
          -- Drop actions the server marks as inapplicable (LSP `disabled`
          -- field). Otherwise they show as "(disabled)" entries you can't pick.
          filter = function(a) return not a.disabled end,
        },
      },
    },
  },

  -- :Rg → quickfix-reflector workflow for project-wide find/replace
  -- We provide a :Rg command that mirrors fzf.vim's behaviour: results into
  -- the quickfix list, then quickfix-reflector lets you :wq to apply edits.
  {
    "stefandtw/quickfix-reflector.vim",
    event = "QuickFixCmdPost",
    keys = {
      { "<leader>s", ":Rg ", desc = "Project find/replace via :Rg + qf-reflector" },
    },
    init = function()
      vim.api.nvim_create_user_command("Rg", function(opts)
        local query = opts.args
        if query == "" then
          query = vim.fn.input("Rg: ")
          if query == "" then return end
        end
        local cmd = string.format(
          "rg --vimgrep --no-heading --smart-case -- %s",
          vim.fn.shellescape(query)
        )
        local lines = vim.fn.systemlist(cmd)
        if vim.v.shell_error ~= 0 and #lines == 0 then
          vim.notify("Rg: no matches", vim.log.levels.WARN)
          return
        end
        vim.fn.setqflist({}, " ", { title = "Rg " .. query, lines = lines })
        vim.cmd("copen")
      end, { nargs = "*" })
    end,
  },
}
