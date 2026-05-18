-- LSP Configuration

local ts_root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" }
local tailwind_root_markers = {
	"tailwind.config.js",
	"tailwind.config.cjs",
	"tailwind.config.mjs",
	"tailwind.config.ts",
	"postcss.config.js",
	"postcss.config.cjs",
	"postcss.config.mjs",
	"postcss.config.ts",
}
local tailwind_packages = {
	["tailwindcss"] = true,
	["@tailwindcss/vite"] = true,
	["@tailwindcss/postcss"] = true,
}

local function get_ts_root(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	return vim.fs.root(filename, ts_root_markers)
end

local function has_local_tsgo(root)
	return root and vim.uv.fs_stat(root .. "/node_modules/.bin/tsgo") ~= nil
end

local function has_tailwind_dependency(dependencies)
	if type(dependencies) ~= "table" then
		return false
	end

	for package_name in pairs(tailwind_packages) do
		if dependencies[package_name] ~= nil then
			return true
		end
	end

	return false
end

local function package_json_has_tailwind(package_json_path)
	local ok, lines = pcall(vim.fn.readfile, package_json_path)
	if not ok then
		return false
	end

	local ok_json, package_json = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok_json or type(package_json) ~= "table" then
		return false
	end

	return has_tailwind_dependency(package_json.dependencies)
		or has_tailwind_dependency(package_json.devDependencies)
		or has_tailwind_dependency(package_json.peerDependencies)
		or has_tailwind_dependency(package_json.optionalDependencies)
end

local function get_tailwind_root(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local config_root = vim.fs.root(filename, tailwind_root_markers)
	if config_root then
		return config_root
	end

	local package_json_paths = vim.fs.find("package.json", {
		path = filename,
		upward = true,
		limit = 20,
	})

	for _, package_json_path in ipairs(package_json_paths) do
		if package_json_has_tailwind(package_json_path) then
			return vim.fs.dirname(package_json_path)
		end
	end
end

-- Configure tsgo with more memory
vim.lsp.config("tsgo", {
	root_dir = function(bufnr, on_dir)
		local root = get_ts_root(bufnr)
		if has_local_tsgo(root) then
			on_dir(root)
		end
	end,
	init_options = {
		maxTsServerMemory = 16384,
	},
	settings = {
		typescript = {
			inlayHints = {
				parameterNames = {
					enabled = "all",
					suppressWhenArgumentMatchesName = false,
				},
				parameterTypes = { enabled = true },
				variableTypes = { enabled = true },
				propertyDeclarationTypes = { enabled = true },
				functionLikeReturnTypes = { enabled = true },
				enumMemberValues = { enabled = true },
			},
		},
	},
})

vim.lsp.config("ts_ls", {
	root_dir = function(bufnr, on_dir)
		local root = get_ts_root(bufnr)
		if root and not has_local_tsgo(root) then
			on_dir(root)
		end
	end,
})

vim.lsp.config("oxlint", {
	cmd = { "oxlint", "--lsp" },
})

vim.lsp.config("gopls", {
	settings = {
		gopls = {
			gofumpt = true,
			staticcheck = true,
			analyses = {
				fieldalignment = true,
				nilness = true,
				shadow = true,
				unusedparams = true,
				unusedwrite = true,
			},
			hints = {
				assignVariableTypes = true,
				compositeLiteralFields = true,
				constantValues = true,
				functionTypeParameters = true,
				parameterNames = true,
				rangeVariableTypes = true,
			},
		},
	},
})

vim.lsp.config("tailwindcss", {
	-- Avoid nvim-lspconfig's Tailwind v4 `.git` fallback, which can start a
	-- second monorepo-root server for non-Tailwind packages.
	root_dir = function(bufnr, on_dir)
		local root = get_tailwind_root(bufnr)
		if root then
			on_dir(root)
		end
	end,
	filetypes = {
		"html",
		"css",
		"scss",
		"postcss",
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
		"mdx",
		"vue",
		"svelte",
	},
	settings = {
		tailwindCSS = {
			hovers = true,
			suggestions = true,
			colorDecorators = true,
			classFunctions = { "cn", "clsx", "cva", "tw", "twMerge" },
		},
	},
})

-- Enable servers (configs come from nvim-lspconfig)
vim.lsp.enable({
	"tsgo",
	"ts_ls",
	"oxlint",
	"gopls",
	"tailwindcss",
	"eslint",
	"prettier",
	"biome",
	-- Add more servers as needed:
	-- "lua_ls",
	-- "pyright",
	-- "rust_analyzer",
})

-- LSP keymaps on attach
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = function(args)
		local opts = { buffer = args.buf }

		-- Navigation (using Snacks picker for nice display)
		vim.keymap.set("n", "gd", function() Snacks.picker.lsp_definitions() end, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
		vim.keymap.set(
			"n",
			"gD",
			function() Snacks.picker.lsp_declarations() end,
			vim.tbl_extend("force", opts, { desc = "Go to declaration" })
		)
		vim.keymap.set(
			"n",
			"gy",
			function() Snacks.picker.lsp_type_definitions() end,
			vim.tbl_extend("force", opts, { desc = "Go to type definition" })
		)
		vim.keymap.set(
			"n",
			"gi",
			function() Snacks.picker.lsp_references() end,
			vim.tbl_extend("force", opts, { desc = "Go to references" })
		)
		vim.keymap.set("n", "gr", function() Snacks.picker.lsp_references() end, vim.tbl_extend("force", opts, { desc = "Find references" }))

		-- Info
		vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover" }))
		vim.keymap.set(
			"n",
			"<leader>k",
			vim.lsp.buf.signature_help,
			vim.tbl_extend("force", opts, { desc = "Signature help" })
		)

		-- Actions
		vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename" }))
		vim.keymap.set(
			{ "n", "v" },
			"<leader>ca",
			vim.lsp.buf.code_action,
			vim.tbl_extend("force", opts, { desc = "Code action" })
		)
		vim.keymap.set("n", "<leader>cf", function()
			vim.lsp.buf.format({ async = true })
		end, vim.tbl_extend("force", opts, { desc = "Format" }))

		-- Diagnostics
		vim.keymap.set(
			"n",
			"<leader>cd",
			vim.diagnostic.open_float,
			vim.tbl_extend("force", opts, { desc = "Line diagnostics" })
		)
		vim.keymap.set(
			"n",
			"[d",
			vim.diagnostic.goto_prev,
			vim.tbl_extend("force", opts, { desc = "Previous diagnostic" })
		)
		vim.keymap.set("n", "]d", vim.diagnostic.goto_next, vim.tbl_extend("force", opts, { desc = "Next diagnostic" }))
	end,
})

-- Diagnostic appearance
vim.diagnostic.config({
	virtual_text = {
		prefix = "●",
		spacing = 4,
	},
	signs = true,
	underline = true,
	update_in_insert = false,
	severity_sort = true,
	float = {
		border = "rounded",
		source = true,
	},
})
