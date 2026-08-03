local opt = vim.opt

opt.shell = "/bin/zsh"

-- Buffers / files
opt.hidden = true
opt.title = true
opt.backup = false
opt.writebackup = false
opt.undofile = true
opt.undodir = vim.fn.expand("~/.vimdid")

-- Editing
opt.encoding = "utf-8"
opt.timeoutlen = 300
opt.updatetime = 300
opt.scrolloff = 2
opt.wrap = false
opt.joinspaces = false
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.autoindent = true
opt.formatoptions:append("tcqj")

-- Splits
opt.splitright = true
opt.splitbelow = true

-- Wildmenu / completion
opt.wildmode = "list:longest"
opt.wildignore = {
  ".hg", ".svn", "*~", "*.png", "*.jpg", "*.gif",
  "*.settings", "Thumbs.db", "*.min.js", "*.swp",
  "publish/*", "intermediate/*", "*.o", "*.hi",
  "Zend", "vendor",
}

-- Search
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true
opt.inccommand = "nosplit"

-- UI
opt.number = true
opt.relativenumber = true
opt.ruler = true
opt.colorcolumn = "80"
opt.laststatus = 2
opt.lazyredraw = false -- noxious with modern plugins
opt.mouse = "a"
opt.foldenable = false
opt.shortmess:append("c")
opt.showcmd = true
opt.signcolumn = "yes"
opt.synmaxcol = 300
opt.termguicolors = true
opt.background = "dark"

-- Diff
opt.diffopt:append("iwhite")
opt.diffopt:append("algorithm:patience")
opt.diffopt:append("indent-heuristic")

-- Listchars
opt.list = false
opt.listchars = { nbsp = "¬", extends = "»", precedes = "«", trail = "•" }

-- Yank to system clipboard by default (external clipboard history tool consumes it)
opt.clipboard = "unnamedplus"

-- Statusline (kept simple; LSP plugin extends it later if desired)
opt.statusline = " %f %m %a%=%l, %c %y %P "

-- POSIX shell highlighting
vim.g.is_posix = 1

-- Disable some unused providers, which speeds startup and hides install warnings
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
