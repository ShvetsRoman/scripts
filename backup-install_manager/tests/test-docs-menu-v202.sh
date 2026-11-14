#!/usr/bin/env bash
# Контракт документації, версії й єдиного блоку підказок.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/src/core/version.sh"
[[ "$SETUP_VERSION" == '2.0.2' ]]
[[ "$(bash "$root/backup-install_manager.sh" --version)" == "$SETUP_VERSION" ]]
[[ $(grep -cF 'case "$title" in' "$root/src/cli/menu.sh") -eq 1 ]]
[[ $(grep -cF 'Архів містить dotfiles/ проєкту' "$root/src/cli/menu.sh") -eq 1 ]]
[[ $(grep -cF 'Recovery — захисні копії' "$root/src/cli/menu.sh") -eq 1 ]]
[[ -f "$root/README.md" ]]
grep -qF 'Backup Install Manager' "$root/README.md"
! grep -Eq '^# .*Bash Setup Manager|^# .*Setup Manager' "$root/README.md"
printf '[PASS] test-docs-menu-v202\n'
