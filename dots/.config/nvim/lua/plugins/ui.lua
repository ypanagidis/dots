vim.cmd("colorscheme mono-charcoal")
local palette = require("config.theme").palette

-- Lualine
require("lualine").setup({
	options = {
		theme = {
			normal = {
				a = { fg = palette.bg, bg = palette.blue, gui = "bold" },
				b = { fg = palette.fg, bg = palette.panel },
				c = { fg = palette.fg, bg = "NONE" },
			},
			insert = {
				a = { fg = palette.bg, bg = palette.green, gui = "bold" },
				b = { fg = palette.fg, bg = palette.panel },
				c = { fg = palette.fg, bg = "NONE" },
			},
			visual = {
				a = { fg = palette.bg, bg = palette.magenta, gui = "bold" },
				b = { fg = palette.fg, bg = palette.panel },
				c = { fg = palette.fg, bg = "NONE" },
			},
			replace = {
				a = { fg = palette.bg, bg = palette.red, gui = "bold" },
				b = { fg = palette.fg, bg = palette.panel },
				c = { fg = palette.fg, bg = "NONE" },
			},
			command = {
				a = { fg = palette.bg, bg = palette.yellow, gui = "bold" },
				b = { fg = palette.fg, bg = palette.panel },
				c = { fg = palette.fg, bg = "NONE" },
			},
			inactive = {
				a = { fg = palette.muted, bg = "NONE" },
				b = { fg = palette.muted, bg = "NONE" },
				c = { fg = palette.muted, bg = "NONE" },
			},
		},
		component_separators = { left = "", right = "" },
		section_separators = { left = "", right = "" },
		globalstatus = true,
	},
	sections = {
		lualine_a = { "mode" },
		lualine_b = { "branch", "diff", "diagnostics" },
		lualine_c = { { "filename", path = 1 } },
		lualine_x = { "encoding", "fileformat", "filetype" },
		lualine_y = { "progress" },
		lualine_z = { "location" },
	},
	inactive_sections = {
		lualine_a = {},
		lualine_b = {},
		lualine_c = { "filename" },
		lualine_x = { "location" },
		lualine_y = {},
		lualine_z = {},
	},
})
