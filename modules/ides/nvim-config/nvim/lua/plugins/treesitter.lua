require("nvim-treesitter").setup()

vim.api.nvim_create_autocmd("FileType", {
	callback = function()
		local ok = pcall(vim.treesitter.start)
		if not ok then
			return
		end

		vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end,
})
