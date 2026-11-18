#!/usr/bin/env bash

frontend_network_name() {
    printf '%s_frontend\n' "$PROJECT_NAME"
}

ipv4_to_int() {
    local IFS='.'
    local -r octets=($1)

    printf '%d\n' "$(( (octets[0] << 24) + (octets[1] << 16) + (octets[2] << 8) + octets[3] ))"
}

# Для CIDR виводить "<перший_адрес> <останній_адрес>" (32-бітні цілі числа).
# Повертає 1 для некоректного запису.
cidr_range() {
    local cidr="$1"
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"

    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        [[ ! "$prefix" =~ ^[0-9]+$ ]] ||
        (( prefix > 32 )); then
        return 1
    fi

    local start
    local mask

    start="$(ipv4_to_int "$ip")"
    mask=$(( 0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF ))
    start=$(( start & mask ))

    printf '%d %d\n' "$start" "$(( start + (1 << (32 - prefix)) - 1 ))"
}

cidrs_overlap() {
    local a_start a_end b_start b_end

    read -r a_start a_end <<<"$(cidr_range "$1")" || return 1
    read -r b_start b_end <<<"$(cidr_range "$2")" || return 1

    (( a_start <= b_end && b_start <= a_end ))
}

collect_existing_ipv4_subnets() {
    local subnets=""

    if command_exists docker; then
        local network_ids
        network_ids="$(docker network ls -q 2>/dev/null || true)"

        if [[ -n "$network_ids" ]]; then
            # shellcheck disable=SC2086
            subnets+="$(docker network inspect $network_ids \
                --format '{{range .IPAM.Config}}{{.Subnet}}
{{end}}' 2>/dev/null || true)"
        fi
    fi

    subnets+="$(ip -4 -o addr show 2>/dev/null | awk '$3 == "inet" {print $4}' || true)"
    subnets+="$(ip -4 route show 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/) print $i}' || true)"

    printf '%s\n' "$subnets" |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' |
        sort -u
}

# Підмережі приватного блоку 172.16.0.0/12 як кандидати авто-підбору.
frontend_subnet_candidates() {
    local second_octet

    for second_octet in 28 29 30 31 16 17 18 19 20 21 22 23 24 25 26 27; do
        printf '172.%d.0.0/16\n' "$second_octet"
    done
}

# Перша існуюча підмережа, що перетинається з candidate; друкує її або повертає 1.
first_conflicting_subnet() {
    local candidate="$1"
    local subnet

    while IFS= read -r subnet; do
        [[ -n "$subnet" ]] || continue

        if cidrs_overlap "$candidate" "$subnet"; then
            printf '%s\n' "$subnet"
            return 0
        fi
    done <<<"$2"

    return 1
}

resolve_frontend_subnet() {
    log_step "Перевірка FRONTEND_SUBNET."

    if [[ "$NO_TRAEFIK" == true && "$DEPLOY_MODE" == "internet" ]]; then
        log_info "NO_TRAEFIK: фронтенд-мережа не використовується для проксування."
    fi

    if ! cidr_range "$FRONTEND_SUBNET" >/dev/null; then
        die "Некоректна FRONTEND_SUBNET: $FRONTEND_SUBNET"
    fi

    # Повторний запуск: використовуємо підмережу з наявного .env,
    # бо мережі цієї інсталяції вже створені.
    local env_file="$INSTALL_DIR/.env"

    if [[ -f "$env_file" ]]; then
        local old_subnet
        old_subnet="$(read_env_value "$env_file" FRONTEND_SUBNET)"

        if [[ -n "$old_subnet" ]]; then
            if ! cidr_range "$old_subnet" >/dev/null; then
                die "Некоректна FRONTEND_SUBNET у наявному .env: $old_subnet"
            fi

            FRONTEND_SUBNET="$old_subnet"
            log_info "FRONTEND_SUBNET з наявного .env: $FRONTEND_SUBNET."
            return 0
        fi
    fi

    local existing
    existing="$(collect_existing_ipv4_subnets || true)"

    if [[ -z "$existing" ]]; then
        log_success "FRONTEND_SUBNET ${FRONTEND_SUBNET} доступна."
        return 0
    fi

    local conflict
    conflict="$(first_conflicting_subnet "$FRONTEND_SUBNET" "$existing")" || conflict=""

    if [[ -z "$conflict" ]]; then
        log_success "FRONTEND_SUBNET ${FRONTEND_SUBNET} доступна."
        return 0
    fi

    local candidate

    while IFS= read -r candidate; do
        if ! first_conflicting_subnet "$candidate" "$existing" >/dev/null; then
            log_warning \
                "FRONTEND_SUBNET ${FRONTEND_SUBNET} перетинається з ${conflict}. Автоматично обрано вільну: ${candidate}."
            FRONTEND_SUBNET="$candidate"
            return 0
        fi
    done <<<"$(frontend_subnet_candidates)"

    die "FRONTEND_SUBNET ${FRONTEND_SUBNET} перетинається з існуючою мережею ${conflict}, а вільних підмереж у 172.16.0.0/12 не знайдено. Звільніть адресний простір або змініть FRONTEND_SUBNET у config/defaults.conf."
}

