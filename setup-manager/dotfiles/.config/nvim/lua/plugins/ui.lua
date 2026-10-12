-- UI
-- Інтерфейс Neovim

return {
	{
		"nvim-tree/nvim-web-devicons",
		lazy = true,
		opts = {
			color_icons = true,
			default = true,
		},
	},

	{
		"nvim-lualine/lualine.nvim",

		event = "VeryLazy",

		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},

		opts = {
			options = {
				theme = "auto",

				icons_enabled = true,

				globalstatus = true,

				component_separators = {
					left = "│",
					right = "│",
				},

				section_separators = {
					left = "",
					right = "",
				},

				disabled_filetypes = {
					statusline = {},
					winbar = {},
				},
			},

			sections = {
				lualine_a = {
					"mode",
				},

				lualine_b = {
					"branch",
					"diff",
					"diagnostics",
				},

				lualine_c = {
					{
						"filename",
						path = 1,
					},
				},

				lualine_x = {
					"encoding",
					"fileformat",
					"filetype",
				},

				lualine_y = {
					"progress",
				},

				lualine_z = {
					"location",
				},
			},

			inactive_sections = {
				lualine_a = {},
				lualine_b = {},

				lualine_c = {
					"filename",
				},

				lualine_x = {
					"location",
				},

				lualine_y = {},
				lualine_z = {},
			},

			tabline = {},
			winbar = {},
			inactive_winbar = {},

			extensions = {
				"lazy",
				"man",
				"quickfix",
			},
		},
	},
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			preset = "helix",
			delay = 300,
			icons = {
				breadcrumb = "»",
				separator = "➜",
				group = "+",
			},
			win = {
				border = "rounded",
				padding = { 1, 2 },
			},
			layout = {
				width = { min = 20, max = 50 },
				spacing = 3,
			},
		},
		keys = {
			{
				"<leader>?",
				function()
					require("which-key").show({ global = false })
				end,
				desc = "Локальні клавіші",
			},
		},
		config = function(_, opts)
			local wk = require("which-key")
			wk.setup(opts)
			wk.add({
				{ "<leader>f", group = "Пошук" },
				{ "<leader>g", group = "Git" },
				{ "<leader>l", group = "LSP" },
				{ "<leader>b", group = "Буфери" },
				{ "<leader>u", group = "UI" },
			})
		end,
	},
}
