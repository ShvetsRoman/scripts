#!/usr/bin/env bash
# Два напрямки: backup HOME -> репозиторій, restore репозиторій -> HOME.
dotfiles_load() {
    # shellcheck source=../config/dotfiles.conf
    source "$ROOT_DIR/config/dotfiles.conf"
    DOTFILES_ITEMS=("${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}")
}
dotfiles_source() { printf '%s/%s' "$HOME" "$1"; }
dotfiles_repo() { printf '%s/dotfiles/%s' "$ROOT_DIR" "$1"; }
dotfiles_status() {
    local path src dest rc status=0
    dotfiles_load
    print_header 'Smart Status — HOME ↔ dotfiles'
    for path in "${DOTFILES_ITEMS[@]}"; do
        if ! core_safe_relative "$path"; then
            log_error "Некоректний шлях: $path"
            status=1
            continue
        fi
        src="$(dotfiles_source "$path")"
        dest="$(dotfiles_repo "$path")"
        if [[ ! -e "$src" && ! -L "$src" ]]; then
            if [[ ! -e "$dest" && ! -L "$dest" ]]; then
                log_warn "[MISSING] $path — відсутній у HOME та dotfiles"
            else
                log_state DEL "$path — є в dotfiles, але відсутній у HOME"
            fi
            status=1
        elif [[ ! -e "$dest" && ! -L "$dest" ]]; then
            log_state NEW "$path — є в HOME, але відсутній у dotfiles"
            status=1
        elif core_compare "$src" "$dest"; then
            log_state OK "$path"
        else
            rc=$?
            if ((rc == 2)); then
                log_error "$path — помилка порівняння"
            else
                log_state CHANGED "$path — вміст відрізняється"
            fi
            status=1
        fi
    done
    return "$status"
}

# Backup/Restore використовують спільне файлове ядро, але різні групи захисту.
dotfiles_sync() {
    local mode="$1" path from to result count=0 skipped=0
    shift
    dotfiles_load
    local -a items=("$@")
    if ((${#items[@]} == 0)); then
        items=("${DOTFILES_ITEMS[@]}")
    fi
    for path in "${items[@]}"; do
        if ! core_safe_relative "$path"; then
            log_error "Небезпечний шлях: $path"
            return 2
        fi
        if [[ "$mode" == backup ]]; then
            from="$(dotfiles_source "$path")"
            to="$(dotfiles_repo "$path")"
        else
            from="$(dotfiles_repo "$path")"
            to="$(dotfiles_source "$path")"
        fi
        if [[ ! -e "$from" && ! -L "$from" ]]; then
            log_warn "Пропущено, джерело відсутнє: $path"
            ((skipped += 1))
            continue
        fi
        if core_compare "$from" "$to"; then
            log_info "$path — вже синхронізовано"
            ((skipped += 1))
            continue
        else
            result=$?
            if ((result == 2)); then
                return 1
            fi
        fi
        # Додаткові файли у призначенні не видаляються без окремої політики.
        if core_compare_copy "$from" "$to"; then
            log_warn "$path — у призначенні є додаткові файли; залишено без змін"
            ((skipped += 1))
            continue
        else
            result=$?
            if ((result == 2)); then
                return 1
            fi
        fi
        if [[ "$mode" == backup && "${SETUP_BACKUP_ENABLED:-true}" == true ]]; then
            SYNC_DELETE=false core_protect "$to" dotfiles "$path" || return 1
        elif [[ "$mode" == restore && "${SETUP_RECOVERY_ENABLED:-true}" == true ]]; then
            SYNC_DELETE=false core_protect "$to" recovery "$path" || return 1
        fi
        log_step "$mode: $path"
        log_info "Звідки: $from"
        log_info "Куди: $to"
        SYNC_DELETE=false core_copy "$from" "$to" || return 1
        ((count += 1))
        if [[ "${DRY_RUN:-false}" != true ]]; then
            if ! core_compare_copy "$from" "$to"; then
                log_error "$path — перевірка після копіювання не пройдена"
                return 1
            fi
            if ! core_compare "$from" "$to"; then
                log_warn "$path — копіювання завершено; зайві файли у призначенні збережено"
            fi
        fi
    done
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "[DRY-RUN] $mode: заплановано $count; пропущено $skipped"
    else
        log_ok "$mode завершено; скопійовано: $count; пропущено: $skipped"
    fi
}

dotfiles_diff() {
    local path left right rc output differences=0
    dotfiles_load
    local -a items=("$@")
    if ((${#items[@]} == 0)); then
        items=("${DOTFILES_ITEMS[@]}")
    fi
    for path in "${items[@]}"; do
        if ! core_safe_relative "$path"; then
            log_error "Небезпечний шлях: $path"
            return 2
        fi
        left="$(dotfiles_source "$path")"
        right="$(dotfiles_repo "$path")"
        if [[ ! -e "$left" && ! -L "$left" && ! -e "$right" && ! -L "$right" ]]; then
            log_warn "[MISSING] $path — відсутній у HOME та dotfiles"
            differences=1
            continue
        fi
        if [[ ! -e "$left" && ! -L "$left" ]]; then
            log_state DEL "$path — відсутній у HOME" || return 1
            differences=1
            continue
        fi
        if [[ ! -e "$right" && ! -L "$right" ]]; then
            log_state NEW "$path — відсутній у dotfiles" || return 1
            differences=1
            continue
        fi
        if core_compare "$left" "$right"; then
            continue
        else
            rc=$?
            if ((rc == 2)); then return 2; fi
        fi
        differences=1
        if output="$(diff -ruN -- "$right" "$left" 2>&1)"; then
            continue
        else
            rc=$?
            if ((rc > 1)); then
                log_error "Помилка diff: $path: $output"
                return 2
            fi
        fi
        print_header "Diff: $path"
        printf '%s\n' "$output"
    done
    return "$differences"
}
dotfiles_main() {
    local cmd="${1:-}"; if (($#)); then shift; fi
    if [[ "$cmd" == --dry-run ]]; then export DRY_RUN=true; cmd="${1:-}"; if (($#)); then shift; fi; fi
    case "$cmd" in
        ''|menu) dotfiles_menu ;;
        -h|--help|help) dotfiles_help ;;
        backup|restore)
            if [[ "${1:-}" == changed ]]; then shift; fi
            dotfiles_sync "$cmd" "$@" ;;
        status|verify) dotfiles_status ;;
        diff) dotfiles_diff "$@" ;;
        archive) archive_main "$@" ;;
        recovery) recovery_main "$@" ;;
        *) log_error "Невідома команда Dotfiles: $cmd"; return 2 ;;
    esac
}
dotfiles_help() {
    print_header 'Допомога: Dotfiles'
    printf '%s\n' '[NEW] — є в HOME, але відсутній у dotfiles' '[DEL] — є в dotfiles, але відсутній у HOME' './setup.sh dotfiles backup' './setup.sh dotfiles backup .config/nvim' './setup.sh dotfiles restore .zshrc' './setup.sh dotfiles status' './setup.sh dotfiles verify' './setup.sh dotfiles diff .config/nvim' './setup.sh dotfiles archive create' './setup.sh dotfiles archive list' './setup.sh dotfiles archive restore NAME' './setup.sh dotfiles recovery list'
}
