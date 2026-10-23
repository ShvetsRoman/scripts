#!/usr/bin/env bash
# Перевірка залежностей без змін користувацької системи.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$root/backup-install_manager.sh"
[[ "$(bash "$cli" modules deps docker)" == "Залежності docker:"* ]]
[[ "$(bash "$cli" modules reverse base)" == "Залежать від base:"* ]]
mapfile -t order < <(bash "$cli" modules plan | tail -n +2)
[[ "${order[0]}" == base ]]
source "$root/src/packages/registry.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/valid" <<'CONF'
[alpha]
title = Alpha
depends = beta
[beta]
title = Beta
CONF
packages_load "$tmp/valid"
[[ "$(registry_graph_order)" == $'beta\nalpha' ]]
cat > "$tmp/cycle" <<'CONF'
[alpha]
title = Alpha
depends = beta
[beta]
title = Beta
depends = alpha
CONF
if packages_load "$tmp/cycle" >/dev/null 2>&1; then exit 1; fi
cat > "$tmp/missing" <<'CONF'
[alpha]
title = Alpha
depends = missing
CONF
if packages_load "$tmp/missing" >/dev/null 2>&1; then exit 1; fi
printf '[PASS] test-module-graph-v200\n'
