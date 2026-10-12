#!/usr/bin/env bash
# Очищення тільки відомих каталогів Setup Manager, без обходу символьних посилань.
maintenance_usage() {
    du -sh -- "$ROOT_DIR/backups" "$ROOT_DIR/archives" "$ROOT_DIR/logs" "$ROOT_DIR/dotfiles"
    df -h -- "$ROOT_DIR"
}

maintenance_safe_directory() {
    local dir="$1" prefix="$1"
    [[ -d "$dir" && ! -L "$dir" ]] || return 1
    # Перевірка всіх компонентів абсолютного шляху, включно з ROOT_DIR.
    while [[ "$prefix" != / && -n "$prefix" ]]; do
        [[ ! -L "$prefix" ]] || return 1
        prefix="$(dirname -- "$prefix")"
    done
}

maintenance_cleanup() {
    local type="${1:-}" base age="${SETUP_KEEP_DAYS:-30}" item minutes
    local -a candidates=()
    if [[ ! "$age" =~ ^[0-9]+$ ]] || ((10#$age < 1)); then
        log_error 'Некоректний термін зберігання'
        return 2
    fi
    minutes=$((10#$age * 1440))
    case "$type" in
        logs) base="$ROOT_DIR/logs" ;;
        installer) base="$ROOT_DIR/backups/installer" ;;
        dotfiles) base="$ROOT_DIR/backups/dotfiles" ;;
        recovery) base="$ROOT_DIR/backups/recovery" ;;
        *) log_error 'Тип: logs|installer|dotfiles|recovery'; return 2 ;;
    esac
    if [[ ! -e "$base" && ! -L "$base" ]]; then
        log_info "Каталог відсутній, очищувати нічого: $base"
        return 0
    fi
    if ! maintenance_safe_directory "$base"; then
        log_error "Небезпечний каталог для очищення: $base"
        return 1
    fi
    if [[ "$type" == logs ]]; then
        mapfile -d '' -t candidates < <(find -P "$base" -mindepth 1 -maxdepth 1 -type f -name '*.log' -mmin "+$minutes" -print0)
    else
        mapfile -d '' -t candidates < <(find -P "$base" -mindepth 1 -maxdepth 1 -type d -mmin "+$minutes" -print0)
    fi
    if ((${#candidates[@]} == 0)); then
        log_info "Немає старих об’єктів"
        return 0
    fi
    printf '%s\n' "${candidates[@]}"
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "[DRY-RUN] Заплановано видалення: ${#candidates[@]}; нічого не змінено"
        return 0
    fi
    setup_confirm "Видалити ${#candidates[@]} об’єкт(ів)?" || return 0
    for item in "${candidates[@]}"; do
        if [[ "$item" != "$base/"* || "$item" == "$base" || -L "$item" ]] || ! maintenance_safe_directory "$base"; then
            log_error "Небезпечний шлях, видалення зупинено: $item"
            return 1
        fi
        # Не виходимо за межі обраного каталогу; кандидати знайдені з maxdepth 1.
        if [[ "$(dirname -- "$item")" != "$base" ]]; then
            log_error "Шлях не є безпосереднім дочірнім об’єктом: $item"
            return 1
        fi
        rm -rf -- "$item" || return 1
    done
    log_ok 'Очищення завершено'
}

maintenance_main() {
    local choice="${1:-menu}"
    if [[ "$choice" == --dry-run ]]; then
        export DRY_RUN=true
        shift
        choice="${1:-menu}"
    fi
    case "$choice" in
        disk) maintenance_usage ;;
        cleanup) maintenance_cleanup "${2:-}" ;;
        menu)
            while :; do
                menu_header 'MAINTENANCE'
                menu_item 1 'Archive Create' 'Створити архів dotfiles'
                menu_item 2 'Archive List' 'Переглянути архіви'
                menu_item 3 'Archive Restore' 'Відновити архів'
                menu_item 4 'Recovery List' 'Переглянути копії'
                menu_item 5 'Recovery Restore' 'Відновити копію'
                menu_item 6 'Recovery Delete' 'Видалити копію'
                menu_item 7 'Logs Cleanup' 'Очистити старі журнали'
                menu_item 8 'Installer Cleanup' 'Очистити резервні копії Installer'
                menu_item 9 'Recovery Cleanup' 'Очистити старі точки відновлення'
                menu_item 10 'Disk Usage' 'Використання диска'
                menu_item 11 'Dotfiles Cleanup' 'Очистити резервні копії Dotfiles'
                menu_footer
                menu_read
                case "$MENU_CHOICE" in
                    1) archive_create ;; 2) archive_list ;;
                    3) read -r -p 'Назва архіву: ' choice; archive_restore "$choice" ;;
                    4) recovery_list ;;
                    5) read -r -p 'ID recovery: ' choice; recovery_restore "$choice" ;;
                    6) read -r -p 'ID recovery: ' choice; recovery_delete "$choice" ;;
                    7) maintenance_cleanup logs ;; 8) maintenance_cleanup installer ;; 9) maintenance_cleanup recovery ;;
                    10) maintenance_usage ;; 11) maintenance_cleanup dotfiles ;;
                    0) return 0 ;; 00) menu_exit ;; *) log_warn 'Невідома дія' ;;
                esac
            done ;;
        *) log_error 'maintenance [--dry-run] [menu|disk|cleanup logs|installer|dotfiles|recovery]'; return 2 ;;
    esac
}
