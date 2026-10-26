-- ============================================================
-- FLOAT APPEARANCE — NORDIC
-- Єдине джерело підсвічування floating-вікон.
-- Викликається з init.lua після ініціалізації Lazy.nvim.
-- ============================================================

local M = {}

-- ------------------------------------------------------------
-- Кольори панелей і акцентів Nordic.
-- ------------------------------------------------------------
local palette = {
    panel = "#242933",
    fg = "#D8DEE9",
    muted = "#8294AB",
    border = "#60758D",
    cyan = "#88C0D0",
    blue = "#81A1C1",
    yellow = "#EBCB8B",
    green = "#A3BE8C",
    red = "#BF616A",
    selected = "#384B61",
}

-- ------------------------------------------------------------
-- Фон редактора береться з активної теми.
-- Якщо тема прозора, фон також залишається прозорим.
-- ------------------------------------------------------------
local function editor_bg()
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    return normal.bg and string.format("#%06X", normal.bg) or "NONE"
end

-- ------------------------------------------------------------
-- Допоміжні функції оголошення груп.
-- ------------------------------------------------------------
local function set(group, fg, bg, bold)
    vim.api.nvim_set_hl(0, group, { fg = fg, bg = bg, bold = bold or false })
end

function M.apply()
    local outer = editor_bg()
    local p = palette

    -- Зовнішній край використовує фон редактора.
    -- Непрозорий фон панелі залишається лише всередині вікон.
    set("NormalFloat", p.fg, p.panel)
    set("FloatBorder", p.border, outer)
    set("FloatTitle", p.yellow, outer, true)

    -- Контейнер і вміст Snacks Picker.
    set("SnacksPickerBox", p.fg, outer)
    set("SnacksPickerBoxBorder", p.border, outer)
    set("SnacksPickerBoxTitle", p.yellow, outer, true)
    set("SnacksPickerNormal", p.fg, p.panel)
    set("SnacksPickerBorder", p.border, outer)
    set("SnacksPickerTitle", p.yellow, outer, true)
    set("SnacksPickerInput", p.fg, p.panel)
    set("SnacksPickerInputBorder", p.cyan, outer)
    set("SnacksPickerInputTitle", p.yellow, outer, true)
    set("SnacksPickerList", p.fg, p.panel)
    set("SnacksPickerListBorder", p.border, outer)
    set("SnacksPickerListTitle", p.yellow, outer, true)
    set("SnacksPickerListCursorLine", p.fg, p.selected, true)
    set("SnacksPickerPreview", p.fg, p.panel)
    set("SnacksPickerPreviewBorder", p.border, outer)
    set("SnacksPickerPreviewTitle", p.yellow, outer, true)
    set("SnacksPickerDir", p.blue)
    set("SnacksPickerDirectory", p.cyan, nil, true)
    set("SnacksPickerFile", p.fg)
    set("SnacksPickerDimmed", p.muted)
    set("SnacksPickerMatch", p.yellow, nil, true)
    set("SnacksPickerGitStatusAdded", p.green)
    set("SnacksPickerGitStatusModified", p.yellow)
    set("SnacksPickerGitStatusDeleted", p.red)
    set("SnacksInputNormal", p.fg, p.panel)
    set("SnacksInputBorder", p.cyan, outer)
    set("SnacksInputTitle", p.yellow, outer, true)

    -- Noice: однаковий фон для рамки та вмісту Cmdline.
    set("NoiceCmdlinePopup", p.fg, outer)
    set("NoiceCmdlinePopupBorder", p.cyan, outer)
    set("NoiceCmdlinePopupBorderSearch", p.yellow, outer)
    set("NoiceCmdlinePopupTitle", p.yellow, outer, true)
    set("NoiceCmdlineIcon", p.yellow, outer)
    set("NoiceCmdlineIconSearch", p.yellow, outer)
    set("NoicePopupmenu", p.fg, outer)
    set("NoicePopupmenuBorder", p.border, outer)
    set("NoicePopupmenuSelected", p.fg, p.selected, true)
    set("NoicePopupmenuMatch", p.yellow)
    set("NoicePopup", p.fg, outer)
    set("NoicePopupBorder", p.border, outer)
    set("NoiceConfirm", p.fg, outer)
    set("NoiceConfirmBorder", p.border, outer)

    -- Blink.cmp: меню, документація та signature help.
    set("BlinkCmpMenu", p.fg, p.panel)
    set("BlinkCmpMenuBorder", p.cyan, outer)
    set("BlinkCmpMenuSelection", p.fg, p.selected, true)
    set("BlinkCmpLabel", p.fg)
    set("BlinkCmpLabelDescription", p.muted)
    set("BlinkCmpDoc", p.fg, p.panel)
    set("BlinkCmpDocBorder", p.border, outer)
    set("BlinkCmpSignatureHelp", p.fg, p.panel)
    set("BlinkCmpSignatureHelpBorder", p.border, outer)

    -- WhichKey: праве меню з таким самим стилем.
    set("WhichKeyNormal", p.fg, p.panel)
    set("WhichKeyBorder", p.border, outer)
    set("WhichKeyTitle", p.yellow, outer, true)
    set("WhichKey", p.yellow)
    set("WhichKeyDesc", p.fg)
    set("WhichKeyGroup", p.yellow, nil, true)
    set("WhichKeySeparator", p.muted)
    set("WhichKeyValue", p.blue)

    -- Типові рамки LSP і кольори діагностики.
    set("DiagnosticFloatingError", p.red)
    set("DiagnosticFloatingWarn", p.yellow)
    set("DiagnosticFloatingInfo", p.blue)
    set("DiagnosticFloatingHint", p.cyan)
end

function M.setup()
    -- Загальна форма рамки для плагінів, що не перевизначають її.
    vim.o.winborder = "rounded"
    vim.o.winblend = 0
    vim.o.pumblend = 0

    local group = vim.api.nvim_create_augroup("NordicUnifiedFloatAppearance", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
            vim.schedule(M.apply)
        end,
    })

    -- Lazy.nvim уже запущений; перезастосувати після встановлення теми.
    M.apply()
    vim.schedule(M.apply)
end

return M
