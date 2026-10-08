-- AUTOCMDS
-- Автоматичні команди Neovim

local api = vim.api

local group = api.nvim_create_augroup("UserConfig", {
	clear = true,
})

api.nvim_create_autocmd("TextYankPost", {
	group = group,
	desc = "Підсвічувати скопійований текст",
	callback = function()
		vim.highlight.on_yank({
			higroup = "IncSearch",
			timeout = 150,
		})
	end,
})

api.nvim_create_autocmd("BufReadPost", {
	group = group,
	desc = "Повернути курсор до останньої позиції у файлі",
	callback = function(event)
		local mark = api.nvim_buf_get_mark(event.buf, '"')
		local line_count = api.nvim_buf_line_count(event.buf)
		if mark[1] > 0 and mark[1] <= line_count then
			pcall(api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

api.nvim_create_autocmd("BufWritePre", {
	group = group,
	desc = "Створити каталог перед збереженням файла",
	callback = function(event)
		if event.match:match("^%w%w+:[\\/][\\/]") then
			return
		end

		local file = vim.uv.fs_realpath(event.match) or event.match
		local dir = vim.fs.dirname(file)
		if dir then
			vim.fn.mkdir(dir, "p")
		end
	end,
})

api.nvim_create_autocmd("FileType", {
	group = group,
	pattern = {
		"help",
		"qf",
		"checkhealth",
		"man",
		"notify",
	},
	callback = function(event)
		vim.keymap.set("n", "q", "<cmd>close<CR>", {
			buffer = event.buf,
			silent = true,
			desc = "Закрити вікно",
		})
	end,
})
