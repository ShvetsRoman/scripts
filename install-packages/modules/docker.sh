#!/usr/bin/env bash

# ============================================================
# МОДУЛЬ DOCKER
# ============================================================
#
# Загальна установка виконується через install_registered_module.
# Тут залишається лише Docker-специфічний post-install hook.
# ============================================================

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

    # Якщо конфіги Docker встановлювалися, застосовуємо їх.
    if [[ "$INSTALL_CONFIGS" == true ]]; then
        restart_service docker
    fi
}

install_module() {
    install_registered_module docker
}
