# ============================================================
# ZSHRC — ІНТЕРАКТИВНА КОНФІГУРАЦІЯ (Arch Linux / Kitty)
# ============================================================
# Ядро в одному файлі, зверху вниз у порядку завантаження:
# PATH → опції → історія → доповнення → аліаси (alias.zsh) →
# клавіатура → інтеграції → ZLE-плагіни (plugins.zsh — обов'язково
# останніми, вимога zsh-syntax-highlighting) → власні скрипти.
# Змінні середовища для ВСІХ сесій zsh — в .zshenv (місток ~/.zshenv).

[[ -o interactive ]] || return 0

# Не робимо глобальні readonly, щоб повторний source працював.
typeset -g ZSH_CONFIG_DIR="${ZDOTDIR:-$HOME/.config/zsh}"
# XDG_CACHE_HOME/XDG_STATE_HOME тут явно не встановлюються (див. .zshenv):
# fallback-значення нижче збігаються зі стандартними дефолтами XDG spec.
# Якщо колись зміните дефолти в .zshenv — оновіть і ці рядки.
typeset -g ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
typeset -g ZSH_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
mkdir -p -- "$ZSH_CACHE_DIR" "$ZSH_STATE_DIR" || return 1

# Builtin-модулі часу (спільні для compinit та init-кешів):
# zsh/datetime дає $EPOCHSECONDS, zsh/stat — builtin zstat
# (перевірка mtime без fork stat/date).
zmodload zsh/datetime 2>/dev/null
zmodload zsh/stat 2>/dev/null

# ============================================================
# 1. PATH
# ============================================================

# Локальні користувацькі програми мають пріоритет над системними.
if [[ -d "$HOME/.local/bin" ]]; then
    path=(
        "$HOME/.local/bin"
        $path
    )
fi
# Видалити дублікати з PATH.
typeset -U path PATH

# ============================================================
# 2. ПОВЕДІНКА ІНТЕРАКТИВНОГО ZSH
# ============================================================

setopt INTERACTIVE_COMMENTS AUTO_CD AUTO_LIST AUTO_MENU COMPLETE_IN_WORD
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS EXTENDED_GLOB
unsetopt BEEP CORRECT

# ============================================================
# 3. ІСТОРІЯ
# ============================================================

# Історія у XDG_STATE_HOME з достатнім лімітом.
HISTFILE="$ZSH_STATE_DIR/history"
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY INC_APPEND_HISTORY HIST_FCNTL_LOCK
setopt HIST_IGNORE_DUPS HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS HIST_VERIFY HIST_NO_STORE
# SHARE_HISTORY не вмикаємо: не змішуємо поточну історію різних вікон.
unsetopt SHARE_HISTORY

# ============================================================
# 4. ДОПОВНЕННЯ — СТАНДАРТНИЙ COMPINIT
# ============================================================

