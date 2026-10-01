return {
  -- 1. Вимикаємо стандартний Telescope
  {
    "nvim-telescope/telescope.nvim",
    enabled = false,
  },

  -- 2. Додаємо та налаштовуємо FZF-lua (Загальний конфіг + LSP)
  {
    "ibhagwan/fzf-lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = "FzfLua",
    config = function()
      local fzf = require "fzf-lua"
      fzf.setup {
        -- Загальні налаштування пошукового рушія
        fzf_opts = {
          ["--ansi"] = "",
          ["--info"] = "inline", -- Інформація про кількість результатів в один рядок
          ["--height"] = "100%",
          ["--layout"] = "reverse", -- Рядок введення згори, результати йдуть вниз
        },
        -- Зовнішній вигляд вікна (Красивий Floating Border)
        winopts = {
          height = 0.75, -- Висота вікна (75% екрана)
          width = 0.85, -- Ширина вікна (85% екрана)
          row = 0.35, -- Центрування по вертикалі
          col = 0.50, -- Центрування по горизонталі
          border = "rounded", -- Округлі рамки
          preview = {
            border = "border", -- Окрема рамка для вікна попереднього перегляду коду
            wrap = "nowrap", -- Не переносити довгі рядки коду
            default = "bat", -- Синтаксичне підсвічування через bat (якщо встановлено)
            layout = "flex", -- Авто-дизайн прев'ю (праворуч або знизу залежно від екрана)
            horizontal = "right:50%",
          },
        },

        -- Налаштування відображення іконок
        files = {
          git_icons = true,
          file_icons = true,
          color_icons = true,
        },

        -- Пошук тексту (grep) через утиліту RipGrep
        grep = {
          rg_opts = "--column --line-number --no-heading --color=always --smart-case --hidden",
        },

        -- ==========================================================
        -- НАЛАШТУВАННЯ LSP НАВІГАЦІЇ В FZF
        -- ==========================================================
        lsp = {
          prompt_postfix = " ➔ ", -- Символ стрілочки в рядку пошуку LSP
          cwd_only = false, -- Шукати посилання по всьому проєкту/воркспейсу
          async_or_timeout = 5000, -- Таймаут для важких запитів у великих репозиторіях
          file_icons = true, -- Показувати іконки файлів біля знайденого коду
          git_icons = false,
          includeDeclaration = true, -- Включати оголошення у пошук посилань
        },
      }
    end,
  },
}
