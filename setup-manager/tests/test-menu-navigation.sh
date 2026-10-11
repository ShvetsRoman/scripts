#!/usr/bin/env bash
# Перевіряє 0=назад, 00=вихід у вкладених інтерактивних меню.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
assert_contains() { grep -Fq -- "$1" "$2" || { printf '[FAIL] Немає: %s\n' "$1" >&2; return 1; }; }
for file in "$ROOT/setup.sh" "$ROOT/install-packages/lib/menu.sh" "$ROOT/dotfiles-manager/dotfiles-manager.sh"; do
    assert_contains '00)' "$file"
done
assert_contains 'SETUP_MENU_CHILD' "$ROOT/install-packages/lib/menu.sh"
assert_contains 'SETUP_MENU_CHILD' "$ROOT/dotfiles-manager/dotfiles-manager.sh"
assert_contains "run_nested_menu \"\$INSTALLER\"" "$ROOT/setup.sh"
assert_contains "run_nested_menu \"\$DOTFILES\"" "$ROOT/setup.sh"
# Не запускає встановлення або копіювання: тільки вибір пунктів меню.
output="$(printf '7\n0\n00\n' | "$ROOT/setup.sh")"
[[ "$(grep -c 'SETUP MANAGER V3.0' <<<"$output")" -eq 2 ]] || { printf '[FAIL] 0 не повернув із Maintenance до головного меню\n' >&2; exit 1; }
output="$(printf '2\n0\n00\n' | "$ROOT/setup.sh")"
[[ "$(grep -c 'SETUP MANAGER V3.0' <<<"$output")" -eq 2 ]] || { printf '[FAIL] 0 не повернув із Dotfiles до головного меню\n' >&2; exit 1; }
output="$(printf '2\n00\n' | "$ROOT/setup.sh")"
[[ "$(grep -c 'SETUP MANAGER V3.0' <<<"$output")" -eq 1 ]] || { printf '[FAIL] 00 не завершив Setup Manager із Dotfiles\n' >&2; exit 1; }
printf '[PASS] Меню: 0 — назад, 00 — повний вихід\n'
