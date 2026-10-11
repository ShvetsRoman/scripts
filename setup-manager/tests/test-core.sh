#!/usr/bin/env bash
# Інтеграційні тести спільного ядра без зміни справжнього HOME.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/core.sh
source "$ROOT/lib/core.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/src/sub" "$tmp/repo"
printf 'alpha\n' >"$tmp/src/sub/test"
core_snapshot dotfiles "$tmp/src" "$tmp/repo" false >/dev/null
core_compare "$tmp/src" "$tmp/repo"
printf 'beta\n' >"$tmp/repo/sub/test"
if core_compare "$tmp/src" "$tmp/repo"; then echo '[FAIL] Diff'; exit 1; fi
core_snapshot recovery "$tmp/repo" "$tmp/recovery" false
cmp -s "$tmp/repo/sub/test" "$tmp/recovery/sub/test"
core_sync "$tmp/src" "$tmp/repo" true false >/dev/null
core_compare "$tmp/src" "$tmp/repo"
core_snapshot installer "$tmp/repo" "$tmp/installer-backup" false
core_compare "$tmp/repo" "$tmp/installer-backup"
printf '[PASS] Core sync / compare / installer / recovery / dotfiles\n'
