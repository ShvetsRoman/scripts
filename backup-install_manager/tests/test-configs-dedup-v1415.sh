#!/usr/bin/env bash
# Перевірка повторних конфігурацій та захисту під час застосування.
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
# shellcheck source=../src/packages/packages.sh
source "$ROOT_DIR/src/packages/packages.sh"
log() { :; }
header() { :; }
stage() { :; }
hooks_validate() { return 0; }
pkgs_install() { return 0; }
hooks_run() { :; }
hooks_run_bound() { :; }
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
cat > "$work/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha beta
aur =
configs_group = shell
configs =
config.alpha = extra
config.beta = another
hooks =
INI
packages_load "$work/packages.conf"
sources_load() {
    SRC_ROWS=('a | home | ~/.a' 'b | home | ~/.b' 'extra | home | ~/.extra' 'another | home | ~/.another')
    DOTFILES_GROUPS=(shell other)
    declare -gA DOTFILES_ITEM_GROUP=([a]=shell [b]=shell [extra]=other [another]=other)
}
sources_load
packages_validate_references
configs_apply() { printf '%s\n' "$@" >> "$work/applied"; }
: > "$work/applied"
pkg_run_module demo > "$work/output"
[[ "$(sort "$work/applied" | uniq -d | wc -l)" -eq 0 ]]
[[ "$(wc -l < "$work/applied")" -eq 4 ]]
# Повтори між різними прив'язаними пакетами також заборонені.
PACKAGE_BOUND_CONFIGS['demo|beta']='extra'
if packages_validate_references > /dev/null; then exit 1; fi
# Повторення через групу та явний configs не допускається.
PACKAGE_BOUND_CONFIGS['demo|beta']='another'
PACKAGE_CONFIGS[demo]='a'
if packages_validate_references > /dev/null; then exit 1; fi
# Повторення через групу та прив'язку теж заборонене.
PACKAGE_CONFIGS[demo]=''
PACKAGE_BOUND_CONFIGS['demo|alpha']='a'
if packages_validate_references > /dev/null; then exit 1; fi
printf '[PASS] test-configs-dedup-v1415\n'
