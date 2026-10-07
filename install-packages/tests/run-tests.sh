#!/usr/bin/env bash

# ShellCheck не може статично визначити ROOT_DIR для dynamic source.
# shellcheck disable=SC1091
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Синтаксис.
while IFS= read -r -d '' file; do
    bash -n "$file" || fail "syntax: $file"
done < <(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name '*.conf' \) -print0)
pass "syntax"

# 2. Структура.
required_files=(
    install.sh README.md
    config/installer.conf config/packages.conf config/modules.conf config/configs.conf
    lib/colors.sh lib/common.sh lib/cleanup.sh lib/package-manager.sh lib/configs.sh
    lib/services.sh lib/modules.sh lib/status.sh lib/ui.sh
    docs/ADDING_MODULE.md templates/module.sh
)
for file in "${required_files[@]}"; do
    [[ -f "$ROOT_DIR/$file" ]] || fail "missing: $file"
done
pass "structure"

# 3. Завантаження проєкту.
# shellcheck disable=SC2034
source "$ROOT_DIR/lib/colors.sh"
# shellcheck disable=SC2034
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/installer.conf"
source "$ROOT_DIR/config/packages.conf"
source "$ROOT_DIR/config/modules.conf"
source "$ROOT_DIR/config/configs.conf"
source "$ROOT_DIR/lib/package-manager.sh"
source "$ROOT_DIR/lib/configs.sh"
source "$ROOT_DIR/lib/services.sh"
source "$ROOT_DIR/lib/modules.sh"
source "$ROOT_DIR/lib/status.sh"
source "$ROOT_DIR/lib/ui.sh"

build_module_configs || fail "build-module-configs"
validate_config_map || fail "config-map validation"
pass "config-map"

# 4. MODULE_CONFIGS генерується автоматично.
[[ -v 'MODULE_CONFIGS[base]' ]] || fail "generated base config entry"
[[ -v 'MODULE_CONFIGS[docker]' ]] || fail "generated docker config entry"
[[ " ${MODULE_CONFIGS[cli]} " == *" nvim "* ]] || fail "nvim not mapped to cli"
[[ " ${MODULE_CONFIGS[cli]} " == *" kitty "* ]] || fail "kitty not mapped to cli"
[[ " ${MODULE_CONFIGS[cli]} " == *" wezterm "* ]] || fail "wezterm not mapped to cli"
[[ " ${MODULE_CONFIGS[cli]} " == *" superfile "* ]] || fail "superfile config not mapped to cli"
[[ " ${MODULE_CONFIGS[shell]} " == *" zsh "* ]] || fail "zsh not mapped to shell"
[[ " ${MODULE_CONFIGS[shell]} " == *" starship "* ]] || fail "starship not mapped to shell"
[[ -z "${MODULE_CONFIGS[base]}" ]] || fail "base configs should be empty"
pass "auto-module-configs"

# 5. configs.conf не містить ручного MODULE_CONFIGS mapping.
if grep -Eq '^\s*\[[a-zA-Z0-9_-]+\]=' "$ROOT_DIR/config/configs.conf" | grep -q 'MODULE_CONFIGS'; then
    fail "manual MODULE_CONFIGS mapping"
fi
# Точніша перевірка: після declare MODULE_CONFIGS не повинно бути [module]= записів.
if awk '/declare -Ag MODULE_CONFIGS=\(\)/{seen=1; next} seen && /\[[^]]+\]=/{exit 0} END{exit 1}' "$ROOT_DIR/config/configs.conf"; then
    fail "manual MODULE_CONFIGS entries found"
fi
pass "no-manual-module-configs"

# 6. Metadata модулів.
for module in "${MODULES[@]}"; do
    [[ -f "$ROOT_DIR/modules/$module.sh" ]] || fail "missing module file: $module"
    validate_module_metadata "$module" || fail "metadata: $module"
done
pass "module-metadata"

# 7. Resolver залежностей.
REQUESTED_MODULES=(docker)
# shellcheck disable=SC2034
INSTALL_DEPENDENCIES=true
resolve_requested_modules
[[ "${RESOLVED_MODULES[*]}" == "docker" ]] || fail "dependencies: ${RESOLVED_MODULES[*]}"
pass "dependencies"

# shellcheck disable=SC2034
REQUESTED_MODULES=(base docker cli)
resolve_requested_modules
[[ "${RESOLVED_MODULES[*]}" == "base docker cli" ]] || fail "dependency-dedup: ${RESOLVED_MODULES[*]}"
pass "dependency-dedup"

