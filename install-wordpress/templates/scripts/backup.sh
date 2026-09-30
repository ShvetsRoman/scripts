#!/usr/bin/env bash

set -Eeuo pipefail

readonly PROJECT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
    pwd -P
)"

cd "$PROJECT_DIR"

[[ -f .env ]] || {
    echo "ERROR: .env не знайдено." >&2
    exit 1
}

set -a
# shellcheck disable=SC1091
source .env
set +a

readonly TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
readonly BACKUP_ROOT="$PROJECT_DIR/backups"
readonly BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

cleanup_failed_backup() {
    local exit_code="$?"

    if (( exit_code != 0 )); then
        echo "Backup failed." >&2
        rm -rf -- "$BACKUP_DIR"
    fi
}

trap cleanup_failed_backup EXIT

echo "[1/3] MySQL dump"

docker compose \
    -f compose.yml \
    -f compose.override.yml \
    exec \
    -T \
    db \
    mysqldump \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --no-tablespaces \
    -u"$MYSQL_USER" \
    -p"$MYSQL_PASSWORD" \
    "$MYSQL_DATABASE" |
    gzip > "$BACKUP_DIR/database.sql.gz"

echo "[2/3] WordPress files"

tar \
    -C "$PROJECT_DIR/data" \
    -czf "$BACKUP_DIR/wordpress.tar.gz" \
    wordpress

echo "[3/3] Metadata"

cat > "$BACKUP_DIR/backup.info" <<EOF
created=$(date --iso-8601=seconds)
domain=${DOMAIN}
database=${MYSQL_DATABASE}
EOF

echo "Backup created:"
echo "$BACKUP_DIR"

if [[ "${BACKUP_RETENTION_DAYS:-0}" =~ ^[0-9]+$ ]] &&
   (( BACKUP_RETENTION_DAYS > 0 )); then

    find "$BACKUP_ROOT" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -mtime "+${BACKUP_RETENTION_DAYS}" \
        -exec rm -rf -- {} +
fi
