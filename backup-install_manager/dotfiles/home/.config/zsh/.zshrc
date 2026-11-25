# ============================================================
# ZSHRC — ІНТЕРАКТИВНА СЕСІЯ ZSH (Arch Linux)
# ============================================================
# Порядок завантаження зверху вниз:
#   1 PATH → 2 опції → 3 історія → 4 доповнення → 5 аліаси →
#   6 клавіатура → 7 інтеграції → 8 ZLE-плагіни → 9 власні команди
#
# Змінні середовища (LANG, EDITOR, XDG) — у .zshenv, не тут.
# Аліаси — alias.zsh, ZLE-плагіни — plugins.zsh, свої команди — scripts/.

[[ -o interactive ]] || return 0

# --- Шляхи конфігурації, кешу та стану -------------------------
typeset -g ZSH_CONFIG_DIR="${ZDOTDIR:-$HOME/.config/zsh}"
typeset -g ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
typeset -g ZSH_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
if ! mkdir -p -- "$ZSH_CACHE_DIR" "$ZSH_STATE_DIR"; then
    print -u2 "zsh: не вдалося створити $ZSH_CACHE_DIR або $ZSH_STATE_DIR"
    return 1
fi

# ============================================================
# 1. PATH
# ============================================================

# Користувацькі програми мають пріоритет над системними.
if [[ -d "$HOME/.local/bin" ]]; then
    path=(
        "$HOME/.local/bin"
        $path
    )
fi
# Видалити дублікати з PATH.
typeset -U path PATH

# ============================================================
# 2. ОПЦІЇ
# ============================================================

setopt INTERACTIVE_COMMENTS AUTO_CD AUTO_LIST AUTO_MENU COMPLETE_IN_WORD
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS EXTENDED_GLOB
unsetopt BEEP CORRECT

# ============================================================
# 3. ІСТОРІЯ
# ============================================================

HISTFILE="$ZSH_STATE_DIR/history"
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY INC_APPEND_HISTORY HIST_FCNTL_LOCK
setopt HIST_IGNORE_DUPS HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS HIST_VERIFY HIST_NO_STORE
# Не змішуємо історію різних вікон.
unsetopt SHARE_HISTORY

# ============================================================
# 4. ДОПОВНЕННЯ
# ============================================================

# Системні функції доповнення Arch Linux (zsh-completions).
fpath=(/usr/share/zsh/site-functions ${fpath:#/usr/share/zsh/site-functions})

# compinit перевіряє права каталогів і сам оновлює дамп, коли
# змінюється набір доповнень: нові команди після pacman -S
# підхоплюються автоматично. Дамп у $ZSH_CACHE_DIR прискорює старт.
autoload -Uz compinit
compinit -d "$ZSH_CACHE_DIR/zcompdump"

# Меню вибору варіанта (діє, коли Tab не перехоплено fzf — секція 7).
zstyle ':completion:*' menu select

# Групи, підписи та повідомлення.
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{cyan}-- %d --%f'
zstyle ':completion:*:messages' format '%F{yellow}%d%f'
zstyle ':completion:*:warnings' format '%F{red}Немає відповідників: %d%f'
zstyle ':completion:*' verbose yes

# Без врахування регістру, потім часткове доповнення.
zstyle ':completion:*' matcher-list \
    'm:{a-zA-Z}={A-Za-z}' \
    'r:|[._-]=** r:|=**'


# ============================================================
# 5. АЛІАСИ
# ============================================================

if [[ -r "$ZSH_CONFIG_DIR/alias.zsh" ]]; then
    source "$ZSH_CONFIG_DIR/alias.zsh"
else
    print -u2 "zsh: не знайдено $ZSH_CONFIG_DIR/alias.zsh"
fi

# ============================================================
# 6. КЛАВІАТУРА (EMACS-РЕЖИМ)
# ============================================================

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
# Завантажуємо лише за наявності програми.
# ============================================================

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
    # Читається бінарником starship під час рендерингу промпта.
    export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship/starship.toml"
    eval "$(starship init zsh)"
fi

# ============================================================
# 8. ZLE-ПЛАГІНИ
# Обов'язково останніми серед ZLE — вимога zsh-syntax-highlighting.
# ============================================================

if [[ -r "$ZSH_CONFIG_DIR/plugins.zsh" ]]; then
    source "$ZSH_CONFIG_DIR/plugins.zsh"
else
    print -u2 "zsh: не знайдено $ZSH_CONFIG_DIR/plugins.zsh"
fi

# ============================================================
# 9. ВЛАСНІ КОМАНДИ
# ============================================================

for _zsh_script in "$ZSH_CONFIG_DIR"/scripts/*.zsh(N); do
    source "$_zsh_script"
done
unset _zsh_script
