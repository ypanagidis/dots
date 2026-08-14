-- Cyberdream theme
require("cyberdream").setup({
  -- Enable transparent background
  transparent = false,
  
  -- Enable italics comments
  italic_comments = false,
  
  -- Replace all fillchars with ' ' for the ultimate clean look
  hide_fillchars = false,
  
  -- Modern borderless telescope theme
  borderless_telescope = true,
  
  -- Set terminal colors used in `:terminal`
  terminal_colors = true,
  
  theme = {
    variant = "default", -- use "light" for light mode
    highlights = {
      -- You can add custom overrides here
    },
  },
})
vim.cmd("colorscheme cyberdream")

-- Lualine
require("lualine").setup({
  options = {
    theme = "auto", -- Cyberdream provides its own lualine theme automatically
    component_separators = { left = "", right = "" },
    section_separators = { left = "", right = "" },
    globalstatus = true,
  },
  sections = {
    lualine_a = { "mode" },
    lualine_b = { "branch", "diff", "diagnostics" },
    lualine_c = { { "filename", path = 1 } },
    lualine_x = { "encoding", "fileformat", "filetype" },
    lualine_y = { "progress" },
    lualine_z = { "location" },
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = { "filename" },
    lualine_x = { "location" },
    lualine_y = {},
    lualine_z = {},
  },
})
