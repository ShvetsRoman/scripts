#!/usr/bin/env bash

set -Eeuo pipefail

readonly WP_PATH="/var/www/html"
readonly DB_WAIT_ATTEMPTS=60
readonly DB_WAIT_INTERVAL=2

log() {
    printf '[WP-CLI] %s\n' "$*"
}

# shellcheck disable=SC2016
database_ready() {
    php -r '
        $host = getenv("WORDPRESS_DB_HOST") ?: "db:3306";
        $user = getenv("WORDPRESS_DB_USER") ?: "";
        $pass = getenv("WORDPRESS_DB_PASSWORD") ?: "";
        $name = getenv("WORDPRESS_DB_NAME") ?: "";

        $hostname = $host;
        $port = 3306;

        if (str_contains($host, ":")) {
            [$hostname, $portValue] = array_pad(
                explode(":", $host, 2),
                2,
                "3306"
            );

            if ($portValue !== "") {
                $port = (int) $portValue;
            }
        }

        mysqli_report(MYSQLI_REPORT_OFF);

        $db = @new mysqli(
            $hostname,
            $user,
            $pass,
            $name,
            $port
        );

        if ($db->connect_errno) {
            exit(1);
        }

        $db->close();
        exit(0);
    ' >/dev/null 2>&1
}

wait_for_database() {
    local attempt

    log "Очікування database."

    for ((attempt = 1; attempt <= DB_WAIT_ATTEMPTS; attempt++)); do
        if database_ready; then
            log "Database доступна."
            return 0
        fi

        if (( attempt < DB_WAIT_ATTEMPTS )); then
            sleep "$DB_WAIT_INTERVAL"
        fi
    done

    log "Database недоступна після $((DB_WAIT_ATTEMPTS * DB_WAIT_INTERVAL)) секунд."
    return 1
}

cd "$WP_PATH"

wait_for_database

if wp core is-installed >/dev/null 2>&1; then
    log "WordPress уже встановлено."

    if [[ "${INSTALL_FORCE:-false}" == "true" ]]; then
        log "Синхронізація URL та admin email (--force)."
        wp option update home "$APP_URL"
        wp option update siteurl "$APP_URL"
        wp option update admin_email "$WORDPRESS_ADMIN_EMAIL"
    fi

    exit 0
fi

if [[ ! "$WORDPRESS_ADMIN_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
    log "Некоректний admin email: $WORDPRESS_ADMIN_EMAIL"
    exit 1
fi

log "Встановлення WordPress."

wp core install \
    --url="$APP_URL" \
    --title="$WORDPRESS_TITLE" \
    --admin_user="$WORDPRESS_ADMIN_USER" \
    --admin_password="$WORDPRESS_ADMIN_PASSWORD" \
    --admin_email="$WORDPRESS_ADMIN_EMAIL" \
    --skip-email

log "Налаштування permalink."

wp rewrite structure '/%postname%/'
wp rewrite flush --hard

log "Налаштування timezone."

wp option update timezone_string "Europe/Kyiv"
wp option update date_format "d.m.Y"
wp option update time_format "H:i"

log "Видалення Hello Dolly."

wp plugin delete hello >/dev/null 2>&1 || true

log "WordPress встановлено."