# 8. Модулі не містять config paths/package arrays.
if grep -RE '\.config/|\.zshrc|\.gitconfig|daemon\.json' "$ROOT_DIR/modules"/*.sh >/dev/null; then
    fail "hardcoded config path in modules"
fi
pass "module-config-separation"

if grep -RE '[A-Z][A-Z0-9_]*_(AUR_)?PACKAGES' "$ROOT_DIR/modules"/*.sh >/dev/null; then
    fail "direct package-array reference in modules"
fi
pass "module-package-separation"

# 9. Стандартний runner.
for module in "${MODULES[@]}"; do
    grep -Eq "install_registered_module[[:space:]]+\"?$module\"?" "$ROOT_DIR/modules/$module.sh" || \
        fail "module runner: $module"
done
pass "registered-module-runner"

# 10. Post hooks.
[[ "${MODULE_POST_HOOKS[shell]}" == "configure_default_shell" ]] || fail "shell hook mapping"
[[ "${MODULE_POST_HOOKS[docker]}" == "configure_docker_user" ]] || fail "docker hook mapping"
source "$ROOT_DIR/modules/shell.sh"
declare -F configure_default_shell >/dev/null || fail "missing configure_default_shell"
unset -f install_module configure_default_shell
source "$ROOT_DIR/modules/docker.sh"
declare -F configure_docker_user >/dev/null || fail "missing configure_docker_user"
unset -f install_module configure_docker_user
pass "post-hooks"

# 11. Порожній AUR mapping не потребує масиву.
[[ -z "${MODULE_AUR_ARRAYS[shell]}" ]] || fail "shell AUR mapping"
if declare -p SHELL_AUR_PACKAGES >/dev/null 2>&1; then
    fail "SHELL_AUR_PACKAGES should be optional"
fi
pass "optional-aur-array"

# 12. Зовнішні/GitHub packages.
[[ "${MODULE_GITHUB_ARRAYS[cli]}" == "CLI_GITHUB_PACKAGES" ]] || fail "cli github array mapping"
[[ " ${CLI_GITHUB_PACKAGES[*]} " == *" superfile "* ]] || fail "superfile not in cli github packages"
[[ "${GITHUB_PACKAGES[superfile]}" == 'script|https://superfile.dev/install.sh|spf' ]] || fail "superfile github mapping"
parse_github_package superfile >/dev/null || fail "parse github package"

# Перевіряємо всі підтримувані типи без реального встановлення.
GITHUB_PACKAGES["test-git"]='git|https://github.com/user/repo.git|mytool|~/.local/share/mytool|bin/mytool'
GITHUB_PACKAGES["test-binary"]='binary|https://github.com/user/repo/releases/download/v1.0/mytool|mytool|~/.local/bin/mytool'
parse_github_package test-git >/dev/null || fail "parse git package"
parse_github_package test-binary >/dev/null || fail "parse binary package"
unset 'GITHUB_PACKAGES[test-git]' 'GITHUB_PACKAGES[test-binary]'
pass "github-packages"

# 13. Starship — каталог і належить shell.
[[ "${CONFIG_MAP[starship]}" == 'shell|home|.config/starship|.config/starship' ]] || fail "starship mapping"
[[ "${CONFIG_MAP[superfile]}" == 'cli|home|.config/superfile|.config/superfile' ]] || fail "superfile config mapping"
pass "starship-directory"

# 13. Shell dry-run hook.
# shellcheck disable=SC2034
(
    DRY_RUN=true
    USER=nobody
    unset SUDO_USER || true
    source "$ROOT_DIR/modules/shell.sh"
    configure_default_shell >/dev/null
) || fail "shell dry-run hook"
pass "shell-dry-run-hook"

# 14. Динамічне меню.
menu_tmp="$(mktemp)"
trap 'rm -f -- "$menu_tmp"' EXIT
render_main_menu > "$menu_tmp"
module_count=${#MODULES[@]}
[[ "$MENU_INSTALL_ALL" -eq $((module_count + 1)) ]] || fail "dynamic menu install-all"
[[ "$MENU_DEPS" -eq $((module_count + 6)) ]] || fail "dynamic menu deps"
[[ "$MENU_HELP" -eq $((module_count + 8)) ]] || fail "dynamic menu help"
rm -f -- "$menu_tmp"
trap - EXIT
pass "dynamic-menu"

# 15. Версія.
for file in install.sh README.md lib/ui.sh docs/ADDING_MODULE.md; do
    grep -q 'V1\.6' "$ROOT_DIR/$file" || fail "version: $file"
done
pass "version"

# 16. Status/Verify різні.
grep -q 'STATUS: поточний стан системи' "$ROOT_DIR/lib/status.sh" || fail "status marker"
grep -q 'VERIFY: перевірка очікуваного стану' "$ROOT_DIR/lib/status.sh" || fail "verify marker"
grep -q 'Підсумок VERIFY' "$ROOT_DIR/lib/status.sh" || fail "verify summary"
pass "status-verify-separation"

# 17. Документація V1.6.
for needle in \
    'config/packages.conf' \
    'config/modules.conf' \
    'config/configs.conf' \
    'modules/<module>.sh' \
    'MODULE_POST_HOOKS' \
    'MODULE_GITHUB_ARRAYS' \
    'GITHUB_PACKAGES' \
    'install_registered_module' \
    'MODULE_CONFIGS'; do
    grep -Fq "$needle" "$ROOT_DIR/docs/ADDING_MODULE.md" || fail "docs: $needle"
done
pass "adding-module-docs"

# 18. Формат CONFIG_MAP має 4 поля.
for config_name in "${!CONFIG_MAP[@]}"; do
    IFS='|' read -r a b c d e <<< "${CONFIG_MAP[$config_name]}"
    [[ -n "$a" && -n "$b" && -n "$c" && -n "$d" && -z "${e:-}" ]] || fail "4-field map: $config_name"
done
pass "config-map-v1.6-format"

# 19. Help.
for needle in 'ДОДАВАННЯ ЗОВНІШНЬОЇ / GITHUB-ПРОГРАМИ' 'TYPE=script' 'TYPE=git' 'TYPE=binary' 'ДОДАВАННЯ AUR-ПАКЕТА' 'ОБСЛУГОВУВАННЯ' 'superfile'; do
    grep -Fq "$needle" "$ROOT_DIR/lib/ui.sh" || fail "help: $needle"
done
pass "help"

# 20. ShellCheck.
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -t files < <(find "$ROOT_DIR" -type f -name '*.sh')
    shellcheck -x "${files[@]}" || fail "shellcheck"
    pass "shellcheck"
else
    echo "SKIP: shellcheck не встановлено"
fi

pass "all"
