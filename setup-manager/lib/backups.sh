#!/usr/bin/env bash
# Перевірка цілісності створених fs_protect() захисних копій.
backups_group() {
    # sources.conf дозволяє власні групи, тож не обмежуємося dotfiles/recovery.
    [[ "${1:-}" =~ ^[a-zA-Z0-9_-]+$ ]] || {
        log error 'Некоректна група'; return 2;
    }
    return 0
}

backups_list() {
    local group="${1:-}" dir
    backups_group "$group" || return 2
    dir="$ROOT_DIR/backups/$group"
    path_ok_abs "$dir" || return 2
    [[ -d "$dir" ]] || { log info "Немає backup: $group"; return 0; }
    find -P "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r
}

backups_verify() {
    local group="${1:-}" id="${2:-}" snap rc=0
    backups_group "$group" || return 2
    recovery_valid_id "$id" || { log error 'Некоректний ID'; return 2; }
    snap="$ROOT_DIR/backups/$group/$id"
    [[ -d "$snap" && ! -L "$snap" ]] && path_ok_abs "$snap" || {
        log error "Немає безпечного backup: $group/$id"; return 2;
    }
    if [[ ! -f "$snap/manifest.tsv" || -L "$snap/manifest.tsv" ]]; then
        log warn "Legacy backup без manifest: $group/$id (цілісність не підтверджена)"
        return 3
    fi
    python3 "$ROOT_DIR/tools/recovery_safe.py" verify "$snap" || rc=$?
    return "$rc"
}

backups_main() {
    case "${1:-}" in
        list)   backups_list "${2:-}" ;;
        verify) backups_verify "${2:-}" "${3:-}" ;;
        *) log error 'backups list GROUP | backups verify GROUP ID'; return 2 ;;
    esac
}
