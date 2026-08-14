require("snacks").setup({
	bigfile = { enabled = true },
	dashboard = {
		enabled = true,
		preset = {
			keys = {
				{ icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.picker.files()" },
				{ icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
				{ icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.picker.grep()" },
				{ icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.picker.recent()" },
				{ icon = " ", key = "c", desc = "Config", action = ":e $MYVIMRC" },
				{ icon = "󰒲 ", key = "q", desc = "Quit", action = ":qa" },
			},
			header = [[
                                                                   
      ████ ██████           █████      ██                    
     ███████████             █████                            
     █████████ ███████████████████ ███   ███████████  
    █████████  ███    █████████████ █████ ██████████████  
   █████████ ██████████ █████████ █████ █████ ████ █████  
 ███████████ ███    ███ █████████ █████ █████ ████ █████ 
██████  █████████████████████ ████ █████ █████ ████ ██████
      ]],
		},
		sections = {
			{ section = "header" },
			{ section = "keys", gap = 1, padding = 1 },
			{ icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1 },
		},
	},
	indent = { enabled = true },
	input = { enabled = true },
	dim = { enabled = true },
	lazygit = { enabled = true },
	notifier = { enabled = true },
	picker = {
		enabled = true,
		formatters = {
			file = {
				filename_first = true,  -- Show filename before path (easier to read)
				truncate = "left",      -- Truncate beginning of path, keep the important end
			},
		},
		sources = {
			-- For LSP sources, use vertical layout and hide the code line content
			lsp_references = {
				layout = { preset = "vertical" },
				transform = function(item)
					item.line = nil  -- Remove the code line from display
					return item
				end,
			},
			lsp_definitions = {
				layout = { preset = "vertical" },
				transform = function(item)
					item.line = nil
					return item
				end,
			},
			lsp_implementations = {
				layout = { preset = "vertical" },
				transform = function(item)
					item.line = nil
					return item
				end,
			},
			lsp_type_definitions = {
				layout = { preset = "vertical" },
				transform = function(item)
					item.line = nil
					return item
				end,
			},
			diagnostics = {
				layout = { preset = "vertical" },
			},
		},
		actions = {
			list_scroll_right = function(picker)
				if picker.list.win:valid() then
					vim.api.nvim_win_call(picker.list.win.win, function()
						vim.cmd("normal! 40zl")
					end)
				end
			end,
			list_scroll_left = function(picker)
				if picker.list.win:valid() then
					vim.api.nvim_win_call(picker.list.win.win, function()
						vim.cmd("normal! 40zh")
					end)
				end
			end,
		},
		win = {
			input = {
				keys = {
					["zl"] = { "list_scroll_right", mode = "n", desc = "Scroll list right" },
					["zh"] = { "list_scroll_left", mode = "n", desc = "Scroll list left" },
				},
			},
			list = {
				keys = {
					["zl"] = { "list_scroll_right", desc = "Scroll list right" },
					["zh"] = { "list_scroll_left", desc = "Scroll list left" },
				},
			},
		},
	},
	quickfile = { enabled = true },
	scope = { enabled = true },
	scroll = { enabled = true },
	toggle = { enabled = true },
	zoom = { enabled = true },
	statuscolumn = { enabled = true },
	words = { enabled = true },
})

local map = vim.keymap.set

-- Lazygit
map("n", "<leader>G", function()
	Snacks.lazygit()
end, { desc = "Lazygit" })

-- Terminal
map("n", "<leader>t", function()
	Snacks.terminal()
end, { desc = "Terminal" })

-- File pickers
map("n", "<leader>ff", function() Snacks.picker.files({ hidden = true }) end, { desc = "Find files" })
map("n", "<leader>fg", function() Snacks.picker.grep() end, { desc = "Grep" })
map("n", "<leader>fb", function() Snacks.picker.buffers() end, { desc = "Buffers" })
map("n", "<leader>fr", function() Snacks.picker.recent() end, { desc = "Recent files" })
map("n", "<leader>fw", function() Snacks.picker.grep_word() end, { desc = "Grep word under cursor" })

-- Git
map("n", "<leader>gc", function() Snacks.picker.git_log() end, { desc = "Git commits" })
map("n", "<leader>gs", function() Snacks.picker.git_status() end, { desc = "Git status" })
map("n", "<leader>gb", function() Snacks.picker.git_branches() end, { desc = "Git branches" })
map("n", "<leader>gd", function() Snacks.picker.git_diff() end, { desc = "Git diff" })

-- LSP
map("n", "<leader>fs", function() Snacks.picker.lsp_symbols() end, { desc = "Document symbols" })
map("n", "<leader>fS", function() Snacks.picker.lsp_workspace_symbols() end, { desc = "Workspace symbols" })
map("n", "<leader>fd", function() Snacks.picker.diagnostics() end, { desc = "Diagnostics" })

-- Search
map("n", "<leader>sh", function() Snacks.picker.help() end, { desc = "Help pages" })
map("n", "<leader>sk", function() Snacks.picker.keymaps() end, { desc = "Keymaps" })
map("n", "<leader>sc", function() Snacks.picker.commands() end, { desc = "Commands" })
map("n", "<leader>/", function() Snacks.picker.lines() end, { desc = "Search in buffer" })

-- Resume
map("n", "<leader><leader>", function() Snacks.picker.resume() end, { desc = "Resume last picker" })

-- UI Toggles (<leader>u) - LazyVim style
map("n", "<leader>ur", "<Cmd>nohlsearch<Bar>diffupdate<Bar>normal! <C-L><CR>", { desc = "Redraw / Clear hlsearch" })
map("n", "<leader>ui", vim.show_pos, { desc = "Inspect Pos" })
map("n", "<leader>uI", function()
	vim.treesitter.inspect_tree()
	vim.api.nvim_input("I")
end, { desc = "Inspect Tree" })

-- Snacks toggles
Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>us")
Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>uL")
Snacks.toggle.diagnostics():map("<leader>ud")
Snacks.toggle.line_number():map("<leader>ul")
Snacks.toggle.option("conceallevel", {
	off = 0,
	on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2,
	name = "Conceal Level",
}):map("<leader>uc")
Snacks.toggle({
	name = "Tabline",
	get = function()
		return vim.o.showtabline == 2
	end,
	set = function(state)
		vim.o.showtabline = state and 2 or 0
	end,
}):map("<leader>uA")
Snacks.toggle.treesitter():map("<leader>uT")
Snacks.toggle.option("background", { off = "light", on = "dark", name = "Dark Background" }):map("<leader>ub")
Snacks.toggle.dim():map("<leader>uD")
Snacks.toggle.indent():map("<leader>ug")
Snacks.toggle.scroll():map("<leader>uS")
Snacks.toggle.zoom():map("<leader>uZ")
Snacks.toggle.zoom():map("<leader>wm")

-- Inlay hints (if supported)
if vim.lsp.inlay_hint then
	Snacks.toggle.inlay_hints():map("<leader>uh")
end

-- Dismiss notifications
map("n", "<leader>un", function()
	Snacks.notifier.hide()
end, { desc = "Dismiss All Notifications" })

