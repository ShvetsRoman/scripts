#!/usr/bin/env bash

get_server_ip() {
    ip \
        -4 \
        route \
        get 1.1.1.1 \
        2>/dev/null |
        awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i == "src") {
                        print $(i + 1)
                        exit
                    }
                }
            }
        '
}

show_final_info() {
    local admin_password

    admin_password="$(
        sed -n 's/^WORDPRESS_ADMIN_PASSWORD=//p' "$INSTALL_DIR/.env"
    )"

    printf '\n'
    printf '============================================================\n'
    printf ' WORDPRESS STACK V2.0\n'
    printf '============================================================\n'
    printf '\n'

    if [[ "$NO_START" == true ]]; then
        log_success "Конфігурацію створено та перевірено."
        printf '\n'
        printf 'Запуск:\n'
        printf '  cd %s\n' "$INSTALL_DIR"
        printf '  make up\n'
        printf '  make install\n'
        printf '\n'
        return
    fi

    log_success "WordPress stack встановлено."

    printf '\n'
    printf 'Доступ:\n'

    if [[ "$DEPLOY_MODE" == "internet" ]]; then
        printf '  WordPress: https://%s\n' "$DOMAIN"
        printf '  WP-Admin:  https://%s/wp-admin\n' "$DOMAIN"
        printf '  HTTPS:     Let'\''s Encrypt / Traefik auto-renew\n'
    else
        local server_ip
        server_ip="$(get_server_ip)"

        printf '  WordPress: http://%s\n' "${server_ip:-SERVER_IP}"
        printf '  Hostname:  http://%s\n' "$DOMAIN"
        printf '\n'
        printf 'Для клієнтського /etc/hosts за потреби:\n'
        printf '  %s %s\n' "${server_ip:-SERVER_IP}" "$DOMAIN"
    fi

    printf '\n'
    printf 'Admin:\n'
    printf '  User:     %s\n' "$WORDPRESS_ADMIN_USER"
    printf '  Password: %s\n' "$admin_password"

    printf '\n'
    printf 'Project:\n'
    printf '  %s\n' "$INSTALL_DIR"

    printf '\n'
    printf 'Commands:\n'
    printf '  cd %s\n' "$INSTALL_DIR"
    printf '  make help\n'
    printf '  make status\n'
    printf '  make logs\n'
    printf '  make backup\n'
    printf '  make healthcheck\n'

    printf '\n'
    log_warning "Збережи admin password у password manager."
    log_warning "Не додавай ${INSTALL_DIR}/.env до Git."
}
