#!/usr/bin/env bash

# ============================================================
# ГЛОБАЛЬНІ ШЛЯХИ ТА ФАЙЛИ
# ============================================================

if [[ -z "${ROOT_DIR:-}" ]]; then
    ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fi

readonly SCRIPT_DIR="$ROOT_DIR"
readonly CONFIG_FILE="${DOTFILES_MANAGER_CONFIG:-$SCRIPT_DIR/config/dotfiles.conf}"
readonly DOTFILES_DIR="${DOTFILES_MANAGER_BACKUP_DIR:-$SCRIPT_DIR/dotfiles}"
readonly RECOVERY_LIMIT=5
readonly RECOVERY_DIR="${DOTFILES_MANAGER_RECOVERY_DIR:-$SCRIPT_DIR/dotfiles-recovery}"
readonly ARCHIVE_DIR="${DOTFILES_MANAGER_ARCHIVE_DIR:-$SCRIPT_DIR/dotfiles-archive}"
readonly ARCHIVE_PREFIX="dotfiles-backup"


if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" ]]; then
    LOCK_DIR="$XDG_RUNTIME_DIR"
else
    LOCK_DIR="/tmp"
fi
readonly LOCK_DIR

readonly LOCK_FILE="${DOTFILES_MANAGER_LOCK_FILE:-$LOCK_DIR/dotfiles-manager-${UID}.lock}"
