#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$repo"
source "$repo/src/packages/registry.sh"
source "$repo/src/core/path.sh"
source "$repo/src/hooks/hooks.sh"
log() { printf '[%s] %s\n' "$1" "$2" >&2; }
packages_load "$repo/config/packages.conf"
[[ "${#PACKAGE_IDS[@]}" == 13 ]]
for id in "${PACKAGE_IDS[@]}"; do
    registry_valid "$id"
    packages_select "$id"
    [[ -n "${PACKAGE_TITLES[$id]}" ]]
    hooks_validate "$id"
done
packages_select cli
[[ "${CONFIG_ITEMS[*]}" == *superfile* ]]
[[ -z "${PACKAGE_HOOKS[cli]:-}" ]]
[[ "${PACKAGE_HOOKS[snapper]}" == snapper ]]
[[ -z "${PACKAGE_CONFIGS[shell]}" ]]
[[ "${PACKAGE_BOUND_CONFIGS[shell|zsh]}" == 'zsh zshenv' ]]
[[ "${PACKAGE_BOUND_CONFIGS[shell|starship]}" == starship ]]
! grep -Eiq 'github|GITHUB_ITEMS|PACKAGE_ORDERS' "$repo/config/packages.conf"
[[ ! -f "$repo/setup.sh" && ! -e "$repo/config/sources.conf" && ! -d "$repo/modules" ]]
# Дублікат секції повинен бути помилкою.
tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT
printf '[base]\ntitle = One\n[base]\ntitle = Two\n' > "$tmp"
if (packages_load "$tmp") 2>/dev/null; then exit 1; fi
printf '[PASS] test-packages-config-v4\n'
