-- ============================================================
-- OPTIONS
-- Базові налаштування Neovim
-- ============================================================

local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.numberwidth = 4
opt.showmode = false
opt.laststatus = 3
opt.splitright = true
opt.splitbelow = true
opt.scrolloff = 8
opt.sidescrolloff = 8

opt.wrap = false
opt.breakindent = true

opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = true
opt.autoindent = true
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true

opt.swapfile = false
opt.backup = false
opt.writebackup = false
opt.undofile = true

opt.clipboard = "unnamedplus"
opt.wildmode = "longest:full,full"

opt.completeopt = {
    "menu",
    "menuone",
    "noselect",
}

opt.updatetime = 250
opt.timeoutlen = 300

opt.list = true
opt.listchars = {
    tab = "» ",
    trail = "·",
    nbsp = "␣",
}

opt.confirm = true
opt.termguicolors = true
