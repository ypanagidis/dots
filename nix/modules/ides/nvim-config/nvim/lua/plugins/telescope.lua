local telescope = require("telescope")
local actions = require("telescope.actions")
local builtin = require("telescope.builtin")

telescope.setup({
  defaults = {
    prompt_prefix = "> ",
    selection_caret = "> ",
    entry_prefix = "  ",
    path_display = { "truncate" },
    sorting_strategy = "ascending",
    layout_config = {
      horizontal = {
        prompt_position = "top",
        preview_width = 0.55,
      },
      width = 0.87,
      height = 0.80,
    },
    mappings = {
      i = {
        ["<C-n>"] = actions.move_selection_next,
        ["<C-p>"] = actions.move_selection_previous,
        ["<C-j>"] = actions.move_selection_next,
        ["<C-k>"] = actions.move_selection_previous,
        ["<Down>"] = actions.move_selection_next,
        ["<Up>"] = actions.move_selection_previous,
        ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
        ["<Esc>"] = actions.close,
        ["<CR>"] = actions.select_default,
      },
      n = {
        ["j"] = actions.move_selection_next,
        ["k"] = actions.move_selection_previous,
        ["<Down>"] = actions.move_selection_next,
        ["<Up>"] = actions.move_selection_previous,
        ["q"] = actions.close,
        ["<Esc>"] = actions.close,
        ["<CR>"] = actions.select_default,
      },
    },
  },
  pickers = {
    find_files = {
      hidden = true,
      file_ignore_patterns = { "node_modules", ".git/", "dist/", "build/" },
    },
    live_grep = {
      additional_args = function()
        return { "--hidden" }
      end,
    },
  },
})

local map = vim.keymap.set

-- File pickers
map("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
map("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
map("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
map("n", "<leader>fr", builtin.oldfiles, { desc = "Recent files" })
map("n", "<leader>fw", builtin.grep_string, { desc = "Grep word under cursor" })

-- Git
map("n", "<leader>gc", builtin.git_commits, { desc = "Git commits" })
map("n", "<leader>gs", builtin.git_status, { desc = "Git status" })
map("n", "<leader>gb", builtin.git_branches, { desc = "Git branches" })

-- LSP (these work nicely with telescope)
map("n", "<leader>fs", builtin.lsp_document_symbols, { desc = "Document symbols" })
map("n", "<leader>fS", builtin.lsp_workspace_symbols, { desc = "Workspace symbols" })
map("n", "<leader>fd", builtin.diagnostics, { desc = "Diagnostics" })

-- Search
map("n", "<leader>sh", builtin.help_tags, { desc = "Help tags" })
map("n", "<leader>sk", builtin.keymaps, { desc = "Keymaps" })
map("n", "<leader>sc", builtin.commands, { desc = "Commands" })
map("n", "<leader>/", builtin.current_buffer_fuzzy_find, { desc = "Search in buffer" })

-- Resume
map("n", "<leader><leader>", builtin.resume, { desc = "Resume last picker" })
