local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local output = vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"--branch=stable",
		lazyrepo,
		lazypath,
	})

	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ output, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = {
		{
			"nvim-lualine/lualine.nvim",
			priority = 1000,
			lazy = false,
			config = function()
				require("plugins.ui")
			end,
		},
		{
			"folke/snacks.nvim",
			priority = 1000,
			lazy = false,
			config = function()
				require("plugins.snacks")
			end,
		},
		{
			"mason-org/mason.nvim",
			lazy = false,
			dependencies = {
				"mason-org/mason-lspconfig.nvim",
				"WhoIsSethDaniel/mason-tool-installer.nvim",
				"neovim/nvim-lspconfig",
			},
			config = function()
				require("plugins.mason")
			end,
		},
		{
			"neovim/nvim-lspconfig",
			event = { "BufReadPre", "BufNewFile" },
			config = function()
				require("plugins.lsp")
			end,
		},
		{
			"j-hui/fidget.nvim",
			lazy = false,
			config = function()
				require("plugins.fidget")
			end,
		},
		{
			"stevearc/conform.nvim",
			event = { "BufWritePre", "BufReadPre", "BufNewFile" },
			config = function()
				require("plugins.conform")
			end,
		},
		{
			"saghen/blink.cmp",
			version = "1.*",
			event = "InsertEnter",
			config = function()
				require("plugins.blink")
			end,
		},
		{
			"nvim-treesitter/nvim-treesitter",
			lazy = false,
			build = ":TSUpdate",
			config = function()
				require("plugins.treesitter")
			end,
		},
		{
			"nvim-treesitter/nvim-treesitter-context",
			event = { "BufReadPost", "BufNewFile" },
			dependencies = { "nvim-treesitter/nvim-treesitter" },
			config = function()
				require("plugins.treesitter-context")
			end,
		},
		{
			"folke/noice.nvim",
			event = "VeryLazy",
			dependencies = {
				"MunifTanjim/nui.nvim",
				"rcarriga/nvim-notify",
			},
			config = function()
				require("plugins.noice")
			end,
		},
		{
			"echasnovski/mini.nvim",
			event = "VeryLazy",
			config = function()
				require("plugins.mini")
			end,
		},
		{
			"akinsho/bufferline.nvim",
			event = "VeryLazy",
			dependencies = { "nvim-tree/nvim-web-devicons" },
			config = function()
				require("plugins.bufferline")
			end,
		},
		{
			"stevearc/oil.nvim",
			cmd = "Oil",
			keys = {
				{ "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
				{ "<leader>e", "<cmd>Oil --float<cr>", desc = "Open file explorer (float)" },
			},
			dependencies = { "nvim-tree/nvim-web-devicons" },
			config = function()
				require("plugins.oil")
			end,
		},
		{
			"mikavilpas/yazi.nvim",
			cmd = "Yazi",
			keys = {
				{ "<leader>y", "<cmd>Yazi<cr>", desc = "Open Yazi" },
				{ "<leader>Y", "<cmd>Yazi cwd<cr>", desc = "Open Yazi in cwd" },
			},
			dependencies = { "nvim-lua/plenary.nvim" },
			config = function()
				require("plugins.yazi")
			end,
		},
		{
			"christoomey/vim-tmux-navigator",
			lazy = false,
			config = function()
				require("plugins.tmux")
			end,
		},
		{
			"folke/trouble.nvim",
			cmd = "Trouble",
			keys = {
				{ "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics" },
				{ "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics" },
				{ "<leader>xs", "<cmd>Trouble symbols toggle<cr>", desc = "Symbols" },
				{ "<leader>xr", "<cmd>Trouble lsp_references toggle<cr>", desc = "References" },
				{ "<leader>xq", "<cmd>Trouble quickfix toggle<cr>", desc = "Quickfix" },
				{ "<leader>xt", "<cmd>Trouble todo toggle<cr>", desc = "Todo (Trouble)" },
			},
			dependencies = { "nvim-tree/nvim-web-devicons" },
			config = function()
				require("plugins.trouble")
			end,
		},
		{
			"JoosepAlviste/nvim-ts-context-commentstring",
			event = { "BufReadPost", "BufNewFile" },
			dependencies = { "nvim-treesitter/nvim-treesitter" },
			config = function()
				require("plugins.ts-comments")
			end,
		},
		{
			"supermaven-inc/supermaven-nvim",
			event = "InsertEnter",
			config = function()
				require("plugins.supermaven")
			end,
		},
		{
			"folke/which-key.nvim",
			event = "VeryLazy",
			config = function()
				require("plugins.which-key")
			end,
		},
		{
			"mfussenegger/nvim-dap",
			dependencies = {
				"rcarriga/nvim-dap-ui",
				"nvim-neotest/nvim-nio",
			},
			config = function()
				require("plugins.dap")
			end,
		},
		{
			"lewis6991/gitsigns.nvim",
			event = { "BufReadPre", "BufNewFile" },
			config = function()
				require("plugins.gitsigns")
			end,
		},
		{
			"folke/todo-comments.nvim",
			event = { "BufReadPost", "BufNewFile" },
			dependencies = { "nvim-lua/plenary.nvim" },
			config = function()
				require("plugins.todo-comments")
			end,
		},
		{
			"catgoose/nvim-colorizer.lua",
			event = { "BufReadPost", "BufNewFile" },
			config = function()
				require("plugins.colorizer")
			end,
		},
		{
			"MeanderingProgrammer/render-markdown.nvim",
			ft = { "markdown" },
			dependencies = {
				"nvim-treesitter/nvim-treesitter",
				"nvim-tree/nvim-web-devicons",
			},
			config = function()
				require("plugins.markdown")
			end,
		},
		{
			"iamcco/markdown-preview.nvim",
			cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
			ft = { "markdown" },
			build = "cd app && npm install",
			config = function()
				require("plugins.markdown-preview")
			end,
		},
	},
	install = {
		colorscheme = { "mono-charcoal", "default" },
	},
	checker = {
		enabled = true,
		notify = false,
	},
	change_detection = {
		notify = false,
	},
	rocks = {
		enabled = false,
	},
})
