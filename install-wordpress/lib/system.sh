#!/usr/bin/env bash

get_invoking_user() {
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        printf '%s\n' "$SUDO_USER"
    else
        id -un
    fi
}

get_user_home() {
    local user="$1"
    local home

    home="$(getent passwd "$user" | cut -d: -f6)"

    if [[ -z "$home" ]]; then
        die "Не вдалося визначити home для користувача: $user"
    fi

    printf '%s\n' "$home"
}

init_runtime_defaults() {
    local invoking_user
    local invoking_home

    invoking_user="$(get_invoking_user)"
    invoking_home="$(get_user_home "$invoking_user")"

    if [[ -z "$INSTALL_DIR" ]]; then
        INSTALL_DIR="${invoking_home}/wordpress"
    fi
}

sanitize_project_component() {
    local value="$1"

    value="${value,,}"
    value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//')"

    if [[ -z "$value" ]]; then
        value="wordpress"
    fi

    printf '%s\n' "$value"
}

generate_project_name() {
    local base
    local suffix

    base="$(sanitize_project_component "$(basename -- "$INSTALL_DIR")")"

    suffix="$(
        printf '%s' "$INSTALL_DIR" |
        sha256sum |
        awk '{print substr($1, 1, 8)}'
    )"

    printf 'wp-%s-%s\n' "$base" "$suffix"
}

resolve_runtime_defaults() {
    if [[ -z "$ADMIN_EMAIL" ]]; then
        if [[ "$DEPLOY_MODE" == "internet" ]]; then
            ADMIN_EMAIL="$ACME_EMAIL"
        else
            ADMIN_EMAIL="admin@example.com"
        fi
    fi

    if [[ -z "$PROJECT_NAME" ]]; then
        PROJECT_NAME="$(generate_project_name)"
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
    log_info "User: $(get_invoking_user)"
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
        realpath
        df
        getent
        sha256sum
    )

    local command_name

    for command_name in "${commands[@]}"; do
        require_command "$command_name"
    done

    if ! docker compose version >/dev/null 2>&1; then
        die "Не знайдено Docker Compose v2: docker compose"
    fi

    log_success "Залежності перевірено."
}

check_docker_access() {
    log_step "Перевірка доступу до Docker."

    if docker info >/dev/null 2>&1; then
        log_success "Docker daemon доступний поточному користувачу."
        return 0
    fi

    if (( EUID != 0 )); then
        die "Немає доступу до Docker daemon. Додай користувача до групи docker або запускай через sudo."
    fi

    die "Docker daemon недоступний."
}

validate_privilege_requirements() {
    if [[ "$ENABLE_FAIL2BAN" == true && "$EUID" -ne 0 ]]; then
        die "--enable-fail2ban потребує root."
    fi

    if [[ "$MANAGE_FIREWALL" == true && "$EUID" -ne 0 ]]; then
        die "--manage-firewall потребує root."
    fi
}

prepare_install_path() {
    log_step "Підготовка шляху встановлення."

    local parent
    parent="$(dirname -- "$INSTALL_DIR")"

    if [[ ! -d "$parent" ]]; then
        if ! mkdir -p -- "$parent" 2>/dev/null; then
            die "Не вдалося створити parent directory: $parent. Для системного шляху може знадобитися sudo."
        fi
    fi

    if [[ ! -w "$parent" && ! -d "$INSTALL_DIR" ]]; then
        die "Немає прав на створення $INSTALL_DIR."
    fi

    mkdir -p -- "$INSTALL_DIR"

    [[ -w "$INSTALL_DIR" ]] ||
        die "Немає прав на запис у $INSTALL_DIR."

    chmod 0750 "$INSTALL_DIR"

    log_info "Шлях встановлення: $INSTALL_DIR"
    log_success "Шлях підготовлено."
}

check_disk_space() {
    log_step "Перевірка вільного місця."

    local available_kb
    local required_kb

    available_kb="$(
        df -Pk "$INSTALL_DIR" |
        awk 'NR == 2 {print $4}'
    )"

    required_kb=$((MIN_FREE_SPACE_GB * 1024 * 1024))

    if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
        log_warning "Не вдалося визначити вільне місце."
        return 0
    fi

    if (( available_kb < required_kb )); then
        die "Потрібно щонайменше ${MIN_FREE_SPACE_GB} GiB вільного місця."
    fi

    log_success "Вільного місця достатньо."
}
