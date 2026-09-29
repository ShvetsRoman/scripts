#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
    echo 'SKIP: shellcheck не встановлений.'
    exit 0
fi

# lib/*.sh є модулями, а не самостійними програмами.
# -P SCRIPTDIR змушує ShellCheck шукати source-файли відносно
# директорії скрипта, що перевіряється, а не поточного $PWD.
shellcheck \
    -x \
    -P SCRIPTDIR \
    "$ROOT/dotfiles-manager.sh"

mapfile -t test_scripts < <(
    find "$ROOT/tests" \
        -maxdepth 1 \
        -type f \
        -name '*.sh' \
        ! -name 'test_shellcheck.sh' \
        -print |
        sort
)

if ((${#test_scripts[@]} > 0)); then
    shellcheck \
        -x \
        -P SCRIPTDIR \
        "${test_scripts[@]}"
fi

echo 'PASS: shellcheck'
