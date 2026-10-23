#!/usr/bin/env bash
# Валідація реєстру до будь-якого запису та відсутні записи в CLI.
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/ui.sh
source "$PROJECT_DIR/src/core/ui.sh"
ui_init_colors
# shellcheck source=../src/core/path.sh
source "$PROJECT_DIR/src/core/path.sh"
# shellcheck source=../src/dotfiles/sources.sh
source "$PROJECT_DIR/src/dotfiles/sources.sh"
fail() { printf '[FAIL] test-validation: %s\n' "$1" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
ROOT_DIR="$tmp/repo"
mkdir -p "$ROOT_DIR"
cp -a "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tools" "$ROOT_DIR/tools"; mkdir -p "$ROOT_DIR/config"
file="$ROOT_DIR/config/dotfiles.conf"
printf '[test]\nconf | home | ~/.config\n' > "$file"
sources_validate >/dev/null || fail 'valid entry'

printf '%s\n' 'vim | home | ~/.config/nvim' >> "$file"
if sources_validate >/dev/null 2>&1; then fail 'nested destination accepted'; fi
printf '[test]\nconf | home | ~/.config\n' > "$file"
printf '%s\n' 'other | home | ~/.extra' >> "$file"
sources_validate >/dev/null || fail 'disjoint entries rejected'

if sources_add bad home .file .config/nvim >/dev/null 2>&1; then fail 'sources add accepted overlapping dst'; fi
if sources_add bad home .file $'name\nunsafe' >/dev/null 2>&1; then fail 'control character accepted'; fi

# Якщо реєстр зник або став symlink, runtime не мовчить.
rm -f -- "$file"
if sources_load >/dev/null 2>&1; then fail 'missing registry accepted'; fi
printf '[test]\nnew | home | ~/.new\n' > "$tmp/foreign"
ln -s "$tmp/foreign" "$file"
if sources_load >/dev/null 2>&1; then fail 'symlink registry accepted'; fi

printf '[PASS] test-validation\n'
