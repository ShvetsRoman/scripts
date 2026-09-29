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
        log_warning "Шлях відсутній всюди: $path"
        return 0
    fi
    if [[ ! -e "$source" && ! -L "$source" ]]; then
        log_warning "[MISSING] HOME: $path"
        return 0
    fi
    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
        log_warning "[NEW] HOME: $path"
        return 0
    fi

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
    local path

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        echo
        echo "===== $path ====="
        if ! diff_path "$path"; then
            log_warning "Не вдалося порівняти: $path"
        fi
    done
}
