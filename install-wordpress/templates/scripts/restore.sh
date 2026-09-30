#!/usr/bin/env bash

set -Eeuo pipefail

readonly PROJECT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
    pwd -P
)"

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
"$PROJECT_DIR/scripts/backup.sh"

docker compose \
    -f compose.yml \
    -f compose.override.yml \
    exec \
    -T \
    wpcli \
    wp maintenance-mode activate \
    >/dev/null 2>&1 || true

maintenance_off() {
    docker compose \
        -f compose.yml \
        -f compose.override.yml \
        exec \
        -T \
        wpcli \
        wp maintenance-mode deactivate \
        >/dev/null 2>&1 || true
}

trap maintenance_off EXIT

echo "[1/2] WordPress files"

rm -rf -- "$PROJECT_DIR/data/wordpress"
mkdir -p "$PROJECT_DIR/data"

tar \
    -C "$PROJECT_DIR/data" \
    -xzf "$BACKUP_DIR/wordpress.tar.gz"

echo "[2/2] Database"

gzip -dc "$BACKUP_DIR/database.sql.gz" |
docker compose \
    -f compose.yml \
    -f compose.override.yml \
    exec \
    -T \
    db \
    mysql \
    -u"$MYSQL_USER" \
    -p"$MYSQL_PASSWORD" \
    "$MYSQL_DATABASE"

echo "Restore completed."
