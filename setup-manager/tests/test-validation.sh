#!/usr/bin/env bash
# Валідація реєстру до будь-якого запису та відсутні записи в CLI.
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/ui.sh
source "$PROJECT_DIR/lib/ui.sh"
# shellcheck source=../lib/path.sh
source "$PROJECT_DIR/lib/path.sh"
# shellcheck source=../lib/sources.sh
source "$PROJECT_DIR/lib/sources.sh"
fail() { printf '[FAIL] test-validation: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"; mkdir -p "$ROOT_DIR/config"
file="$ROOT_DIR/config/sources.conf"
printf '%s\n' 'conf | home | .config | .config | dotfiles' > "$file"
sources_validate >/dev/null || fail 'valid entry'

printf '%s\n' 'vim | home | .config/nvim | .config/nvim | dotfiles' >> "$file"
if sources_validate >/dev/null 2>&1; then fail 'nested destination accepted'; fi
printf '%s\n' 'conf | home | .config | .config | dotfiles' > "$file"
printf '%s\n' 'other | home | .extra | .extra | dotfiles' >> "$file"
sources_validate >/dev/null || fail 'disjoint entries rejected'

if sources_add bad home .file .config/nvim >/dev/null 2>&1; then fail 'sources add accepted overlapping dst'; fi
if sources_add bad home .file $'name\nunsafe' >/dev/null 2>&1; then fail 'control character accepted'; fi

# Якщо реєстр зник або став symlink, runtime не мовчить.
rm -f -- "$file"
if sources_load >/dev/null 2>&1; then fail 'missing registry accepted'; fi
printf '%s\n' 'new | home | .new | .new | dotfiles' > "$tmp/foreign"
ln -s "$tmp/foreign" "$file"
if sources_load >/dev/null 2>&1; then fail 'symlink registry accepted'; fi

printf '[PASS] test-validation\n'
