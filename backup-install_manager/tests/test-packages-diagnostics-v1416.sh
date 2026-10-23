#!/usr/bin/env bash
# Декілька незалежних помилок мають бути показані за один прохід.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/path.sh
source "$ROOT_DIR/src/core/path.sh"
# shellcheck source=../src/packages/registry.sh
source "$ROOT_DIR/src/packages/registry.sh"
# shellcheck source=../src/dotfiles/sources.sh
source "$ROOT_DIR/src/dotfiles/sources.sh"
# shellcheck source=../src/packages/packages_validation.sh
source "$ROOT_DIR/src/packages/packages_validation.sh"
log() { printf '[%s] %s\n' "$1" "$2"; }
packages_load "$ROOT_DIR/config/packages.conf"
sources_load
output="$(packages_validate_references)"
[[ "$output" == *'packages.conf: configs та джерела пакетів перевірено'* ]]
PACKAGE_CONFIGS_GROUP[base]='nonexistent_group_v1416'
PACKAGE_CONFIGS[base]='nonexistent_config_v1416'
PACKAGE_AUR[base]="${PACKAGE_PACMAN[base]%% *}"
PACKAGE_CONFIGS[cli]='another_missing_config_v1416'
if output="$(packages_validate_references)"; then
    printf '[FAIL] Валідація мала завершитися помилкою\n' >&2
    exit 1
fi
[[ "$output" == *'base.configs_group: невідома група'* ]]
[[ "$output" == *'base.configs: невідомий запис'* ]]
[[ "$output" == *'cli.configs: невідомий запис'* ]]
[[ "$output" == *'одночасно в pacman і aur'* ]]
[[ "$output" == *'packages.conf: знайдено помилок: 4'* ]]
[[ "$(printf '%s\n' "$output" | grep -c '^\[error\]')" == 5 ]]
packages_load "$ROOT_DIR/config/packages.conf"
PACKAGE_CONFIGS[shell]="${PACKAGE_BOUND_CONFIGS['shell|zsh']}"
if output="$(packages_validate_references)"; then exit 1; fi
[[ "$output" == *'повторено'* ]]
[[ "$output" == *'packages.conf: знайдено помилок: 2'* ]]
printf '[PASS] test-packages-diagnostics-v1416\n'
