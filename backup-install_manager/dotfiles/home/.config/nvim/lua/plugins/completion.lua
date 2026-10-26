-- АВТОДОПОВНЕННЯ
-- blink.cmp

return {
	{
		"saghen/blink.cmp",

		version = "1.*",

		dependencies = {
			-- Готові сніпетів для багатьох мов
			"rafamadriz/friendly-snippets",
		},

		---@module "blink.cmp"
		---@type blink.cmp.Config
		opts = {
			-- КЛАВІШІ
			-- Enter приймає автодоповнення.
			-- Tab / Shift-Tab використовуються для сніпетів.
			keymap = {
				preset = "enter",

				-- Показати автодоповнення / documentation
				["<C-Space>"] = {
					"show",
					"show_documentation",
					"hide_documentation",
				},

				-- Наступний пункт
				["<C-n>"] = {
					"select_next",
					"fallback",
				},

				-- Попередній пункт
				["<C-p>"] = {
					"select_prev",
					"fallback",
				},

				-- Стрілки
				["<Down>"] = {
					"select_next",
					"fallback",
				},

				["<Up>"] = {
					"select_prev",
					"fallback",
				},

				-- Закрити автодоповнення
				["<C-e>"] = {
					"hide",
					"fallback",
				},

				-- Прокручування документації
				["<C-f>"] = {
					"scroll_documentation_down",
					"fallback",
				},

				["<C-b>"] = {
					"scroll_documentation_up",
					"fallback",
				},

				-- Snippets
				["<Tab>"] = {
					"snippet_forward",
					"fallback",
				},

				["<S-Tab>"] = {
					"snippet_backward",
					"fallback",
				},

				-- Сигнатура функції через Blink.cmp у режимі Insert
				["<C-k>"] = {
					"show_signature",
					"hide_signature",
					"fallback",
				},
			},

			-- ОФОРМЛЕННЯ
			appearance = {
				nerd_font_variant = "mono",
			},

			-- АВТОДОПОВНЕННЯ
			completion = {
				-- УМОВИ ВИКЛИКУ
				trigger = {
					-- Показувати автодоповнення під час введення
					show_on_keyword = true,

					-- Не запускати новий автодоповнення всередині сніпета
					show_in_snippet = false,
				},

				-- СПИСОК
				list = {
					selection = {
						-- Не вставляти перший елемент автоматично
						preselect = false,

						-- Не вставляти елемент до підтвердження
						auto_insert = false,
					},
				},

				-- МЕНЮ
				menu = {
					border = "rounded",

					max_height = 15,

					draw = {
						columns = {
							{
								"kind_icon",
							},

							{
								"label",
								"label_description",
								gap = 1,
							},

							{
								"source_name",
							},
						},
					},
				},

				-- ДОКУМЕНТАЦІЯ
				documentation = {
					auto_show = true,

					auto_show_delay_ms = 250,

					window = {
						border = "rounded",
					},
				},

				-- ПРИМАРНИЙ ТЕКСТ
				ghost_text = {
					enabled = false,
				},
			},

			-- ПІДКАЗКА СИГНАТУРИ
			signature = {
				enabled = true,

				window = {
					border = "rounded",
				},
			},

			-- ДЖЕРЕЛА
			sources = {
				default = {
					"lsp",
					"path",
					"snippets",
					"buffer",
				},

				providers = {
					-- LSP
					lsp = {
						name = "LSP",

						fallbacks = {},
					},

					-- PATH
					path = {
						name = "Path",
					},

					-- SNIPPETS
					snippets = {
						name = "Snippets",

						opts = {
							friendly_snippets = true,
						},
					},

					-- BUFFER
					buffer = {
						name = "Buffer",

						min_keyword_length = 3,
					},
				},
			},

			-- НЕЧІТКИЙ ПОШУК
			fuzzy = {
				implementation = "prefer_rust",
			},
		},

		opts_extend = {
			"sources.default",
		},
	},
}
