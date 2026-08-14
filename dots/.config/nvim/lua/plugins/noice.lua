require("noice").setup({
  lsp = {
    -- override markdown rendering so that cmp and other plugins use Treesitter
    override = {
      ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
      ["vim.lsp.util.stylize_markdown"] = true,
      ["cmp.entry.get_documentation"] = true,
    },
    hover = { enabled = true },
    signature = { enabled = true },
  },
  presets = {
    bottom_search = true,         -- use a classic bottom cmdline for search
    command_palette = true,       -- position the cmdline and popupmenu together
    long_message_to_split = true, -- long messages will be sent to a split
    inc_rename = false,           -- enables an input dialog for inc-rename.nvim
    lsp_doc_border = true,        -- add a border to hover docs and signature help
  },
  routes = {
    -- Hide "written" messages
    {
      filter = {
        event = "msg_show",
        kind = "",
        find = "written",
      },
      opts = { skip = true },
    },
    -- Hide search count messages
    {
      filter = {
        event = "msg_show",
        kind = "search_count",
      },
      opts = { skip = true },
    },
    -- Hide noisy LSP empty-info notifications (e.g. from secondary clients)
    {
      filter = {
        event = "msg_show",
        kind = "",
        find = "No information available",
      },
      opts = { skip = true },
    },
    {
      filter = {
        event = "notify",
        find = "No information available",
      },
      opts = { skip = true },
    },
  },
  views = {
    hover = {
      border = {
        style = "rounded",
      },
    },
    cmdline_popup = {
      position = {
        row = 5,
        col = "50%",
      },
      size = {
        width = 60,
        height = "auto",
      },
    },
    popupmenu = {
      relative = "editor",
      position = {
        row = 8,
        col = "50%",
      },
      size = {
        width = 60,
        height = 10,
      },
      border = {
        style = "rounded",
        padding = { 0, 1 },
      },
    },
  },
})

-- Keymaps
local map = vim.keymap.set
map("n", "<leader>sn", "<cmd>Noice<cr>", { desc = "Noice messages" })
map("n", "<leader>nd", "<cmd>NoiceDismiss<cr>", { desc = "Dismiss notifications" })
