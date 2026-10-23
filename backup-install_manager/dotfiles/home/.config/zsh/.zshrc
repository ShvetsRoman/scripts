# ============================================================
# ZSH CONFIGURATION
# ============================================================

# Основний каталог конфігурації Zsh.
readonly ZSH_CONFIG_DIR="$HOME/.config/zsh"

# Каталог додаткових скриптів.
readonly ZSH_SCRIPTS_DIR="$ZSH_CONFIG_DIR/scripts"

# Каталог кешу Zsh.
readonly ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"

# Каталог постійного стану Zsh.
readonly ZSH_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"

# Створюємо службові каталоги, якщо їх ще немає.
mkdir -p "$ZSH_CACHE_DIR"
mkdir -p "$ZSH_STATE_DIR"

# ============================================================
# POWERLEVEL10K INSTANT PROMPT
# ============================================================
# Instant prompt повинен знаходитися максимально близько
# до початку .zshrc.
#
# Код, який може вимагати введення користувача
# (паролі, підтвердження [y/n] тощо),
# потрібно розміщувати ВИЩЕ цього блоку.

# if [[ -r "$ZSH_CACHE_DIR/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#     source "$ZSH_CACHE_DIR/p10k-instant-prompt-${(%):-%n}.zsh"
# fi

# ============================================================
# BASIC ZSH OPTIONS
# ============================================================
# Дозволяє коментарі "#" безпосередньо в інтерактивній оболонці.
setopt INTERACTIVE_COMMENTS

# ============================================================
# PATH
# ============================================================
# Окремий файл для налаштування PATH.
if [[ -f "$ZSH_CONFIG_DIR/path.zsh" ]]; then
    source "$ZSH_CONFIG_DIR/path.zsh"
fi

# ============================================================
# ALIASES
# ============================================================
# Окремий файл з aliases.
if [[ -f "$ZSH_CONFIG_DIR/alias.zsh" ]]; then
    source "$ZSH_CONFIG_DIR/alias.zsh"
fi

# ============================================================
# ADDITIONAL ZSH SCRIPTS
# ============================================================
# Автоматично підключаємо всі *.zsh файли:
# ~/.config/zsh/scripts/
# (N) — якщо файлів немає, Zsh не видає помилку.
if [[ -d "$ZSH_SCRIPTS_DIR" ]]; then
    for script in "$ZSH_SCRIPTS_DIR"/*.zsh(N); do
        source "$script"
    done
fi
# Видаляє змінну script після завершення циклу
unset script

# ============================================================
# FZF
# ============================================================
# Підключення окремої конфігурації fzf.
if command -v fzf >/dev/null 2>&1; then
    if [[ -f "$HOME/.config/fzf/fzf.zsh" ]]; then
        source "$HOME/.config/fzf/fzf.zsh"
    fi
fi

# ============================================================
# HISTORY
# ============================================================
# History зберігаємо відповідно до XDG Base Directory:
# ~/.local/state/zsh/history

HISTFILE="$ZSH_STATE_DIR/history"
# Кількість команд у пам'яті поточної сесії.
HISTSIZE=1000
# Кількість команд, які записуються у файл.
SAVEHIST=1000
# Формат часу.
HIST_STAMPS="yyyy-mm-dd"
# Команди, які не потрібно зберігати.
HISTORY_IGNORE="(l|la|lt|ls|lsa|ll|lla|pwd|exit|x|clear|c)"
# History options
# Формат:
# : start:elapsed;command
setopt EXTENDED_HISTORY
# Додавати команди до history відразу.
setopt INC_APPEND_HISTORY
# Спільна history між відкритими сесіями Zsh.
setopt SHARE_HISTORY
# Не записувати команду, якщо попередня була такою самою.
setopt HIST_IGNORE_DUPS
# Видаляти старі дублікати.
setopt HIST_IGNORE_ALL_DUPS
# Не записувати команду, яка починається з пробілу.
setopt HIST_IGNORE_SPACE
# Не записувати дублікати у файл history.
setopt HIST_SAVE_NO_DUPS
# Після history expansion показувати команду,
# а не виконувати її одразу.
setopt HIST_VERIFY
# Додавати history, а не перезаписувати файл.
setopt APPEND_HISTORY
# Не записувати самі history-команди.
setopt HIST_NO_STORE
# Прибирати зайві пробіли.
setopt HIST_REDUCE_BLANKS

# ============================================================
# ZSH AUTOCOMPLETE
# ============================================================
# Потужне автодоповнення команд у стилі Fish.
if [[ -f "/usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh" ]]; then
    source "/usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh"
fi

# ============================================================
# ZSH AUTOSUGGESTIONS
# ============================================================
# Показує підказки з history під час введення команди.
if [[ -f "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# ============================================================
# TELEVISION
# ============================================================
if command -v tv >/dev/null 2>&1; then
    eval "$(tv init zsh)"
fi

# ============================================================
# ZOXIDE
# ============================================================
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

# ============================================================
# THEME
# ============================================================
# Powerlevel10k використовуємо, якщо він встановлений.
# Якщо Powerlevel10k відсутній, використовуємо Starship.
if [[ -f "/Qusr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme" ]]; then
    # Powerlevel10k
    source "/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme"
    # Конфігурація Powerlevel10k.
    P10K_CONFIG="$ZSH_CONFIG_DIR/p10k_my_nordic_v1.zsh"
    if [[ -f "$P10K_CONFIG" ]]; then
        source "$P10K_CONFIG"
    else
        source "$ZSH_CONFIG_DIR/p10k.zsh"
    fi
else
    # Starship
    if command -v starship >/dev/null 2>&1; then
        eval "$(starship init zsh)"
    fi
fi

# ============================================================
# ZSH SYNTAX HIGHLIGHTING
# ============================================================
# zsh-syntax-highlighting рекомендується підключати
# максимально близько до кінця .zshrc, щоб він бачив
# усі віджети та key bindings, створені раніше.
if [[ -f "/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
