-- COLORSCHEME
-- Catppuccin Mocha + Nordic background

return {
	{
		"catppuccin/nvim",

		name = "catppuccin",

		priority = 1000,
		lazy = false,

		opts = {
			flavour = "mocha",

			transparent_background = false,

			-- NORDIC-LIKE BACKGROUND
			color_overrides = {
				mocha = {
					-- Основний фон редактора
					base = "#242933",

					-- Другорядні поверхні
					mantle = "#212630",

					-- Найтемніші UI-елементи
					crust = "#191D24",
				},
			},

			integrations = {
				gitsigns = true,
				treesitter = true,
				mason = true,
				snacks = true,
				which_key = true,
			},
		},

		config = function(_, opts)
			require("catppuccin").setup(opts)

			vim.cmd.colorscheme("catppuccin-mocha")
		end,
	},
}
