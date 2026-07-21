local aug = vim.api.nvim_create_augroup
local au = vim.api.nvim_create_autocmd

-- Highlight yanked region briefly (replaces vim-highlightedyank)
au("TextYankPost", {
  group = aug("highlight_yank", { clear = true }),
  callback = function() vim.hl.on_yank({ timeout = 200 }) end,
})

-- Filetype detection that vim.filetype.add can't trivially express
vim.filetype.add({
  extension = {
    plot = "gnuplot",
    md = "markdown",
    pathrc = "sh",
    monitrc = "monitrc",
    dockerfile = "dockerfile",
  },
  filename = {
    [".npmignore"] = "gitignore",
    APKBUILD = "sh",
    Justfile = "just",
    ["ledger.dat"] = "ledger",
    ["master.cf"] = "sh", -- postfix
  },
  pattern = {
    [".*/etc/monit/.*"] = "monitrc",
    ["ledger%-.*%.dat"] = "ledger",
  },
})

-- Read-only protection for .orig files
au("BufRead", {
  pattern = "*.orig",
  callback = function() vim.bo.readonly = true end,
})

-- Folding per-filetype
au("FileType", {
  pattern = "javascript",
  callback = function() vim.opt_local.foldmethod = "syntax" end,
})
au("FileType", {
  pattern = "yaml",
  callback = function() vim.opt_local.foldmethod = "indent" end,
})

-- Restore last cursor position when opening a file (skip git commit messages)
au("BufReadPost", {
  callback = function(args)
    local path = vim.api.nvim_buf_get_name(args.buf)
    if path:match("/%.git/") then return end
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local lcount = vim.api.nvim_buf_line_count(args.buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Markdown: real prose, not code
au("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.textwidth = 0
    vim.opt_local.colorcolumn = ""
    vim.opt_local.indentexpr = ""
    -- <End> → end of visual line, not logical line
    vim.keymap.set("i", "<End>", "<C-O>$<Right>", { buffer = true })
  end,
})

-- LaTeX conceal
au("FileType", {
  pattern = "tex",
  callback = function() vim.opt_local.conceallevel = 1 end,
})

-- Markdown fenced code highlighting via treesitter handles this; keep
-- plain-vim's `markdown_fenced_languages` for the legacy markdown.vim
-- syntax fallback only.
vim.g.markdown_fenced_languages = {
  "html", "css", "scss", "sql", "javascript", "js=javascript",
  "ts=typescript", "bash=sh", "c", "lua", "json", "yaml",
  "docker=dockerfile", "makefile=make",
}

-- "Save Harder" workspaces (autocmd to apply the user command per buffer)
au("BufRead", {
  pattern = "*/projects/by/*",
  callback = function() vim.cmd("SaveHarder") end,
})

-- Leave paste mode automatically
au("InsertLeave", {
  callback = function() vim.opt.paste = false end,
})
