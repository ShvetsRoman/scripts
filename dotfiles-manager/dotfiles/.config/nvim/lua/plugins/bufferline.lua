return {

	{
		"akinsho/bufferline.nvim",

		version = "*",

		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},

		event = "VeryLazy",

		opts = {
			options = {
				mode = "buffers",

				numbers = "none",

				diagnostics = "nvim_lsp",

				separator_style = "thin",

				show_buffer_close_icons = true,

				show_close_icon = false,

				always_show_bufferline = true,

				offsets = {},
			},
		},

		keys = {
			{
				"<S-Tab>",
				"<cmd>BufferLineCyclePrev<CR>",
				desc = "Попередній буфер",
			},

			{
				"<Tab>",
				"<cmd>BufferLineCycleNext<CR>",
				desc = "Наступний буфер",
			},

			{
				"<leader>bp",
				"<cmd>BufferLinePick<CR>",
				desc = "Вибрати буфер",
			},

			{
				"<leader>bc",
				"<cmd>bdelete<CR>",
				desc = "Закрити буфер",
			},
			{
				"<leader>x",
				"<cmd>bdelete<CR>",
				desc = "Закрити буфер",
			},
		},
	},
}
