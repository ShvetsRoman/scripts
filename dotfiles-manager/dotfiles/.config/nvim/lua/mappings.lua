require "nvchad.mappings"

local map = vim.keymap.set

-- enter cmd mode with ";"
map("n", ";", ":", { desc = "CMD enter command mode" })

-- exit insert mode with "jk"
map("i", "jk", "<ESC>")

-- save using Ctrl+s
map({ "n", "i", "v" }, "<C-s>", "<cmd> :w <CR>")

-- Insert Line Below
map("n","<C-CR>","O<ESC>",{ desc = "Insert Insert line below UP" })
map("n", "<CR>", "o<ESC>", { desc = "Insert Insert line below" })

-- -- < > text
-- map("v", "<", "<gv", { desc = "Unindent and keep selection" })
-- map("v", ">", ">gv", { desc = "Indent and keep selection" })

-- Відкриває nvim-tree в директорії проекту
map("n", "<F1>", "<cmd> :NvimTreeToggle <CR>", { desc = "Nvim-tree" })
-- Відкриває nvim-tree в домашній директорії
map("n", "<F2>", function()
  local home = vim.fn.expand("~")
  require("nvim-tree.api").tree.open({ path = home })
end, { desc = "Open NvimTree in Home directory" })
-- Search Replace
map("n", "<F4>", ":%s///gc<LEFT><LEFT><LEFT><LEFT>", { desc = "Search Пошук та заміна" })
map("i", "<F4>", "<ESC>:%s///gc<LEFT><LEFT><LEFT><LEFT>", { desc = "Search Пошук та заміна" })

map("n", "<F5>", ":g/^$/d", { desc = "Видалення абсолютно всіх порожніх рядків" })
map("n", "<F6>", [[:%s/\n\{3,}/\r\r/g]], { desc = "Видалити зайві порожні рядки (залишиться тільки 1)" })

map("n", "<F8>", "<cmd> :NvCheatsheet <CR>", { desc = "Mappings" })
map("n", "<laeder> + <F8>", "<cmd> :Telescope keymaps <CR>", { desc = "Mappings" })

map("n", "<F9>", function()
  require("nvchad.themes").open()
end, { desc = "telescope nvchad themes" })

-- Mason install all
map("n", "<F11>", "<cmd> :MasonInstallAll <CR>", { desc = "Mason install all" })

-- Lazy sync
map("n", "<F12>", "<cmd> :Lazy sync <CR>", { desc = "Lazy sync" })

-- FZF
-- Переконуємося, що використовуємо функції fzf-lua
map("n", "<leader>ff", "<cmd>FzfLua files<CR>", { desc = "FZF Пошук файлів" })
map("n", "<leader>fw", "<cmd>FzfLua live_grep<CR>", { desc = "FZF Пошук тексту" })
map("n", "<leader>fb", "<cmd>FzfLua buffers<CR>", { desc = "FZF Буфери" })
map("n", "<leader>fo", "<cmd>FzfLua oldfiles<CR>", { desc = "FZF Історія файлів" })
map("n", "<leader>fh", "<cmd>FzfLua help_tags<CR>", { desc = "FZF Довідка Neovim" })
map("n", "<leader>fz", "<cmd>FzfLua current_buffer_fuzzy_find<CR>", { desc = "FZF Пошук у поточному файлі" })

-- LSP Навігація через FZF
-- Перейти до визначення (Definition) функції/змінної
map("n", "gd", "<cmd>FzfLua lsp_definitions<CR>", { desc = "FZF LSP Визначення" })
-- Знайти всі згадки/посилання (References) у проєкті
map("n", "gr", "<cmd>FzfLua lsp_references<CR>", { desc = "FZF LSP Посилання" })
-- Перейти до реалізації (Implementation) інтерфейсу
map("n", "gi", "<cmd>FzfLua lsp_implementations<CR>", { desc = "FZF LSP Реалізації" })
-- Перейти до визначення типу (Type Definition)
map("n", "gt", "<cmd>FzfLua lsp_typedefs<CR>", { desc = "FZF LSP Визначення типу" })
-- Показати список усіх помилок та попереджень (Diagnostics) у поточному файлі
map("n", "<leader>ld", "<cmd>FzfLua lsp_document_diagnostics<CR>", { desc = "FZF Помилки в документі" })
-- Показати список усіх помилок та попереджень (Diagnostics) по всьому проєкту
map("n", "<leader>lD", "<cmd>FzfLua lsp_workspace_diagnostics<CR>", { desc = "FZF Помилки в проєкті" })
-- Пошук символів (функцій, класів, змінних) у поточному файлі
map("n", "<leader>ls", "<cmd>FzfLua lsp_document_symbols<CR>", { desc = "FZF Символи документа" })
-- Пошук символів по всьому проєкту (Workspace Symbols)
map("n", "<leader>lS", "<cmd>FzfLua lsp_workspace_symbols<CR>", { desc = "FZF Символи проєкту" })
-- Швидкі дії LSP (Code Actions) — виправлення помилок, імпорти тощо
map({ "n", "v" }, "<leader>la", "<cmd>FzfLua lsp_code_actions<CR>", { desc = "FZF Дії коду (LSP)" })
