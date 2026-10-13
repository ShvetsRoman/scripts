#!/usr/bin/env bash
# Recovery.

# recovery_dir — каталог recovery-знімків.
recovery_dir() { printf '%s/backups/recovery' "$ROOT_DIR"; }

# recovery_valid_id — формат ID: YYYY-MM-DD_HH-MM-SS_PID.
recovery_valid_id() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9]+$ ]]
}

# recovery_list — список ID (новіші першими).
recovery_list() {
    local dir; dir="$(recovery_dir)"
    [[ -d "$dir" ]] || { log info 'Recovery-копій немає.'; return 0; }
    local -a snaps=()
    mapfile -t snaps < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
    ((${#snaps[@]})) || { log info 'Recovery-копій немає.'; return 0; }
    printf '%s\n' "${snaps[@]}"
}

# recovery_restore — відновлює вміст знімка у $HOME.
# Кожен файл повертається через apply (з новим захистом).
recovery_restore() {
    local id="$1"
    recovery_valid_id "$id" || { log error "ID: $id"; return 2; }
    local src; src="$(recovery_dir)/$id"
    [[ -d "$src" && ! -L "$src" ]] || { log error "Немає: $id"; return 1; }
    [[ "${DRY_RUN:-false}" != true ]] && { setup_confirm "Відновити $id?" || return 0; }

    local path st=0
    while IFS= read -r -d '' path; do
        path="${path#"$src"/}"
        path_ok_rel "$path" || continue
        apply "$src/$path" "$HOME/$path" recovery "$path" || st=$?
        (( st == 2 )) && return 1
    done < <(find "$src" -mindepth 1 \( -type f -o -type l \) -print0 | sort -z)
    log ok "Recovery: $id"
}

# recovery_delete — видаляє знімок.
recovery_delete() {
    local id="$1"
    recovery_valid_id "$id" || return 2
    local dir; dir="$(recovery_dir)/$id"
    [[ -d "$dir" && ! -L "$dir" ]] || return 1
    setup_confirm "Видалити $id?" || return 0
    [[ "${DRY_RUN:-false}" == true ]] && { log info "[DRY-RUN] rm $dir"; return 0; }
    rm -rf -- "$dir"
}

# recovery_main — диспетчер підкоманд recovery.
recovery_main() {
    case "${1:-list}" in
        list) recovery_list ;;
        restore) [[ -n "${2:-}" ]] || { log error 'Потрібен ID'; return 2; }; recovery_restore "$2" ;;
        delete)  [[ -n "${2:-}" ]] || { log error 'Потрібен ID'; return 2; }; recovery_delete "$2" ;;
        *) log error 'recovery list|restore ID|delete ID'; return 2 ;;
    esac
}
