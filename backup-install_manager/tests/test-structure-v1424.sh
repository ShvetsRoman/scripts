#!/usr/bin/env bash
# Перевірка однозначної структури та документації проєкту.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
expected_version="$(bash -c 'source "$1/src/core/version.sh"; printf "%s" "$SETUP_VERSION"' bash "$root")"
for dir in core cli packages dotfiles recovery hooks diagnostics; do
    [[ -d "$root/src/$dir" ]] || { printf '[FAIL] Немає src/%s\n' "$dir" >&2; exit 1; }
done
for dir in lib core app packages recovery scripts; do
    [[ ! -e "$root/$dir" ]] || { printf '[FAIL] Застарілий каталог %s\n' "$dir" >&2; exit 1; }
done
[[ -f "$root/docs/architecture.md" && -f "$root/README.md" ]]
grep -Fq 'diagnostics/' "$root/docs/architecture.md"
[[ "$(bash "$root/backup-install_manager.sh" --version)" == "$expected_version" ]]
printf '[PASS] test-structure-v1424\n'
