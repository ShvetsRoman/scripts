#!/usr/bin/env bash
# Регресійні тести: доступні, відсутні та вже встановлені пакети.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../install-packages/lib/package-manager.sh
source "$ROOT/install-packages/lib/package-manager.sh"

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok() { printf '[OK] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; }
log_error() { printf '[ERROR] %s\n' "$*"; }
log_step() { printf '[STEP] %s\n' "$*"; }
package_installed() { [[ "$1" == already ]]; }
pacman_package_exists() { [[ "$1" == valid ]]; }
aur_package_exists() { [[ "$1" == aur-valid ]]; }
ensure_paru() { :; }
# У середовищі тесту paru може бути відсутнім; створимо мок-команду.
mock_dir="$(mktemp -d)"
trap 'rm -rf -- "$mock_dir"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$mock_dir/paru"
chmod +x "$mock_dir/paru"
PATH="$mock_dir:$PATH"
DRY_RUN=true
ASSUME_YES=false
run_cmd() { printf '[CMD] %s\n' "$*"; }

output="$(install_pacman already valid absent)"
[[ "$output" == *"already вже встановлено"* ]] || { echo '[FAIL] встановлений пакет'; exit 1; }
[[ "$output" == *"Пакет 'absent' не знайдено"* ]] || { echo '[FAIL] відсутній pacman'; exit 1; }
[[ "$output" == *"[CMD] sudo pacman -S --needed valid"* ]] || { echo '[FAIL] список pacman'; exit 1; }
[[ "$output" != *"--needed valid absent"* ]] || { echo '[FAIL] відсутній пакет передано pacman'; exit 1; }

output="$(install_paru already aur-valid aur-absent)"
[[ "$output" == *"AUR-пакет 'aur-absent' не знайдено"* ]] || { echo '[FAIL] відсутній AUR'; exit 1; }
[[ "$output" == *"[CMD] paru -S --needed aur-valid"* ]] || { echo '[FAIL] список AUR'; exit 1; }
[[ "$output" != *"--needed aur-valid aur-absent"* ]] || { echo '[FAIL] відсутній пакет передано paru'; exit 1; }

output="$(install_pacman absent)"
[[ "$output" != *'[CMD]'* ]] || { echo '[FAIL] зайве встановлення pacman'; exit 1; }
output="$(install_paru aur-absent)"
[[ "$output" != *'[CMD]'* ]] || { echo '[FAIL] зайве встановлення AUR'; exit 1; }
printf '[PASS] Перевірка доступності Pacman та AUR, пропуск відсутніх пакетів\n'
