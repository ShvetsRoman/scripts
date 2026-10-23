#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo/src/packages/registry.sh"

# Порядок реєстру має збігатися з порядком секцій INI-файлу.
mapfile -t expected < <(sed -nE 's/^\[([a-z][a-z0-9_-]*)\]$/\1/p' "$repo/config/packages.conf")
((${#expected[@]} > 0))

packages_load "$repo/config/packages.conf"
mapfile -t actual < <(registry_ids)

[[ "${#actual[@]}" -eq "${#expected[@]}" ]]
for i in "${!expected[@]}"; do
    [[ "${actual[$i]}" == "${expected[$i]}" ]]
    registry_valid "${expected[$i]}"
    [[ -n "$(registry_title "${expected[$i]}")" ]]
done

# Реєстр не повинен приймати неіснуючу групу.
if registry_valid '__not_a_package__'; then
    printf '[FAIL] registry_valid прийняв неіснуючу групу\n' >&2
    exit 1
fi

printf '[PASS] test-registry-order\n'
