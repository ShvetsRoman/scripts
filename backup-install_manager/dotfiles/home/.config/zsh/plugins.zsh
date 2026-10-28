# ============================================================
# ПЛАГІНИ ZSH — ПІДКАЗКИ ТА ПІДСВІЧУВАННЯ (NORDIC)
# ============================================================

# Сірі підказки з історії команд.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#616E88'

if [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# Підсвічування завантажуємо останнім, після налаштувань ZLE.
if [[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

    # Оголосити асоціативний масив, якщо він ще не існує.
    if ((! ${+ZSH_HIGHLIGHT_STYLES})); then
        typeset -gA ZSH_HIGHLIGHT_STYLES
    fi

    # Кольори Nordic.
    ZSH_HIGHLIGHT_STYLES[command]='fg=#A3BE8C'
    ZSH_HIGHLIGHT_STYLES['unknown-token']='fg=#BF616A'
    ZSH_HIGHLIGHT_STYLES['single-hyphen-option']='fg=#88C0D0'
    ZSH_HIGHLIGHT_STYLES['double-hyphen-option']='fg=#88C0D0'
    ZSH_HIGHLIGHT_STYLES['single-quoted-argument']='fg=#EBCB8B'
    ZSH_HIGHLIGHT_STYLES['double-quoted-argument']='fg=#EBCB8B'
fi
