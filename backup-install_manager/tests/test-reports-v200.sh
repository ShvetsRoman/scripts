#!/usr/bin/env bash
# Контракт read-only команд для перегляду модулів.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$root/backup-install_manager.sh"
[[ "$(bash "$cli" modules list)" == *base* ]]
[[ "$(bash "$cli" modules info base)" == *'Модуль: base'* ]]
[[ "$(bash "$cli" modules stats)" == *'Модулів:'* ]]
[[ "$(bash "$cli" modules plan)" == *'Порядок модулів'* ]]
[[ "$(bash "$cli" modules deps base)" == *'Залежності base:'* ]]
[[ "$(bash "$cli" modules reverse base)" == *'Залежать від base:'* ]]
source "$root/src/core/version.sh"
[[ "$(bash "$cli" report summary)" == *"$SETUP_VERSION"* ]]
if bash "$cli" modules info unknown >/dev/null 2>&1; then
    printf '[FAIL] Невідомий модуль прийнято\n' >&2
    exit 1
fi
