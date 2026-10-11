#!/usr/bin/env bash

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Файл конфігурації не знайдено: $CONFIG_FILE"
        exit 1
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    : "${RECOVERY_LIMIT:=10}"
    : "${ARCHIVE_PREFIX:=dotfiles-backup}"

    if ! declare -p BACKUP_DIRS >/dev/null 2>&1; then
        BACKUP_DIRS=()
    fi
    if ! declare -p BACKUP_FILES >/dev/null 2>&1; then
        BACKUP_FILES=()
    fi
    if ! declare -p EXCLUDE_PATTERNS >/dev/null 2>&1; then
        EXCLUDE_PATTERNS=()
    fi

    if [[ "$(declare -p BACKUP_DIRS 2>/dev/null)" != "declare -a "* ]]; then
        log_error "BACKUP_DIRS має бути indexed array."
        exit 1
    fi
    if [[ "$(declare -p BACKUP_FILES 2>/dev/null)" != "declare -a "* ]]; then
        log_error "BACKUP_FILES має бути indexed array."
        exit 1
    fi
    if [[ "$(declare -p EXCLUDE_PATTERNS 2>/dev/null)" != "declare -a "* ]]; then
        log_error "EXCLUDE_PATTERNS має бути indexed array."
        exit 1
    fi
    if [[ ! "$RECOVERY_LIMIT" =~ ^[0-9]+$ ]]; then
        log_error "RECOVERY_LIMIT має бути невід'ємним цілим числом."
        exit 1
    fi
}

show_config() {
    printf 'Config: %s\n' "$CONFIG_FILE"
    printf 'Backup: %s\n' "$DOTFILES_DIR"
    printf 'Recovery: %s\n' "$RECOVERY_DIR"
    printf 'Archive: %s\n\n' "$ARCHIVE_DIR"
    printf 'Recovery limit: %s\n' "$RECOVERY_LIMIT"
    printf '\nDirectories:\n'
    printf '  %s\n' "${BACKUP_DIRS[@]}"
    printf '\nFiles:\n'
    printf '  %s\n' "${BACKUP_FILES[@]}"
    printf '\nExclude:\n'
    printf '  %s\n' "${EXCLUDE_PATTERNS[@]}"
}
