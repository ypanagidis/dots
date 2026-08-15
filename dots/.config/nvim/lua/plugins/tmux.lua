-- Seamless navigation between Herdr/tmux panes and Neovim splits.

vim.g.tmux_navigator_no_mappings = 1
vim.g.tmux_navigator_save_on_switch = 2

-- Herdr installs this as a managed plugin. Its adapter moves within Neovim
-- first, then asks Herdr to focus the neighboring pane at a split edge. It
-- falls back to vim-tmux-navigator when Neovim is running outside Herdr.
local herdr_adapters = vim.fn.glob(
	vim.fn.expand("~/.config/herdr/plugins/github/vim-herdr-navigation-*/editor/nvim.lua"),
	false,
	true
)

if #herdr_adapters > 0 then
	dofile(herdr_adapters[1])
	return
end

-- Keep the old tmux-only behavior on machines where the Herdr plugin has not
-- been installed yet.
vim.keymap.set("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { silent = true, desc = "Navigate left" })
vim.keymap.set("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>", { silent = true, desc = "Navigate down" })
vim.keymap.set("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>", { silent = true, desc = "Navigate up" })
vim.keymap.set("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>", { silent = true, desc = "Navigate right" })
vim.keymap.set("n", "<C-\\>", "<cmd>TmuxNavigatePrevious<cr>", { silent = true, desc = "Navigate previous" })
