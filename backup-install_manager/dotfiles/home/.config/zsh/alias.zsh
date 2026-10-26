# ZSH ALIASES / FUNCTIONS

# EZA
if command -v eza >/dev/null 2>&1; then
    # Каталог конфігурації eza.
    export EZA_CONFIG_DIR="$HOME/.config/eza"
    # Короткий список.
    alias ls='eza --icons=always --color=always --group-directories-first'
    # Детальний список.
    alias l='eza -lgh --icons=always --color=always --group-directories-first'
    # Детальний список + приховані файли.
    alias la='eza -lgah --icons=always --color=always --group-directories-first'
    # Усі файли.
    alias lsa='eza -a --icons=always --color=always --group-directories-first'
    # Дерево до двох рівнів.
    alias lt='eza -lga --tree --level=2 --icons=always --color=always --group-directories-first'

fi

# PING
if command -v grc >/dev/null 2>&1; then
    alias ping='grc --colour=auto ping -c 4'
else
    alias ping='ping -c 4'
fi

# MIDNIGHT COMMANDER
# Запуск MC з C.UTF-8.
alias mc='LANG=C.UTF-8 LC_ALL=C.UTF-8 mc'

# FILE MANAGERS
# Yazi.
alias y='yazi'
# Superfile.
alias fm='spf'
alias fmh='spf "$HOME"'

# TUI APPLICATIONS
# LazyGit.
alias lg='lazygit'
# LazyDocker.
alias ld='lazydocker'
# LazyRSync
alias lsc='lazyrsync'
# Zellij.
alias ze='zellij'
alias zz='zellij'
# Helix
alias hx='helix'

# USER SCRIPTS
# Генерація паролю.
alias genpass='bash "$HOME/00_setup/scripts_bash/gen_pass.sh"'
# Setup Manager.
alias setup-manager='bash "$HOME/00_setup/scripts_bash/setup-manager/setup-manager.sh"'
# Backup Sync.
alias backup-sync='bash "$HOME/00_setup/scripts_bash/backup-sync/backup-sync.sh"'

# EDITORS
# Zed.
alias zed='zeditor'
# Neovim
alias v='nvim'
alias vi='nvim'
alias vim='nvim'
alias n='nvim'
alias nv='nvim'

# ZSH CONFIG
# Основний .zshrc.
alias nzc='${EDITOR:-nvim} "$HOME/.config/zsh/.zshrc"'
# Alias.
alias nza='${EDITOR:-nvim} "$HOME/.config/zsh/alias.zsh"'
# PATH / environment.
alias nzp='${EDITOR:-nvim} "$HOME/.config/zsh/path.zsh"'
# Каталог додаткових Zsh-скриптів.
alias nzs='${EDITOR:-nvim} "$HOME/.config/zsh/scripts"'

# TELEVISION
# Перейти в каталог, вибраний через Television.
tvd() {
    local dir

    dir="$(tv dirs)" || return

    if [[ -n "$dir" && -d "$dir" ]]; then
        cd -- "$dir" || return
    fi
}
# Відкрити файл через Television у редакторі.
tvf() {
    local file

    file="$(tv files)" || return

    if [[ -n "$file" ]]; then
        "${EDITOR:-nvim}" -- "$file"
    fi
}
# Знайти текст через Television та відкрити результат.
tvt() {
    local result

    result="$(tv text)" || return

    if [[ -n "$result" ]]; then
        "${EDITOR:-nvim}" -- "$result"
    fi
}

# FASTFETCH
# Сумісність зі старою звичкою викликати neofetch.
if command -v fastfetch >/dev/null 2>&1; then
    alias neofetch='fastfetch'
fi

# PYTHON
alias py='python'
# Оновити pip поточного Python.
alias pip_up='python -m pip install --upgrade pip'

# FILE UTILITIES
# Rsync copy.
alias rcp='rsync -avPh'
# Безпечні додаткові варіанти cp/mv.
alias cpi='cp -iv'
alias cpu='cp -uv'
alias mvi='mv -iv'
# rm
alias rmi='rm -Iv'
alias rmr='rm -Ivr'
# mkdir
alias md='mkdir -pv'
# ln
alias lns='ln -s'

# Shell
alias c='clear'
alias x='exit'

# DOCKER COMPOSE
alias dcu='docker compose up'
alias dcud='docker compose up -d'

alias dcd='docker compose down'
alias dcdv='docker compose down --volumes'

alias dcps='docker compose ps'
alias dcpsa='docker compose ps -a'

alias dci='docker compose images'

alias dcst='docker compose start'
alias dcsp='docker compose stop'
alias dcr='docker compose restart'

alias dcl='docker compose logs'
alias dclf='docker compose logs -f'

# DOCKER
# Docker volumes.
alias dcv='docker volume ls'
# Очистити невикористані Docker-об'єкти.
alias dsp='docker system prune'
# Видалити також усі невикористані images.
alias dspa='docker system prune -a'

# SYSTEMD
# Усі service units.
alias sysservice='systemctl list-units --type=service'
# Запущені services.
alias sysrunservice='systemctl list-units --type=service --state=running'

# Service operations
alias sst='sudo systemctl start'
alias sss='systemctl status'
alias ssp='sudo systemctl stop'
alias srt='sudo systemctl restart'
alias se='sudo systemctl enable'
alias sd='sudo systemctl disable'
# Enable/disable + start/stop
# Увімкнути автозапуск і одразу запустити.
alias sen='sudo systemctl enable --now'
# Вимкнути автозапуск і одразу зупинити.
alias sdn='sudo systemctl disable --now'

