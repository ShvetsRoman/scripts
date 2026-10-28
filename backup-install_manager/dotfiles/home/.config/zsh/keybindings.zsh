# Штатний Emacs-режим редагування; Neovim залишається EDITOR.
bindkey -e
# Навігація історією за введеним префіксом.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
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
