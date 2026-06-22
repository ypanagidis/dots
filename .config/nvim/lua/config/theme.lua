local M = {}

M.palette = {
	bg = "#1b1b1d",
	panel = "#242426",
	panel_alt = "#2d2d30",
	fg = "#d7d7d7",
	muted = "#8e8e93",
	red = "#ff5c57",
	green = "#5af078",
	yellow = "#ffd866",
	blue = "#45c8ff",
	magenta = "#ff40ff",
	cyan = "#45c8ff",
	white = "#ffffff",
}

local function hl(name, opts)
	vim.api.nvim_set_hl(0, name, opts)
end

function M.apply()
	local p = M.palette
	vim.o.termguicolors = true
	vim.g.colors_name = "mono-charcoal"

	vim.g.terminal_color_0 = p.bg
	vim.g.terminal_color_1 = p.red
	vim.g.terminal_color_2 = p.green
	vim.g.terminal_color_3 = p.yellow
	vim.g.terminal_color_4 = p.blue
	vim.g.terminal_color_5 = p.magenta
	vim.g.terminal_color_6 = p.cyan
	vim.g.terminal_color_7 = p.fg
	vim.g.terminal_color_8 = "#5f6368"
	vim.g.terminal_color_9 = "#ff6b66"
	vim.g.terminal_color_10 = "#69ff8a"
	vim.g.terminal_color_11 = "#ffe680"
	vim.g.terminal_color_12 = "#5ad4ff"
	vim.g.terminal_color_13 = "#ff66ff"
	vim.g.terminal_color_14 = "#5ad4ff"
	vim.g.terminal_color_15 = p.white

	hl("Normal", { fg = p.fg, bg = "NONE" })
	hl("NormalNC", { fg = p.fg, bg = "NONE" })
	hl("SignColumn", { bg = "NONE" })
	hl("EndOfBuffer", { fg = p.bg, bg = "NONE" })
	hl("LineNr", { fg = p.muted, bg = "NONE" })
	hl("CursorLineNr", { fg = p.yellow, bg = "NONE", bold = true })
	hl("CursorLine", { bg = p.panel })
	hl("Visual", { bg = "#3f3f44" })
	hl("Search", { fg = p.bg, bg = p.yellow })
	hl("IncSearch", { fg = p.bg, bg = p.magenta })
	hl("NormalFloat", { fg = p.fg, bg = p.panel })
	hl("FloatBorder", { fg = p.muted, bg = p.panel })
	hl("Pmenu", { fg = p.fg, bg = p.panel })
	hl("PmenuSel", { fg = p.bg, bg = p.blue })
	hl("PmenuSbar", { bg = p.panel_alt })
	hl("PmenuThumb", { bg = p.muted })
	hl("VertSplit", { fg = p.panel_alt, bg = "NONE" })
	hl("WinSeparator", { fg = p.panel_alt, bg = "NONE" })

	hl("Comment", { fg = p.muted, italic = true })
	hl("Constant", { fg = p.yellow })
	hl("String", { fg = p.green })
	hl("Character", { fg = p.green })
	hl("Number", { fg = p.yellow })
	hl("Boolean", { fg = p.yellow })
	hl("Identifier", { fg = p.fg })
	hl("Function", { fg = p.blue })
	hl("Statement", { fg = p.magenta })
	hl("Keyword", { fg = p.magenta })
	hl("PreProc", { fg = p.magenta })
	hl("Type", { fg = p.blue })
	hl("Special", { fg = p.cyan })
	hl("Underlined", { fg = p.blue, underline = true })
	hl("Error", { fg = p.red })
	hl("Todo", { fg = p.bg, bg = p.yellow, bold = true })

	hl("DiagnosticError", { fg = p.red })
	hl("DiagnosticWarn", { fg = p.yellow })
	hl("DiagnosticInfo", { fg = p.blue })
	hl("DiagnosticHint", { fg = p.cyan })
	hl("DiffAdd", { fg = p.green, bg = "NONE" })
	hl("DiffChange", { fg = p.yellow, bg = "NONE" })
	hl("DiffDelete", { fg = p.red, bg = "NONE" })
	hl("DiffText", { fg = p.blue, bg = p.panel })
end

return M
