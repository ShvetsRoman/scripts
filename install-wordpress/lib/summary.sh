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
        sed \
            -n \
            's/^WORDPRESS_ADMIN_PASSWORD=//p' \
            "$INSTALL_DIR/.env"
    )"

    printf '\n'
    printf '============================================================\n'
    printf ' WORDPRESS STACK V2.0.8\n'
    printf '============================================================\n'
    printf '\n'

    printf 'Install path:\n'
    printf '  %s\n' "$INSTALL_DIR"
    printf '\n'

    if [[ "$NO_START" == true ]]; then
        log_success "Конфігурацію створено та перевірено."

        printf '\n'
        printf 'Запуск:\n'
        printf '  cd %q\n' "$INSTALL_DIR"
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
    else
        local server_ip
        server_ip="$(get_server_ip)"

        printf '  LAN hostname: http://%s\n' "$DOMAIN"
        printf '  На сервері:   http://localhost\n'
        printf '  На сервері:   http://127.0.0.1\n'

        printf '\n'
        printf 'Для доступу з іншого LAN-компʼютера додай у /etc/hosts:\n'
        printf '  %s %s\n' "${server_ip:-SERVER_IP}" "$DOMAIN"

        printf '\n'
        printf 'Важливо: localhost і 127.0.0.1 працюють лише на самому сервері.\n'
    fi

    printf '\n'
    printf 'Admin:\n'
    printf '  User:     %s\n' "$WORDPRESS_ADMIN_USER"
    printf '  Password: %s\n' "$admin_password"

    printf '\n'
    printf 'Commands:\n'
    printf '  cd %q\n' "$INSTALL_DIR"
    printf '  make help\n'
    printf '  make status\n'
    printf '  make logs\n'
    printf '  make backup\n'
    printf '  make healthcheck\n'

    printf '\n'

    if (( EUID == 0 )); then
        log_info "Installer запущено як root."
    else
        log_info "Installer виконано без root."
    fi

    log_warning "Збережи admin password у password manager."
    log_warning "Не додавай ${INSTALL_DIR}/.env до Git."
}
