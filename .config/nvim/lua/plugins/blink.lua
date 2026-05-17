require("blink.cmp").setup({
	keymap = {
		preset = "default",
		["<C-j>"] = { "select_next", "fallback" },
		["<C-k>"] = { "select_prev", "fallback" },
		["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
		["<C-e>"] = { "hide" },
		["<CR>"] = { "accept", "fallback" },
		-- Tab reserved for Supermaven AI suggestions
	},

	completion = {
		list = {
			selection = { preselect = true, auto_insert = false },
		},
		menu = {
			border = "rounded",
			draw = {
				columns = { { "kind_icon" }, { "label", "label_description", gap = 1 }, { "kind" } },
			},
		},
		documentation = {
			auto_show = true,
			auto_show_delay_ms = 200,
			window = {
				border = "rounded",
			},
		},
	},

	sources = {
		default = { "lsp", "path", "buffer" },
	},
})
