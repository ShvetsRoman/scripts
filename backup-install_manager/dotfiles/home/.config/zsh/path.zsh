# ZSH ENVIRONMENT / PATH

# Основна локаль системи для поточної shell-сесії.
export LANG="uk_UA.UTF-8"

# DEFAULT APPLICATIONS
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
# Конфігураційні файли.
export XDG_CONFIG_HOME="$HOME/.config"
# Дані програм.
export XDG_DATA_HOME="$HOME/.local/share"
# Кеш програм.
export XDG_CACHE_HOME="$HOME/.cache"
# Постійний runtime/state стан програм.
export XDG_STATE_HOME="$HOME/.local/state"

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

# PROGRAM CONFIGURATION
# Starship
export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship/starship.toml"
