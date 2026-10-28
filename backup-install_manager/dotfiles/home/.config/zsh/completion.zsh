# ============================================================
# ZSH COMPLETION — СТАНДАРТНИЙ COMPINIT
# Без zsh-autocomplete: безпечно, швидко, керування через Tab.
# ============================================================

# Системний каталог доповнень Arch Linux (zsh-completions).
# Не дублюємо його у fpath.
if [[ -d /usr/share/zsh/site-functions ]]; then
    fpath=(/usr/share/zsh/site-functions ${fpath:#/usr/share/zsh/site-functions})
fi

# Запуск вбудованого механізму автодоповнення.
# compinit перевіряє права каталогів і не використовує прапорці -u/-i.
autoload -Uz compinit

# Каталог кешу вже створюється в головному .zshrc.
# Перший запуск будує кеш, наступні використовують його повторно.
compinit -d "$ZSH_CACHE_DIR/zcompdump"

# Показувати список, якщо відповідників декілька.
setopt AUTO_LIST
setopt AUTO_MENU
setopt COMPLETE_IN_WORD

# Tab відкриває меню, у якому можна обрати варіант.
zstyle ':completion:*' menu select

# Зрозумілі групи та підписи, кольори Nordic.
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{cyan}-- %d --%f'
zstyle ':completion:*:messages' format '%F{yellow}%d%f'
zstyle ':completion:*:warnings' format '%F{red}Немає відповідників: %d%f'
zstyle ':completion:*' verbose yes

# Зіставлення без врахування регістру, а потім часткове доповнення.
zstyle ':completion:*' matcher-list \
    'm:{a-zA-Z}={A-Za-z}' \
    'r:|[._-]=** r:|=**'

# Використовувати кольори ls/eza, якщо вони визначені у LS_COLORS.
if [[ -n ${LS_COLORS-} ]]; then
    zstyle ':completion:*' list-colors "${(@s.:.)LS_COLORS}"
fi
