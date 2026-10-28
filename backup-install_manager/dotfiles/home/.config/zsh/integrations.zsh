# Інтеграції: завантажуємо лише за наявності програм.
if (( $+commands[fzf] )) && [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/fzf/fzf.zsh" ]]; then
    source "${XDG_CONFIG_HOME:-$HOME/.config}/fzf/fzf.zsh"
fi
if (( $+commands[tv] )); then
    eval "$(tv init zsh)"
fi
if (( $+commands[zoxide] )); then
    eval "$(zoxide init zsh)"
fi
if (( $+commands[starship] )); then
    eval "$(starship init zsh)"
fi
