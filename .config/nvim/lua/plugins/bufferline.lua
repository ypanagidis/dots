require("bufferline").setup({
  options = {
    mode = "buffers",
    themable = true,
    numbers = "none",
    close_command = "bdelete! %d",
    right_mouse_command = "bdelete! %d",
    left_mouse_command = "buffer %d",
    indicator = {
      style = "icon",
      icon = "▎",
    },
    buffer_close_icon = "󰅖",
    modified_icon = "●",
    close_icon = "",
    left_trunc_marker = "",
    right_trunc_marker = "",
    max_name_length = 30,
    max_prefix_length = 30,
    truncate_names = true,
    tab_size = 21,
    diagnostics = "nvim_lsp",
    diagnostics_update_in_insert = false,
    diagnostics_indicator = function(count, level)
      local icon = level:match("error") and " " or " "
      return " " .. icon .. count
    end,
    offsets = {
      {
        filetype = "oil",
        text = "File Explorer",
        highlight = "Directory",
        separator = true,
      },
    },
    color_icons = true,
    show_buffer_icons = true,
    show_buffer_close_icons = true,
    show_close_icon = true,
    show_tab_indicators = true,
    show_duplicate_prefix = true,
    persist_buffer_sort = true,
    separator_style = "thin",
    enforce_regular_tabs = false,
    always_show_bufferline = true,
    sort_by = "insert_after_current",
  },
})

local map = vim.keymap.set

-- Buffer navigation
map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })
map("n", "[b", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous buffer" })
map("n", "]b", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })

-- Buffer reordering
map("n", "<leader>bp", "<cmd>BufferLineTogglePin<cr>", { desc = "Pin buffer" })
map("n", "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<cr>", { desc = "Close unpinned buffers" })
map("n", "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", { desc = "Close other buffers" })
map("n", "<leader>bl", "<cmd>BufferLineCloseRight<cr>", { desc = "Close buffers to the right" })
map("n", "<leader>bh", "<cmd>BufferLineCloseLeft<cr>", { desc = "Close buffers to the left" })

-- Pick buffer
map("n", "<leader>bs", "<cmd>BufferLinePick<cr>", { desc = "Pick buffer" })
