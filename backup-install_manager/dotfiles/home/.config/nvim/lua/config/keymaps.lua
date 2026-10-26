-- КЛАВІШІ
-- Базові клавіатурні скорочення

local map = vim.keymap.set

map("n", "L", "$", { desc = "Перейти на кінець рядка" })
map("n", "H", "0", { desc = "Перейти на початок рядка" })

map("n", "<leader>a", "GVgg", { desc = "Виділити весь текст в файлі" })
map("n", "<leader>ф", "GVgg", { desc = "Виділити весь текст в файлі" })

map("n", "<leader>/", "gcc", { remap = true, desc = "Коментувати або розкоментувати рядок" })
map("v", "<leader>/", "gc", { remap = true, desc = "Коментувати або розкоментувати виділення" })

map("n", ";", ":", { desc = "Відкрити командний рядок" })
map("n", "ж", ":", { desc = "Відкрити командний рядок" })

map("i", "jk", "<ESC>", { desc = "Вийти з режиму введення через jk" })

map({ "n", "i", "v" }, "<C-s>", "<cmd> :w <CR>", { desc = "Зберегти файл через Ctrl+S" })
map({ "n", "i", "v" }, "<C-і>", "<cmd> :w <CR>", { desc = "Зберегти файл через Ctrl+S" })

map("n", "<S-CR>", "O<ESC>", { desc = "Додати порожній рядок вище" })
map("n", "<CR>", "o<ESC>", { desc = "Додати порожній рядок нижче" })

map("n", "<F2>", function()
	Snacks.explorer()
end, {
	desc = "Файловий менеджер",
})
map("n", "<leader>у", function()
	Snacks.explorer()
end, {
	desc = "Файловий менеджер",
})

map("n", "<F4>", ":%s///gc<LEFT><LEFT><LEFT><LEFT>", { desc = "Пошук та заміна" })
map("i", "<F4>", "<ESC>:%s///gc<LEFT><LEFT><LEFT><LEFT>", { desc = "Пошук та заміна" })

map("n", "<F5>", ":g/^$/d", { desc = "Видалення абсолютно всіх порожніх рядків" })

map(
	"n",
	"<F6>",
	[[:%s/\n\{3,}/\r\r/g]],
	{ desc = "Видалити зайві порожні рядки (залишиться тільки 1)" }
)

map("n", "<F11>", "<cmd> :Mason <CR>", { desc = "Відкрити менеджер LSP Mason" })

map("n", "<F12>", "<cmd> :Lazy sync <CR>", { desc = "Синхронізувати плагіни Lazy" })

map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Прибрати підсвічування пошуку" })

map("n", "<leader>w", "<cmd>write<CR>", { desc = "Зберегти файл" })

map("n", "<leader>Q", "<cmd>qa<CR>", { desc = "Закрити Neovim" })

map("n", "<C-h>", "<C-w>h", { desc = "Перейти у вікно ліворуч" })
map("n", "<C-j>", "<C-w>j", { desc = "Перейти у вікно вниз" })
map("n", "<C-k>", "<C-w>k", { desc = "Перейти у вікно вгору" })
map("n", "<C-l>", "<C-w>l", { desc = "Перейти у вікно праворуч" })

map("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Збільшити висоту вікна" })
map("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Зменшити висоту вікна" })
map("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Зменшити ширину вікна" })
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Збільшити ширину вікна" })

map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Перемістити виділення вниз" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Перемістити виділення вгору" })
map("v", "<", "<gv", { desc = "Зменшити відступ" })
map("v", ",", "<gv", { desc = "Зменшити відступ" })
map("v", ">", ">gv", { desc = "Збільшити відступ" })
map("v", ".", ">gv", { desc = "Збільшити відступ" })

map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", {
	expr = true,
	silent = true,
})

map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", {
	expr = true,
	silent = true,
})

map("x", "p", [["_dP]], { desc = "Вставити без перезапису регістра" })
