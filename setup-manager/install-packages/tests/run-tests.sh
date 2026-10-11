#!/usr/bin/env bash
# ShellCheck без -x не переходить за source до локальних бібліотек.
# shellcheck disable=SC1091
# Спільний контракт змінних між Bash-модулями.
# shellcheck disable=SC2034
# Автономні тести V2.0. Не встановлюють програм.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
while IFS= read -r -d '' file; do
    bash -n "$file" || fail "Синтаксис $file"
done < <(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name '*.conf' \) -print0)
pass 'Синтаксис Bash'
source "$ROOT_DIR/config/installer.conf"
source "$ROOT_DIR/lib/registry.sh"
source "$ROOT_DIR/../lib/ui.sh"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/configs.sh"
source "$ROOT_DIR/lib/package-manager.sh"
source "$ROOT_DIR/lib/modules.sh"
source "$ROOT_DIR/lib/menu.sh"
((${#MODULES[@]} == 12)) || fail 'Модулі не завантажені'
pass 'Автовиявлення модулів'
build_module_configs
validate_config_map
for module in "${MODULES[@]}"; do
    [[ -f "$ROOT_DIR/modules/$module.sh" ]] || fail "Файл модуля $module"
    validate_module_metadata "$module" || fail "Метадані $module"
done
pass 'Метадані та конфіги'
[[ -v 'GITHUB_PACKAGES[superfile]' ]] || fail 'Superfile'
[[ -v 'CONFIG_MAP[nvim]' ]] || fail 'Neovim config'
[[ "${MODULE_POST_HOOKS[shell]}" == configure_default_shell ]] || fail 'Zsh hook'
[[ "${MODULE_SERVICES[docker]}" == docker ]] || fail 'Docker service'
declare -F configure_default_shell >/dev/null || fail 'Функція Zsh hook'
declare -F configure_docker_user >/dev/null || fail 'Функція Docker hook'
pass 'Перенесення даних V1.6'
REQUESTED_MODULES=(base docker cli)
resolve_requested_modules
[[ "${RESOLVED_MODULES[*]}" == 'base docker cli' ]] || fail 'Залежності'
pass 'Залежності'
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning -e SC1090,SC1091,SC2034 "$ROOT_DIR/install.sh" "$ROOT_DIR"/lib/*.sh "$ROOT_DIR"/modules/*.sh "$ROOT_DIR"/tests/run-tests.sh || fail ShellCheck
    pass ShellCheck
fi
# Перевіряємо автоматичне підхоплення нового модуля без редагування registry.
TEMP_MODULE="$ROOT_DIR/modules/test-v2-auto.sh"
cleanup_test_module() { rm -f -- "$TEMP_MODULE"; }
trap cleanup_test_module EXIT
cat > "$TEMP_MODULE" <<'MODULE'
MODULE_ID="test-v2-auto"
MODULE_TITLE="Тестовий модуль"
MODULE_ORDER=998
MODULE_DEPENDS=""
MODULE_SERVICES_LIST=""
MODULE_POST_HOOK="test_v2_auto_hook"
test_v2_auto_hook() { :; }
PACMAN_PACKAGES=(test-example-pkg)
AUR_PACKAGES=()
GITHUB_ITEMS=()
CONFIG_ITEMS=("test-v2-auto|home|.config/test-v2-auto|.config/test-v2-auto")
MODULE
MODULES=()
load_module_registry
module_exists 'test-v2-auto' || fail 'Новий модуль не виявлено'
[[ -v 'CONFIG_MAP[test-v2-auto]' ]] || fail 'Автоконфіг нового модуля'
[[ "${MODULE_PACMAN_ARRAYS[test-v2-auto]}" == MOD_test_v2_auto_PACMAN ]] || fail 'Нові пакети'
# Тестовий hook визначається в тому ж модулі без окремого файлу.
declare -F test_v2_auto_hook >/dev/null || fail 'Hook нового модуля'
cleanup_test_module
trap - EXIT
pass 'Автоматичне додавання нового модуля'
printf '\nУсі перевірки V2.0 завершено.\n'
