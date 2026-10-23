#!/usr/bin/env bash
# Перевірка поведінки журналу після зникнення тимчасового каталогу.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export SETUP_LOG_FILE="$tmp/session.log"
export SETUP_COLOR=never
# shellcheck source=../src/core/ui.sh
source "$ROOT_DIR/src/core/ui.sh"
ui_init_colors
log info 'Журнал існує'
grep -Fq '[INFO] Журнал існує' "$SETUP_LOG_FILE"
rm -rf -- "$tmp"
output="$(log info 'Каталог журналу вже видалено' 2>&1)"
[[ "$output" == *'[INFO] Каталог журналу вже видалено'* ]]
[[ "$output" != *'No such file or directory'* ]]
mkdir -p -- "$tmp"
log ok 'Журнал відновлено'
grep -Fq '[OK] Журнал відновлено' "$SETUP_LOG_FILE"
printf '[PASS] test-log-lifecycle-v143\n'
