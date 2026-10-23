#!/usr/bin/env bash
# Перевірка явної групи конфігурацій і порядку hooks.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/path.sh
source "$ROOT_DIR/src/core/path.sh"
# shellcheck source=../src/packages/registry.sh
source "$ROOT_DIR/src/packages/registry.sh"
# shellcheck source=../src/dotfiles/sources.sh
source "$ROOT_DIR/src/dotfiles/sources.sh"
# shellcheck source=../src/packages/packages.sh
source "$ROOT_DIR/src/packages/packages.sh"
# shellcheck source=../src/packages/packages_validation.sh
source "$ROOT_DIR/src/packages/packages_validation.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha beta
aur =
configs_group = shell
configs =
config.alpha = demo_extra
hooks = general
hook.alpha = bound
INI
packages_load "$tmp/packages.conf"
[[ "${PACKAGE_CONFIGS_GROUP[demo]}" == shell ]]
log() { :; }
header() { :; }
stage() { :; }
hooks_validate() { return 0; }
pkgs_install() { [[ "$2" == alpha ]]; }
sources_load() {
    SRC_ROWS=('zsh | home | ~/.zshrc' 'zsh-alias | home | ~/.zsh_alias.zsh' 'other | home | ~/.other')
    DOTFILES_GROUPS=(shell other)
    declare -gA DOTFILES_ITEM_GROUP=([zsh]=shell [zsh-alias]=shell [other]=other [demo_extra]=other)
}
configs_apply() { printf 'config:%s\n' "$@" >> "$tmp/actions"; }
hooks_run() { printf 'hook:general\n' >> "$tmp/actions"; }
hooks_run_bound() { printf 'hook:bound:%s\n' "$2" >> "$tmp/actions"; }
: > "$tmp/actions"
pkg_run_module demo > "$tmp/result"
mapfile -t lines < "$tmp/actions"
[[ "${lines[0]}" == config:zsh ]]
[[ "${lines[1]}" == config:zsh-alias ]]
[[ "${lines[2]}" == config:demo_extra ]]
[[ "${lines[3]}" == hook:general ]]
[[ "${lines[4]}" == hook:bound:alpha ]]
[[ "${#lines[@]}" == 5 ]]
# Група повинна бути явною: без configs_group — без її копіювання.
sed -i 's/configs_group = shell/configs_group =/' "$tmp/packages.conf"
packages_load "$tmp/packages.conf"
: > "$tmp/actions"
pkg_run_module demo > "$tmp/result"
! grep -q 'config:zsh' "$tmp/actions"
# Doctor перевіряє невідому групу та дублювання записів.
sources_load
PACKAGE_CONFIGS_GROUP[demo]=absent
if packages_validate_references; then exit 1; fi
PACKAGE_CONFIGS_GROUP[demo]=shell
PACKAGE_CONFIGS[demo]=zsh
if packages_validate_references; then exit 1; fi
printf '[PASS] test-configs-group-v1413\n'
