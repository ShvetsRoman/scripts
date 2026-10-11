#!/usr/bin/env bash
# ShellCheck без -x не переходить за source до локальних бібліотек.
# shellcheck disable=SC1091
# Спільний контракт змінних між Bash-модулями.
# shellcheck disable=SC2034

set -Eeuo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=test_helper.sh
source "$TESTS_DIR/test_helper.sh"

BACKUP_DIRS=(".config/nvim")
BACKUP_FILES=(".zshrc")
EXCLUDE_PATTERNS=(".git" "*.tmp" "*.swp")

path_is_safe ".config/nvim"

if path_is_safe "../secret"; then
    exit 1
fi

if path_is_safe "/etc/passwd"; then
    exit 1
fi

if ! is_managed_path ".config/nvim"; then
    exit 1
fi

if ! is_managed_path ".config/nvim/lua/init.lua"; then
    exit 1
fi

if is_managed_path ".config"; then
    echo "FAIL: parent path .config не повинен бути допустимим backup path."
    exit 1
fi

if ! is_managed_or_parent ".config"; then
    echo "FAIL: parent path .config повинен зберігатися під час clean."
    exit 1
fi

printf 'PASS: validation - OK\n'
