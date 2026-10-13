#!/usr/bin/env bash
# install.sh — ставить symlink setup → setup.sh у PATH.
# Аргумент: каталог призначення (за замовчуванням ~/.local/bin).
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$HOME/.local/bin}"

mkdir -p -- "$TARGET_DIR"
ln -sf -- "$ROOT_DIR/setup.sh" "$TARGET_DIR/setup"

printf '[ok] %s/setup → %s/setup.sh\n' "$TARGET_DIR" "$ROOT_DIR"
case ":$PATH:" in
    *":$TARGET_DIR:"*) ;;
    *) printf '[warn] Додайте %s у PATH\n' "$TARGET_DIR" ;;
esac
