#!/usr/bin/env bash

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
            /scripts/wp-install.sh
    )

    log_success "WordPress налаштовано."
}

run_healthcheck() {
    log_step "Healthcheck."

    (
        cd "$INSTALL_DIR"
        ./scripts/healthcheck.sh
    )
}
