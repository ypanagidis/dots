-- LSP Configuration

local ts_root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" }

-- One server per monorepo, not one per package: prefer the workspace root.
local ts_workspace_markers = { "pnpm-workspace.yaml" }

local function get_ts_root(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	return vim.fs.root(filename, ts_workspace_markers) or vim.fs.root(filename, ts_root_markers)
end

local function ts_major(root)
	local ok, lines = pcall(vim.fn.readfile, root .. "/node_modules/typescript/package.json")
	if not ok then
		return nil
	end
	local decoded, pkg = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decoded or type(pkg) ~= "table" or type(pkg.version) ~= "string" then
		return nil
	end
	return tonumber(pkg.version:match("^(%d+)"))
end

-- The project's own TypeScript 7 language server: the preview package's
-- `tsgo`, or stable TypeScript 7+, which ships the native server as `tsc`.
local function local_native_ts(root)
	if not root then
		return nil
	end
	local tsgo = root .. "/node_modules/.bin/tsgo"
	if vim.fn.executable(tsgo) == 1 then
		return tsgo
	end
	local tsc = root .. "/node_modules/.bin/tsc"
	local major = ts_major(root)
	if major and major >= 7 and vim.fn.executable(tsc) == 1 then
		return tsc
	end
	return nil
end

local function has_local_native_ts(root)
	return local_native_ts(root) ~= nil
end

-- TypeScript 7 native LSP. nvim-lspconfig ships this as `tsc` (the old `tsgo`
-- name is deprecated). Its default cmd prefers a binary called `tsc`, which in
-- a TypeScript 5/6 project rejects `--lsp`, so the server exits immediately.
-- Launch the project's own TypeScript 7 when it has one; projects on 5/6 get
-- ts_ls with their own tsserver instead.
vim.lsp.config("tsc", {
	cmd = function(dispatchers, config)
		local bin = local_native_ts(config and config.root_dir) or "tsgo"
		return vim.lsp.rpc.start({ bin, "--lsp", "--stdio" }, dispatchers)
	end,
	root_dir = function(bufnr, on_dir)
		local root = get_ts_root(bufnr)
		if has_local_native_ts(root) then
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
		if root and not has_local_native_ts(root) then
			on_dir(root)
		end
	end,
})

vim.lsp.config("oxlint", {
	cmd = { "oxlint", "--lsp" },
})

vim.lsp.config("gopls", {
	filetypes = { "go", "gomod", "gowork" },
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

vim.lsp.config("clangd", {
	cmd = {
		"clangd",
		"--background-index",
		"--clang-tidy",
		"--completion-style=detailed",
		"--header-insertion=never",
		"--fallback-style=llvm",
	},
	root_markers = {
		"compile_commands.json",
		"compile_flags.txt",
		".clangd",
		".git",
	},
})

-- Enable servers (configs come from nvim-lspconfig)
vim.lsp.enable({
	"tsc",
	"ts_ls",
	"oxlint",
	"gopls",
	"clangd",
	-- "tailwindcss",
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
