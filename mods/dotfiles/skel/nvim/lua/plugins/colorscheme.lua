return {
  {
    "sainnhe/gruvbox-material",
    lazy = false,
    priority = 1000,
    config = function()
      -- gruvbox-material is configured via vim.g globals that must be set
      -- *before* the colorscheme command (termguicolors/background already
      -- come from config/options.lua).
      vim.g.gruvbox_material_background = "medium" -- 'hard' | 'medium' | 'soft'
      vim.g.gruvbox_material_foreground = "mix" -- 'material' | 'mix' | 'original'
      vim.g.gruvbox_material_enable_italic = true
      vim.g.gruvbox_material_better_performance = 1
      vim.cmd.colorscheme("gruvbox-material")
    end,
  },
}
