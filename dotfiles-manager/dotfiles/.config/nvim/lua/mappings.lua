-- Завантажуємо стандартні клавіатурні скорочення NvChad
require "nvchad.mappings"

local map = vim.keymap.set

-- enter cmd mode with ";"
map("n", ";", ":", { desc = "CMD enter command mode" })
-- exit insert mode with "jk"
map("i", "jk", "<ESC>")
-- save using Ctrl+s
map({ "n", "i", "v" }, "<C-s>", "<cmd> :w <CR>")
-- Insert Line Below
map("n", "<C-CR>", "O<ESC>", { desc = "Insert Insert line below UP" })
map("n", "<CR>", "o<ESC>", { desc = "Insert Insert line below" })
-- Відкриває nvim-tree в директорії проекту
map("n", "<F1>", "<cmd> :NvimTreeToggle <CR>", { desc = "Nvim-tree" })
-- Відкриває nvim-tree в домашній директорії
map("n", "<F2>", function()
  local home = vim.fn.expand "~"
  require("nvim-tree.api").tree.open { path = home }
end, { desc = "Open NvimTree in Home directory" })
-- Search Replace
map("n", "<F4>", ":%s///gc<LEFT><LEFT><LEFT><LEFT>", { desc = "Search Пошук та заміна" })
map("i", "<F4>", "<ESC>:%s///gc<LEFT><LEFT><LEFT><LEFT>", { desc = "Search Пошук та заміна" })

map("n", "<F5>", ":g/^$/d", { desc = "Видалення абсолютно всіх порожніх рядків" })

map("n", "<F6>", [[:%s/\n\{3,}/\r\r/g]], { desc = "Видалити зайві порожні рядки (залишиться тільки 1)" })

map("n", "<F8>", "<cmd> :NvCheatsheet <CR>", { desc = "Mappings" })
map("n", "<laeder> + <F8>", "<cmd> :Telescope keymaps <CR>", { desc = "Mappings" })

map("n", "<F9>", function() require("nvchad.themes").open() end, { desc = "telescope nvchad themes" })
-- Mason install all
map("n", "<F11>", "<cmd> :MasonInstallAll <CR>", { desc = "Mason install all" })
-- Lazy sync
map("n", "<F12>", "<cmd> :Lazy sync <CR>", { desc = "Lazy sync" })

-- ПЕРЕМИКАННЯ МІЖ БУФЕРОМ ТА ЕКСПЛОРЕРОМ
-- Варіант А: Через Alt + h/j/k/l (Рекомендовано)
map("n", "<A-h>", "<C-w>h", { desc = "Перейти ліворуч (в експлорер)" })
map("n", "<A-l>", "<C-w>l", { desc = "Перейти праворуч (в код)" })
map("n", "<A-j>", "<C-w>j", { desc = "Перейти вниз" })
map("n", "<A-k>", "<C-w>k", { desc = "Перейти вгору" })
-- Варіант Б: Через Alt + Стрілочки
map("n", "<A-Left>", "<C-w>h", { desc = "Перейти ліворуч (в експлорер)" })
map("n", "<A-Right>", "<C-w>l", { desc = "Перейти праворуч (в код)" })
map("n", "<A-Down>", "<C-w>j", { desc = "Перейти вниз" })
map("n", "<A-Up>", "<C-w>k", { desc = "Перейти вгору" })

-- FZF
-- Переконуємося, що використовуємо функції fzf-lua
-- map("n", "<leader>ff", "<cmd>FzfLua files<CR>", { desc = "FZF Пошук файлів" })
-- map("n", "<leader>fw", "<cmd>FzfLua live_grep<CR>", { desc = "FZF Пошук тексту" })
-- map("n", "<leader>fb", "<cmd>FzfLua buffers<CR>", { desc = "FZF Буфери" })
-- map("n", "<leader>fo", "<cmd>FzfLua oldfiles<CR>", { desc = "FZF Історія файлів" })
-- map("n", "<leader>fh", "<cmd>FzfLua help_tags<CR>", { desc = "FZF Довідка Neovim" })
-- map("n", "<leader>fz", "<cmd>FzfLua current_buffer_fuzzy_find<CR>", { desc = "FZF Пошук у поточному файлі" })

