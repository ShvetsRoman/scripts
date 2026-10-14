#!/usr/bin/env bash
# Обслуговування.

# _cleanup_dirs — мапа type → каталог.
_cleanup_dirs() {
    case "$1" in
        logs)      printf '%s/logs' "$ROOT_DIR" ;;
        installer) printf '%s/backups/installer' "$ROOT_DIR" ;;
        dotfiles)  printf '%s/backups/dotfiles' "$ROOT_DIR" ;;
        recovery)  printf '%s/backups/recovery' "$ROOT_DIR" ;;
        *) return 1 ;;
    esac
}

# safe_dir — чи безпечний каталог для очищення:
# існує, не symlink, і всі його батьки не symlink.
safe_dir() {
    local p="$1"
    [[ -d "$p" && ! -L "$p" ]] || return 1
    while [[ "$p" != / && -n "$p" ]]; do
        [[ ! -L "$p" ]] || return 1
        p="$(dirname -- "$p")"
    done
}

# maintenance_usage — du/df для ключових каталогів.
maintenance_usage() {
    ui_clear
    header '▤  disk usage'
    du -sh -- "$ROOT_DIR/backups" "$ROOT_DIR/archives" "$ROOT_DIR/logs" "$ROOT_DIR/dotfiles" 2>/dev/null || true
    df -h -- "$ROOT_DIR"
}

# maintenance_cleanup — видаляє об’єкти, старші за SETUP_KEEP_DAYS.
# Аргумент: type (logs|installer|dotfiles|recovery).
# DRY_RUN=true → лише показує.
# Захищається від symlink і виходу за межі base.
maintenance_cleanup() {
    ui_clear
    header "✕  cleanup: ${1:-}"
    local type="${1:-}"
    local age="${SETUP_KEEP_DAYS:-30}"
    [[ "$age" =~ ^[0-9]+$ ]] && (( age >= 1 && age <= 3650 )) \
        || { log error "SETUP_KEEP_DAYS: $age"; return 2; }
    local base; base="$(_cleanup_dirs "$type")" || { log error "Тип: logs|installer|dotfiles|recovery"; return 2; }
    [[ -e "$base" || -L "$base" ]] || { log info "Немає: $base"; return 0; }
    safe_dir "$base" || { log error "Небезпечний: $base"; return 1; }

    local minutes=$((age * 1440))
    local -a found=()
    if [[ "$type" == logs ]]; then
        mapfile -d '' -t found < <(find -P "$base" -mindepth 1 -maxdepth 1 -type f -name '*.log' -mmin "+$minutes" -print0)
    else
        mapfile -d '' -t found < <(find -P "$base" -mindepth 1 -maxdepth 1 -type d -mmin "+$minutes" -print0)
    fi
    ((${#found[@]})) || { log info "Немає старих об’єктів"; return 0; }
    printf '%s\n' "${found[@]}"
    [[ "${DRY_RUN:-false}" == true ]] && { log info "[DRY-RUN] ${#found[@]}"; return 0; }
    setup_confirm "Видалити ${#found[@]}?" || return 0
    local item
    for item in "${found[@]}"; do
        [[ "$item" == "$base/"* && "$item" != "$base" && ! -L "$item" ]] || { log error "Небезпечно: $item"; return 1; }
        [[ "$(dirname -- "$item")" == "$base" ]] || { log error "Не дочірній: $item"; return 1; }
        rm -rf -- "$item" || return 1
    done
    log ok 'Очищення завершено'
}

# Залишити KEEP найновіших захисних копій. Лише директорії верхнього рівня.
# Не викликається автоматично: оператор сам обирає політику зберігання.
maintenance_rotate() {
    local type="${1:-}" keep="${2:-}" base idx=0 item
    [[ "$type" == installer || "$type" == dotfiles || "$type" == recovery ]] || {
        log error 'rotate: installer|dotfiles|recovery'; return 2;
    }
    [[ "$keep" =~ ^[0-9]{1,4}$ ]] || { log error 'KEEP має бути 1..9999'; return 2; }
    keep=$((10#$keep))
    (( keep >= 1 )) || { log error 'KEEP має бути >= 1'; return 2; }
    base="$(_cleanup_dirs "$type")" || return 2
    [[ -d "$base" ]] || { log info 'Немає backup'; return 0; }
    safe_dir "$base" || { log error 'Небезпечний каталог'; return 2; }
    local -a entries=() obsolete=()
    mapfile -t entries < <(find -P "$base" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort -r)
    for item in "${entries[@]}"; do
        [[ "$item" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9]+(_[0-9]+)?$ ]] || {
            log warn "Пропущено невідомий каталог: $item"; continue;
        }
        ((idx+=1))
        if (( idx > keep )); then obsolete+=("$item"); fi
    done
    ((${#obsolete[@]})) || { log info "Rotate $type: очищати нічого"; return 0; }
    printf 'Rotate %s: залишити %d, видалити %d:\n' "$type" "$keep" "${#obsolete[@]}"
    printf '  %s\n' "${obsolete[@]}"
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info '[DRY-RUN] Жодних видалень'; return 0
    fi
    setup_confirm "Видалити ${#obsolete[@]} старих backup?" || return 0
    for item in "${obsolete[@]}"; do
        path_ok_abs "$base/$item" && [[ -d "$base/$item" && ! -L "$base/$item" ]] || return 2
        rm -rf -- "${base:?}/${item:?}" || return 1
    done
    log ok "Rotate $type: видалено ${#obsolete[@]}"
}

# maintenance_main — диспетчер maintenance.
maintenance_main() {
    [[ "${1:-}" == --dry-run ]] && { export DRY_RUN=true; shift; }
    case "${1:-menu}" in
        disk)    maintenance_usage ;;
        cleanup) maintenance_cleanup "${2:-}" ;;
        rotate) maintenance_rotate "${2:-}" "${3:-}" ;;
        menu)    menu_run 'MAINTENANCE' "${MAINTENANCE_MENU[@]}" ;;
        *) log error 'maintenance [--dry-run] [menu|disk|cleanup TYPE]'; return 2 ;;
    esac
}
