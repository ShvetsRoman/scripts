#!/usr/bin/env bash

status_one() {
    local path="$1"
    local home_path="$HOME/$path"
    local backup_path="$DOTFILES_DIR/$path"

    if path_exists_in_home "$path" && ! path_exists_in_backup "$path"; then
        printf '%b[NEW]     %s %b\n' "$BLUE" "$path" "$NC"
        return 0
    fi

    if ! path_exists_in_home "$path" && path_exists_in_backup "$path"; then
        printf '%b[MISSING] %s — відсутній у HOME %b\n' "$RED" "$path" "$NC"
        return 0
    fi

    if ! path_exists_in_home "$path" && ! path_exists_in_backup "$path"; then
        printf '%b[MISSING] %s — відсутній всюди %b\n' "$RED" "$path" "$NC"

        return 0
    fi

    if paths_differ "$home_path" "$backup_path"; then
        printf '%b[CHANGED] %s %b\n' "$YELLOW" "$path" "$NC"
    else
        printf '%b[OK]%b      %s\n' "$GREEN" "$NC" "$path"
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
