-- Gitsigns: Git change indicators in gutter
require("gitsigns").setup({
	signs = {
		add = { text = "+" },
		change = { text = "~" },
		delete = { text = "_" },
		topdelete = { text = "-" },
		changedelete = { text = "~" },
		untracked = { text = "|" },
	},
	signs_staged = {
		add = { text = "+" },
		change = { text = "~" },
		delete = { text = "_" },
		topdelete = { text = "-" },
		changedelete = { text = "~" },
	},
	current_line_blame = true, -- Toggle with <leader>hb
	current_line_blame_opts = {
		virt_text = true,
		virt_text_pos = "eol",
		delay = 500,
	},
	on_attach = function(bufnr)
		local gs = require("gitsigns")
		local map = vim.keymap.set

		-- Navigation
		map("n", "]h", function()
			if vim.wo.diff then
				vim.cmd.normal({ "]c", bang = true })
			else
				gs.nav_hunk("next")
			end
		end, { buffer = bufnr, desc = "Next hunk" })

		map("n", "[h", function()
			if vim.wo.diff then
				vim.cmd.normal({ "[c", bang = true })
			else
				gs.nav_hunk("prev")
			end
		end, { buffer = bufnr, desc = "Previous hunk" })

		-- Actions
		map("n", "<leader>hs", gs.stage_hunk, { buffer = bufnr, desc = "Stage hunk" })
		map("n", "<leader>hr", gs.reset_hunk, { buffer = bufnr, desc = "Reset hunk" })
		map("v", "<leader>hs", function()
			gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
		end, { buffer = bufnr, desc = "Stage hunk" })
		map("v", "<leader>hr", function()
			gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
		end, { buffer = bufnr, desc = "Reset hunk" })
		map("n", "<leader>hS", gs.stage_buffer, { buffer = bufnr, desc = "Stage buffer" })
		map("n", "<leader>hu", gs.undo_stage_hunk, { buffer = bufnr, desc = "Undo stage hunk" })
		map("n", "<leader>hR", gs.reset_buffer, { buffer = bufnr, desc = "Reset buffer" })
		map("n", "<leader>hp", gs.preview_hunk, { buffer = bufnr, desc = "Preview hunk" })
		map("n", "<leader>hb", gs.toggle_current_line_blame, { buffer = bufnr, desc = "Toggle line blame" })
		map("n", "<leader>hd", gs.diffthis, { buffer = bufnr, desc = "Diff this" })
		map("n", "<leader>hD", function()
			gs.diffthis("~")
		end, { buffer = bufnr, desc = "Diff this ~" })

		-- Text object
		map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { buffer = bufnr, desc = "Select hunk" })
	end,
})
