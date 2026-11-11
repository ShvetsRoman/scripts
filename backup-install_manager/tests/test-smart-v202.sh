#!/usr/bin/env bash
# Регресія smart: задокументований виклик без аргументів виконує dry-run
# усіх модулів і не передає літеральний --dry-run у packages_main.
set -Eeuo pipefail
BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cp -a -- "$BASE" "$tmp/project"
repo="$tmp/project"
# Застарілий lock-файл у вихідному дереві не має впливати на перевірку.
rm -f -- "$repo/.setup-manager.lock"
mkdir -p "$tmp/home"
export HOME="$tmp/home"
_smart_run() {
    bash "$repo/backup-install_manager.sh" "$@" </dev/null 2>&1
}
# smart без аргументів: doctor + dry-run усіх модулів, код 0, без помилок прапорців.
output="$(_smart_run smart)"
[[ "$output" != *'Параметр: --dry-run'* ]]
[[ "$output" == *'[DRY-RUN]'* ]]
[[ ! -e "$repo/.setup-manager.lock" ]]
# smart --dry-run: прапорець розбирається CLI, поведінка ідентична bare-виклику.
output="$(_smart_run smart --dry-run)"
[[ "$output" != *'Параметр: --dry-run'* ]]
[[ "$output" == *'[DRY-RUN]'* ]]
printf '[PASS] test-smart-v202\n'
