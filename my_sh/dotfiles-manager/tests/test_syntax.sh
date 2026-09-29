#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mapfile -t scripts < <(find "$ROOT" -type f -name '*.sh' ! -path '*/.git/*' | sort)
for script in "${scripts[@]}"; do
    bash -n "$script"
done
bash -n "$ROOT/dotfiles-manager.sh"
echo 'PASS: syntax - OK'
