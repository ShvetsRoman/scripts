#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
# shellcheck source=../lib/core.sh
source "$ROOT/lib/core.sh"
mkdir -p "$TMP/home" "$TMP/dot"
printf 'equal\n' > "$TMP/home/same"
cp "$TMP/home/same" "$TMP/dot/same"
touch -t 202001010000 "$TMP/dot/same"
chmod 600 "$TMP/dot/same"
[[ -z "$(core_changes "$TMP/home" "$TMP/dot")" ]] || exit 1
printf 'new\n' > "$TMP/home/new.txt"
printf 'old\n' > "$TMP/dot/old.txt"
printf 'different\n' > "$TMP/dot/same"
result="$(core_changes "$TMP/home" "$TMP/dot")"
grep -q '^NEW|new.txt$' <<< "$result"
grep -q '^DEL|old.txt$' <<< "$result"
grep -q '^CHANGED|same$' <<< "$result"
if core_compare "$TMP/home" "$TMP/dot"; then
    printf '[FAIL] Порівняння не виявило відмінності\n' >&2
    exit 1
fi
# shellcheck source=../dotfiles-manager/lib/status.sh
source "$ROOT/dotfiles-manager/lib/status.sh"
path_exists_in_home() { [[ -e "$HOME/$1" || -L "$HOME/$1" ]]; }
path_exists_in_backup() { [[ -e "$DOTFILES_DIR/$1" || -L "$DOTFILES_DIR/$1" ]]; }
export HOME="$TMP/home"
DOTFILES_DIR="$TMP/dot"
# Ці значення використовуються у функції status_one, яка завантажується через source.
# shellcheck disable=SC2034
EXCLUDE_PATTERNS=()
# Використовуємо справжню спільну бібліотеку кольорів, без дублювання змінних.
# shellcheck source=../lib/ui.sh
source "$ROOT/lib/ui.sh"
# Status перевіряємо на стандартному зареєстрованому каталозі.
mkdir -p "$TMP/home/.config/example" "$TMP/dot/.config/example"
printf 'added\n' > "$TMP/home/.config/example/new"
printf 'deleted\n' > "$TMP/dot/.config/example/old"
output="$(status_one '.config/example')"
grep -Fq '[NEW]     .config/example/new - файл є в HOME, але відсутній у dotfiles' <<< "$output"
grep -Fq '[DEL]     .config/example/old - файл є в dotfiles, але відсутній у HOME' <<< "$output"
printf 'changed\n' > "$TMP/home/.config/example/changed"
printf 'other\n' > "$TMP/dot/.config/example/changed"
output="$(status_one '.config/example')"
grep -Fq '[CHANGED] .config/example/changed - вміст файлу змінено' <<< "$output"
printf 'PASS: content-only comparison and described NEW/DEL/CHANGED labels\n'
