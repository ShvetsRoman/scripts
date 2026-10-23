#!/usr/bin/env bash
# Перевірка прив'язки конфігурацій до результату встановлення пакета.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/packages/registry.sh
source "$ROOT_DIR/src/packages/registry.sh"
# shellcheck source=../src/packages/packages.sh
source "$ROOT_DIR/src/packages/packages.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha beta
configs = common
config.alpha = a_config
config.beta = b_config
hooks =
INI
packages_load "$tmp/packages.conf"
[[ "${PACKAGE_BOUND_CONFIGS[demo|alpha]}" == a_config ]]
[[ "${PACKAGE_BOUND_CONFIGS[demo|beta]}" == b_config ]]
log() { :; }
header() { :; }
stage() { :; }
hooks_validate() { return 0; }
hooks_run_bound() { return 0; }
hooks_run() { return 0; }
# alpha не встановлюється, beta встановлюється.
pkgs_install() { [[ "$2" != alpha ]]; }
configs_apply() { printf '%s\n' "$@" >> "$tmp/applied"; }
: > "$tmp/applied"
pkg_run_module demo > "$tmp/output"
grep -Fxq common "$tmp/applied"
grep -Fxq b_config "$tmp/applied"
if grep -Fxq a_config "$tmp/applied"; then exit 1; fi
grep -Fq 'a_config' "$tmp/output" || exit 1
# Явна конфігураційна команда обробляє всі записи.
: > "$tmp/applied"
CONFIGS_ONLY=true pkg_run_module demo > "$tmp/output"
for entry in common a_config b_config; do grep -Fxq "$entry" "$tmp/applied"; done
# Відсутній пакет у прив'язці — помилка.
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha
config.beta = b_config
INI
if packages_load "$tmp/packages.conf" 2>/dev/null; then exit 1; fi
# Подвійне використання конфігурації — помилка.
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha
configs = a_config
config.alpha = a_config
INI
if packages_load "$tmp/packages.conf" 2>/dev/null; then exit 1; fi
# Порожній загальний configs не повинен викликати configs_apply без аргументів,
# якщо є конфігурація, прив'язана до успішного пакета.
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = git
configs =
config.git = git-config
hooks =
INI
packages_load "$tmp/packages.conf"
pkgs_install() { return 0; }
configs_apply() {
    if (($# == 0)); then
        printf '%s\n' 'Конфігів немає.' >> "$tmp/empty-configs"
        return 0
    fi
    printf '%s\n' "$@" >> "$tmp/applied"
}
: > "$tmp/applied"
: > "$tmp/empty-configs"
pkg_run_module demo > "$tmp/output"
grep -Fxq 'git-config' "$tmp/applied"
[[ ! -s "$tmp/empty-configs" ]]
printf '[PASS] test-packages-config-bound-v146\n'
