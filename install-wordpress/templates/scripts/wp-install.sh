#!/usr/bin/env bash

set -Eeuo pipefail

readonly WP_PATH="/var/www/html"

log() {
    printf '[WP-CLI] %s\n' "$*"
}

cd "$WP_PATH"

if wp core is-installed >/dev/null 2>&1; then
    log "WordPress уже встановлено."
    exit 0
fi

log "Очікування database."

for attempt in {1..60}; do
    if wp db check >/dev/null 2>&1; then
        break
    fi

    if (( attempt == 60 )); then
        log "Database недоступна."
        exit 1
    fi

    sleep 2
done

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
