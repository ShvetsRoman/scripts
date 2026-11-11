# ZSH — модульна конфігурація Arch Linux / Kitty

[[ -o interactive ]] || return 0

# Не робимо глобальні readonly, щоб повторний source працював.
typeset -g ZSH_CONFIG_DIR="${ZDOTDIR:-$HOME/.config/zsh}"
# XDG_CACHE_HOME/XDG_STATE_HOME тут явно не встановлюються (див. path.zsh):
# fallback-значення нижче збігаються зі стандартними дефолтами XDG spec.
# Якщо колись зміните дефолти в path.zsh — оновіть і ці рядки.
typeset -g ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
typeset -g ZSH_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
mkdir -p -- "$ZSH_CACHE_DIR" "$ZSH_STATE_DIR" || return 1

# Послідовність важлива: compinit -> клавіші -> інтеграції -> highlighting.
for _zsh_module in path options history completion alias keybindings integrations plugins; do
    if [[ -r "$ZSH_CONFIG_DIR/${_zsh_module}.zsh" ]]; then
        source "$ZSH_CONFIG_DIR/${_zsh_module}.zsh"
    fi
done
unset _zsh_module

# Власні команди в окремому каталозі.
for _zsh_script in "$ZSH_CONFIG_DIR"/scripts/*.zsh(N); do
    source "$_zsh_script"
done
unset _zsh_script
