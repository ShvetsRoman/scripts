#!/usr/bin/env bash
# Перевіряємо блокування операцій запису з меню архівів і Recovery.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/cli/menu.sh
source "$ROOT_DIR/src/cli/menu.sh"

for action in archive_create archive_restore recovery_restore recovery_delete rotate_dotfiles; do
    if ! menu_is_mutating "$action"; then
        printf '[FAIL] Немає блокування для %s\n' "$action" >&2
        exit 1
    fi
done
for action in archive_list recovery_list recovery_verify recovery_plan; do
    if menu_is_mutating "$action"; then
        printf '[FAIL] Зайве блокування для %s\n' "$action" >&2
        exit 1
    fi
done
printf '[PASS] test-backups-menu-lock-v201\n'
