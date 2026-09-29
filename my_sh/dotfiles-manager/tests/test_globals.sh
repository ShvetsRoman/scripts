#!/usr/bin/env bash

set -Eeuo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export DOTFILES_MANAGER_BACKUP_DIR="$TMP/backup"
export DOTFILES_MANAGER_RECOVERY_DIR="$TMP/recovery"
export DOTFILES_MANAGER_ARCHIVE_DIR="$TMP/archive"
export DOTFILES_MANAGER_CONFIG="$TMP/dotfiles.conf"

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=test_helper.sh
source "$TESTS_DIR/test_helper.sh"

if [[ "$DOTFILES_DIR" != "$TMP/backup" ]]; then
    exit 1
fi
if [[ "$RECOVERY_DIR" != "$TMP/recovery" ]]; then
    exit 1
fi
if [[ "$ARCHIVE_DIR" != "$TMP/archive" ]]; then
    exit 1
fi
if [[ "$CONFIG_FILE" != "$TMP/dotfiles.conf" ]]; then
    exit 1
fi
if [[ -z "$LOCK_FILE" ]]; then
    exit 1
fi

printf 'PASS: globals\n'