-- LSP Навігація через FZF
-- Перейти до визначення (Definition) функції/змінної
-- map("n", "gd", "<cmd>FzfLua lsp_definitions<CR>", { desc = "FZF LSP Визначення" })
-- -- Знайти всі згадки/посилання (References) у проєкті
-- map("n", "gr", "<cmd>FzfLua lsp_references<CR>", { desc = "FZF LSP Посилання" })
-- -- Перейти до реалізації (Implementation) інтерфейсу
-- map("n", "gi", "<cmd>FzfLua lsp_implementations<CR>", { desc = "FZF LSP Реалізації" })
-- -- Перейти до визначення типу (Type Definition)
-- map("n", "gt", "<cmd>FzfLua lsp_typedefs<CR>", { desc = "FZF LSP Визначення типу" })
-- -- Показати список усіх помилок та попереджень (Diagnostics) у поточному файлі
-- map("n", "<leader>ld", "<cmd>FzfLua lsp_document_diagnostics<CR>", { desc = "FZF Помилки в документі" })
-- -- Показати список усіх помилок та попереджень (Diagnostics) по всьому проєкту
-- map("n", "<leader>lD", "<cmd>FzfLua lsp_workspace_diagnostics<CR>", { desc = "FZF Помилки в проєкті" })
-- -- Пошук символів (функцій, класів, змінних) у поточному файлі
-- map("n", "<leader>ls", "<cmd>FzfLua lsp_document_symbols<CR>", { desc = "FZF Символи документа" })
-- -- Пошук символів по всьому проєкту (Workspace Symbols)
-- map("n", "<leader>lS", "<cmd>FzfLua lsp_workspace_symbols<CR>", { desc = "FZF Символи проєкту" })
-- -- Швидкі дії LSP (Code Actions) — виправлення помилок, імпорти тощо
-- map({ "n", "v" }, "<leader>la", "<cmd>FzfLua lsp_code_actions<CR>", { desc = "FZF Дії коду (LSP)" })