# Перевіряє (або створює) спільну proxy-мережу для режиму --no-traefik.
ensure_proxy_network() {
    log_step "Перевірка proxy-мережі ${PROXY_NETWORK}."

    if [[ "$NO_TRAEFIK" == false ]]; then
        return 0
    fi

    if [[ "$DEPLOY_MODE" == "lan" ]]; then
        # LAN: nginx публікує 80 напряму, спільна мережа не потрібна.
        PROXY_SUBNET=""
        return 0
    fi

    if docker network inspect "$PROXY_NETWORK" > /dev/null 2>&1; then
        PROXY_SUBNET="$(
            docker network inspect "$PROXY_NETWORK" \
                --format '{{(index .IPAM.Config 0).Subnet}}'
        )"
        log_info "Спільна proxy-мережа існує (${PROXY_SUBNET})."
        return 0
    fi

    die "Спільної proxy-мережі ${PROXY_NETWORK} не існує. Спочатку створіть центральний proxy: ./wordpress-stack.sh --init-proxy --email you@example.com --dir /srv/wp-proxy"
}

create_traefik_config() {
    if [[ "$NO_TRAEFIK" == true ]]; then
        log_info "NO_TRAEFIK: свій Traefik не створюється (центральний proxy керує роутингом)."
        return 0
    fi

    log_step "Створення Traefik configuration."

    local frontend_network
    frontend_network="$(frontend_network_name)"

    local ca_server_line=""

    if [[ "$DEPLOY_MODE" == "internet" && "$ACME_STAGING" == true ]]; then
        ca_server_line='      caServer: "https://acme-staging-v02.api.letsencrypt.org/directory"'
        log_warning "Let's Encrypt STAGING активний: сертифікати не будуть довірені браузерами."
        if [[ -f "$INSTALL_DIR/letsencrypt/acme.json" ]]; then
            log_warning "Знайдено letsencrypt/acme.json: для перемикання staging↔production видали його."
        fi
    fi

    if [[ "$DEPLOY_MODE" == "internet" ]]; then
        cat > "$INSTALL_DIR/traefik/traefik.yml" <<EOF
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
    network: "${frontend_network}"

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${ACME_EMAIL}"
${ca_server_line}
      storage: "/letsencrypt/acme.json"
      httpChallenge:
        entryPoint: web
EOF
    else
        cat > "$INSTALL_DIR/traefik/traefik.yml" <<EOF
log:
  level: WARN

accessLog: {}

api:
  dashboard: false

ping: {}

entryPoints:
  web:
    address: ":80"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: "${frontend_network}"
EOF
    fi

    chmod 0644 "$INSTALL_DIR/traefik/traefik.yml"
}

create_real_ip_config() {
    log_step "Створення Nginx real-IP configuration."

    cat > "$INSTALL_DIR/nginx/real-ip.conf" <<EOF
# Managed by wordpress-stack installer.
# Only the proxy (frontend network + loopback) is trusted for X-Forwarded-For.

set_real_ip_from 127.0.0.1;
set_real_ip_from ${FRONTEND_SUBNET};
EOF

    if [[ "$NO_TRAEFIK" == true && "$DEPLOY_MODE" == "internet" ]]; then
        printf 'set_real_ip_from %s;\n' "$PROXY_SUBNET" >> "$INSTALL_DIR/nginx/real-ip.conf"
    fi

    cat >> "$INSTALL_DIR/nginx/real-ip.conf" <<EOF

real_ip_header X-Forwarded-For;
real_ip_recursive on;
EOF

    chmod 0644 "$INSTALL_DIR/nginx/real-ip.conf"

    log_success "real-ip.conf готова (frontend: ${FRONTEND_SUBNET})."
}

