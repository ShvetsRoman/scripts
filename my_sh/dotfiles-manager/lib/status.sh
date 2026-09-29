#!/usr/bin/env bash

status_one() {
    local path="$1"
    local home_path="$HOME/$path"
    local backup_path="$DOTFILES_DIR/$path"

    if path_exists_in_home "$path" && ! path_exists_in_backup "$path"; then
        printf '[NEW]     %s\n' "$path"
        return 0
    fi

    if ! path_exists_in_home "$path" && path_exists_in_backup "$path"; then
        printf '[MISSING] %s — відсутній у HOME\n' "$path"
        return 0
    fi

    if ! path_exists_in_home "$path" && ! path_exists_in_backup "$path"; then
        printf '[MISSING] %s — відсутній всюди\n' "$path"
        return 0
    fi

    if paths_differ "$home_path" "$backup_path"; then
        printf '[CHANGED] %s\n' "$path"
    else
        printf '[OK]      %s\n' "$path"
    fi
}

show_status() {
    local path

    echo "Smart Status"
    echo "============"

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        status_one "$path"
    done
}
