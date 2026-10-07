-- ============================================================
-- COMPLETION
-- blink.cmp
-- Neovim 0.12+
-- ============================================================

return {
    {
        "saghen/blink.cmp",

        version = "1.*",

        dependencies = {
            -- Готові snippets для багатьох мов
            "rafamadriz/friendly-snippets",
        },

        ---@module "blink.cmp"
        ---@type blink.cmp.Config
        opts = {
            -- ====================================================
            -- KEYMAPS
            -- ====================================================

            -- Enter приймає completion.
            -- Tab / Shift-Tab використовуються для snippets.
            keymap = {
                preset = "enter",

                -- Показати completion / documentation
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

                -- Закрити completion
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

                -- Signature help
                ["<C-k>"] = {
                    "show_signature",
                    "hide_signature",
                    "fallback",
                },
            },

            -- ====================================================
            -- APPEARANCE
            -- ====================================================

            appearance = {
                nerd_font_variant = "mono",
            },

            -- ====================================================
            -- COMPLETION
            -- ====================================================

            completion = {
                -- ------------------------------------------------
                -- TRIGGER
                -- ------------------------------------------------

                trigger = {
                    -- Показувати completion під час введення
                    show_on_keyword = true,

                    -- Не запускати новий completion всередині snippet
                    show_in_snippet = false,
                },

                -- ------------------------------------------------
                -- LIST
                -- ------------------------------------------------

                list = {
                    selection = {
                        -- Не вставляти перший item автоматично
                        preselect = false,

                        -- Не вставляти item до підтвердження
                        auto_insert = false,
                    },
                },

                -- ------------------------------------------------
                -- MENU
                -- ------------------------------------------------

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

                -- ------------------------------------------------
                -- DOCUMENTATION
                -- ------------------------------------------------

                documentation = {
                    auto_show = true,

                    auto_show_delay_ms = 250,

                    window = {
                        border = "rounded",
                    },
                },

                -- ------------------------------------------------
                -- GHOST TEXT
                -- ------------------------------------------------

                ghost_text = {
                    enabled = false,
                },
            },

            -- ====================================================
            -- SIGNATURE HELP
            -- ====================================================

            signature = {
                enabled = true,

                window = {
                    border = "rounded",
                },
            },

            -- ====================================================
            -- SOURCES
            -- ====================================================

            sources = {
                default = {
                    "lsp",
                    "path",
                    "snippets",
                    "buffer",
                },

                providers = {
                    -- --------------------------------------------
                    -- LSP
                    -- --------------------------------------------

                    lsp = {
                        name = "LSP",

                        fallbacks = {},
                    },

                    -- --------------------------------------------
                    -- PATH
                    -- --------------------------------------------

                    path = {
                        name = "Path",
                    },

                    -- --------------------------------------------
                    -- SNIPPETS
                    -- --------------------------------------------

                    snippets = {
                        name = "Snippets",

                        opts = {
                            friendly_snippets = true,
                        },
                    },

                    -- --------------------------------------------
                    -- BUFFER
                    -- --------------------------------------------

                    buffer = {
                        name = "Buffer",

                        min_keyword_length = 3,
                    },
                },
            },

            -- ====================================================
            -- FUZZY MATCHING
            -- ====================================================

            fuzzy = {
                implementation = "prefer_rust",
            },
        },

        opts_extend = {
            "sources.default",
        },
    },
}
