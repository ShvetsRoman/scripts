#!/usr/bin/env bash

diff_path() {
    local path
    local source
    local backup
    local status
    local -a excludes=()
    local -a diff_excludes=()
    local arg

    path="$(resolve_backup_path "${1:-}")" || return
    source="$HOME/$path"
    backup="$DOTFILES_DIR/$path"

    if [[ ! -e "$source" && ! -L "$source" && ! -e "$backup" && ! -L "$backup" ]]; then
        log_warn "Шлях відсутній всюди: $path"
        return 0
    fi
    if [[ ! -e "$source" && ! -L "$source" ]]; then
        log_warn "[DEL] $path - файл є в dotfiles, але відсутній у HOME"
        return 0
    fi
    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
        log_warn "[NEW] $path - файл є в HOME, але відсутній у dotfiles"
        return 0
    fi

    # Перед unified diff показуємо, що саме додано, видалено чи змінено.
    local changes kind relative description shown
    if ! declare -F core_changes >/dev/null 2>&1; then
        # shellcheck source=../../lib/core.sh
        source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/lib/core.sh"
    fi
    changes="$(core_changes "$source" "$backup" "${EXCLUDE_PATTERNS[@]}")" || {
        log_warn "[ERROR] Не вдалося порівняти: $path"
        return 2
    }
    while IFS='|' read -r kind relative; do
        [[ -n "$kind" ]] || continue
        shown="$path"
        if [[ -d "$source" && -d "$backup" ]]; then
            shown="$path/$relative"
        fi
        case "$kind" in
            NEW) description="файл є в HOME, але відсутній у dotfiles" ;;
            DEL) description="файл є в dotfiles, але відсутній у HOME" ;;
            CHANGED) description="вміст файлу змінено" ;;
            *) continue ;;
        esac
        case "$kind" in
            CHANGED) printf '[CHANGED] %s - %s\n' "$shown" "$description" ;;
            NEW) printf '[NEW]     %s - %s\n' "$shown" "$description" ;;
            DEL) printf '[DEL]     %s - %s\n' "$shown" "$description" ;;
        esac
    done <<<"$changes"

    if [[ -L "$source" || -L "$backup" ]]; then
        if paths_are_equal "$source" "$backup"; then
            return 0
        fi
        printf '%s -> %s\n' "$backup" "$(readlink -- "$backup" 2>/dev/null || printf '<not-symlink>')"
        printf '%s -> %s\n' "$source" "$(readlink -- "$source" 2>/dev/null || printf '<not-symlink>')"
        return 0
    fi

    if [[ -d "$source" && -d "$backup" ]]; then
        build_exclude_args excludes
        for arg in "${excludes[@]}"; do
            diff_excludes+=("--exclude=${arg#--exclude=}")
        done

        status=0
        diff -ruN "${diff_excludes[@]}" -- "$backup" "$source" || status=$?
    else
        status=0
        diff -u -- "$backup" "$source" || status=$?
    fi

    if ((status == 0 || status == 1)); then
        return 0
    fi

    return "$status"
}

diff_all() {
    echo
    echo "======================="
    echo "         Diff"
    echo "======================="

    local path

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        echo "===== $path ====="
        if ! diff_path "$path"; then
            log_warn "Не вдалося порівняти: $path"
        fi
    done
}
