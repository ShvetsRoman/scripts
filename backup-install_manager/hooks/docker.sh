#!/usr/bin/env bash
# Логіка hook; середовище надає src/hooks/hook_runtime.sh.
hook_main() {
    # Hooks модуля docker.
    hook_add_to_docker_group() {
        local user="${SUDO_USER:-$USER}"
        getent group docker >/dev/null || {
            log warn 'Немає групи docker'
            return 0
        }
        id -nG "$user" | tr ' ' '\n' | grep -qx docker && {
            log info "$user уже в docker"
            return 0
        }
        [[ "${DRY_RUN:-false}" == true ]] && {
            log info "[DRY-RUN] usermod -aG docker $user"
            return 0
        }
        sudo usermod -aG docker "$user"
        log warn 'Потрібен повторний вхід'
    }

    # Hook: увімкнути docker.socket.
    hook_enable_docker_socket() {
        systemctl is-enabled docker.socket >/dev/null 2>&1 && {
            log info 'уже увімкнено'
            return 0
        }
        [[ "${DRY_RUN:-false}" == true ]] && {
            log info '[DRY-RUN] systemctl enable docker.socket'
            return 0
        }
        sudo systemctl enable docker.socket && log ok 'docker.socket'
    }

    hook_add_to_docker_group
    hook_enable_docker_socket
}
