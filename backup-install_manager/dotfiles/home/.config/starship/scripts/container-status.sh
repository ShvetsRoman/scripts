#!/usr/bin/env bash
# ============================================================
# CONTAINER STATUS
# Відображення Compose-проєкту та стану його контейнерів.
#
# Пріоритет рушіїв:
#   1. Podman
#   2. Docker (запасний варіант, якщо проєкт не знайдено
#      серед контейнерів podman)
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
    containers=$(podman compose ps -q 2>/dev/null)
else
    containers=$(docker compose ps --all --quiet 2>/dev/null)
fi

# Запасний варіант: podman нічого не знайшов, але проєкт може
# керуватися Docker (podman compose фільтрує лише власні
# контейнери за лейблом com.docker.compose.project).
if [[ -z "$containers" ]] \
    && [[ "$ENGINE" == "podman" ]] \
    && command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
    SYMBOL="🐳"
    containers=$(docker compose ps --all --quiet 2>/dev/null)
fi

# Рушій недоступний або контейнерів ще не створено.
if [[ -z "$containers" ]]; then
    printf '%s project\n' "$SYMBOL"
    exit 0
fi

# Збираємо ID контейнерів у масив.
ids=()
while IFS= read -r container_id; do
    [[ -z "$container_id" ]] && continue
    ids+=("$container_id")
done <<<"$containers"

if ((${#ids[@]} == 0)); then
    printf '%s project\n' "$SYMBOL"
    exit 0
fi

# Один пакетний виклик inspect замість O(N) окремих викликів.
# Помилка inspect (рушій тимчасово недоступний, контейнер зник)
# не вважається станом «зупинено» — показуємо нейтральний проект.
states=$("$ENGINE" inspect \
    --format '{{.State.Running}}' \
    "${ids[@]}" 2>/dev/null) || {
    printf '%s project\n' "$SYMBOL"
    exit 0
}

total=${#ids[@]}
running=$(grep -c '^true$' <<<"$states") || running=0

# Показуємо кількість запущених контейнерів.
printf '%s %s/%s\n' "$SYMBOL" "$running" "$total"
