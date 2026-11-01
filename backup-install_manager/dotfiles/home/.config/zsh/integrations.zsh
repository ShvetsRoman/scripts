# Інтеграції: завантажуємо лише за наявності програм.
if (($+commands[fzf])); then
    eval "$(fzf --zsh)"
    if [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/fzf/fzf.zsh" ]]; then
        source "${XDG_CONFIG_HOME:-$HOME/.config}/fzf/fzf.zsh"
    fi
fi
if (($+commands[zoxide])); then
    eval "$(zoxide init zsh)"
fi
if (($+commands[starship])); then
    eval "$(starship init zsh)"
    export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship/starship.toml"
fi
