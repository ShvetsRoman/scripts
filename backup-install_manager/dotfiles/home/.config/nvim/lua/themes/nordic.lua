-- ============================================================
-- COLORSCHEME
-- Тема Nordic для Neovim
-- ============================================================
return {
	{
		"AlexvZyl/nordic.nvim",
		-- Завантажувати тему під час запуску Neovim
		lazy = false,
		-- Високий пріоритет завантаження теми
		priority = 1000,
		config = function()
			require("nordic").setup({
				-- ====================================================
				-- TRANSPARENCY
				-- Прозорість фону
				-- ====================================================
				transparent = {
					-- Прозорий фон основного редактора
					bg = false,
					-- Прозорий фон плаваючих вікон
					float = false,
				},
				-- ====================================================
				-- VISUAL SELECTION
				-- Налаштування виділення тексту
				-- ====================================================
				visual = {
					bold = false,
					bold_number = true,
					theme = "dark",
					blend = 0.85,
				},
				-- ====================================================
				-- TREESITTER CONTEXT
				-- Підсвічування контексту коду
				-- ====================================================
				ts_context = {
					dark_background = true,
				},
				-- ====================================================
				-- CUSTOM HIGHLIGHTS
				-- Додаткові налаштування підсвічування
				-- ====================================================
				on_highlight = function(highlights, _palette)
					-- Непрозорий фон Neovim, відмінний від стандартного фону Kitty.
					-- Не використовувати NONE для головної області редактора.
					highlights.Normal = vim.tbl_extend("force", highlights.Normal or {}, {
						bg = "#242933",
					})
					highlights.NormalNC = vim.tbl_extend("force", highlights.NormalNC or {}, {
						bg = "#242933",
					})
					-- Вимкнути курсив для всіх груп підсвічування
					for _, highlight in pairs(highlights) do
						highlight.italic = false
					end
					-- Підсвічування рядка під курсором
					highlights.CursorLine = {
						bg = "#2B323D",
					}
				end,
			})
			-- Застосувати тему Nordic
			require("nordic").load()
		end,
	},
}
