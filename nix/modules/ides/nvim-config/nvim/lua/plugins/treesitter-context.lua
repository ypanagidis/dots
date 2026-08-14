require("treesitter-context").setup({
  enable = true,
  max_lines = 3, -- How many lines the context window can show
  min_window_height = 0, -- Minimum editor window height to enable context
  line_numbers = true,
  multiline_threshold = 20, -- Maximum number of lines to show for a single context
  trim_scope = "outer", -- Which context lines to discard if max_lines is exceeded
  mode = "cursor", -- Line used to calculate context: 'cursor' or 'topline'
  separator = nil, -- Separator between context and content (nil = no separator)
  zindex = 20, -- Z-index of the context window
})

-- Optional: Toggle keybinding
vim.keymap.set("n", "<leader>tc", "<cmd>TSContextToggle<CR>", { desc = "Toggle treesitter context" })
