-- ============================================================
-- SNACKS — СУЧАСНЕ ОФОРМЛЕННЯ NORDIC
-- Провідник + Пошук + Пошук тексту + Поле вводу
--
-- Зміни:
--   • Прибрано заголовок Explorer із зовнішньої рамки
--   • Єдиний фон для всього плаваючого вікна
--   • Збережено контрастні рамки та заголовки
--   • Збережено всі клавіші та функції
-- ============================================================

-- ============================================================
-- РОЗМІРИ
-- ============================================================

-- Загальна ширина плаваючого вікна
local picker_width = 0.88

-- Загальна висота плаваючого вікна
local picker_height = 0.80

-- Ширина лівої панелі
local list_width = 0.36

-- ============================================================
-- СПІЛЬНЕ КОМПОНУВАННЯ ВІКОН ПОШУКУ
-- ============================================================

local picker_layout = {
	preview = true,

	layout = {
		box = "vertical",

		-- Розміри головного вікна
		width = picker_width,
		height = picker_height,

		-- Не затемнювати редактор
		backdrop = false,

		-- Зовнішня рамка
		border = "rounded",

		-- Заголовок головної рамки не задаємо.
		-- Напис Explorer більше не відображатиметься.

		-- ----------------------------------------------------
		-- ПОШУК
		-- ----------------------------------------------------

		{
			win = "input",

			height = 1,

			border = "rounded",

			title = " Пошук ",
			title_pos = "center",
		},

		-- ----------------------------------------------------
		-- СПИСОК + PREVIEW
		-- ----------------------------------------------------

		{
			box = "horizontal",

			-- Ліва панель
			{
				win = "list",

				width = list_width,

				border = "rounded",

				title = " 󰉋 Результати ",
				title_pos = "center",
			},

			-- Права панель
			{
				win = "preview",

				border = "rounded",

				title = " {preview:Перегляд} ",
				title_pos = "center",
			},
		},
	},
}

-- ============================================================
-- КОМПОНУВАННЯ ПРОВІДНИКА
-- ============================================================

local explorer_layout = {
	-- Preview увімкнений за замовчуванням
	preview = true,

	-- Спільна геометрія
	layout = vim.deepcopy(picker_layout.layout),
}

-- ============================================================
-- SNACKS
-- ============================================================

