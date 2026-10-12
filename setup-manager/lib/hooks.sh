#!/usr/bin/env bash
# Точкові hooks, виконуються тільки після успішного встановлення пакунків.
hook_docker() {
    local user="${SUDO_USER:-$USER}"
    if ! getent group docker >/dev/null; then log_warn 'Група docker відсутня'; return 0; fi
    if id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
        log_info "Користувач $user уже в групі docker"
        return 0
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then log_info "[DRY-RUN] sudo usermod -aG docker $user"; return 0; fi
    sudo usermod -aG docker "$user"
    log_warn 'Для застосування групи docker потрібно повторно увійти в сесію'
}
hook_shell() {
    local user="${SUDO_USER:-$USER}" shell_path current
    shell_path="$(command -v zsh || :)"
    [[ -n "$shell_path" ]] || { log_warn 'Zsh не встановлено'; return 0; }
    current="$(getent passwd "$user" | cut -d: -f7)"
    [[ "$current" != "$shell_path" ]] || { log_info 'Zsh уже є стандартною оболонкою'; return 0; }
    if [[ "${DRY_RUN:-false}" == true ]]; then log_info "[DRY-RUN] chsh -s $shell_path $user"; return 0; fi
    # Установка оболонки користувача, root не змінюється автоматично.
    chsh -s "$shell_path" "$user"
}
hooks_run() {
    case "$1" in
        docker) hook_docker ;;
        shell) hook_shell ;;
    esac
}
