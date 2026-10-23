#!/usr/bin/env bash
# Статус не повинен очищати екран або змінювати scrollback Kitty.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Контроль функції, щоб очистка не спрацьовувала навіть під час інтерактивного виклику.
source "$root/src/dotfiles/sync.sh"
ui_clear() { printf 'UNEXPECTED_CLEAR\n'; return 99; }
sources_load() { SRC_ROWS=(); }
sync_validate_filter() { return 0; }
header() { printf '=== %s ===\n' "$*"; }
sync_report_untracked() { :; }
log() { printf '[%s] %s\n' "$1" "$2"; }
output="$(sync_status)"
[[ "$output" != *UNEXPECTED_CLEAR* ]] || { printf '[FAIL] sync_status викликає ui_clear\n' >&2; exit 1; }
[[ "$(grep -c 'status    HOME ↔ dotfiles' <<< "$output")" == 1 ]] || { printf '[FAIL] Повтор заголовка статусу\n' >&2; exit 1; }
# Перевірка CLI: без escape-послідовностей очищення та одного заголовка.
output="$(SETUP_COLOR=never bash "$root/backup-install_manager.sh" dotfiles status)"
[[ "$(grep -c 'status    HOME ↔ dotfiles' <<< "$output")" == 1 ]] || { printf '[FAIL] Повтор заголовка CLI\n' >&2; exit 1; }
[[ "$output" != *$'\033[2J'* && "$output" != *$'\033[3J'* ]] || { printf '[FAIL] CLI змінює історію термінала\n' >&2; exit 1; }
printf '[PASS] test-dotfiles-status-ui-v201\n'
