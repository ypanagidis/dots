-- Show current directory in the winbar at the top
function _G.get_oil_winbar()
	local bufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
	local dir = require("oil").get_current_dir(bufnr)
	if dir then
		return vim.fn.fnamemodify(dir, ":~:.") -- Relative to cwd, or ~ for home
	else
		return vim.api.nvim_buf_get_name(0)
	end
end

require("oil").setup({
	default_file_explorer = true,
	win_options = {
		winbar = "%!v:lua.get_oil_winbar()",
	},
	delete_to_trash = false,
	skip_confirm_for_simple_edits = true,
	view_options = {
		show_hidden = true,
		natural_order = true,
	},
	float = {
		padding = 2,
		max_width = 90,
		max_height = 30,
	},
	keymaps = {
		["g?"] = "actions.show_help",
		["<CR>"] = "actions.select",
		["<C-s>"] = { "actions.select", opts = { vertical = true }, desc = "Open in vertical split" },
		["<C-h>"] = { "actions.select", opts = { horizontal = true }, desc = "Open in horizontal split" },
		["<C-t>"] = { "actions.select", opts = { tab = true }, desc = "Open in new tab" },
		["<C-p>"] = "actions.preview",
		["<C-c>"] = "actions.close",
		["<C-l>"] = "actions.refresh",
		["-"] = "actions.parent",
		["_"] = "actions.open_cwd",
		["`"] = "actions.cd",
		["~"] = { "actions.cd", opts = { scope = "tab" }, desc = "cd to home" },
		["gs"] = "actions.change_sort",
		["gx"] = "actions.open_external",
		["g."] = "actions.toggle_hidden",
		["g\\"] = "actions.toggle_trash",
	},
})

vim.keymap.set("n", "-", "<cmd>Oil<cr>", { desc = "Open parent directory" })
vim.keymap.set("n", "<leader>e", "<cmd>Oil --float<cr>", { desc = "Open file explorer (float)" })
