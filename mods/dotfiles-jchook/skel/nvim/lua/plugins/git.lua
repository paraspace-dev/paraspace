return {
  {
    "tpope/vim-fugitive",
    cmd = { "G", "Git", "Gdiff", "Gdiffsplit", "Gvdiffsplit", "Gwrite", "Gread", "Gblame", "Glog", "GBrowse" },
  },

  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add          = { text = "│" },
        change       = { text = "│" },
        delete       = { text = "_" },
        topdelete    = { text = "‾" },
        changedelete = { text = "~" },
        untracked    = { text = "┆" },
      },
      current_line_blame = false,
      preview_config = { border = "rounded" },
    },
  },
}
