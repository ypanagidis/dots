local treesitter = require("nvim-treesitter")

local languages = {
	"bash",
	"c",
	"cmake",
	"css",
	"cpp",
	"go",
	"gomod",
	"gosum",
	"gowork",
	"graphql",
	"html",
	"javascript",
	"json",
	"lua",
	"luadoc",
	"make",
	"markdown",
	"markdown_inline",
	"nix",
	"query",
	"regex",
	"scss",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
	"yaml",
}

treesitter.setup({
	install_dir = vim.fn.stdpath("data") .. "/site",
})

local installed = {}
for _, lang in ipairs(treesitter.get_installed("parsers")) do
	installed[lang] = true
end

local missing = {}
for _, lang in ipairs(languages) do
	if not installed[lang] then
		table.insert(missing, lang)
	end
end

if #missing > 0 then
	treesitter.install(missing)
end

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("UserTreesitter", { clear = true }),
	pattern = languages,
	callback = function(args)
		pcall(vim.treesitter.start, args.buf)
		vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end,
})