return {
	{
		"folke/snacks.nvim",

		priority = 1000,
		lazy = false,

		---@type snacks.Config
		opts = {
			-- =================================================
			-- EXPLORER
			-- =================================================

			explorer = {
				enabled = true,

				-- Замінити стандартний netrw
				replace_netrw = true,

				-- Використовувати системний кошик
				trash = true,
			},

			-- =================================================
			-- ВІКНА ПОШУКУ
			-- =================================================

			picker = {
				enabled = true,

				ui_select = true,

				-- Початковий фокус на полі пошуку
				focus = "input",

				-- Спільний дизайн Picker
				layout = picker_layout,

				matcher = {
					fuzzy = true,
					smartcase = true,
					ignorecase = true,
					filename_bonus = true,
					file_pos = true,
					cwd_bonus = true,
					frecency = true,
					history_bonus = true,
				},

				-- =============================================
				-- КЛАВІШІ PICKER
				-- =============================================

				win = {
					input = {
						keys = {
							["<Esc>"] = {
								"cancel",
								mode = { "n", "i" },
							},

							["<C-j>"] = {
								"list_down",
								mode = { "n", "i" },
							},

							["<C-k>"] = {
								"list_up",
								mode = { "n", "i" },
							},

							["<C-d>"] = {
								"list_scroll_down",
								mode = { "n", "i" },
							},

							["<C-u>"] = {
								"list_scroll_up",
								mode = { "n", "i" },
							},

							["<C-f>"] = {
								"preview_scroll_down",
								mode = { "n", "i" },
							},

							["<C-b>"] = {
								"preview_scroll_up",
								mode = { "n", "i" },
							},

							["<CR>"] = {
								"confirm",
								mode = { "n", "i" },
							},

							["<C-v>"] = {
								"edit_vsplit",
								mode = { "n", "i" },
							},

							["<C-s>"] = {
								"edit_split",
								mode = { "n", "i" },
							},

							["<C-t>"] = {
								"tab",
								mode = { "n", "i" },
							},

							["<A-p>"] = {
								"toggle_preview",
								mode = { "n", "i" },
							},
						},
					},

					list = {
						keys = {
							["<Esc>"] = "cancel",
							["q"] = "cancel",

							["j"] = "list_down",
							["k"] = "list_up",

							["<CR>"] = "confirm",

							["<C-v>"] = "edit_vsplit",
							["<C-s>"] = "edit_split",
							["<C-t>"] = "tab",

							["<A-p>"] = "toggle_preview",
						},
					},

					preview = {
						keys = {
							["<Esc>"] = "cancel",
							["q"] = "cancel",
						},
					},
				},

				-- =============================================
				-- ДЖЕРЕЛА PICKER
				-- =============================================

				sources = {
					-- =========================================
					-- EXPLORER
					-- =========================================

					explorer = {
						title = "Провідник",

						-- Фокус на списку файлів
						focus = "list",

						layout = explorer_layout,

						-- Закривати після відкриття файлу
						auto_close = true,

						jump = {
							close = true,
						},

						-- Приховані файли
						hidden = true,
						ignored = false,

						-- Відстежувати відкритий файл
						follow_file = true,

						-- Дерево директорій
						tree = true,
						watch = true,

						-- Діагностика
						diagnostics = true,
						diagnostics_open = false,

						-- Статуси Git
						git_status = true,
						git_status_open = false,
						git_untracked = true,

						-- Сортування
						sort = {
							fields = { "sort" },
						},

						matcher = {
							sort_empty = false,
							fuzzy = false,
						},

						formatters = {
							file = {
								filename_only = true,
							},

							severity = {
								pos = "right",
							},
						},

						-- =====================================
						-- КЛАВІШІ EXPLORER
						-- =====================================

						win = {
							list = {
								keys = {
									-- -------------------------
									-- НАВІГАЦІЯ
									-- -------------------------

									["<CR>"] = "confirm",

									["<Right>"] = "confirm",
									["l"] = "confirm",

									["<Left>"] = "explorer_close",
									["h"] = "explorer_close",

									["<BS>"] = "explorer_up",

									-- -------------------------
									-- СТВОРИТИ
									-- -------------------------

									["a"] = "explorer_add",

									-- -------------------------
									-- ПЕРЕЙМЕНУВАТИ
									-- -------------------------

									["r"] = "explorer_rename",

									-- -------------------------
									-- ПЕРЕМІСТИТИ
									-- -------------------------

									["m"] = "explorer_move",
									["x"] = "explorer_move",

									-- -------------------------
									-- КОПІЮВАТИ
									-- -------------------------

									["c"] = "explorer_copy",

									-- -------------------------
									-- ВИДАЛИТИ
									-- -------------------------

									["d"] = "explorer_del",

									-- -------------------------
									-- YANK
									-- -------------------------

									["y"] = {
										"explorer_yank",
										mode = { "n", "x" },
									},

									-- -------------------------
									-- PASTE
									-- -------------------------

									["p"] = "explorer_paste",

									-- -------------------------
									-- ОНОВИТИ
									-- -------------------------

									["u"] = "explorer_update",

									-- -------------------------
									-- СИСТЕМНЕ ВІДКРИТТЯ
									-- -------------------------

									["o"] = "explorer_open",

									-- -------------------------
									-- ПОТОЧНИЙ КАТАЛОГ
									-- -------------------------

									["."] = "explorer_focus",

									-- -------------------------
									-- ПРИХОВАНІ ФАЙЛИ
									-- -------------------------

									["H"] = "toggle_hidden",
									["I"] = "toggle_ignored",

									-- -------------------------
									-- ЗГОРНУТИ ВСЕ ДЕРЕВО
									-- -------------------------

									["Z"] = "explorer_close_all",

									-- -------------------------
									-- ПОПЕРЕДНІЙ ПЕРЕГЛЯД
									-- -------------------------

									["P"] = "toggle_preview",

									-- -------------------------
									-- ВИБІР ФАЙЛІВ
									-- -------------------------

									["<Tab>"] = "select_and_next",
								},
							},
						},
					},

					-- =========================================
					-- SMART SEARCH
					-- =========================================

					smart = {
						title = "Розумний пошук",
						layout = picker_layout,
					},

					-- =========================================
					-- ПОШУК ФАЙЛІВ
					-- =========================================

					files = {
						title = "Пошук файлів",
						layout = picker_layout,
						hidden = true,
					},

					-- =========================================
					-- ПОШУК ЗА ВМІСТОМ
					-- =========================================

					grep = {
						title = "Пошук за вмістом",
						layout = picker_layout,
						hidden = true,
					},

					-- =========================================
					-- НЕЩОДАВНІ ФАЙЛИ
					-- =========================================

					recent = {
						title = "Нещодавні файли",
						layout = picker_layout,
					},

					-- =========================================
					-- БУФЕРИ
					-- =========================================

					buffers = {
						title = "Буфери",
						layout = picker_layout,
					},
				},
			},

			-- =================================================
			-- ПОЛЕ ВВОДУ
			-- =================================================

			input = {
				enabled = true,

				icon = " ",
				icon_pos = "left",

				prompt_pos = "title",

				win = {
					style = "input",
				},

				expand = true,
			},

			-- =================================================
			-- СТИЛІ
			-- =================================================

			styles = {
				input = {
					backdrop = false,

					position = "float",
					relative = "editor",

					row = 0.40,

					width = 60,
					height = 1,

					border = "rounded",
					title_pos = "center",

					noautocmd = true,

					wo = {
						winhighlight = table.concat({
							"NormalFloat:SnacksInputNormal",
							"FloatBorder:SnacksInputBorder",
							"FloatTitle:SnacksInputTitle",
						}, ","),

						cursorline = false,
					},

					bo = {
						filetype = "snacks_input",
						buftype = "prompt",
					},

					b = {
						-- Вимкнути автодоповнення від blink.cmp
						completion = false,
					},

					-- =========================================
					-- КЛАВІШІ INPUT
					-- =========================================

					keys = {
						n_esc = {
							"<esc>",
							{ "cmp_close", "cancel" },
							mode = "n",
							expr = true,
						},

						i_esc = {
							"<esc>",
							{ "cmp_close", "stopinsert" },
							mode = "i",
							expr = true,
						},

						i_cr = {
							"<cr>",
							{ "cmp_accept", "confirm" },
							mode = { "i", "n" },
							expr = true,
						},

						i_tab = {
							"<tab>",
							{ "cmp_select_next", "cmp" },
							mode = "i",
							expr = true,
						},

						i_ctrl_w = {
							"<c-w>",
							"<c-s-w>",
							mode = "i",
							expr = true,
						},

						i_up = {
							"<up>",
							{ "hist_up" },
							mode = { "i", "n" },
						},

						i_down = {
							"<down>",
							{ "hist_down" },
							mode = { "i", "n" },
						},

						q = "cancel",
					},
				},
			},

			-- =================================================
			-- ПОВІДОМЛЕННЯ
			-- =================================================

			notifier = {
				enabled = true,
				timeout = 3000,
			},

			-- =================================================
			-- ІНШІ МОЖЛИВОСТІ
			-- =================================================

			quickfile = {
				enabled = true,
			},

			bigfile = {
				enabled = true,
			},

			scope = {
				enabled = true,
			},

			words = {
				enabled = true,
			},
		},

		-- ====================================================
		-- ГЛОБАЛЬНІ КЛАВІШІ
		-- ====================================================

		keys = {
			-- Explorer
			{
				"<leader>e",
				function()
					Snacks.explorer()
				end,
				desc = "Провідник файлів",
			},

			-- Smart Search
			{
				"<leader><space>",
				function()
					Snacks.picker.smart()
				end,
				desc = "Розумний пошук",
			},

			{
				"<leader>fs",
				function()
					Snacks.picker.smart()
				end,
				desc = "Розумний пошук",
			},

			-- Find Files
			{
				"<leader>ff",
				function()
					Snacks.picker.files()
				end,
				desc = "Пошук файлів",
			},

			-- Live Grep
			{
				"<leader>fg",
				function()
					Snacks.picker.grep()
				end,
				desc = "Пошук за вмістом файлів",
			},

			-- Recent Files
			{
				"<leader>fr",
				function()
					Snacks.picker.recent()
				end,
				desc = "Нещодавні файли",
			},

			-- Buffers
			{
				"<leader>fb",
				function()
					Snacks.picker.buffers()
				end,
				desc = "Буфери",
			},

			{
				"<leader>,",
				function()
					Snacks.picker.buffers()
				end,
				desc = "Буфери",
			},

			-- Конфігурація Neovim
			{
				"<leader>fc",
				function()
					Snacks.picker.files({
						cwd = vim.fn.stdpath("config"),
					})
				end,
				desc = "Конфігурація Neovim",
			},

			-- Відновити попередній Picker
			{
				"<leader>fp",
				function()
					Snacks.picker.resume()
				end,
				desc = "Відновити попередній пошук",
			},
		},
	},
}
