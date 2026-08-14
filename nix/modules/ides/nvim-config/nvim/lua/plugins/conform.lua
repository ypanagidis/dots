local conform = require("conform")
local util = require("conform.util")

conform.setup({
	formatters_by_ft = {
		javascript = { "oxfmt", stop_after_first = true },
		javascriptreact = { "oxfmt", stop_after_first = true },
		typescript = { "oxfmt", stop_after_first = true },
		typescriptreact = { "oxfmt", stop_after_first = true },

		json = { "prettierd", "prettier", stop_after_first = true },
		jsonc = { "prettierd", "prettier", stop_after_first = true },
		html = { "prettierd", "prettier", stop_after_first = true },
		css = { "prettierd", "prettier", stop_after_first = true },
		scss = { "prettierd", "prettier", stop_after_first = true },
		markdown = { "prettierd", "prettier", stop_after_first = true },
		yaml = { "prettierd", "prettier", stop_after_first = true },
		graphql = { "prettierd", "prettier", stop_after_first = true },

		lua = { "stylua" },
		nix = { "nixfmt" },
		go = { "goimports", "gofumpt" },
		gomod = { "gofmt" },
		gowork = { "gofmt" },
		gotmpl = { "gofmt" },
	},

	formatters = {
		oxfmt = {
			command = "oxfmt",
			stdin = false,
			args = { "--write", "$FILENAME" },
			cwd = util.root_file({ ".oxfmtrc.json", "package.json", ".git" }),
		},
	},

	format_on_save = {
		timeout_ms = 3000,
		lsp_fallback = true,
	},
})
