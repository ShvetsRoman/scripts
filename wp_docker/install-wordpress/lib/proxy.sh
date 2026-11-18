#!/usr/bin/env bash
# Центральний proxy-стек (Traefik) для кількох сайтів на одному сервері.
# Один стек на 80/443; сайти приєднуються через мережу PROXY_NETWORK.

proxy_subnet_candidates() {
    printf '%s\n' \
        172.31.250.0/24 \
        172.31.249.0/24 \
        172.31.248.0/24 \
        172.31.247.0/24 \
        172.31.246.0/24 \
        172.31.245.0/24 \
        172.31.244.0/24 \
        172.31.243.0/24
}

resolve_proxy_subnet() {
    log_step "Вибір PROXY_SUBNET."

    # Повторний запуск: використовуємо значення з наявного .env.
    local env_file="$INSTALL_DIR/.env"

    if [[ -f "$env_file" ]]; then
        local old_subnet
        old_subnet="$(read_env_value "$env_file" PROXY_SUBNET)"

        if [[ -n "$old_subnet" ]]; then
            if ! cidr_range "$old_subnet" >/dev/null; then
                die "Некоректна PROXY_SUBNET у наявному .env: $old_subnet"
            fi

            PROXY_SUBNET="$old_subnet"
            log_info "PROXY_SUBNET з наявного .env: $PROXY_SUBNET."
            return 0
        fi
    fi

    local existing
    existing="$(collect_existing_ipv4_subnets || true)"

    if [[ -z "$existing" ]]; then
        PROXY_SUBNET="$(proxy_subnet_candidates | head -n 1)"
        return 0
    fi

    local candidate conflict

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue

        conflict="$(
            first_conflicting_subnet "$candidate" "$existing"
        )" || conflict=""

        if [[ -z "$conflict" ]]; then
            PROXY_SUBNET="$candidate"
            return 0
        fi
    done <<<"$(proxy_subnet_candidates)"

    die "Не знайдено вільну підмережу для мережі ${PROXY_NETWORK} у 172.16.0.0/12."
}

create_proxy_env_file() {
    local env_file="$INSTALL_DIR/.env"

    cat > "$env_file" <<EOF
COMPOSE_PROJECT_NAME=wp-proxy

PROXY_SUBNET=${PROXY_SUBNET}
PROXY_NETWORK=${PROXY_NETWORK}

TRAEFIK_VERSION=${TRAEFIK_VERSION}
TRAEFIK_MEM_LIMIT=${TRAEFIK_MEM_LIMIT}
PIDS_LIMIT=${PIDS_LIMIT}

ACME_EMAIL=${ACME_EMAIL}
EOF

    chmod 0600 "$env_file"

    log_success "Створено $env_file (PROXY_SUBNET=${PROXY_SUBNET})."
}

create_proxy_traefik_config() {
    local config_file="$INSTALL_DIR/traefik/traefik.yml"
    local ca_server_line=""

    if [[ "$ACME_STAGING" == true ]]; then
        ca_server_line='      caServer: "https://acme-staging-v02.api.letsencrypt.org/directory"'
        log_warning "Let's Encrypt STAGING активний: сертифікати не будуть довірені браузерами."
    fi

    cat > "$config_file" <<EOF
# Managed by wordpress-stack installer (--init-proxy).
log:
  level: WARN

accessLog: {}

api:
  dashboard: false

ping: {}

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: "${PROXY_NETWORK}"

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${ACME_EMAIL}"
${ca_server_line}
      storage: "/letsencrypt/acme.json"
      httpChallenge:
        entryPoint: web
EOF

    chmod 0644 "$config_file"

    log_success "traefik.yml готова (провайдер docker: ${PROXY_NETWORK})."
}

create_proxy_structure() {
    log_step "Створення структури proxy-стека."

    mkdir -p "$INSTALL_DIR/traefik" "$INSTALL_DIR/letsencrypt"
    chmod 0700 "$INSTALL_DIR/letsencrypt"

    install -m 0644 \
        "$SCRIPT_DIR/templates/proxy/compose.yml" \
        "$INSTALL_DIR/compose.yml"

    install -m 0644 \
        "$SCRIPT_DIR/templates/proxy/Makefile" \
        "$INSTALL_DIR/Makefile"

    cat > "$INSTALL_DIR/.gitignore" <<EOF
.env
letsencrypt/
EOF

    log_success "Структуру proxy-стека створено."
}

validate_proxy() {
    log_step "Перевірка Docker Compose (proxy)."

    (
        cd "$INSTALL_DIR" || exit 1
        docker compose -f compose.yml config --quiet
    )

    log_success "Конфігурацію proxy перевірено."
}

start_proxy_services() {
    log_step "Запуск proxy-стека."

    (
        cd "$INSTALL_DIR" || exit 1
        docker compose -f compose.yml up -d --remove-orphans
    )
}

wait_proxy_services() {
    log_step "Очікування готовності Traefik."

    local timeout=180
    local elapsed=0
    local id health

    cd "$INSTALL_DIR" || return 1

    while (( elapsed < timeout )); do
        id="$(docker compose -f compose.yml ps -q traefik 2>/dev/null || true)"

        if [[ -n "$id" ]]; then
            health="$(
                docker inspect \
                    --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
                    "$id"
            )"

            if [[ "$health" == "healthy" || "$health" == "none" ]]; then
                log_success "Traefik готовий (health=$health)."
                return 0
            fi
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    die "Traefik не став healthy за ${timeout}s."
}

show_proxy_info() {
    printf '\n'
    printf '============================================================\n'
    printf ' WORDPRESS PROXY STACK V%s\n' "$VERSION"
    printf '============================================================\n'
    printf '\n'
    printf 'Proxy path:\n  %s\n' "$INSTALL_DIR"
    printf 'Shared network: %s (%s)\n' "$PROXY_NETWORK" "$PROXY_SUBNET"
    printf 'ACME email: %s\n' "$ACME_EMAIL"
    printf '\n'
    printf 'Запуск proxy:\n'
    printf '  cd %q && make up\n' "$INSTALL_DIR"
    printf '\n'
    printf 'Сайти цього proxy:\n'
    printf '  ./wordpress-stack.sh --mode internet --domain <domain> \\\n'
    printf '      --email %q --no-traefik --dir <site-dir>\n' "$ACME_EMAIL"
    printf '\n'
    printf 'Перевірка proxy:\n'
    printf '  make healthcheck\n'
}

run_proxy_flow() {
    check_system
    check_dependencies
    check_docker_access
    validate_privilege_requirements
    prepare_install_path
    check_disk_space
    resolve_proxy_subnet

    create_proxy_structure
    create_proxy_env_file
    create_proxy_traefik_config
    fix_install_ownership

    if [[ "$MANAGE_FIREWALL" == true ]]; then
        setup_nftables
    fi

    validate_proxy

    if [[ "$NO_START" == false ]]; then
        start_proxy_services
        wait_proxy_services
    fi

    show_proxy_info
}
