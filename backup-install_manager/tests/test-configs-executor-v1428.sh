#!/usr/bin/env bash
# Перевірка спільного виконавця конфігурацій трьох джерел.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/packages/packages.sh
source "$ROOT_DIR/src/packages/packages.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
configs_apply() {
    printf '%s\n' "$@" >> "$work/applied"
    if [[ "${FAIL_CONFIG:-}" == "${1:-}" ]]; then return 7; fi
}
declare -A applied_configs=()
declare -A PACKAGE_BOUND_CONFIGS=(["demo|alpha"]='a b' ["demo|beta"]='b c')
: > "$work/applied"
pkg_configs_apply_once a b
pkg_configs_apply_once b c
pkg_configs_apply_bound demo alpha
pkg_configs_apply_bound demo beta
[[ "$(cat "$work/applied")" == $'a\nb\nc' ]]
[[ "${#applied_configs[@]}" -eq 3 ]]
# Код помилки конфігурації не втрачається.
applied_configs=()
FAIL_CONFIG=broken
if pkg_configs_apply_once broken; then exit 1; else [[ "$?" -eq 7 ]]; fi
# Невдала операція не заважає вже завершеним застосуванням.
[[ "$(cat "$work/applied")" == $'a\nb\nc\nbroken' ]]
printf '[PASS] test-configs-executor-v1428\n'
