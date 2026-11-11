#!/usr/bin/env bash
# Контракт мутуючих операцій: update змінює код лише після підтвердження
# або --yes; DRY-RUN не змінює нічого і підтвердження не потребує.
set -Eeuo pipefail
BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cp -a -- "$BASE" "$tmp/project"
repo="$tmp/project"
mkdir -p "$tmp/home"
export HOME="$tmp/home"
printf 'not a release archive\n' > "$tmp/fake.tar.gz"
# Без tty і без --yes: підтвердження неможливе, хелпер оновлення не запускається.
output="$(bash "$repo/backup-install_manager.sh" update "$tmp/fake.tar.gz" </dev/null 2>&1)"
[[ "$output" == *'Потрібне інтерактивне підтвердження'* ]]
[[ "$output" != *'update_safe'* ]]
# DRY-RUN: підтвердження не потрібне; некоректний архів відхиляється хелпером.
code=0
output="$(bash "$repo/backup-install_manager.sh" update "$tmp/fake.tar.gz" --dry-run </dev/null 2>&1)" || code=$?
[[ "$code" != 0 ]]
[[ "$output" != *'Потрібне інтерактивне підтвердження'* ]]
# --yes: підтвердження пропущено; некоректний архів відхиляється хелпером.
code=0
output="$(bash "$repo/backup-install_manager.sh" update --yes "$tmp/fake.tar.gz" </dev/null 2>&1)" || code=$?
[[ "$code" != 0 ]]
[[ "$output" != *'Потрібне інтерактивне підтвердження'* ]]
printf '[PASS] test-update-confirm-v202\n'
