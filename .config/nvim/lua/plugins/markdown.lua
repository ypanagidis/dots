-- Render markdown with styled headings, lists, and code blocks
require("render-markdown").setup({
	file_types = { "markdown" },
})

vim.keymap.set("n", "<leader>um", "<cmd>RenderMarkdown toggle<cr>", { desc = "Toggle markdown render" })
