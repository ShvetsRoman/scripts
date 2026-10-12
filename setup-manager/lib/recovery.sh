#!/usr/bin/env bash
# Recovery має власний список знімків; усі шляхи обмежено коренем проєкту.
recovery_root() { printf '%s/backups/recovery' "$ROOT_DIR"; }
recovery_list() {
    local dir
    dir="$(recovery_root)"
    if [[ ! -d "$dir" ]]; then
        log_info 'Recovery-копій немає.'
        return 0
    fi
    local -a snapshots=()
    mapfile -t snapshots < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
    if ((${#snapshots[@]} == 0)); then
        log_info 'Recovery-копій немає.'
        return 0
    fi
    printf '%s\n' "${snapshots[@]}"
}
recovery_valid_id() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9]+$ ]]; }
recovery_restore() {
    local id="$1" source path target
    recovery_valid_id "$id" || { log_error 'Некоректний ID recovery'; return 2; }
    source="$(recovery_root)/$id"
    [[ -d "$source" && ! -L "$source" ]] || { log_error 'Recovery не знайдено'; return 1; }
    if [[ "${DRY_RUN:-false}" != true ]]; then
        setup_confirm "Відновити recovery $id до HOME?" || return 0
    fi
    while IFS= read -r -d '' path; do
        path="${path#"$source"/}"
        core_safe_relative "$path" || return 1
        target="$HOME/$path"
        if [[ -e "$target" || -L "$target" ]]; then
            core_protect "$target" recovery "$path" || return 1
        fi
        core_copy "$source/$path" "$target" || return 1
    done < <(find "$source" -mindepth 1 \( -type f -o -type l \) -print0)
    log_ok "Recovery відновлено: $id"
}
recovery_delete() {
    local id="$1" dir
    recovery_valid_id "$id" || return 2
    dir="$(recovery_root)/$id"
    [[ -d "$dir" && ! -L "$dir" ]] || return 1
    setup_confirm "Видалити recovery $id?" || return 0
    if [[ "${DRY_RUN:-false}" == true ]]; then log_info "[DRY-RUN] Видалення: $dir"; return 0; fi
    rm -rf -- "$dir"
}
recovery_main() {
    local action="${1:-list}" id="${2:-}"
    case "$action" in
        list) recovery_list ;;
        restore) [[ -n "$id" ]] || { log_error 'Вкажи recovery ID'; return 2; }; recovery_restore "$id" ;;
        delete) [[ -n "$id" ]] || { log_error 'Вкажи recovery ID'; return 2; }; recovery_delete "$id" ;;
        *) log_error 'recovery list|restore ID|delete ID'; return 2 ;;
    esac
}
