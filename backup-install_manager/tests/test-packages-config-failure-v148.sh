#!/usr/bin/env bash
# Прив'язана конфігурація, що не застосувалась, блокує тільки власний hook.
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
pacman = alpha beta gamma
configs = common
config.alpha = cfg_alpha
config.beta = cfg_beta
config.gamma = cfg_gamma
hooks = general
hook.alpha = hook_alpha
hook.beta = hook_beta
hook.gamma = hook_gamma
INI
packages_load "$tmp/packages.conf"
log() { printf '[%s] %s\n' "$1" "$2"; }
header() { :; }
stage() { :; }
hooks_validate() { return 0; }
pkgs_install() { printf 'install:%s\n' "$2" >> "$tmp/actions"; }
configs_apply() {
    local item
    for item in "$@"; do
        printf 'config:%s\n' "$item" >> "$tmp/actions"
        [[ "$item" != cfg_beta ]] || return 1
    done
}
hooks_run_bound() { printf 'hook:%s:%s\n' "$1" "$2" >> "$tmp/actions"; }
hooks_run() { printf 'general:%s\n' "$1" >> "$tmp/actions"; }
pkg_run_module demo > "$tmp/output"
cat > "$tmp/expected" <<'EXPECTED'
install:alpha
install:beta
install:gamma
config:common
config:cfg_alpha
config:cfg_beta
config:cfg_gamma
general:demo
hook:hook_alpha:alpha
hook:hook_gamma:gamma
EXPECTED
diff -u "$tmp/expected" "$tmp/actions"
grep -Fq 'Demo: частковий успіх' "$tmp/output"
grep -Fq 'Пропущені конфіги (1)' "$tmp/output"
grep -Fq 'cfg_beta' "$tmp/output"
grep -Fq 'Пропущені hooks (1)' "$tmp/output"
grep -Fq 'hook_beta (пакет: beta; помилка конфігурації)' "$tmp/output"
# Збій загальної конфігурації залишається критичним.
: > "$tmp/actions"
configs_apply() { return 1; }
if pkg_run_module demo > "$tmp/output"; then
    printf '[FAIL] Загальна конфігурація має зупиняти групу\n' >&2
    exit 1
fi
if grep -Eq '^(hook:|general:)' "$tmp/actions"; then
    printf '[FAIL] Hook запущено після збою загальної конфігурації\n' >&2
    exit 1
fi
printf '[PASS] test-packages-config-failure-v148\n'
