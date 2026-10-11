#!/usr/bin/env bash
# Змінні цього файла читаються іншими модулями через source.
# shellcheck disable=SC2034
# Модуль docker: пакети, конфігурації та необов’язковий post-install hook.
MODULE_ID="docker"
MODULE_TITLE="Docker"
MODULE_ORDER=60
MODULE_DEPENDS=""
MODULE_SERVICES_LIST="docker"
MODULE_POST_HOOK="configure_docker_user"

# Пакети офіційних репозиторіїв Arch Linux.
PACMAN_PACKAGES=(
    docker
    docker-compose
)

# Пакети AUR (через paru).
AUR_PACKAGES=(

)

# Зовнішні програми: ID|TYPE|URL|CHECK_COMMAND[|DEST|EXEC_REL].
# Для TYPE=script запускається код із вказаного URL: перевіряйте джерело!
GITHUB_ITEMS=(
)

# Конфіги: ID|SCOPE|SOURCE|DESTINATION (SOURCE відносно DOTFILES_DIR).
# SCOPE: home або system. Для home DESTINATION відносно ~.
CONFIG_ITEMS=(
)

# ------------------------------------------------------------
# POST-INSTALL: специфічні налаштування модуля
# ------------------------------------------------------------
configure_docker_user() {
    local current_user="${SUDO_USER:-${USER:-}}"

    if [[ -z "$current_user" || "$current_user" == root ]]; then
        log_error "Не вдалося визначити користувача для групи docker."
        return 1
    fi

    if ! id -nG "$current_user" | grep -qw docker; then
        log_step "Додавання користувача '$current_user' до групи docker."
        run_cmd sudo usermod -aG docker "$current_user"
        log_warn "Для застосування групи docker потрібно повторно увійти в систему."
    else
        log_info "Користувач '$current_user' вже входить до групи docker."
    fi

    # Перезапускаємо Docker тільки якщо для модуля реально є
    # конфіги і їх копіювання не вимкнене.
    if [[ "$INSTALL_CONFIGS" == true && -n "${MODULE_CONFIGS[docker]-}" ]]; then
        restart_service docker
    fi
}
