-- ============================================================
-- TREESITTER
-- Syntax highlighting + Indent + Folds
-- Neovim 0.12+
-- ============================================================

-- ------------------------------------------------------------
-- PARSERS
-- ------------------------------------------------------------

local parsers = {
    -- Neovim / Lua
    "lua",
    "luadoc",
    "vim",
    "vimdoc",
    "query",

    -- Shell
    "bash",

    -- Data / Config
    "json",
    -- "jsonc",
    "yaml",
    "toml",

    -- Markdown
    "markdown",
    "markdown_inline",

    -- Web
    "html",
    "css",
    "javascript",
    "typescript",
    "tsx",

    -- Docker
    "dockerfile",

    -- PHP
    "php",

    -- SQL
    "sql",

    -- Git
    "git_config",
    "git_rebase",
    "gitattributes",
    "gitcommit",
    "gitignore",

    -- Інше
    "regex",
}

-- ------------------------------------------------------------
-- FILETYPES
-- ------------------------------------------------------------

local filetypes = {
    -- Neovim / Lua
    "lua",
    "vim",
    "help",

    -- Shell
    "sh",
    "bash",
    "zsh",

    -- Data / Config
    "json",
    "jsonc",
    "yaml",
    "toml",

    -- Markdown
    "markdown",

    -- Web
    "html",
    "css",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",

    -- Docker
    "dockerfile",

    -- PHP
    "php",

    -- SQL
    "sql",

    -- Git
    "gitconfig",
    "gitrebase",
    "gitcommit",
}

-- ============================================================
-- PLUGIN
-- ============================================================

return {
    {
        "nvim-treesitter/nvim-treesitter",

        lazy = false,

        build = ":TSUpdate",

        config = function()
            local treesitter = require("nvim-treesitter")

            -- ====================================================
            -- SETUP
            -- ====================================================

            treesitter.setup({
                install_dir = vim.fn.stdpath("data") .. "/site",
            })

            -- ====================================================
            -- INSTALL PARSERS
            -- ====================================================

            treesitter.install(parsers)

            -- ====================================================
            -- FILETYPE -> LANGUAGE
            -- ====================================================

            vim.treesitter.language.register("bash", {
                "sh",
                "bash",
                "zsh",
            })

            vim.treesitter.language.register(
                "javascript",
                "javascriptreact"
            )

            vim.treesitter.language.register(
                "tsx",
                "typescriptreact"
            )

            vim.treesitter.language.register(
                "vimdoc",
                "help"
            )

            -- ====================================================
            -- AUTOCMD GROUP
            -- ====================================================

            local group = vim.api.nvim_create_augroup(
                "UserTreesitter",
                {
                    clear = true,
                }
            )

            -- ====================================================
            -- ENABLE TREESITTER
            -- ====================================================

            vim.api.nvim_create_autocmd("FileType", {
                group = group,

                pattern = filetypes,

                desc = "Увімкнути Treesitter",

                callback = function(event)
                    -- --------------------------------------------
                    -- HIGHLIGHTING
                    -- --------------------------------------------

                    pcall(
                        vim.treesitter.start,
                        event.buf
                    )

                    -- --------------------------------------------
                    -- LANGUAGE
                    -- --------------------------------------------

                    local filetype =
                        vim.bo[event.buf].filetype

                    local language =
                        vim.treesitter.language.get_lang(filetype)

                    if not language then
                        return
                    end

                    -- --------------------------------------------
                    -- INDENT
                    -- --------------------------------------------

                    local indent_ok, indent_query =
                        pcall(
                            vim.treesitter.query.get,
                            language,
                            "indents"
                        )

                    if indent_ok and indent_query then
                        vim.bo[event.buf].indentexpr =
                            "v:lua.require'nvim-treesitter'.indentexpr()"
                    end

                    -- --------------------------------------------
                    -- FOLDS
                    -- --------------------------------------------

                    local folds_ok, folds_query =
                        pcall(
                            vim.treesitter.query.get,
                            language,
                            "folds"
                        )

                    if folds_ok and folds_query then
                        vim.wo.foldmethod = "expr"

                        vim.wo.foldexpr =
                            "v:lua.vim.treesitter.foldexpr()"

                        vim.wo.foldlevel = 99
                        vim.wo.foldenable = true
                    end
                end,
            })
        end,
    },
}
