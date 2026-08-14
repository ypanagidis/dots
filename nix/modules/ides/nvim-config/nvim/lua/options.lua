-- Leader
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Line numbers
vim.o.number = true
vim.o.relativenumber = true
vim.o.signcolumn = "yes"

-- Tabs & indentation
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.softtabstop = 2
vim.o.expandtab = true
vim.o.smartindent = true

-- Search
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.hlsearch = true
vim.o.incsearch = true

-- Appearance
vim.o.termguicolors = true
vim.o.cursorline = true
vim.o.linespace = 10
vim.o.scrolloff = 8
vim.o.sidescrolloff = 8

-- Behavior
vim.o.clipboard = "unnamedplus"
vim.o.mouse = "a"
vim.o.updatetime = 300
vim.o.timeoutlen = 500
vim.o.splitright = true
vim.o.splitbelow = true
vim.o.wrap = false
vim.o.swapfile = false
vim.o.backup = false
vim.o.undofile = true

-- Completion
vim.o.completeopt = "menu,menuone,noselect"