# GIT
alias gits='git status'
alias gs='git status'
alias gita='git add .'
alias ga='git add .'
alias gitp='git push'
alias gp='git push'
alias gitpl='git pull'
alias gpl='git pull'
# Git commit
gc() {
    local message
    if (($# == 0)); then
        message="add"
    else
        message="$*"
    fi
    git commit -m "$message"
}

# NIXOS
alias snrs='sudo nixos-rebuild switch'
alias snrsu='sudo nixos-rebuild switch --upgrade'
alias snp='sudo nvim /etc/nixos/programs.nix'
alias snnc='sudo nvim /etc/nixos/configuration.nix'
alias snc='sudo nvim /etc/nixos/config.nix'
alias sns='sudo nvim /etc/nixos/services.nix'

# PACMAN / ARCH LINUX
# Reflector
alias mlu='sudo reflector 
    --country Ukraine,Poland,Germany,Czechia,Netherlands 
    --latest 15 
    --protocol https 
    --sort rate 
    --download-timeout 15 
    --save /etc/pacman.d/mirrorlist'

alias mls='reflector 
    --country Ukraine,Poland,Germany,Czechia,Netherlands 
    --latest 15 
    --protocol https 
    --sort rate 
    --download-timeout 15'

alias mln='sudoedit /etc/pacman.d/mirrorlist'

# Pacman
# Встановити пакет.
alias spi='sudo pacman -S'
# Повне оновлення системи.
alias spu='sudo pacman -Syu'
# Оновити базу файлів.
alias spfy='sudo pacman -Fy'
# Пошук.
alias spss='sudo pacman -Ss'
# Видалення.
alias spr='sudo pacman -R'
alias sprns='sudo pacman -Rns'

# ORPHAN PACKAGES
# Показує пакети, які:
#   - були встановлені як залежності
#   - більше не потрібні жодному встановленому пакету
sprs() {
    local -a packages
    local answer
    # Отримати список orphan-пакетів
    packages=("${(@f)$(pacman -Qtdq 2>/dev/null)}")
    # Якщо orphan-пакетів немає
    if ((${#packages[@]} == 0)); then
        printf 'Orphan-пакети не знайдено.\n'
        return 0
    fi
    # Показати список
    printf 'Знайдено orphan-пакетів: %d\n\n' "${#packages[@]}"
    printf 'Буде запропоновано видалити:\n'
    local package
    for package in "${packages[@]}"; do
        printf '  %s\n' "$package"
    done
    printf '\n'
    # Підтвердження
    printf 'Видалити ці пакети? [y/N]: '
    read -r answer
    case "${answer:l}" in
        y | yes | так)
            ;;
        *)
            printf 'Скасовано.\n'
            return 0
            ;;
    esac
    # Видалення
    sudo pacman -Rns -- "${packages[@]}"
}

sprsl() {
    local -a packages
    packages=("${(@f)$(pacman -Qtdq 2>/dev/null)}")
    if ((${#packages[@]} == 0)); then
        printf 'Orphan-пакети не знайдено.\n'
        return 0
    fi
    printf 'Orphan-пакети: %d\n\n' "${#packages[@]}"
    printf '  %s\n' "${packages[@]}"
}

# PARU
# Встановлення пакетів без повторного встановлення
# вже актуальних пакетів.
alias pi='paru -S --skipreview --needed'
# Повне оновлення.
alias pu='paru -Syu --skipreview --needed'
# Оновлення тільки AUR-пакетів.
alias pua='paru -Sua --skipreview --needed'
# Пошук.
alias pss='paru -Ss'
# Видалення.
alias pr='paru -R'

# APT / UBUNTU
# alias sau='sudo apt update && sudo apt upgrade'
# alias sai='sudo apt -y install'
# alias sar='sudo apt -y remove'
# alias sap='sudo apt -y purge'
# alias saa='sudo apt autoremove'
# alias sas='sudo apt search'
# alias sal='sudo apt list --installed'

# MIKROTIK
# Перезавантаження MikroTik через SSH.
alias mikreboot='ssh -p 2240 -i "$HOME/.ssh/id_mik" roman@192.168.88.1 "/system reboot"'

# SUDO COMMAND LINE
sudo-command-line() {
    # Якщо командний рядок порожній —
    # завантажуємо попередню команду.
    [[ -z "$BUFFER" ]] && zle up-history
    if [[ "$BUFFER" == sudo\ * ]]; then
        # sudo command -> command
        LBUFFER="${LBUFFER#sudo }"
    elif [[ "$BUFFER" == "$EDITOR"\ * ]]; then
        # nvim file -> sudoedit file
        LBUFFER="${LBUFFER#"$EDITOR" }"
        LBUFFER="sudoedit $LBUFFER"
    elif [[ "$BUFFER" == sudoedit\ * ]]; then
        # sudoedit file -> nvim file
        LBUFFER="${LBUFFER#sudoedit }"
        LBUFFER="$EDITOR $LBUFFER"
    else
        # command -> sudo command
        LBUFFER="sudo $LBUFFER"
    fi
}
zle -N sudo-command-line
# Emacs mode.
bindkey -M emacs '\e\e' sudo-command-line
# Vim command mode.
bindkey -M vicmd '\e\e' sudo-command-line
# Vim insert mode.
bindkey -M viins '\e\e' sudo-command-line
