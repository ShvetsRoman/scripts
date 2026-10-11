#!/usr/bin/env bash
# Перевірка спільних заголовків усіх інтерактивних меню.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
grep -Fq "print_header 'SETUP MANAGER V3.0'" "$ROOT/setup.sh"
grep -Fq "print_header 'MAINTENANCE'" "$ROOT/setup.sh"
grep -Fq 'print_header "DOTFILES MANAGER"' "$ROOT/dotfiles-manager/dotfiles-manager.sh"
grep -Fq 'print_header "INSTALLER PACKAGES V2.0"' "$ROOT/install-packages/lib/menu.sh"
grep -Fq 'print_header "ОБСЛУГОВУВАННЯ"' "$ROOT/install-packages/lib/menu.sh"
[[ ! -e "$ROOT/install-packages/lib/ui.sh" ]]
[[ ! -e "$ROOT/install-packages/lib/colors.sh" ]]
[[ ! -e "$ROOT/dotfiles-manager/lib/logging.sh" ]]
# shellcheck source=../lib/ui.sh
source "$ROOT/lib/ui.sh"
[[ "$(NO_COLOR=1 bash -c 'source "$1/lib/ui.sh"; print_header "TEST"' _ "$ROOT")" == *TEST* ]]
printf '[PASS] Єдині заголовки меню та узгоджені назви файлів\n'
