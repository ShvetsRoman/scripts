#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../config/dotfiles.conf
source "$ROOT/config/dotfiles.conf"

if ((${#BACKUP_DIRS[@]} == 0)); then
    echo "FAIL: BACKUP_DIRS порожній."
    exit 1
fi

if ((${#BACKUP_FILES[@]} == 0)); then
    echo "FAIL: BACKUP_FILES порожній."
    exit 1
fi

if ((RECOVERY_LIMIT <= 0)); then
    echo "FAIL: RECOVERY_LIMIT має бути більше 0."
    exit 1
fi

if [[ -z "$ARCHIVE_PREFIX" ]]; then
    echo "FAIL: ARCHIVE_PREFIX порожній."
    exit 1
fi

echo "PASS: config"
