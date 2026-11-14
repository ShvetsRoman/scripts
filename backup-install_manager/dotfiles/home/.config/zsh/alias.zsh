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

# LazyDocker для Docker.
alias ld='lazydocker'

# LazyDocker для rootless Podman.
# Socket запускається лише на час роботи LazyDocker,
# якщо до виклику він не був активним.
if (($+commands[podman] && $+commands[lazydocker] && $+commands[systemctl])); then
    ldp() {
        local socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
        local socket_was_active=false
        local lazydocker_exit_code=0

        # Перевірити, чи socket уже працював.
        if systemctl --user is-active --quiet podman.socket; then
            socket_was_active=true
        else
            # Тимчасово запустити socket.
            if ! systemctl --user start podman.socket; then
                print -u2 'Помилка: не вдалося запустити Podman socket.'
                return 1
            fi
        fi

        # Переконатися, що socket доступний.
        if [[ ! -S "$socket" ]]; then
            print -u2 "Помилка: Podman socket не знайдено: $socket"

            # Зупинити socket, якщо його запустила ця функція.
            if [[ "$socket_was_active" == false ]]; then
                systemctl --user stop podman.socket
            fi

            return 1
        fi

        # Запустити LazyDocker з підключенням до Podman API.
        DOCKER_HOST="unix://$socket" lazydocker
        lazydocker_exit_code=$?

        # Не зупиняти socket, якщо він працював до виклику ldp.
        if [[ "$socket_was_active" == false ]]; then
            systemctl --user stop podman.socket
        fi

        return "$lazydocker_exit_code"
    }
fi

# LazyRSync.
alias lsc='lazyrsync'

# Zellij.
alias ze='zellij'

# Helix.
alias hx='helix'

# USER SCRIPTS
# Генерація паролю.
alias genpass='bash "$HOME/00_setup/scripts_bash/gen_pass.sh"'

# Setup Manager.
alias backup-install='bash "$HOME/00_setup/scripts_bash/backup-install_manager/backup-install_manager.sh"'

# Backup Sync.
alias backup-sync='bash "$HOME/00_setup/scripts_bash/backup-sync/backup-sync.sh"'

# EDITORS
# Zed.
alias zed='zeditor'

# Neovim.
alias v='nvim'
alias vim='nvim'

# ZSH CONFIG
# Основний .zshrc.
alias nzc='nvim "$HOME/.config/zsh/.zshrc"'

# Alias.
alias nza='nvim "$HOME/.config/zsh/alias.zsh"'

# PATH / environment.
alias nzp='nvim "$HOME/.config/zsh/path.zsh"'

# Каталог додаткових Zsh-скриптів.
alias nzs='nvim "$HOME/.config/zsh/scripts"'

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

# rm.
alias rmi='rm -Iv'
alias rmr='rm -Ivr'

# mkdir.
alias md='mkdir -pv'

# ln.
alias lns='ln -s'

# SHELL
alias c='clear'
alias x='exit'

# CONTAINER ENGINE: PODMAN / DOCKER
if (($+commands[podman])); then
    # PODMAN COMPOSE
    alias pcu='podman compose up'
    alias pcud='podman compose up -d'
    alias pcd='podman compose down'
    alias pcdv='podman compose down --volumes'
    alias pcps='podman compose ps'
    alias pcpsa='podman compose ps'
    alias pci='podman compose images'
    alias pcst='podman compose start'
    alias pcsp='podman compose stop'
    alias pcr='podman compose restart'
    alias pcl='podman compose logs'
    alias pclf='podman compose logs -f'

    # PODMAN
    alias pv='podman volume ls'
    alias psp='podman system prune'
    alias pspa='podman system prune --all'
fi

# DOCKER
if (($+commands[docker])); then
    # DOCKER COMPOSE
    alias dcu='docker compose up'
    alias dcud='docker compose up -d'
    alias dcd='docker compose down'
    alias dcdv='docker compose down --volumes'
    alias dcps='docker compose ps'
    alias dcpsa='docker compose ps --all'
    alias dci='docker compose images'
    alias dcst='docker compose start'
    alias dcsp='docker compose stop'
    alias dcr='docker compose restart'
    alias dcl='docker compose logs'
    alias dclf='docker compose logs -f'

    # DOCKER
    alias dv='docker volume ls'
    alias dsp='docker system prune'
    alias dspa='docker system prune --all'
fi

# SYSTEMD
# Усі service units.
alias sysservice='systemctl list-units --type=service'

# Запущені services.
alias sysrunservice='systemctl list-units --type=service --state=running'

# Service operations.
alias sst='sudo systemctl start'
alias sss='systemctl status'
alias ssp='sudo systemctl stop'
alias srt='sudo systemctl restart'
alias se='sudo systemctl enable'
alias sd='sudo systemctl disable'

# Enable/disable + start/stop.
# Увімкнути автозапуск і одразу запустити.
alias sen='sudo systemctl enable --now'

# Вимкнути автозапуск і одразу зупинити.
alias sdn='sudo systemctl disable --now'

# GIT
alias gs='git status'
alias gp='git push'
alias gpl='git pull'

# Git add.
ga() {
    if (($# == 0)); then
        print -u2 'Використання: ga "файл|директорія|. - всі зміни поточної директорії"'
        return 2
    fi

    git add "$@"
}

# Git commit.
gc() {
    if (($# == 0)); then
        print -u2 'Використання: gc "повідомлення коміту"'
        return 2
    fi

    git commit -m "$*"
}

# PACMAN / ARCH LINUX
# Reflector.
alias mlu='sudo reflector --country Ukraine,Poland,Germany,Czechia,Netherlands --latest 15 --protocol https --sort rate --download-timeout 15 --save /etc/pacman.d/mirrorlist'

alias mls='reflector --country Ukraine,Poland,Germany,Czechia,Netherlands --latest 15 --protocol https --sort rate --download-timeout 15'

alias mln='sudoedit /etc/pacman.d/mirrorlist'

# Pacman.
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
# Допоміжна функція: список orphan-пакетів, які:
#   - були встановлені як залежності;
#   - більше не потрібні жодному встановленому пакету.
_orphan_packages() {
    pacman -Qtdq 2>/dev/null
}

sprs() {
    local -a packages
    local answer
    local package

    # Отримати список orphan-пакетів.
    packages=("${(@f)$(_orphan_packages)}")

    # Якщо orphan-пакетів немає.
    if ((${#packages[@]} == 0)); then
        printf 'Orphan-пакети не знайдено.\n'
        return 0
    fi

    # Показати список.
    printf 'Знайдено orphan-пакетів: %d\n\n' "${#packages[@]}"
    printf 'Буде запропоновано видалити:\n'

    for package in "${packages[@]}"; do
        printf '  %s\n' "$package"
    done

    printf '\n'

    # Підтвердження.
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

    # Видалення.
    sudo pacman -Rns -- "${packages[@]}"
}

sprsl() {
    local -a packages

    packages=("${(@f)$(_orphan_packages)}")

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
