#!/usr/bin/env bash

check_root() {
    if (( EUID != 0 )); then
        die "Installer потрібно запускати через sudo/root."
    fi
}

check_system() {
    log_step "Перевірка системи."

    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64|aarch64)
            ;;
        *)
            log_warning "Архітектура $arch не тестувалась."
            ;;
    esac

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        log_info "OS: ${PRETTY_NAME:-unknown}"
    fi

    log_info "Architecture: $arch"
}

check_dependencies() {
    log_step "Перевірка залежностей."

    local commands=(
        docker
        openssl
        curl
        tar
        gzip
        awk
        sed
        grep
        install
        ip
    )

    local command_name
    for command_name in "${commands[@]}"; do
        require_command "$command_name"
    done

    if ! docker compose version >/dev/null 2>&1; then
        die "Не знайдено Docker Compose v2: docker compose"
    fi

    if command_exists systemctl; then
        if ! systemctl is-active --quiet docker; then
            die "Docker service не запущений."
        fi
    else
        if ! docker info >/dev/null 2>&1; then
            die "Docker daemon недоступний."
        fi
    fi

    log_success "Залежності перевірено."
}
