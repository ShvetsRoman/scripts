#!/usr/bin/env bash
# ============================================================
# DOCKER COMPOSE — ОДНЕ ОПИТУВАННЯ СТАНУ
# Вивід: 3/5 running. Якщо немає Compose або Docker — порожньо.
# Підраховуються контейнери поточного Compose-проєкту.
# ============================================================
set -euo pipefail

# Нічого не показуємо без Compose-проєкту.
found=false
for file in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [[ -f "$file" ]]; then
        found=true
        break
    fi
done
[[ "$found" == true ]] || exit 0
command -v docker >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Один виклик Docker Compose. --format json повертає записи JSON.
# jq -s обробляє як JSON-lines, так і JSON-масив.
if ! records=$(docker compose ps --all --format json 2>/dev/null); then
    exit 0
fi
[[ -n "$records" ]] || exit 0

printf '%s\n' "$records" | jq -rs '
    (if length == 1 and (.[0] | type) == "array" then .[0] else . end) as $items
    | if ($items | length) == 0 then empty
      else "\($items | map(select(.State == "running")) | length)/\($items | length) running" end
' 2>/dev/null
