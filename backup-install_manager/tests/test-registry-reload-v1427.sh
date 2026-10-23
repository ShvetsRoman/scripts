#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Незалежний тест: без системних дій, використовує stubs.
source "$ROOT_DIR/src/packages/configs.sh"
read_count=0
sources_load() { read_count=$((read_count + 1)); }
sources_find() { return 1; }
log() { :; }
STRICT_CONFIGS=false
configs_apply unknown
[[ "$read_count" == 1 ]]
configs_apply unknown
[[ "$read_count" == 2 ]]
# В одному пакеті вже перевірений реєстр не перечитується.
package_context() {
    local PKG_DOTFILES_LOADED=true
    configs_apply unknown
    configs_apply unknown
}
package_context
[[ "$read_count" == 2 ]]
# Поза контекстом повторне читання не заблоковано.
configs_apply unknown
[[ "$read_count" == 3 ]]
# Перевірка, що packages_main() передає тимчасовий прапорець.
grep -Fq 'local PKG_DOTFILES_LOADED=true' "$ROOT_DIR/src/packages/packages.sh"
grep -Fq 'local PKG_DOTFILES_LOADED="${PKG_DOTFILES_LOADED:-false}"' "$ROOT_DIR/src/packages/packages.sh"
