-- Which-key: shows keybinding hints as you type
local wk = require("which-key")

wk.setup({
	preset = "helix", -- Grid layout with icons (like LazyVim)
	delay = 200,
	icons = {
		breadcrumb = "»",
		separator = "➜",
		group = "+",
	},
	win = {
		border = "rounded",
		padding = { 1, 2 },
	},
})

-- Register group labels for leader key prefixes
wk.add({
	mode = { "n", "x" },
	{ "<leader>b", group = "buffer" },
	{ "<leader>c", group = "code" },
	{ "<leader>f", group = "file/find" },
	{ "<leader>g", group = "git" },
	{ "<leader>h", group = "git hunk" },
	{ "<leader>q", group = "quit/quickfix" },
	{ "<leader>s", group = "search" },
	{ "<leader>u", group = "ui" },
	{ "<leader>w", group = "window" },
	{ "<leader>x", group = "diagnostics" },
	{ "[", group = "prev" },
	{ "]", group = "next" },
	{ "g", group = "goto" },
})

-- Keybinding to show which-key menu
vim.keymap.set("n", "<leader>?", function()
	require("which-key").show({ global = false })
end, { desc = "Buffer Keymaps (which-key)" })
