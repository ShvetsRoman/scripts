-- COLORSCHEME
-- Nordic

return {
	{
		"AlexvZyl/nordic.nvim",

		lazy = false,

		priority = 1000,

		config = function()
			require("nordic").setup({
				-- VISUAL SELECTION
				visual = {
					bold = false,
					bold_number = true,

					theme = "dark",

					blend = 0.85,
				},
				-- TREESITTER CONTEXT
				ts_context = {
					dark_background = true,
				},
				-- CUSTOM HIGHLIGHTS
				on_highlight = function(highlights, _palette)
					-- Не використовувати italic
					for _, highlight in pairs(highlights) do
						highlight.italic = false
					end
				end,
			})

			require("nordic").load()
		end,
	},
}
