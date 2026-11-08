local M = {}

-- Kanagawa Wave as T3 Code shows it: the flat #1F1F28 background and
-- #223249 selection, with the syntax colours of the VS Code theme T3
-- imported it from. Same palette as ghostty/themes/t3-kanagawa.
M.palette = {
	bg = "#1f1f28",
	panel = "#2a2a37",
	panel_alt = "#363646",
	selection = "#223249",
	fg = "#dcd7ba",
	muted = "#727169",
	red = "#e46876",
	green = "#98bb6c",
	yellow = "#e6c384",
	orange = "#ffa066",
	pink = "#d27e99",
	blue = "#7e9cd8",
	magenta = "#957fb8",
	cyan = "#7fb4ca",
	aqua = "#7aa89f",
	white = "#edeef2",
}

local function hl(name, opts)
	vim.api.nvim_set_hl(0, name, opts)
end

function M.apply()
	local p = M.palette
	vim.o.termguicolors = true
	vim.g.colors_name = "t3-kanagawa"

	vim.g.terminal_color_0 = "#16161d"
	vim.g.terminal_color_1 = "#c34043"
	vim.g.terminal_color_2 = "#76946a"
	vim.g.terminal_color_3 = "#c0a36e"
	vim.g.terminal_color_4 = p.blue
	vim.g.terminal_color_5 = p.magenta
	vim.g.terminal_color_6 = "#6a9589"
	vim.g.terminal_color_7 = "#c8c093"
	vim.g.terminal_color_8 = p.muted
	vim.g.terminal_color_9 = "#e82424"
	vim.g.terminal_color_10 = p.green
	vim.g.terminal_color_11 = p.yellow
	vim.g.terminal_color_12 = p.cyan
	vim.g.terminal_color_13 = "#938aa9"
	vim.g.terminal_color_14 = p.aqua
	vim.g.terminal_color_15 = p.fg

	hl("Normal", { fg = p.fg, bg = "NONE" })
	hl("NormalNC", { fg = p.fg, bg = "NONE" })
	hl("SignColumn", { bg = "NONE" })
	hl("EndOfBuffer", { fg = p.bg, bg = "NONE" })
	hl("LineNr", { fg = p.muted, bg = "NONE" })
	hl("CursorLineNr", { fg = p.orange, bg = "NONE", bold = true })
	hl("CursorLine", { bg = p.panel })
	hl("Visual", { bg = p.selection })
	hl("Search", { fg = p.bg, bg = p.yellow })
	hl("IncSearch", { fg = p.bg, bg = p.orange })
	hl("NormalFloat", { fg = p.fg, bg = p.panel })
	hl("FloatBorder", { fg = p.panel_alt, bg = p.panel })
	hl("Pmenu", { fg = p.fg, bg = p.panel })
	hl("PmenuSel", { fg = p.fg, bg = p.selection })
	hl("PmenuSbar", { bg = p.panel_alt })
	hl("PmenuThumb", { bg = p.muted })
	hl("VertSplit", { fg = p.panel_alt, bg = "NONE" })
	hl("WinSeparator", { fg = p.panel_alt, bg = "NONE" })

	hl("Comment", { fg = p.muted, italic = true })
	hl("Constant", { fg = p.orange })
	hl("String", { fg = p.green })
	hl("Character", { fg = p.green })
	hl("Number", { fg = p.pink })
	hl("Boolean", { fg = p.orange })
	hl("Identifier", { fg = p.yellow })
	hl("Function", { fg = p.blue })
	hl("Statement", { fg = p.magenta })
	hl("Keyword", { fg = p.magenta })
	hl("PreProc", { fg = p.red })
	hl("Type", { fg = p.aqua })
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
