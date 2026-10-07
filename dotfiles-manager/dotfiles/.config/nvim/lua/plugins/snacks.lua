-- ============================================================
-- SNACKS
-- Explorer + Picker + Search
-- ============================================================

local picker_width = 0.88
local picker_height = 0.80

local picker_layout = {
    layout = {
        box = "vertical",
        width = picker_width,
        height = picker_height,
        border = "none",
        {
            win = "input",
            height = 1,
            border = "rounded",
            title = " {title} {live} {flags} ",
            title_pos = "center",
        },
        {
            box = "horizontal",
            {
                win = "list",
                width = 0.36,
                border = "rounded",
                title = " Results ",
                title_pos = "center",
            },
            {
                win = "preview",
                border = "rounded",
                title = " {preview:Preview} ",
                title_pos = "center",
            },
        },
    },
}

local explorer_layout = {
    preview = true,
    layout = picker_layout.layout,
}

return {
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        ---@type snacks.Config
        opts = {
            explorer = {
                enabled = true,
                replace_netrw = true,
                trash = true,
            },
            picker = {
                enabled = true,
                ui_select = true,
                focus = "input",
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
                win = {
                    input = {
                        keys = {
                            ["<Esc>"] = { "cancel", mode = { "n", "i" } },
                            ["<C-j>"] = { "list_down", mode = { "n", "i" } },
                            ["<C-k>"] = { "list_up", mode = { "n", "i" } },
                            ["<C-d>"] = { "list_scroll_down", mode = { "n", "i" } },
                            ["<C-u>"] = { "list_scroll_up", mode = { "n", "i" } },
                            ["<C-f>"] = { "preview_scroll_down", mode = { "n", "i" } },
                            ["<C-b>"] = { "preview_scroll_up", mode = { "n", "i" } },
                            ["<CR>"] = { "confirm", mode = { "n", "i" } },
                            ["<C-v>"] = { "edit_vsplit", mode = { "n", "i" } },
                            ["<C-s>"] = { "edit_split", mode = { "n", "i" } },
                            ["<C-t>"] = { "tab", mode = { "n", "i" } },
                            ["<A-p>"] = { "toggle_preview", mode = { "n", "i" } },
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
                sources = {
                    explorer = {
                        title = "Explorer",
                        focus = "list",
                        layout = explorer_layout,
                        auto_close = true,
                        jump = {
                            close = true,
                        },
                        hidden = true,
                        ignored = false,
                        follow_file = true,
                        tree = true,
                        watch = true,
                        diagnostics = true,
                        diagnostics_open = false,
                        git_status = true,
                        git_status_open = false,
                        git_untracked = true,
                        sort = {
                            fields = { "sort" },
                        },
                        matcher = {
                            sort_empty = false,
                            fuzzy = false,
                        },
                        formatters = {
                            file = { filename_only = true },
                            severity = { pos = "right" },
                        },
                        win = {
                            list = {
                                keys = {
                                    ["<Right>"] = "confirm",
                                    ["<Left>"] = "explorer_close",
                                    ["l"] = "confirm",
                                    ["h"] = "explorer_close",
                                },
                            },
                        },
                    },
                    smart = {
                        title = "Smart Search",
                        layout = picker_layout,
                    },
                    files = {
                        title = "Find Files",
                        layout = picker_layout,
                        hidden = true,
                    },
                    grep = {
                        title = "Live Grep",
                        layout = picker_layout,
                        hidden = true,
                    },
                    recent = {
                        title = "Recent Files",
                        layout = picker_layout,
                    },
                    buffers = {
                        title = "Buffers",
                        layout = picker_layout,
                    },
                },
            },
            input = { enabled = true },
            notifier = {
                enabled = true,
                timeout = 3000,
            },
            quickfile = { enabled = true },
            bigfile = { enabled = true },
            scope = { enabled = true },
            words = { enabled = true },
        },
        keys = {
            {
                "<leader>e",
                function()
                    Snacks.explorer()
                end,
                desc = "Explorer",
            },
            {
                "<leader><space>",
                function()
                    Snacks.picker.smart()
                end,
                desc = "Smart Search",
            },
            {
                "<leader>fs",
                function()
                    Snacks.picker.smart()
                end,
                desc = "Smart Search",
            },
            {
                "<leader>ff",
                function()
                    Snacks.picker.files()
                end,
                desc = "Find Files",
            },
            {
                "<leader>fg",
                function()
                    Snacks.picker.grep()
                end,
                desc = "Grep",
            },
            {
                "<leader>/",
                function()
                    Snacks.picker.grep()
                end,
                desc = "Grep",
            },
            {
                "<leader>fr",
                function()
                    Snacks.picker.recent()
                end,
                desc = "Recent Files",
            },
            {
                "<leader>fb",
                function()
                    Snacks.picker.buffers()
                end,
                desc = "Buffers",
            },
            {
                "<leader>,",
                function()
                    Snacks.picker.buffers()
                end,
                desc = "Buffers",
            },
            {
                "<leader>fc",
                function()
                    Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
                end,
                desc = "Neovim Config",
            },
            {
                "<leader>fp",
                function()
                    Snacks.picker.resume()
                end,
                desc = "Resume Picker",
            },
        },
    },
}
