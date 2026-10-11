#!/usr/bin/env bash

status_one() {
    local path="$1"
    local home_path="$HOME/$path"
    local backup_path="$DOTFILES_DIR/$path"

    local changes kind relative shown
    if ! path_exists_in_home "$path" && ! path_exists_in_backup "$path"; then
        printf '%b[MISSING] %s — відсутній всюди %b\n' "$RED" "$path" "$NC"
        return 0
    fi
    if ! path_exists_in_home "$path"; then
        printf '%b[DEL]     %s - файл є в dotfiles, але відсутній у HOME%b\n' "$RED" "$path" "$NC"
        return 0
    fi
    if ! path_exists_in_backup "$path"; then
        printf '%b[NEW]     %s - файл є в HOME, але відсутній у dotfiles%b\n' "$BLUE" "$path" "$NC"
        return 0
    fi
    if ! declare -F core_changes >/dev/null 2>&1; then
        # shellcheck source=../../lib/core.sh
        source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/lib/core.sh"
    fi
    if ! changes="$(core_changes "$home_path" "$backup_path" "${EXCLUDE_PATTERNS[@]}")"; then
        printf '%b[ERROR]   %s — помилка порівняння%b\n' "$RED" "$path" "$NC"
        return 2
    fi
    if [[ -z "$changes" ]]; then
        printf '%b[OK]%b      %s\n' "$GREEN" "$NC" "$path"
        return 0
    fi
    while IFS='|' read -r kind relative; do
        [[ -n "$kind" ]] || continue
        shown="$path"
        if [[ -d "$home_path" && -d "$backup_path" ]]; then
            shown="$path/$relative"
        fi
        case "$kind" in
            NEW) printf '%b[NEW]     %s - файл є в HOME, але відсутній у dotfiles%b\n' "$BLUE" "$shown" "$NC" ;;
            DEL) printf '%b[DEL]     %s - файл є в dotfiles, але відсутній у HOME%b\n' "$RED" "$shown" "$NC" ;;
            CHANGED) printf '%b[CHANGED] %s - вміст файлу змінено%b\n' "$YELLOW" "$shown" "$NC" ;;
        esac
    done <<<"$changes"

}

show_status() {
    local path

    echo
    echo "============"
    echo "Smart Status"
    echo "============"

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        status_one "$path"
    done
}
