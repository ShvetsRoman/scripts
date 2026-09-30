#!/usr/bin/env bash

validate_path() {
    local path="$1"

    if ! path_is_safe "$path"; then
        log_error "Небезпечний або некоректний шлях: $path"
        return 1
    fi
}

validate_backup_paths() {
    local path

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        if ! validate_path "$path"; then
            return 1
        fi
    done

    echo
    log_success "Конфігурація шляхів перевірена."
    echo
}

is_managed_path() {
    local path="$1"
    local managed

    for managed in "${BACKUP_FILES[@]}" "${BACKUP_DIRS[@]}"; do
        if [[ "$path" == "$managed" || "$path" == "$managed"/* ]]; then
            return 0
        fi
    done

    return 1
}

is_managed_or_parent() {
    local path="$1"
    local managed

    for managed in "${BACKUP_FILES[@]}" "${BACKUP_DIRS[@]}"; do
        if [[ "$path" == "$managed" || "$path" == "$managed"/* || "$managed" == "$path"/* ]]; then
            return 0
        fi
    done

    return 1
}

is_managed_root() {
    local path="$1"
    local managed

    for managed in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        if [[ "$path" == "$managed" ]]; then
            return 0
        fi
    done

    return 1
}

resolve_backup_path() {
    local path="${1:-}"

    if ! validate_path "$path"; then
        return 1
    fi
    if ! is_managed_path "$path"; then
        log_error "Шлях не входить до конфігурації: $path"
        return 1
    fi

    printf '%s\n' "$path"
}
