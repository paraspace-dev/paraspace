local map = vim.keymap.set

-- Quit-all (with confirm)
map("n", "<C-q>", "<cmd>confirm qall<cr>")

-- Insert: <C-Cr>/<S-Cr> to break a line without inheriting the comment leader
map("i", "<C-CR>", "<Esc>:set fo-=r<cr>a<cr><Esc>:set fo+=r<cr>a")
map("i", "<S-CR>", "<Esc>:set fo-=r<cr>a<cr><Esc>:set fo+=r<cr>a")

-- Visual: search the selected text literally
map("x", "//", [[y/\V<C-r>=escape(@", '/\')<cr><cr>]])

-- Full config reload = real restart (Neovim 0.12+ `:restart`). Stops this
-- instance with `:qall` and relaunches the server with the same args/files,
-- re-attaching the UI. Unlike an in-process `package.loaded` reload, this
-- re-runs init.lua, re-bootstraps lazy.nvim, and re-fires LspAttach, so
-- changes to lua/plugins/* are picked up too.
--
-- `:qall` aborts if any buffer is unsaved; `:wall` writes the named ones
-- first. (Unnamed/no-file buffers will still block, so save or :bd them, or
-- run `:restart +qall!` manually to discard everything.)
map("n", "<leader><F12>", "<cmd>wall <bar> restart<cr>", { desc = "Restart nvim (reload all config)" })

-- <C-c> behaves exactly like <Esc> (so InsertLeave fires, abbrevs expand)
map({ "i", "v" }, "<C-c>", "<Esc>")

-- Yank entire buffer to system clipboard. (Plain `y` already goes to "+" via
-- `clipboard=unnamedplus`, so no visual-mode binding needed.)
map("n", "<leader>c", "<cmd>%y+<cr>", { desc = "Yank buffer to clipboard" })
map({ "n", "v" }, "<leader>d", '"+d')

-- Copy current buffer's relative path to clipboard
map("n", "<leader>yf", function() vim.fn.setreg("+", vim.fn.expand("%")) end)

-- Press <CR> to clear search highlight
map("n", "<CR>", "<cmd>nohlsearch<cr>", { silent = true })

-- Open new file in same dir as current buffer
map("n", "<leader>e", function()
  vim.api.nvim_feedkeys(":e " .. vim.fn.expand("%:h") .. "/", "n", false)
end)

-- Close window
map("n", "<C-g>", "<cmd>close<cr>", { silent = true })

-- Quick-save
map("n", "<leader>w", "<cmd>w<cr>")

-- Toggle to alternate buffer
map("n", "<leader><leader>", "<C-^>")

-- Folding shortcuts (Atom-style)
map("n", "z1", "zM")
map("n", "z2", "zMzr")
map("n", "z3", "zM2zr")
map("n", "z4", "zM3zr")
map("n", "z5", "zM4zr")

-- Re-select what you just yanked or pasted
map("n", "gp", function()
  return "`[" .. string.sub(vim.fn.getregtype(), 1, 1) .. "`]"
end, { expr = true })

-- Keep search results centered
for _, k in ipairs({ "n", "N", "*", "#", "g*" }) do
  map("n", k, k .. "zz", { silent = true })
end

-- Open URL under cursor (replaces Netrw gx, which is flaky)
map("n", "gx", function()
  local cword = vim.fn.expand("<cWORD>")
  vim.fn.jobstart({ "xdg-open", cword }, { detach = true })
end, { silent = true })

-- "-" goes to start of line (avoids fat-finger when reaching for "0")
map("n", "-", "0")

-- Quick spelling fix while in insert mode
map("i", "<C-l>", "<C-g>u<Esc>[s1z=`]a<C-g>u")

-- Close all buffers but the current one
map("n", "<leader>ca", "<cmd>w <bar> %bd <bar> e# <bar> bd#<cr>")

-- Window swap via <C-w>HJKL (preserves marked-buffer dance)
do
  local marked_win, marked_buf
  local function mark()
    marked_win = vim.fn.winnr()
    marked_buf = vim.fn.bufnr("%")
  end
  local function swap()
    if not marked_win then return end
    local cur_win, cur_buf = vim.fn.winnr(), vim.fn.bufnr("%")
    vim.cmd(marked_win .. "wincmd w")
    vim.cmd("hide buf " .. cur_buf)
    vim.cmd(cur_win .. "wincmd w")
    vim.cmd("hide buf " .. marked_buf)
  end
  for _, dir in ipairs({ "H", "J", "K", "L" }) do
    map("n", "<C-w>" .. dir, function()
      mark()
      vim.cmd("wincmd " .. dir:lower())
      swap()
    end)
  end
end

-- "Save Harder" (force-write) for a known set of paths
vim.api.nvim_create_user_command("SaveHarder", function()
  vim.keymap.set("n", "<leader>w", "<cmd>w!<cr>", { buffer = true })
end, {})
