-- Colorizer: Show color codes in their actual color
require("colorizer").setup({
	filetypes = {
		"css",
		"scss",
		"sass",
		"less",
		"html",
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
		"vue",
		"svelte",
		"lua",
		"conf",
		"toml",
		"yaml",
	},
	user_default_options = {
		RGB = true, -- #RGB hex codes
		RRGGBB = true, -- #RRGGBB hex codes
		names = false, -- "Name" codes like Blue (disabled for performance)
		RRGGBBAA = true, -- #RRGGBBAA hex codes
		AARRGGBB = false, -- 0xAARRGGBB hex codes
		rgb_fn = true, -- CSS rgb() and rgba() functions
		hsl_fn = true, -- CSS hsl() and hsla() functions
		css = true, -- Enable all CSS features
		css_fn = true, -- Enable all CSS functions
		mode = "background", -- "foreground" or "background" or "virtualtext"
		tailwind = true, -- Enable tailwind colors
		sass = { enable = true, parsers = { "css" } },
		virtualtext = "  ",
		always_update = false,
	},
	buftypes = {},
})
