#!/usr/bin/env bash

set -Eeuo pipefail

readonly PROJECT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
    pwd -P
)"

cd "$PROJECT_DIR"

set -a
# shellcheck disable=SC1091
source .env
set +a

echo "============================================"
echo " HEALTHCHECK"
echo "============================================"

echo
echo "[Docker]"
docker compose \
    -f compose.yml \
    -f compose.override.yml \
    ps

echo
echo "[Database]"

docker compose \
    -f compose.yml \
    -f compose.override.yml \
    exec \
    -T \
    db \
    mysqladmin \
    ping \
    -h 127.0.0.1 \
    -uroot \
    -p"$MYSQL_ROOT_PASSWORD" \
    --silent

echo "Database: OK"

echo
echo "[WordPress]"

curl_args=(
    --silent
    --show-error
    --location
    --output /dev/null
    --write-out '%{http_code}'
    --connect-timeout 10
    --max-time 30
)

http_code="$(curl "${curl_args[@]}" "$APP_URL")"

case "$http_code" in
    200|301|302)
        echo "WordPress: OK ($http_code)"
        ;;
    *)
        echo "WordPress: ERROR ($http_code)" >&2
        exit 1
        ;;
esac

echo
echo "Healthcheck: OK"
