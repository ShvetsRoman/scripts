#!/usr/bin/env bash
# Перевірка структури меню без інтерактивних системних операцій.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/cli/menu.sh
source "$ROOT_DIR/src/cli/menu.sh"
expected=(packages dotfiles backups system settings)
(( ${#MAIN_MENU[@]} == ${#expected[@]} )) || exit 1
for i in "${!expected[@]}"; do
    [[ "${MAIN_MENU[i]%%|*}" == "${expected[i]}" ]] || exit 1
done
for submenu in menu_sub_packages menu_sub_dotfiles menu_sub_backups menu_sub_system menu_sub_settings; do
    declare -F "$submenu" >/dev/null || exit 1
done
[[ "${PACKAGES_MENU[*]}" == *'packages_choose|'* ]]
[[ "${BACKUPS_MENU[*]}" == *'archive|'* && "${BACKUPS_MENU[*]}" == *'recovery|'* ]]
[[ "${SETTINGS_MENU[*]}" == *'sources|'* ]]
# Провайдер модулів повинен працювати без залежності від назви меню.
[[ "$(declare -f menu_run)" == *'[[ -n "$provider" ]] && registry_valid'* ]]

# Усі дії мають унікальне місце в дереві меню.
declare -A seen=()
for array in MAIN_MENU PACKAGES_MENU DOTFILES_MENU BACKUPS_MENU SYSTEM_MENU SETTINGS_MENU SOURCES_MENU ARCHIVE_MENU RECOVERY_MENU MAINTENANCE_MENU; do
    declare -n entries="$array"
    for entry in "${entries[@]}"; do
        key="${entry%%|*}"
        [[ -z "${seen[$key]:-}" ]] || {
            printf '[FAIL] Повторний пункт: %s (%s, %s)\n' "$key" "${seen[$key]}" "$array" >&2
            exit 1
        }
        seen[$key]="$array"
    done
    unset -n entries
done
[[ "$(declare -f menu_run)" == *"column -t"* ]] || exit 1
printf '[PASS] test-menu-layout-v4\n'
