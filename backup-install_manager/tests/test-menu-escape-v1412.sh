#!/usr/bin/env bash
# Перевірка навігації Esc і повернення без паузи.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/cli/menu.sh
source "$ROOT_DIR/src/cli/menu.sh"
C_HEAD='' C_OFF=''
ui_clear() { :; }
log() { :; }
setup_with_lock() { "$@"; }

menu_read_choice_test() {
    menu_read_choice
    [[ "$MENU_CHOICE" == 0 ]]
}
printf '\033' | menu_read_choice_test
printf '00\n' | { menu_read_choice; [[ "$MENU_CHOICE" == 00 ]]; }
printf '13\n' | { menu_read_choice; [[ "$MENU_CHOICE" == 13 ]]; }

sources_load() {
    SRC_ROWS=('alpha | home | ~/.alpha')
    DOTFILES_GROUPS=(shell)
    declare -gA DOTFILES_ITEM_GROUP=([alpha]=shell)
}
sources_parse() {
    IFS='|' read -r S_NAME S_MODE S_SRC <<< "$1"
    S_NAME="${S_NAME// /}"
    S_MODE="${S_MODE// /}"
    S_SRC="${S_SRC// /}"
}
cli_dotfiles_execute() { printf 'EXEC %s\n' "$*"; }

# Esc на першому екрані повертає без виконання дії.
out="$(printf '\033' | menu_action_dotfiles_backup_group)"
[[ "$out" != *EXEC* ]]
# Esc після вибору групи також повертає без запуску.
out="$(printf '1\n\033' | menu_action_dotfiles_restore_group)"
[[ "$out" != *EXEC* ]]
# Виклик через menu_run: повернення не виводить паузу Enter.
out="$(printf '1\n\0330\n' | menu_run 'Тест' 'dotfiles_backup_group|Резервувати групу|')"
[[ "$out" != *'Enter, щоб продовжити'* ]]
# Список modules: all стоїть після порожнього рядка.
registry_ids() { printf 'base\ncli\n'; }
registry_title() { printf '%s' "$1"; }
out="$(printf '0\n' | menu_run 'Пакети' --provider packages_items)"
# Перевіряємо структуру, а не ширину колонок (залежить від утиліти column).
# all має бути після порожнього рядка і після звичайних модулів.
[[ "$out" == *'Модуль cli'* ]]
[[ "$out" == *$'\n\n3)  all'* ]]
[[ "$out" == *'Встановити всі модулі'* ]]
printf '[PASS] test-menu-escape-v1412\n'
