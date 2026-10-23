#!/usr/bin/env bash
# Перевірка єдиного розбору глобальних параметрів.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Структурні інваріанти: лише cli_parse змінює глобальні прапорці.
! grep -Eq -- '^[[:space:]]*--dry-run\)' "$ROOT_DIR/src/packages/packages.sh"
! grep -Eq -- '^[[:space:]]*\[\[.*--dry-run.*DRY_RUN=true' "$ROOT_DIR/src/core/maintenance.sh"
[[ $(grep -c 'cli_parse "\$@"' "$ROOT_DIR/src/core/bootstrap.sh") -eq 1 ]]

# Нешкідливі команди та прапорці до/після імені команди.
out1="$(bash "$ROOT_DIR/backup-install_manager.sh" --dry-run --no-color --version)"
out2="$(bash "$ROOT_DIR/backup-install_manager.sh" --version --dry-run --no-color)"
# Версія береться з реального модуля, а не жорстко задана в тесті.
# shellcheck source=../src/core/version.sh
source "$ROOT_DIR/src/core/version.sh"
[[ "$out1" == "$SETUP_VERSION" && "$out2" == "$SETUP_VERSION" ]]

# Пакети мають відображати список, не встановлюючи нічого.
out1="$(bash "$ROOT_DIR/backup-install_manager.sh" --dry-run packages --list)"
out2="$(bash "$ROOT_DIR/backup-install_manager.sh" packages --list --dry-run)"
[[ "$out1" == "$out2" ]]

# Maintenance disk не повинна виконувати запис чи запитувати підтвердження.
out1="$(bash "$ROOT_DIR/backup-install_manager.sh" --dry-run maintenance disk)"
out2="$(bash "$ROOT_DIR/backup-install_manager.sh" maintenance disk --dry-run)"
[[ "$out1" == "$out2" ]]

printf '[PASS] test-cli-flags-v1426\n'
