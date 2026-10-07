#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
    pwd -P
)"
readonly PROJECT_DIR

cd "$PROJECT_DIR"

[[ -f .env ]] || {
    echo "ERROR: .env не знайдено." >&2
    exit 1
}

set -a
# shellcheck disable=SC1091
source .env
set +a

compose() {
    docker compose \
        -f compose.yml \
        -f compose.override.yml \
        "$@"
}

check_container_states() {
    echo
    echo "[Containers]"

    compose ps

    local failed=0
    local service
    local id
    local state
    local health

    for service in traefik db wordpress nginx wpcli; do
        id="$(compose ps -q "$service")"

        if [[ -z "$id" ]]; then
            echo "$service: ERROR (container not found)" >&2
            failed=1
            continue
        fi

        state="$(
            docker inspect \
                --format '{{.State.Status}}' \
                "$id"
        )"

        health="$(
            docker inspect \
                --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
                "$id"
        )"

        if [[ "$state" != "running" ]]; then
            echo "$service: ERROR (state=$state)" >&2
            failed=1
            continue
        fi

        case "$health" in
            healthy|none)
                echo "$service: OK (state=$state, health=$health)"
                ;;
            *)
                echo "$service: ERROR (state=$state, health=$health)" >&2
                failed=1
                ;;
        esac
    done

    (( failed == 0 ))
}

check_database() {
    echo
    echo "[Database]"

    compose exec \
        -T \
        -e "MYSQL_PWD=${MYSQL_ROOT_PASSWORD}" \
        db \
        mysqladmin \
        ping \
        -h 127.0.0.1 \
        -uroot \
        --silent

    echo "Database: OK"
}

check_wordpress_php() {
    echo
    echo "[WordPress PHP-FPM]"

    compose exec \
        -T \
        wordpress \
        php-fpm \
        -t \
        >/dev/null

    echo "PHP-FPM: OK"
}

check_nginx_internal() {
    echo
    echo "[Nginx internal]"

    compose exec \
        -T \
        nginx \
        wget \
        -q \
        --spider \
        http://127.0.0.1/

    echo "Nginx: OK"
}

check_traefik_ping() {
    echo
    echo "[Traefik]"

    compose exec \
        -T \
        traefik \
        traefik \
        healthcheck \
        --ping \
        >/dev/null

    echo "Traefik: OK"
}

check_traefik_to_nginx() {
    echo
    echo "[Traefik -> Nginx]"

    compose exec \
        -T \
        traefik \
        wget \
        -q \
        --spider \
        http://nginx:80/

    echo "Traefik -> Nginx: OK"
}

http_status() {
    local url="$1"
    shift

    curl \
        --noproxy '*' \
        --silent \
        --show-error \
        --location \
        --output /dev/null \
        --write-out '%{http_code}' \
        --connect-timeout 5 \
        --max-time 15 \
        "$@" \
        "$url"
}

assert_http_ok() {
    local label="$1"
    local code="$2"

    case "$code" in
        200|301|302)
            echo "${label}: OK (${code})"
            ;;
        *)
            echo "${label}: ERROR (${code})" >&2
            return 1
            ;;
    esac
}

check_end_to_end() {
    echo
    echo "[End-to-end WordPress]"

    local code

    if [[ "$DEPLOY_MODE" == "lan" ]]; then
        code="$(
            http_status \
                "http://${DOMAIN}/" \
                --resolve "${DOMAIN}:80:127.0.0.1"
        )"
        assert_http_ok "${DOMAIN}" "$code"

        code="$(
            http_status \
                "http://localhost/" \
                --resolve "localhost:80:127.0.0.1"
        )"
        assert_http_ok "localhost" "$code"

        code="$(
            http_status \
                "http://127.0.0.1/"
        )"
        assert_http_ok "127.0.0.1" "$code"
    else
        code="$(
            curl \
                --noproxy '*' \
                --silent \
                --show-error \
                --location \
                --output /dev/null \
                --write-out '%{http_code}' \
                --connect-timeout 5 \
                --max-time 20 \
                "$APP_URL"
        )"

        assert_http_ok "$APP_URL" "$code"
    fi
}

echo "============================================"
echo " HEALTHCHECK"
echo "============================================"

check_container_states
check_database
check_wordpress_php
check_nginx_internal
check_traefik_ping
check_traefik_to_nginx
check_end_to_end

echo
echo "Healthcheck: OK"
