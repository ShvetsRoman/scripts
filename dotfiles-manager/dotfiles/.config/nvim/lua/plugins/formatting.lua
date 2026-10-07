-- ============================================================
-- FORMATTING
-- conform.nvim
-- ============================================================

return {
    {
        "stevearc/conform.nvim",

        event = {
            "BufWritePre",
        },

        cmd = {
            "ConformInfo",
        },

        keys = {
            {
                "<leader>lf",

                function()
                    require("conform").format({
                        async = true,
                        lsp_format = "fallback",
                    })
                end,

                mode = {
                    "n",
                    "v",
                },

                desc = "Format",
            },
        },

        opts = {
            -- ====================================================
            -- FORMATTERS
            -- ====================================================

            formatters_by_ft = {
                -- Lua
                lua = {
                    "stylua",
                },

                -- Shell
                sh = {
                    "shfmt",
                },

                bash = {
                    "shfmt",
                },

                zsh = {
                    "shfmt",
                },

                -- JSON
                json = {
                    "prettier",
                },

                jsonc = {
                    "prettier",
                },

                -- YAML
                yaml = {
                    "prettier",
                },

                -- Markdown
                markdown = {
                    "prettier",
                },

                -- HTML
                html = {
                    "prettier",
                },

                -- CSS
                css = {
                    "prettier",
                },

                scss = {
                    "prettier",
                },

                -- JavaScript
                javascript = {
                    "prettier",
                },

                javascriptreact = {
                    "prettier",
                },

                -- TypeScript
                typescript = {
                    "prettier",
                },

                typescriptreact = {
                    "prettier",
                },

                -- PHP
                php = {
                    "php_cs_fixer",
                },
            },

            -- ====================================================
            -- FORMAT ON SAVE
            -- ====================================================

            format_on_save = function(bufnr)
                -- Не форматувати special buffers
                if vim.bo[bufnr].buftype ~= "" then
                    return
                end

                -- Можна вимкнути глобально:
                --
                -- :lua vim.g.disable_autoformat = true
                --
                -- або тільки для поточного buffer:
                --
                -- :lua vim.b.disable_autoformat = true

                if vim.g.disable_autoformat then
                    return
                end

                if vim.b[bufnr].disable_autoformat then
                    return
                end

                return {
                    timeout_ms = 1000,

                    -- Якщо зовнішнього formatter немає,
                    -- використовувати LSP formatting
                    lsp_format = "fallback",
                }
            end,

            -- ====================================================
            -- FORMAT OPTIONS
            -- ====================================================

            default_format_opts = {
                lsp_format = "fallback",
            },

            -- ====================================================
            -- FORMATTER SETTINGS
            -- ====================================================

            formatters = {
                -- --------------------------------------------
                -- SHFMT
                -- --------------------------------------------

                shfmt = {
                    append_args = {
                        "-i",
                        "4",

                        "-ci",
                    },
                },
            },

            notify_on_error = true,

            notify_no_formatters = false,
        },

        init = function()
            -- Використовувати Conform для gq/operator formatting
            vim.o.formatexpr =
                "v:lua.require'conform'.formatexpr()"
        end,

        config = function(_, opts)
            require("conform").setup(opts)

            -- ====================================================
            -- COMMANDS
            -- ====================================================

            vim.api.nvim_create_user_command(
                "FormatDisable",
                function(args)
                    if args.bang then
                        vim.b.disable_autoformat = true

                        vim.notify(
                            "Autoformat вимкнено для поточного buffer"
                        )
                    else
                        vim.g.disable_autoformat = true

                        vim.notify(
                            "Autoformat вимкнено глобально"
                        )
                    end
                end,
                {
                    desc = "Вимкнути format-on-save",
                    bang = true,
                }
            )

            vim.api.nvim_create_user_command(
                "FormatEnable",
                function()
                    vim.g.disable_autoformat = false
                    vim.b.disable_autoformat = false

                    vim.notify(
                        "Autoformat увімкнено"
                    )
                end,
                {
                    desc = "Увімкнути format-on-save",
                }
            )
        end,
    },
}
