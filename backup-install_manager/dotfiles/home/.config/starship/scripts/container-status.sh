#!/usr/bin/env bash
# ============================================================
# CONTAINER STATUS
# Відображення Compose-проєкту та стану його контейнерів.
#
# Пріоритет рушіїв:
#   1. Podman
#   2. Docker
# ============================================================

set -uo pipefail

# Визначаємо рушій.
if command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
    SYMBOL="🦭"
elif command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
    SYMBOL="🐳"
else
    exit 0
fi

# Шукаємо Compose-файл.
compose_found=false

for file in \
    compose.yaml \
    compose.yml \
    docker-compose.yaml \
    docker-compose.yml; do
    if [[ -f "$file" ]]; then
        compose_found=true
        break
    fi
done

# Немає Compose-проєкту.
if [[ "$compose_found" == false ]]; then
    exit 0
fi

# Отримуємо список контейнерів.
if [[ "$ENGINE" == "podman" ]]; then
    containers=$(podman compose ps -q 2>/dev/null) || {
        printf '%s project\n' "$SYMBOL"
        exit 0
    }
else
    containers=$(docker compose ps --all --quiet 2>/dev/null) || {
        printf '%s project\n' "$SYMBOL"
        exit 0
    }
fi

total=0
running=0

# Перевіряємо стан контейнерів.
while IFS= read -r container_id; do
    [[ -z "$container_id" ]] && continue

    ((total += 1))

    if state=$("$ENGINE" inspect \
        --format '{{.State.Running}}' \
        "$container_id" 2>/dev/null); then

        if [[ "$state" == "true" ]]; then
            ((running += 1))
        fi
    fi
done <<<"$containers"

# Compose-проєкт існує, але контейнери ще не створені.
if ((total == 0)); then
    printf '%s project\n' "$SYMBOL"
    exit 0
fi

# Показуємо кількість запущених контейнерів.
printf '%s %s/%s\n' "$SYMBOL" "$running" "$total"
