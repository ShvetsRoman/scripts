#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
    pwd -P
)"
readonly PROJECT_DIR

cd "$PROJECT_DIR"

if (( $# != 1 )); then
    echo "Usage: $0 BACKUP" >&2
    exit 1
fi

readonly BACKUP_NAME="$1"
readonly BACKUP_DIR="$PROJECT_DIR/backups/$BACKUP_NAME"

[[ -d "$BACKUP_DIR" ]] || {
    echo "Backup не знайдено: $BACKUP_DIR" >&2
    exit 1
}

[[ -f "$BACKUP_DIR/database.sql.gz" ]] || {
    echo "database.sql.gz не знайдено." >&2
    exit 1
}

[[ -f "$BACKUP_DIR/wordpress.tar.gz" ]] || {
    echo "wordpress.tar.gz не знайдено." >&2
    exit 1
}

gzip -t "$BACKUP_DIR/database.sql.gz"
tar -tzf "$BACKUP_DIR/wordpress.tar.gz" >/dev/null

set -a
# shellcheck disable=SC1091
source .env
set +a

printf 'Restore backup "%s"? [y/N]: ' "$BACKUP_NAME"
read -r answer

case "$answer" in
    y|Y|yes|YES)
        ;;
    *)
        echo "Скасовано."
        exit 0
        ;;
esac

echo "Creating pre-restore backup..."

# До зупинки контейнерів: backup.sh читає файли через exec у wordpress.
bash "$PROJECT_DIR/scripts/backup.sh"

echo "[1/4] Stopping application services"

docker compose \
    -f compose.yml \
    -f compose.override.yml \
    stop nginx wpcli wordpress

echo "[2/4] Restoring WordPress files"

# Очищення та розпакування теж всередині контейнера (root):
# файли належать www-data, хост-користувач не може їх видалити.
docker compose \
    -f compose.yml \
    -f compose.override.yml \
    run \
    --rm \
    -T \
    -u 0 \
    wordpress \
    sh -c 'find /var/www/html -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +'

docker compose \
    -f compose.yml \
    -f compose.override.yml \
    run \
    --rm \
    -T \
    -u 0 \
    wordpress \
    sh -c 'tar -C /var/www/html -xzf -' \
    < "$BACKUP_DIR/wordpress.tar.gz"

echo "[3/4] Restoring database"

gzip -dc "$BACKUP_DIR/database.sql.gz" |
docker compose \
    -f compose.yml \
    -f compose.override.yml \
    exec \
    -T \
    -e "MYSQL_PWD=${MYSQL_PASSWORD}" \
    db \
    mysql \
    -u"$MYSQL_USER" \
    "$MYSQL_DATABASE"

echo "[4/4] Starting application services"

docker compose \
    -f compose.yml \
    -f compose.override.yml \
    up \
    -d \
    wordpress nginx wpcli

docker compose \
    -f compose.yml \
    -f compose.override.yml \
    exec \
    -T \
    -u 0 \
    wordpress \
    sh -c '
        chown -R www-data:www-data /var/www/html
        find /var/www/html -type d -exec chmod 0755 {} +
        find /var/www/html -type f -exec chmod 0644 {} +
        if [ -f /var/www/html/wp-config.php ]; then chmod 0640 /var/www/html/wp-config.php; fi
    '

echo "Restore completed."
