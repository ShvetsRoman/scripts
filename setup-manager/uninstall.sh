#!/usr/bin/env bash
# uninstall.sh — видаляє symlink setup.
set -Eeuo pipefail

TARGET_DIR="${1:-$HOME/.local/bin}"

if [[ -L "$TARGET_DIR/setup" ]]; then
    rm -- "$TARGET_DIR/setup"
    printf '[ok] Видалено: %s/setup\n' "$TARGET_DIR"
else
    printf '[skip] Не знайдено: %s/setup\n' "$TARGET_DIR"
fi
