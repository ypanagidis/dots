local map = vim.keymap.set

-- Better escape
map("i", "jk", "<Esc>", { desc = "Escape" })

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search" })

-- Better window navigation (without tmux)
-- map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
-- map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
-- map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
-- map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Resize windows
map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

-- Move lines
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move line down" })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move line up" })

-- Better indenting
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })

-- Buffers
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })

-- Keep cursor centered
map("n", "<C-d>", function()
	vim.g.snacks_animate_scroll = false
	vim.cmd("normal! \x04zz")
	vim.g.snacks_animate_scroll = true
end, { desc = "Scroll down" })
map("n", "<C-u>", function()
	vim.g.snacks_animate_scroll = false
	vim.cmd("normal! \x15zz")
	vim.g.snacks_animate_scroll = true
end, { desc = "Scroll up" })
map("n", "n", "nzzzv", { desc = "Next search result" })
map("n", "N", "Nzzzv", { desc = "Previous search result" })

-- Quickfix
map("n", "<leader>qn", "<cmd>cnext<cr>", { desc = "Next quickfix" })
map("n", "<leader>qp", "<cmd>cprev<cr>", { desc = "Previous quickfix" })
map("n", "<leader>qc", "<cmd>cclose<cr>", { desc = "Close quickfix" })

-- Save & Quit
map("n", "<leader>fs", "<cmd>w<cr>", { desc = "Save file" })
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })

-- Windows
map("n", "<leader>wv", "<cmd>vsplit<cr>", { desc = "Vertical split" })
map("n", "<leader>wh", "<cmd>split<cr>", { desc = "Horizontal split" })
map("n", "<leader>wd", "<cmd>close<cr>", { desc = "Close window" })
map("n", "<leader>wo", "<cmd>only<cr>", { desc = "Close other windows" })
map("n", "<leader>w=", "<C-w>=", { desc = "Equal window sizes" })
