-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()

-- lua/configs/lspconfig.lua
local configs = require "nvchad.configs.lspconfig"

-- Отримуємо стандартні обробники NvChad
local on_attach = configs.on_attach
local on_init = configs.on_init
local capabilities = configs.capabilities

-- Масив серверів, які ми хочемо активувати
local servers = { "html", "cssls", "bashls" }

for _, lsp in ipairs(servers) do
  -- Новий синтаксис Neovim 0.11+: змінюємо параметри безпосередньо у vim.lsp.config
  if vim.lsp.config[lsp] then
    vim.lsp.config[lsp] = {
      -- Додаємо або розширюємо стандартні налаштування сервера
      cmd = vim.lsp.config[lsp].cmd,
      filetypes = vim.lsp.config[lsp].filetypes,
      root_markers = vim.lsp.config[lsp].root_markers,

      -- Передаємо функції зворотного виклику та capabilities від NvChad
      on_attach = on_attach,
      on_init = on_init,
      capabilities = capabilities,
    }

    -- Вмикаємо сервер через вбудований метод Neovim
    vim.lsp.enable(lsp)
  end
end
