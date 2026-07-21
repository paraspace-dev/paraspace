return {
  -- Distraction-free writing — replaces Goyo
  {
    "folke/zen-mode.nvim",
    cmd = "ZenMode",
    keys = {
      { "<leader>z", "<cmd>ZenMode<cr>", desc = "Toggle zen mode" },
    },
    opts = {
      window = {
        backdrop = 1,
        width = 0.85,
        height = 1,
        options = {
          number = false,
          relativenumber = false,
          signcolumn = "no",
          cursorline = false,
        },
      },
      plugins = {
        options = { laststatus = 0 },
        gitsigns = { enabled = false },
      },
    },
  },
}
