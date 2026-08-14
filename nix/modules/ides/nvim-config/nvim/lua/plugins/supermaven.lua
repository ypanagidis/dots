-- Supermaven AI completion
require("supermaven-nvim").setup({
	keymaps = {
		accept_suggestion = "<Tab>",
		clear_suggestion = "<C-]>",
		accept_word = "<C-j>",
	},
	ignore_filetypes = { "bigfile", "snacks_input", "snacks_notif" },
	color = {
		suggestion_color = "#585858",
		cterm = 244,
	},
	log_level = "info",
	disable_inline_completion = false, -- Show ghost text
	disable_keymaps = false,
})
