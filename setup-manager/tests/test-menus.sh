#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(printf '1\n0\n2\n0\n7\n0\n00\n' | bash "$PROJECT_DIR/setup.sh")"
for title in 'SETUP MANAGER' 'INSTALLER' 'DOTFILES' 'MAINTENANCE'; do
    [[ "$output" == *"========== $title =========="* ]] || { printf '[FAIL] Меню: %s\n' "$title"; exit 1; }
done
[[ "$output" == *'1)   Installer'* && "$output" == *'9)   Help'* ]] || exit 1
[[ "$output" == *'Резервне копіювання, відновлення, порівняння та перевірка'* ]] || exit 1
[[ "$output" == *'Архіви, точки відновлення та очищення'* ]] || exit 1
[[ "$output" == *'Встановлення модуля Base'* ]] || exit 1
[[ "$output" == *'Встановлення всіх модулів'* ]] || exit 1
[[ "$output" == *$'00) Вихід'*$'\n\n''Виберіть дію:'* ]] || exit 1
[[ "$output" == *'11)  Dotfiles Cleanup'* ]] || exit 1
# Перевірка додаткових вкладених меню.
output="$(printf '2\n6\n0\n7\n0\n00\n' | bash "$PROJECT_DIR/setup.sh")"
[[ "$output" == *'========== ARCHIVE =========='* && "$output" == *'========== RECOVERY =========='* ]] || exit 1
printf '[PASS] Єдиний стиль усіх меню і навігація 0/00\n'
