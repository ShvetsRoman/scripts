#!/usr/bin/env bash
# ShellCheck без -x не переходить за source до локальних бібліотек.
# shellcheck disable=SC1091
# Спільний контракт змінних між Bash-модулями.
# shellcheck disable=SC2034

set -Eeuo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export DOTFILES_MANAGER_BACKUP_DIR="$TMP/backup"

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=test_helper.sh
source "$TESTS_DIR/test_helper.sh"

BACKUP_DIRS=(".config/test")
BACKUP_FILES=()
EXCLUDE_PATTERNS=(".git" "*.tmp" "*.swp")

mkdir -p "$HOME/.config/test" "$DOTFILES_DIR/.config/test"
printf 'same\n' > "$HOME/.config/test/config"
cp "$HOME/.config/test/config" "$DOTFILES_DIR/.config/test/config"

if [[ "$(status_one ".config/test")" != *"[OK]"* ]]; then
    exit 1
fi

printf 'changed\n' > "$HOME/.config/test/config"

if [[ "$(status_one ".config/test")" != *"[CHANGED]"* ]]; then
    exit 1
fi

cp "$DOTFILES_DIR/.config/test/config" "$HOME/.config/test/config"
printf 'ignored\n' > "$HOME/.config/test/cache.tmp"

if [[ "$(status_one ".config/test")" != *"[OK]"* ]]; then
    exit 1
fi

printf 'PASS: status - OK\n'