configure_compose_mode() {
    log_step "Створення Compose override."

    local override="$INSTALL_DIR/compose.override.yml"
    local frontend_network
    frontend_network="$(frontend_network_name)"

    local proxy_trust_line=""
    local proxy_networks_block=""

    if [[ "$NO_TRAEFIK" == true && "$DEPLOY_MODE" == "internet" ]]; then
        proxy_trust_line=$'\n      traefik.docker.network: "'"${PROXY_NETWORK}"'"'
        proxy_networks_block=$'\n\nnetworks:\n  '"${PROXY_NETWORK}"':\n    external: true'
    fi

    if [[ "$DEPLOY_MODE" == "internet" ]]; then
        cat > "$override" <<EOF
services:
  traefik:
    ports:
      - "443:443"

  nginx:
    labels:
      traefik.enable: "true"${proxy_trust_line}

      traefik.http.routers.wordpress.rule: "Host(\`${DOMAIN}\`)"
      traefik.http.routers.wordpress.entrypoints: "websecure"
      traefik.http.routers.wordpress.tls: "true"
      traefik.http.routers.wordpress.tls.certresolver: "letsencrypt"
      traefik.http.routers.wordpress.service: "wordpress"

      traefik.http.services.wordpress.loadbalancer.server.port: "80"

      traefik.http.middlewares.wordpress-security.headers.contentTypeNosniff: "true"
      traefik.http.middlewares.wordpress-security.headers.referrerPolicy: "strict-origin-when-cross-origin"
      traefik.http.middlewares.wordpress-security.headers.stsSeconds: "31536000"

      traefik.http.routers.wordpress.middlewares: "wordpress-security"
EOF
    else
        cat > "$override" <<EOF
services:
  nginx:
    labels:
      traefik.enable: "true"
      traefik.docker.network: "${frontend_network}"

      traefik.http.routers.wordpress.rule: "Host(\`${DOMAIN}\`) || Host(\`localhost\`) || Host(\`127.0.0.1\`)"
      traefik.http.routers.wordpress.entrypoints: "web"
      traefik.http.routers.wordpress.service: "wordpress"

      traefik.http.services.wordpress.loadbalancer.server.port: "80"
EOF

        # LAN + NO_TRAEFIK: nginx сам публікує порт 80 (своїх Traefik немає).
        if [[ "$NO_TRAEFIK" == true ]]; then
            cat >> "$override" <<EOF
    ports:
      - "80:80"
EOF
        fi
    fi

    if [[ -n "$proxy_networks_block" ]]; then
        printf '%b' "$proxy_networks_block" >> "$override"
    fi
}

validate_project() {
    log_step "Перевірка Docker Compose."

    (
        cd "$INSTALL_DIR" || exit 1

        docker compose \
            -f compose.yml \
            -f compose.override.yml \
            config \
            --quiet
    )

    log_success "Compose configuration коректна."
}

start_services() {
    log_step "Запуск Docker stack."

    (
        cd "$INSTALL_DIR" || exit 1

        if docker compose \
            -f compose.yml \
            -f compose.override.yml \
            ps -q 2>/dev/null | grep -q .; then

            log_info "Знайдено існуючий stack — пересоздаю containers/networks без видалення даних."

            docker compose \
                -f compose.yml \
                -f compose.override.yml \
                down \
                --remove-orphans
        fi

        docker compose \
            -f compose.yml \
            -f compose.override.yml \
            up \
            -d \
            --remove-orphans
    )

    log_success "Docker stack запущено."
}

wait_for_services() {
    log_step "Очікування готовності сервісів."

    local timeout=180
    local elapsed=0
    local id
    local name status health
    local info
    local failing=""
    local all_ready=true

    cd "$INSTALL_DIR" || return 1

    while (( elapsed < timeout )); do
        failing=""
        all_ready=true

        while IFS= read -r id; do
            [[ -n "$id" ]] || continue

            info="$(
                docker inspect \
                    --format '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
                    "$id" \
                    2>/dev/null \
                    || true
            )"

            read -r name status health <<<"$info" || true

            case "$health" in
                healthy|none)
                    if [[ -z "$status" ]]; then
                        # inspect race (container recreated) — retry next iteration.
                        all_ready=false
                    elif [[ "$status" != "running" ]]; then
                        failing+="$name state=$status health=$health"$'\n'
                    fi
                    ;;
                starting)
                    all_ready=false
                    ;;
                *)
                    failing+="$name state=$status health=$health"$'\n'
                    ;;
            esac
        done < <(
            docker compose \
                -f compose.yml \
                -f compose.override.yml \
                ps -q \
                2>/dev/null \
                || true
        )

        if [[ -n "$failing" ]]; then
            docker compose \
                -f compose.yml \
                -f compose.override.yml \
                ps \
                --all

            printf '%b' "$failing"
            die "Один або більше контейнерів unhealthy/exited."
        fi

        if [[ "$all_ready" == true ]]; then
            log_success "Сервіси готові."
            return 0
        fi

        sleep 3
        elapsed=$((elapsed + 3))
    done

    docker compose \
        -f compose.yml \
        -f compose.override.yml \
        ps \
        --all

    die "Healthcheck timeout після ${timeout} секунд."
}
