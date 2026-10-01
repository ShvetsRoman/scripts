-- ============================================================
-- SNACKS
-- NvChad + Snacks
-- ============================================================

-- ------------------------------------------------------------
-- СПІЛЬНІ РОЗМІРИ EXPLORER ТА PICKER
-- ------------------------------------------------------------

-- Загальна ширина floating-вікна
local picker_width = 0.88

-- Загальна висота floating-вікна
local picker_height = 0.80

-- Невеликий зсув вправо від центру
local picker_col = 0.058

-- Ширина лівої частини
local list_width = 0.36

-- Ширина preview
local preview_width = 0.64

-- ------------------------------------------------------------
-- ПРИМУСОВО ПОКАЗАТИ PREVIEW
-- ------------------------------------------------------------

local function show_preview(picker)
    vim.schedule(function()
        if picker and not picker.closed then
            picker:toggle("preview", {
                enable = true,
            })
        end
    end)
end

return {
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,

        ---@type snacks.Config
        opts = {
            -- =========================================================
            -- ПРОДУКТИВНІСТЬ
            -- =========================================================

            bigfile = {
                enabled = true,
            },

            quickfile = {
                enabled = true,
            },

            -- =========================================================
            -- DASHBOARD
            -- =========================================================

            dashboard = {
                enabled = true,
            },

            -- =========================================================
            -- EXPLORER
            -- =========================================================

            explorer = {
                enabled = true,

                -- Замінює netrw
                replace_netrw = true,

                -- Видалення через системний кошик
                trash = true,
            },

            -- =========================================================
            -- IMAGE
            -- =========================================================

            image = {
                enabled = false,
            },

            -- =========================================================
            -- PICKER
            -- =========================================================

            picker = {
                enabled = true,

                -- Після переходу до файла Picker закривається
                jump = {
                    close = true,
                },

                -- =====================================================
                -- ВЛАСНІ ACTIONS
                -- =====================================================

                actions = {
                    -- -------------------------------------------------
                    -- ВІДКРИТТЯ ЕЛЕМЕНТА EXPLORER
                    -- -------------------------------------------------

                    explorer_open = function(picker, item)
                        item = item or picker:current()

                        if not item then
                            return
                        end

                        -- Директорія:
                        -- стандартний confirm розгортає / відкриває її
                        if item.dir then
                            picker:action("confirm")
                            return
                        end

                        -- Файл:
                        -- відкриваємо файл стандартною дією
                        picker:action("confirm")

                        -- Після відкриття файла гарантовано
                        -- закриваємо Explorer
                        vim.schedule(function()
                            if picker and not picker.closed then
                                picker:close()
                            end
                        end)
                    end,
                },

                -- =====================================================
                -- LAYOUTS
                -- =====================================================

                layouts = {
                    -- =================================================
                    -- EXPLORER
                    -- =================================================

                    helix_explorer = {
                        cycle = true,

                        -- Не приховувати input/list/preview
                        hidden = {},

                        layout = {
                            box = "horizontal",
                            position = "float",

                            -- Розмір
                            width = picker_width,
                            height = picker_height,

                            -- Невеликий зсув вправо
                            col = picker_col,

                            backdrop = 40,
                            border = "rounded",

                            -- =========================================
                            -- ЛІВА ЧАСТИНА
                            -- =========================================

                            {
                                box = "vertical",
                                width = list_width,

                                {
                                    win = "input",
                                    height = 1,
                                    border = "bottom",

                                    title = " Explorer ",
                                    title_pos = "center",
                                },

                                {
                                    win = "list",
                                    border = "none",
                                },
                            },

                            -- =========================================
                            -- PREVIEW
                            -- =========================================

                            {
                                win = "preview",

                                width = preview_width,

                                border = "left",

                                title = "{preview:Preview}",
                                title_pos = "center",
                            },
                        },
                    },

                    -- =================================================
                    -- ПОШУК / PICKER
                    -- =================================================

                    helix_picker = {
                        cycle = true,
                        hidden = {},

                        layout = {
                            box = "horizontal",
                            position = "float",

                            -- Такий самий розмір, як Explorer
                            width = picker_width,
                            height = picker_height,

                            -- Такий самий зсув вправо
                            col = picker_col,

                            backdrop = 40,
                            border = "rounded",

                            -- =========================================
                            -- ЛІВА ЧАСТИНА
                            -- =========================================

                            {
                                box = "vertical",
                                width = list_width,

                                {
                                    win = "input",
                                    height = 1,
                                    border = "bottom",

                                    title = " Search ",
                                    title_pos = "center",
                                },

                                {
                                    win = "list",
                                    border = "none",
                                },
                            },

                            -- =========================================
                            -- PREVIEW
                            -- =========================================

                            {
                                win = "preview",

                                width = preview_width,

                                border = "left",

                                title = "{preview:Preview}",
                                title_pos = "center",
                            },
                        },
                    },
                },

                -- =====================================================
                -- ГЛОБАЛЬНІ КЛАВІШІ PICKER
                -- =====================================================

                win = {
                    -- =================================================
                    -- INPUT
                    -- =================================================

                    input = {
                        keys = {
                            -- ESC закриває Picker навіть з Insert mode
                            ["<Esc>"] = {
                                "cancel",
                                mode = { "i", "n" },
                            },

                            -- Наступний елемент
                            ["<C-j>"] = {
                                "list_down",
                                mode = { "i", "n" },
                            },

                            -- Попередній елемент
                            ["<C-k>"] = {
                                "list_up",
                                mode = { "i", "n" },
                            },

                            -- Preview on/off
                            ["<A-p>"] = {
                                "toggle_preview",
                                mode = { "i", "n" },
                            },

                            -- Перехід між вікнами Picker
                            ["<A-w>"] = {
                                "cycle_win",
                                mode = { "i", "n" },
                            },
                        },
                    },

                    -- =================================================
                    -- LIST
                    -- =================================================

                    list = {
                        keys = {
                            ["<Esc>"] = "cancel",
                            ["q"] = "cancel",

                            ["j"] = "list_down",
                            ["k"] = "list_up",

                            ["gg"] = "list_top",
                            ["G"] = "list_bottom",

                            -- Перейти до input
                            ["i"] = "focus_input",

                            -- Preview
                            ["<A-p>"] = "toggle_preview",

                            -- Перехід між вікнами
                            ["<A-w>"] = "cycle_win",
                        },
                    },

                    -- =================================================
                    -- PREVIEW
                    -- =================================================

                    preview = {
                        keys = {
                            ["<Esc>"] = "cancel",
                            ["q"] = "cancel",

                            ["i"] = "focus_input",

                            ["<A-p>"] = "toggle_preview",
                            ["<A-w>"] = "cycle_win",
                        },
                    },
                },

                -- =====================================================
                -- SOURCES
                -- =====================================================

                sources = {
                    -- =================================================
                    -- EXPLORER
                    -- =================================================

                    explorer = {
                        -- Показувати приховані файли
                        hidden = true,

                        -- Git ignored не показуємо
                        ignored = false,

                        -- Автоматичне закриття при переході
                        -- в зовнішнє вікно
                        auto_close = true,

                        layout = {
                            preset = "helix_explorer",
                            hidden = {},
                        },

                        -- Preview одразу відкритий
                        on_show = show_preview,

                        -- ---------------------------------------------
                        -- КЛАВІШІ САМЕ EXPLORER
                        -- ---------------------------------------------

                        win = {
                            input = {
                                keys = {
                                    -- Enter:
                                    -- директорія -> відкрити
                                    -- файл -> відкрити та закрити Explorer
                                    ["<CR>"] = {
                                        "explorer_open",
                                        mode = { "i", "n" },
                                    },
                                },
                            },

                            list = {
                                keys = {
                                    -- Enter
                                    ["<CR>"] = "explorer_open",

                                    -- Helix-подібне відкриття вправо
                                    ["l"] = "explorer_open",

                                    -- Вийти / назад стандартною дією Explorer
                                    ["h"] = "explorer_up",
                                },
                            },
                        },
                    },

                    -- =================================================
                    -- FILES
                    -- =================================================

                    files = {
                        hidden = true,

                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- GREP
                    -- =================================================

                    grep = {
                        hidden = true,

                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- GREP WORD
                    -- =================================================

                    grep_word = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- BUFFERS
                    -- =================================================

                    buffers = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- RECENT
                    -- =================================================

                    recent = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- HELP
                    -- =================================================

                    help = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- KEYMAPS
                    -- =================================================

                    keymaps = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- MARKS
                    -- =================================================

                    marks = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- JUMPS
                    -- =================================================

                    jumps = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- QUICKFIX
                    -- =================================================

                    qflist = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- COMMAND HISTORY
                    -- =================================================

                    command_history = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },
                    },

                    -- =================================================
                    -- SEARCH HISTORY
                    -- =================================================

                    search_history = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },
                    },

                    -- =================================================
                    -- GIT STATUS
                    -- =================================================

                    git_status = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- GIT LOG
                    -- =================================================

                    git_log = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- GIT BRANCHES
                    -- =================================================

                    git_branches = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- LSP DEFINITIONS
                    -- =================================================

                    lsp_definitions = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- LSP DECLARATIONS
                    -- =================================================

                    lsp_declarations = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- LSP REFERENCES
                    -- =================================================

                    lsp_references = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- LSP IMPLEMENTATIONS
                    -- =================================================

                    lsp_implementations = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- LSP TYPE DEFINITIONS
                    -- =================================================

                    lsp_type_definitions = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- LSP SYMBOLS
                    -- =================================================

                    lsp_symbols = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },

                    -- =================================================
                    -- LSP WORKSPACE SYMBOLS
                    -- =================================================

                    lsp_workspace_symbols = {
                        layout = {
                            preset = "helix_picker",
                            hidden = {},
                        },

                        on_show = show_preview,
                    },
                },
            },

            -- =========================================================
            -- INPUT
            -- =========================================================

            input = {
                enabled = true,
            },

            -- =========================================================
            -- NOTIFIER
            -- =========================================================

            notifier = {
                enabled = true,
                timeout = 3000,
            },

            -- =========================================================
            -- INDENT
            -- =========================================================

            indent = {
                enabled = true,
            },

            -- =========================================================
            -- SCOPE
            -- =========================================================

            scope = {
                enabled = true,
            },

            -- =========================================================
            -- SCROLL
            -- =========================================================

            scroll = {
                enabled = true,
            },

            -- =========================================================
            -- STATUSCOLUMN
            -- =========================================================

            statuscolumn = {
                enabled = true,
            },

            -- =========================================================
            -- WORDS
            -- =========================================================

            words = {
                enabled = true,
            },

            -- =========================================================
            -- TERMINAL
            -- =========================================================

            terminal = {
                enabled = true,
            },

            -- =========================================================
            -- LAZYGIT
            -- =========================================================

            lazygit = {
                enabled = true,
            },

            -- =========================================================
            -- SCRATCH
            -- =========================================================

            scratch = {
                enabled = true,
            },

            -- =========================================================
            -- ZEN
            -- =========================================================

            zen = {
                enabled = true,
            },

            -- =========================================================
            -- СТИЛІ
            -- =========================================================

            styles = {
                notification = {
                    wo = {
                        wrap = true,
                    },
                },
            },
        },
    },
}
