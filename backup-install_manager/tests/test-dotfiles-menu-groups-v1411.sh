#!/usr/bin/env bash
# Вибір групи, перегляд і явне підтвердження перед Backup/Restore.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/cli/menu.sh
source "$ROOT_DIR/src/cli/menu.sh"
C_HEAD='' C_OFF=''
ui_clear() { :; }
log() { :; }
sources_load() {
    SRC_ROWS=('alpha | home | ~/.alpha' 'beta | home | ~/.beta' 'gamma | system | /etc/gamma')
    DOTFILES_GROUPS=(shell system)
    declare -gA DOTFILES_ITEM_GROUP=([alpha]=shell [beta]=shell [gamma]=system)
}
sources_parse() {
    IFS='|' read -r S_NAME S_MODE S_SRC <<< "$1"
    S_NAME="${S_NAME// /}"; S_MODE="${S_MODE// /}"; S_SRC="${S_SRC// /}"
}
cli_dotfiles_execute() { printf 'EXEC %s\n' "$*"; }
[[ "${DOTFILES_MENU[3]}" == dotfiles_backup_group\|* ]]
[[ "${DOTFILES_MENU[5]}" == dotfiles_plan_backup\|* ]]
[[ "${DOTFILES_MENU[8]}" == dotfiles_restore_group\|* ]]
[[ "${DOTFILES_MENU[10]}" == dotfiles_plan_restore\|* ]]
[[ "${DOTFILES_MENU[11]}" == dotfiles_verify\|* ]]
[[ "${DOTFILES_MENU[12]}" == dotfiles_diff\|* ]]
[[ "${DOTFILES_MENU[*]}" != *dotfiles_group\|* ]]
[[ "$(printf '1\n1\n' | menu_action_dotfiles_backup_group)" == *'EXEC backup --group shell'* ]]
[[ "$(printf '2\n1\n' | menu_action_dotfiles_restore_group)" == *'EXEC restore --group system'* ]]
[[ "$(printf '3\n1\n' | menu_action_dotfiles_backup_group)" == *'EXEC backup'* ]]
output="$(printf '1\n0\n' | menu_action_dotfiles_restore_group)"
[[ "$output" != *'EXEC '* ]]
output="$(printf '1\n2\n3\n1\n' | menu_action_dotfiles_backup_group)"
[[ "$output" == *'EXEC backup'* ]]
[[ "$output" == *'alpha'* && "$output" == *'beta'* ]]
[[ "$(menu_action_dotfiles_backup)" == 'EXEC backup' ]]
[[ "$(menu_action_dotfiles_backup_changed)" == 'EXEC backup changed' ]]
printf '[PASS] test-dotfiles-menu-groups-v1411\n'
