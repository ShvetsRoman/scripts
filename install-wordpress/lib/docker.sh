#!/usr/bin/env bash

frontend_network_name() {
    printf '%s_frontend\n' "$PROJECT_NAME"
}

create_traefik_config() {
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
# Only Traefik (frontend network + loopback) is trusted for X-Forwarded-For.

set_real_ip_from 127.0.0.1;
set_real_ip_from ${FRONTEND_SUBNET};

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

    if [[ "$DEPLOY_MODE" == "internet" ]]; then
        cat > "$override" <<EOF
services:
  traefik:
    ports:
      - "443:443"

  nginx:
    labels:
      traefik.enable: "true"
      traefik.docker.network: "${frontend_network}"

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
    fi
}

configure_php_mode() {
    local secure_cookie="0"

    if [[ "$DEPLOY_MODE" == "internet" ]]; then
        secure_cookie="1"
    fi

    sed \
        -i \
        "s/^session.cookie_secure = .*/session.cookie_secure = ${secure_cookie}/" \
        "$INSTALL_DIR/php/custom.ini"
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