-- ============================================================
-- SNACKS: PICKER
-- ============================================================
-- Розумний пошук файлів, буферів та недавніх файлів
map("n", "<leader><space>", function()
    Snacks.picker.smart()
end, {
    desc = "Розумний пошук",
})
-- Пошук файлів у поточному проєкті
map("n", "<leader>ff", function()
    Snacks.picker.files()
end, {
    desc = "Знайти файли",
})
-- Пошук тексту через grep
map("n", "<leader>fw", function()
    Snacks.picker.grep()
end, {
    desc = "Пошук тексту",
})
-- Пошук серед відкритих буферів
map("n", "<leader>fb", function()
    Snacks.picker.buffers()
end, {
    desc = "Знайти буфер",
})
-- Недавно відкриті файли
map("n", "<leader>fo", function()
    Snacks.picker.recent()
end, {
    desc = "Недавні файли",
})
-- Пошук у документації Neovim
map("n", "<leader>fh", function()
    Snacks.picker.help()
end, {
    desc = "Довідка",
})
-- Показати всі клавіатурні скорочення
map("n", "<leader>fk", function()
    Snacks.picker.keymaps()
end, {
    desc = "Клавіатурні скорочення",
})
-- Пошук файлів конфігурації Neovim
map("n", "<leader>fc", function()
    Snacks.picker.files({
        cwd = vim.fn.stdpath "config",
    })
end, {
    desc = "Файли конфігурації Neovim",
})
-- ============================================================
-- SNACKS: ПОШУК
-- ============================================================
-- Пошук слова під курсором
map("n", "<leader>sw", function()
    Snacks.picker.grep_word()
end, {
    desc = "Пошук слова під курсором",
})
-- Пошук виділеного тексту
map("x", "<leader>sw", function()
    Snacks.picker.grep_word()
end, {
    desc = "Пошук виділеного тексту",
})
-- Пошук рядка у поточному буфері
map("n", "<leader>sl", function()
    Snacks.picker.lines()
end, {
    desc = "Пошук у поточному файлі",
})
-- Пошук тексту у відкритих буферах
map("n", "<leader>sb", function()
    Snacks.picker.grep_buffers()
end, {
    desc = "Пошук у відкритих буферах",
})
-- ============================================================
-- SNACKS: FILE EXPLORER
-- ============================================================
-- Відкрити файловий менеджер Snacks
map("n", "<leader>e", function()
    Snacks.explorer()
end, {
    desc = "Файловий менеджер",
})
-- Аналог стандартного <C-n> NvChad
map("n", "<C-n>", function()
    Snacks.explorer()
end, {
    desc = "Відкрити файловий менеджер",
})
-- Завжди відкриватиме Explorer від кореня поточного робочого каталогу.
map("n", "<leader>fe", function()
    Snacks.explorer({
        cwd = vim.fn.getcwd(),
    })
end, {
    desc = "Файловий менеджер",
})
-- ============================================================
-- SNACKS: GIT
-- ============================================================
-- Відкрити LazyGit
map("n", "<leader>gg", function()
    Snacks.lazygit()
end, {
    desc = "LazyGit",
})
-- Показати Git-гілки
map("n", "<leader>gb", function()
    Snacks.picker.git_branches()
end, {
    desc = "Git гілки",
})
-- Показати Git-журнал
map("n", "<leader>gl", function()
    Snacks.picker.git_log()
end, {
    desc = "Git журнал",
})
-- Показати змінені Git-файли
map("n", "<leader>gs", function()
    Snacks.picker.git_status()
end, {
    desc = "Git статус",
})
-- Показати Git commits
map("n", "<leader>gc", function()
    Snacks.picker.git_log()
end, {
    desc = "Git commits",
})
-- ============================================================
-- SNACKS: LSP
-- ============================================================
-- Перейти до визначення символу
map("n", "gd", function()
    Snacks.picker.lsp_definitions()
end, {
    desc = "Перейти до визначення",
})
-- Перейти до декларації
map("n", "gD", function()
    Snacks.picker.lsp_declarations()
end, {
    desc = "Перейти до декларації",
})
-- Знайти всі використання символу
map("n", "gr", function()
    Snacks.picker.lsp_references()
end, {
    nowait = true,
    desc = "Знайти використання",
})
-- Перейти до реалізації
map("n", "gI", function()
    Snacks.picker.lsp_implementations()
end, {
    desc = "Перейти до реалізації",
})
-- Перейти до визначення типу
map("n", "gy", function()
    Snacks.picker.lsp_type_definitions()
end, {
    desc = "Перейти до визначення типу",
})
-- Символи поточного документа
map("n", "<leader>ss", function()
    Snacks.picker.lsp_symbols()
end, {
    desc = "Символи документа",
})
-- Символи всього workspace
map("n", "<leader>sS", function()
    Snacks.picker.lsp_workspace_symbols()
end, {
    desc = "Символи робочого простору",
})
-- ============================================================
-- SNACKS: TERMINAL
-- ============================================================
-- Відкрити або приховати terminal
map("n", "<leader>tt", function()
    Snacks.terminal()
end, {
    desc = "Термінал",
})
-- Швидке відкриття terminal через Ctrl + /
map({ "n", "t" }, "<C-/>", function()
    Snacks.terminal()
end, {
    desc = "Показати або приховати термінал",
})
-- ============================================================
-- SNACKS: СПОВІЩЕННЯ
-- ============================================================
-- Показати історію сповіщень
map("n", "<leader>nh", function()
    Snacks.notifier.show_history()
end, {
    desc = "Історія сповіщень",
})
-- Приховати всі активні сповіщення
map("n", "<leader>nd", function()
    Snacks.notifier.hide()
end, {
    desc = "Приховати сповіщення",
})
-- ============================================================
-- SNACKS: SCRATCH BUFFER
-- ============================================================
-- Відкрити тимчасовий scratch-буфер
map("n", "<leader>.", function()
    Snacks.scratch()
end, {
    desc = "Scratch буфер",
})
-- Вибрати один із scratch-буферів
map("n", "<leader>S", function()
    Snacks.scratch.select()
end, {
    desc = "Вибрати Scratch буфер",
})
-- ============================================================
-- SNACKS: ZEN MODE
-- ============================================================
-- Увімкнути або вимкнути режим концентрації
map("n", "<leader>z", function()
    Snacks.zen()
end, {
    desc = "Zen режим",
})
-- ============================================================
-- SNACKS: НАВІГАЦІЯ ПО LSP REFERENCES
-- ============================================================
-- Перейти до наступного використання символу
map("n", "]]", function()
    Snacks.words.jump(vim.v.count1)
end, {
    desc = "Наступне використання",
})
-- Перейти до попереднього використання символу
map("n", "[[", function()
    Snacks.words.jump(-vim.v.count1)
end, {
    desc = "Попереднє використання",
})
-- ============================================================
-- SNACKS: ІСТОРІЯ
-- ============================================================
-- Історія виконаних команд
map("n", "<leader>:", function()
    Snacks.picker.command_history()
end, {
    desc = "Історія команд",
})
-- Історія пошуку
map("n", "<leader>/", function()
    Snacks.picker.search_history()
end, {
    desc = "Історія пошуку",
})
-- ============================================================
-- SNACKS: MARKS / JUMPS / QUICKFIX
-- ============================================================
-- Показати marks
map("n", "<leader>ma", function()
    Snacks.picker.marks()
end, {
    desc = "Marks",
})
-- Показати список переходів
map("n", "<leader>fj", function()
    Snacks.picker.jumps()
end, {
    desc = "Історія переходів",
})
-- Показати Quickfix
map("n", "<leader>fq", function()
    Snacks.picker.qflist()
end, {
    desc = "Quickfix список",
})
