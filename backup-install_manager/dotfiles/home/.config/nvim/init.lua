-- NEOVIM
-- Персональна конфігурація Neovim 0.12

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("config.options")
require("config.filetypes")
require("config.lanmap")
require("config.keymaps")
require("config.autocmds")
require("config.lazy")

-- Єдина палітра для плаваючих вікон після завантаження Lazy.
require("config.float_appearance").setup()
