local dap = require("dap")
local dapui = require("dapui")

dapui.setup()

dap.listeners.before.attach.dapui_config = function()
	dapui.open()
end
dap.listeners.before.launch.dapui_config = function()
	dapui.open()
end
dap.listeners.before.event_terminated.dapui_config = function()
	dapui.close()
end
dap.listeners.before.event_exited.dapui_config = function()
	dapui.close()
end

local codelldb = vim.fn.exepath("codelldb")
if codelldb == "" then
	codelldb = vim.fn.stdpath("data") .. "/mason/bin/codelldb"
end

dap.adapters.codelldb = {
	type = "server",
	port = "${port}",
	executable = {
		command = codelldb,
		args = { "--port", "${port}" },
	},
}

dap.configurations.c = {
	{
		name = "Launch executable",
		type = "codelldb",
		request = "launch",
		program = function()
			return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
		end,
		cwd = "${workspaceFolder}",
		stopOnEntry = false,
	},
}

dap.configurations.cpp = dap.configurations.c

local map = vim.keymap.set

map("n", "<leader>db", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
map("n", "<leader>dc", dap.continue, { desc = "Debug continue" })
map("n", "<leader>di", dap.step_into, { desc = "Debug step into" })
map("n", "<leader>do", dap.step_over, { desc = "Debug step over" })
map("n", "<leader>dO", dap.step_out, { desc = "Debug step out" })
map("n", "<leader>dr", dap.repl.open, { desc = "Debug REPL" })
map("n", "<leader>du", dapui.toggle, { desc = "Debug UI" })
map("n", "<leader>dx", dap.terminate, { desc = "Debug terminate" })
