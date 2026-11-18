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

readonly LOG_DIR="$PROJECT_DIR/logs/nginx"

STAMP="$(date '+%Y-%m-%d_%H-%M-%S')"

shopt -s nullglob

rotated=0

for log_file in "$LOG_DIR"/*.log; do
    [[ -s "$log_file" ]] || continue

    cp -a -- "$log_file" "$log_file.$STAMP"
    : > "$log_file"
    gzip -f -- "$log_file.$STAMP"

    rotated=$((rotated + 1))
done

if [[ "${BACKUP_RETENTION_DAYS:-0}" =~ ^[0-9]+$ ]] &&
   (( BACKUP_RETENTION_DAYS > 0 )); then

    find "$LOG_DIR" \
        -name '*.log.*.gz' \
        -type f \
        -mtime "+${BACKUP_RETENTION_DAYS}" \
        -exec rm -f -- {} +
fi

# nginx writes into the truncated files; reopen guards against any
# descriptor drift after rotation.
docker compose \
    -f compose.yml \
    -f compose.override.yml \
    exec \
    -T \
    nginx \
    nginx -s reopen >/dev/null 2>&1 || true

if (( rotated > 0 )); then
    echo "Rotated $rotated nginx log file(s)."
else
    echo "Nothing to rotate."
fi
