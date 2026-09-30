#!/usr/bin/env bash

normalize_wordpress_permissions() {
    log_step "Нормалізація прав WordPress."

    (
        cd "$INSTALL_DIR"

        docker compose \
            -f compose.yml \
            -f compose.override.yml \
            exec \
            -T \
            -u 0 \
            wordpress \
            sh -c '
                chown -R www-data:www-data /var/www/html
                find /var/www/html -type d -exec chmod 0755 {} +
                find /var/www/html -type f -exec chmod 0644 {} +
                if [ -f /var/www/html/wp-config.php ]; then chmod 0640 /var/www/html/wp-config.php; fi
            '
    )

    log_success "Права WordPress нормалізовано."
}

install_wordpress() {
    log_step "Встановлення WordPress."

    (
        cd "$INSTALL_DIR"

        docker compose \
            -f compose.yml \
            -f compose.override.yml \
            exec \
            -T \
            wpcli \
            bash \
            /scripts/wp-install.sh
    )

    log_success "WordPress налаштовано."
}

run_healthcheck() {
    log_step "Healthcheck."

    (
        cd "$INSTALL_DIR"

        bash ./scripts/healthcheck.sh
    )
}
