# ZSH ENVIRONMENT / PATH

# Основна локаль системи для поточної shell-сесії.
export LANG="uk_UA.UTF-8"

# Editor
# Основний текстовий редактор.
export EDITOR="nvim"
# Редактор для програм, які використовують VISUAL.
export VISUAL="$EDITOR"
# Редактор для sudoedit та програм, які підтримують SUDO_EDITOR.
export SUDO_EDITOR="$EDITOR"

# Terminal
# Основний емулятор термінала.
export TERMINAL="kitty"

# Browser
# Основний браузер.
export BROWSER="google-chrome-stable"

# XDG BASE DIRECTORIES
# Стандартні дефолти з XDG Base Directory spec експортуємо лише тоді,
# коли вони ще не задані: значення користувача (з ~/.profile, systemd
# environment тощо) не перезаписуємо. Якщо колись знадобляться
# НЕСТАНДАРТНІ шляхи — задати їх до запуску shell або тут,
# і синхронно оновити fallback у .zshrc (рядки з ZSH_CACHE_DIR/ZSH_STATE_DIR).

: "${XDG_CONFIG_HOME:="$HOME/.config"}"
export XDG_CONFIG_HOME

# PATH
# Локальні користувацькі програми мають пріоритет над системними.
if [[ -d "$HOME/.local/bin" ]]; then
    path=(
        "$HOME/.local/bin"
        $path
    )
fi
# Видалити дублікати з PATH.
typeset -U path PATH
