-- =============================================================================
-- 1. УНІВЕРСАЛЬНА ФУНКЦІЯ ВИЗНАЧЕННЯ МЕЖ ЗГОРТАННЯ
-- =============================================================================

-- Допоміжна функція: перевіряє, чи є рядок лінією-роздільником (==== або ----)
local function is_separator_line(str)
	if not str then
		return false
	end
	return str:match("^#%s*[=-][=-][=-]") ~= nil or str:match("^%-%-%s*[=-][=-][=-]") ~= nil
end

function _G.custom_heading_fold(lnum)
	local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""

	-- Якщо поточний рядок є роздільником
	if is_separator_line(line) then
		local next_line = vim.api.nvim_buf_get_lines(0, lnum, lnum + 1, false)[1] or ""
		-- І якщо НАСТУПНИЙ рядок — це текст заголовка (починається з коментаря, але не є роздільником)
		if (next_line:match("^#") or next_line:match("^%-%-")) and not is_separator_line(next_line) then
			return ">1" -- Гарантовано починаємо новий великий блок фолдінгу тут
		end
	end

	return "=" -- Продовжуємо поточний блок для всіх інших рядків
end

-- =============================================================================
-- 2. ФУНКЦІЯ КРАСИВОГО ПРЕВ'Ю ЗГОРНУТОГО БЛОКУ
-- =============================================================================

function _G.custom_fold_text()
	local fs = vim.v.foldstart
	local fe = vim.v.foldend

	-- Оскільки фолд починається з лінії-роздільника, сам текст лежить на 1 рядок нижче
	local title_line = vim.api.nvim_buf_get_lines(0, fs, fs + 1, false)[1] or ""

	-- Очищаємо текст від коментарів та декоративних символів наприкінці
	local title = title_line:gsub("^#%s*", ""):gsub("^%-%-%s*", ""):gsub("%s*—.*$", ""):gsub("%s*[-=]*%s*$", "")
	if title == "" then
		title = "КОНФІГУРАЦІЯ"
	end

	local folded_lines_count = fe - fs + 1
	return string.format("    [%s] ─── (%d рядків) ", title:upper(), folded_lines_count)
end

-- =============================================================================
-- 3. АВТОКОМАНДА З ЗАХИСТОМ ВІД ПЕРЕЗАПИСУ ПЛАГІНАМИ
-- =============================================================================

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
	-- Список типів файлів (додайте інші через кому, якщо потрібно)
	pattern = { "toml", "conf", "routeros", "rsc", "lua", "sh", "text" },
	callback = function()
		-- vim.schedule гарантує, що налаштування застосуються ПІСЛЯ того, як Treesitter увімкне свої
		vim.schedule(function()
			vim.opt_local.foldmethod = "expr"
			vim.opt_local.foldexpr = "v:lua.custom_heading_fold(v:lnum)"
			vim.opt_local.foldtext = "v:lua.custom_fold_text()"

			vim.opt_local.foldlevel = 99 -- Відкривати файли розгорнутими
			vim.opt_local.foldcolumn = "1" -- Ліва панель статусу фолдів (0 — щоб сховати)
		end)
	end,
})
