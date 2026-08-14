require("codediff").setup({
	diff = {
		layout = "inline",
	},
	explorer = {
		initial_focus = "explorer",
	},
	keymaps = {
		view = {
			toggle_explorer = "<leader>e",
			focus_explorer = "<leader>E",
			next_hunk = "<C-n>",
			prev_hunk = "<C-p>",
			next_file = "]f",
			prev_file = "[f",
		},
	},
})

vim.keymap.set("n", "<leader>gd", "<Cmd>CodeDiff<CR>", { desc = "Open git diff" })
