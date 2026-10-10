#!/usr/bin/env bash

# ============================================================
# DOCKER COMPOSE — СТАН КОНТЕЙНЕРІВ
# ============================================================
#
# Режими:
#   all     — усі контейнери запущені
#   partial — частина контейнерів запущена
#   none    — жоден контейнер не запущений
#
# Результат:
#   5/5 running
#   3/5 running
#   0/5 running
#
# ============================================================

set -uo pipefail

MODE="${1:-}"

# ------------------------------------------------------------
# 1. ПЕРЕВІРКА DOCKER
# ------------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
    exit 1
fi

# Перевіряємо наявність Compose-файлу.
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

if [[ "$compose_found" == false ]]; then
    exit 1
fi

# ------------------------------------------------------------
# 2. ОТРИМАННЯ КОНТЕЙНЕРІВ
# ------------------------------------------------------------

if ! all_containers=$(docker compose ps \
    --all \
    --quiet 2>/dev/null); then
    exit 1
fi

if ! running_containers=$(docker compose ps \
    --status running \
    --quiet 2>/dev/null); then
    exit 1
fi

# ------------------------------------------------------------
# 3. ПІДРАХУНОК
# ------------------------------------------------------------

count_lines() {
    local data="$1"

    if [[ -z "$data" ]]; then
        printf '0\n'
        return 0
    fi

    printf '%s\n' "$data" | awk 'NF { count++ } END { print count+0 }'
}

total=$(count_lines "$all_containers")
running=$(count_lines "$running_containers")

# ------------------------------------------------------------
# 4. ВИЗНАЧЕННЯ СТАНУ
# ------------------------------------------------------------

if ((total == 0 || running == 0)); then
    state="none"
elif ((running == total)); then
    state="all"
else
    state="partial"
fi

# ------------------------------------------------------------
# 5. ПЕРЕВІРКА РЕЖИМУ
# ------------------------------------------------------------

# Без аргументів показуємо стан.
# З аргументом показуємо лише потрібний стан.

if [[ -n "$MODE" && "$MODE" != "$state" ]]; then
    exit 1
fi

# ------------------------------------------------------------
# 6. РЕЗУЛЬТАТ
# ------------------------------------------------------------

printf '%s/%s running\n' "$running" "$total"

exit 0
