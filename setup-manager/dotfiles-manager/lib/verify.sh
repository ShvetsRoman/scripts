#!/usr/bin/env bash

# ============================================================
# VERIFY
# ============================================================

verify_path() {
    local path
    local home_path
    local backup_path

    path="$(resolve_backup_path "${1:-}")" || return 1

    home_path="$HOME/$path"
    backup_path="$DOTFILES_DIR/$path"

    if ! path_exists_in_home "$path"; then
        printf '%b[FAILED]%b %s - файл є в dotfiles, але відсутній у HOME\n' \
            "$RED" "$NC" "$path" >&2
        return 1
    fi

    if ! path_exists_in_backup "$path"; then
        printf '%b[FAILED]%b %s - файл є в HOME, але відсутній у dotfiles\n' \
            "$RED" "$NC" "$path" >&2
        return 1
    fi

    local compare_rc=0
    paths_are_equal "$home_path" "$backup_path" || compare_rc=$?
    if ((compare_rc != 0)); then
        printf '%b[FAILED]%b %s\n' \
            "$RED" "$NC" "$path" >&2
        return 1
    fi

    log_ok "$path"
    return 0
}

verify_all() {
    local path
    local failed=0
    echo
    echo "======="
    echo "Verify"
    echo "======="

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        if ! verify_path "$path"; then
            failed=$((failed + 1))
        fi
    done

    echo

    if ((failed > 0)); then
        log_error "Verify завершено з помилками: $failed"
        return 1
    fi

    log_ok "Verify успішний для всіх шляхів."
    return 0
}