# Системний каталог доповнень Arch Linux (zsh-completions).
# Не дублюємо його у fpath.
if [[ -d /usr/share/zsh/site-functions ]]; then
    fpath=(/usr/share/zsh/site-functions ${fpath:#/usr/share/zsh/site-functions})
fi

# Запуск вбудованого механізму автодоповнення.
# compinit перевіряє права каталогів і не використовує прапорці -u/-i.
autoload -Uz compinit

# Швидкий шлях: dump існує, скомпільований (.zwc) і не старший за 7 днів —
# compinit -C пропускає compaudit (скан прав ~1150 файлів) та регенерацію.
# Повний compinit + zcompile виконуються щонайменше раз на тиждень.
# Для примусового повного аудиту: rm ~/.cache/zsh/zcompdump* та перезапуск.
_compdump="$ZSH_CACHE_DIR/zcompdump"
typeset -ga _compdump_mtime
_compdump_mtime=(-1)
zstat -A _compdump_mtime +mtime -- "$_compdump" 2>/dev/null
if (( _compdump_mtime[1] >= 0 )) &&
   (( EPOCHSECONDS - _compdump_mtime[1] < 604800 )) &&
   [[ -s "$_compdump.zwc" ]]; then
    compinit -C -d "$_compdump"
else
    compinit -d "$_compdump"
    zcompile -- "$_compdump"
fi
unset _compdump _compdump_mtime

# Поведінкові setopt (AUTO_LIST, AUTO_MENU, COMPLETE_IN_WORD)
# налаштовані вище (секція 2) — тут лише zstyle та compinit.

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

# ============================================================
# 5. АЛІАСИ
# Окремий файл: найактивніше редагована частина конфігурації.
# ============================================================

source "$ZSH_CONFIG_DIR/alias.zsh"

# ============================================================
# 6. КЛАВІАТУРА (EMACS-РЕЖИМ)
# ============================================================

# Штатний Emacs-режим редагування; Neovim залишається EDITOR.
bindkey -e

# Навігація історією за введеним префіксом.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
# Дві послідовності: DECCKM (kitty, smkx) та звичайний режим.
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search

# Esc Esc: додати або зняти sudo з командного рядка.
sudo-command-line() {
    [[ -z "$BUFFER" ]] && zle up-history
    if [[ "$BUFFER" == sudo\ * ]]; then
        BUFFER="${BUFFER#sudo }"
    else
        BUFFER="sudo $BUFFER"
    fi
    CURSOR=${#BUFFER}
}
zle -N sudo-command-line
bindkey -M emacs '\e\e' sudo-command-line

# ============================================================
# 7. ІНТЕГРАЦІЇ (fzf / zoxide / starship)
# Init-скрипти генераторів кешуються у $ZSH_CACHE_DIR і
# перегенеровуються не частіше ніж раз на добу: замість 3 fork+exec
# на кожен старт — дешеве builtin-джернило скомпільованого виводу.
# Завантажуємо лише за наявності програм.
# ============================================================

# Кешує вивід init-генератора: $1 — файл кешу, решта — команда.
# Свіжий кеш (<24 год) просто джерниться, інакше перегенеровується.
# Перегенерація АТОМАРНА: запис у тимчасовий файл з PID, потім mv —
# паралельний shell не побачить частково записаний кеш, а збій
# генератора не знищує попередній валідний кеш.
_zsh_init_cache() {
    local file="$1" tmp="$1.tmp.$$"; shift
    typeset -ga mtime
    mtime=(-1)
    if zstat -A mtime +mtime -- "$file" 2>/dev/null &&
       (( EPOCHSECONDS - mtime[1] < 86400 )); then
        source "$file"
        return 0
    fi
    if "$@" >| "$tmp"; then
        mv -f -- "$tmp" "$file"
        source "$file"
    else
        rm -f -- "$tmp"
        # Перегенерація не вдалася: не втрачати старий валідний кеш.
        [[ -s "$file" ]] && source "$file" || return 1
    fi
}

if (($+commands[fzf])); then
    _zsh_init_cache "$ZSH_CACHE_DIR/fzf-init.zsh" fzf --zsh
    if [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/fzf/fzf.zsh" ]]; then
        source "${XDG_CONFIG_HOME:-$HOME/.config}/fzf/fzf.zsh"
    fi
fi
if (($+commands[zoxide])); then
    _zsh_init_cache "$ZSH_CACHE_DIR/zoxide-init.zsh" zoxide init zsh
fi
if (($+commands[starship])); then
    # STARSHIP_CONFIG читається бінарником starship під час рендерингу
    # промпта, тому експортуємо до джернила init-скрипта.
    export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship/starship.toml"
    _zsh_init_cache "$ZSH_CACHE_DIR/starship-init.zsh" starship init zsh
fi

# ============================================================
# 8. ZLE-ПЛАГІНИ (окремий файл з кольорами Nordic)
# Обов'язково останніми серед ZLE — вимога zsh-syntax-highlighting.
# ============================================================

source "$ZSH_CONFIG_DIR/plugins.zsh"

# ============================================================
# 9. ВЛАСНІ КОМАНДИ в окремому каталозі
# ============================================================

for _zsh_script in "$ZSH_CONFIG_DIR"/scripts/*.zsh(N); do
    source "$_zsh_script"
done
unset _zsh_script
