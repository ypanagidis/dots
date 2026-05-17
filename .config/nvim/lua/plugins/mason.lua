require("mason").setup({
	ui = {
		border = "rounded",
	},
})

require("mason-lspconfig").setup({
	ensure_installed = {
		"clangd",
		"gopls",
		"oxlint",
		"tailwindcss",
		"ts_ls",
	},
	automatic_enable = false,
})

require("mason-tool-installer").setup({
	ensure_installed = {
		"clang-format",
		"cmakelang",
		"cmake-language-server",
		"codelldb",
		"delve",
		"golangci-lint",
		"oxfmt",
		"prettier",
		"prettierd",
		"stylua",
	},
	run_on_start = true,
	start_delay = 3000,
	debounce_hours = 12,
})
