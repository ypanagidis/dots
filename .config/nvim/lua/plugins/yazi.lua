require("yazi").setup({
	open_for_directories = false, -- Keep oil as default for directories
	floating_window_scaling_factor = 0.9,
})

vim.keymap.set("n", "<leader>y", "<cmd>Yazi<cr>", { desc = "Open Yazi" })
vim.keymap.set("n", "<leader>Y", "<cmd>Yazi cwd<cr>", { desc = "Open Yazi in cwd" })
