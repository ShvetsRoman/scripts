#!/usr/bin/env bash

# ============================================================
# КЕРУВАННЯ SYSTEMD-СЕРВІСАМИ
# ============================================================

enable_service() {
    local service="$1"
    log_step "Увімкнення сервісу: $service"
    run_cmd sudo systemctl enable --now "$service"
}

restart_service() {
    local service="$1"
    log_step "Перезапуск сервісу: $service"
    run_cmd sudo systemctl restart "$service"
}

service_active() {
    systemctl is-active --quiet "$1"
}

service_enabled() {
    systemctl is-enabled --quiet "$1"
}
