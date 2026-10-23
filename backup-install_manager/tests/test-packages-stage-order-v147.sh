#!/usr/bin/env bash
# Послідовність етапів, зокрема після пропуску пакета.
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
config.alpha = alpha_config
config.beta = beta_config
config.gamma = gamma_config
hooks = general
hook.alpha = alpha_hook
hook.beta = beta_hook
hook.gamma = gamma_hook
INI
packages_load "$tmp/packages.conf"
log() { printf "[%s] %s\n" "$1" "$2"; }
header() { :; }
stage() { :; }
hooks_validate() { return 0; }
pkgs_install() {
    printf 'install:%s\n' "$2" >> "$tmp/actions"
    [[ "$2" != beta ]]
}
configs_apply() {
    local item
    for item in "$@"; do printf 'config:%s\n' "$item" >> "$tmp/actions"; done
}
hooks_run_bound() { printf 'hook:%s:%s\n' "$1" "$2" >> "$tmp/actions"; }
hooks_run() { printf 'general:%s\n' "$1" >> "$tmp/actions"; }
pkg_run_module demo > "$tmp/output"
cat > "$tmp/expected" <<'EXPECTED'
install:alpha
install:beta
install:gamma
config:common
config:alpha_config
config:gamma_config
general:demo
hook:alpha_hook:alpha
hook:gamma_hook:gamma
EXPECTED
diff -u "$tmp/expected" "$tmp/actions"
grep -Fq 'Пропущені пакети (1)' "$tmp/output"
grep -Fq 'Пропущені конфіги (1)' "$tmp/output"
grep -Fq 'Пропущені hooks (1)' "$tmp/output"
printf '[PASS] test-packages-stage-order-v147\n'
