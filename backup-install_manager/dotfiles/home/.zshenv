# Мінімальний стартовий .zshenv для НОВИХ сесій zsh (ZDOTDIR ще не заданий).
# Весь вміст змінних середовища живе у $ZDOTDIR/.zshenv
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
[[ -r "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
