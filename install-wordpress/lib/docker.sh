#!/usr/bin/env bash

create_traefik_config() {
    log_step "Створення Traefik configuration."

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

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${EMAIL}"
      storage: "/letsencrypt/acme.json"
      httpChallenge:
        entryPoint: web
EOF
    else
        cat > "$INSTALL_DIR/traefik/traefik.yml" <<'EOF'
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
EOF
    fi

    chmod 0644 "$INSTALL_DIR/traefik/traefik.yml"
}

configure_compose_mode() {
    log_step "Створення Compose override."

    local override="$INSTALL_DIR/compose.override.yml"

    if [[ "$DEPLOY_MODE" == "internet" ]]; then
        cat > "$override" <<'EOF'
services:
  traefik:
    ports:
      - "443:443"

  nginx:
    labels:
      traefik.enable: "true"

      traefik.http.routers.wordpress.rule: "Host(`${DOMAIN}`)"
      traefik.http.routers.wordpress.entrypoints: "websecure"
      traefik.http.routers.wordpress.tls: "true"
      traefik.http.routers.wordpress.tls.certresolver: "letsencrypt"
      traefik.http.routers.wordpress.service: "wordpress"

      traefik.http.services.wordpress.loadbalancer.server.port: "80"

      traefik.http.middlewares.wordpress-security.headers.contentTypeNosniff: "true"
      traefik.http.middlewares.wordpress-security.headers.referrerPolicy: "strict-origin-when-cross-origin"
      traefik.http.middlewares.wordpress-security.headers.stsSeconds: "31536000"
      traefik.http.middlewares.wordpress-security.headers.stsIncludeSubdomains: "true"
      traefik.http.middlewares.wordpress-security.headers.stsPreload: "true"

      traefik.http.routers.wordpress.middlewares: "wordpress-security"
EOF
    else
        cat > "$override" <<'EOF'
services:
  nginx:
    labels:
      traefik.enable: "true"

      traefik.http.routers.wordpress.rule: "PathPrefix(`/`)"
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
        cd "$INSTALL_DIR"
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
        cd "$INSTALL_DIR"
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

    while (( elapsed < timeout )); do
        local unhealthy
        local starting

        unhealthy="$(
            cd "$INSTALL_DIR"
            docker compose \
                -f compose.yml \
                -f compose.override.yml \
                ps --format json 2>/dev/null |
            grep -c '"Health":"unhealthy"' || true
        )"

        starting="$(
            cd "$INSTALL_DIR"
            docker compose \
                -f compose.yml \
                -f compose.override.yml \
                ps --format json 2>/dev/null |
            grep -c '"Health":"starting"' || true
        )"

        if (( unhealthy > 0 )); then
            (
                cd "$INSTALL_DIR"
                docker compose \
                    -f compose.yml \
                    -f compose.override.yml \
                    ps
            )
            die "Один або більше контейнерів unhealthy."
        fi

        if (( starting == 0 )); then
            log_success "Сервіси готові."
            return 0
        fi

        sleep 3
        elapsed=$((elapsed + 3))
    done

    log_warning "Healthcheck timeout. Показую поточний статус."
    (
        cd "$INSTALL_DIR"
        docker compose \
            -f compose.yml \
            -f compose.override.yml \
            ps
    )
}
