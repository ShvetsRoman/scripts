#!/usr/bin/env bash
# Пакети перевіряються перед установленням; збій мережі не маскуємо під відсутність.
packages_install_list() {
    local type="$1" pkg available=() existing=() missing=()
    shift
    local -a requested=("$@")
    if (( ${#requested[@]} == 0 )); then log_info "Пакетів $type немає."; return 0; fi
    for pkg in "${requested[@]}"; do
        if pacman -Qq -- "$pkg" >/dev/null 2>&1; then
            log_info "$pkg вже встановлено."
            existing+=("$pkg")
            continue
        fi
        if [[ "$type" == pacman ]]; then
            if pacman -Si -- "$pkg" >/dev/null 2>&1; then available+=("$pkg"); else missing+=("$pkg"); fi
        else
            if ! command -v paru >/dev/null; then log_error "Для AUR потрібен paru"; return 1; fi
            if paru -Si --aur -- "$pkg" >/dev/null 2>&1; then available+=("$pkg"); else missing+=("$pkg"); fi
        fi
    done
    for pkg in "${missing[@]}"; do log_warn "Пакет $pkg не знайдено ($type) або репозиторій недоступний; пропущено."; done
    if (( ${#available[@]} )); then
        log_step "Встановлення $type: ${available[*]}"
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log_info "[DRY-RUN] $type: ${available[*]}"
        elif [[ "$type" == pacman ]]; then
            sudo pacman -S --needed -- "${available[@]}" || return 1
        else
            paru -S --needed -- "${available[@]}" || return 1
        fi
    fi
}
packages_run_module() (
    local id="$1" item name kind url command_name
    registry_valid "$id" || { log_error "Невідомий модуль: $id"; return 1; }
    # Ім’я модуля перевірено функцією registry_valid.
    # shellcheck disable=SC1090
    source "$ROOT_DIR/modules/$id.sh"
    print_header "Встановлення модуля: $MODULE_ID — $MODULE_TITLE"
    if [[ "${CONFIGS_ONLY:-false}" != true ]]; then
        packages_install_list pacman "${PACMAN_PACKAGES[@]}" || return 1
        packages_install_list aur "${AUR_PACKAGES[@]}" || return 1
    fi
    if [[ "${CONFIGS_ONLY:-false}" != true ]]; then
    for item in "${GITHUB_ITEMS[@]}"; do
        IFS='|' read -r name kind url command_name _ <<< "$item"
        if [[ "$kind" != script ]]; then
            log_warn "Невідомий тип зовнішньої програми $name: $kind; пропускаю."
        elif command -v "$command_name" >/dev/null 2>&1; then
            log_info "$name вже встановлено."
        else
            log_warn "Зовнішня програма $name ($url): автоматичне виконання стороннього скрипта вимкнено."
        fi
    done
    fi
    if [[ "${NO_CONFIGS:-false}" != true ]]; then
        configs_install "${CONFIG_ITEMS[@]}" || return 1
    fi
    if [[ "${CONFIGS_ONLY:-false}" != true && "${DRY_RUN:-false}" != true ]]; then
        hooks_run "$MODULE_ID" || return 1
    elif [[ "${CONFIGS_ONLY:-false}" != true && "${DRY_RUN:-false}" == true ]]; then
        if [[ "$MODULE_ID" == docker || "$MODULE_ID" == shell ]]; then
            log_info "[DRY-RUN] Post-install: $MODULE_ID"
        fi
    fi
    log_ok "Завершено встановлення модуля: $MODULE_ID — $MODULE_TITLE"
)
packages_main() {
    local choice
    case "${1:-}" in
        --help|-h|help) packages_help; return 0 ;;
        --list|list) registry_show; return 0 ;;
        '') packages_menu; return $? ;;
    esac
    local -a ids=()
    while (($#)); do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            --no-backup)
                # Використовується у configs_install через source.
                # shellcheck disable=SC2034
                SETUP_BACKUP_ENABLED=false
                ;;
            --configs-only) CONFIGS_ONLY=true ;;
            --sync-delete) SYNC_DELETE=true ;;
            --yes)
                SETUP_ASSUME_YES=true
                export SETUP_ASSUME_YES
                ;;
            --no-configs) NO_CONFIGS=true ;;
            --strict-configs)
                # Використовується у configs_install через source.
                # shellcheck disable=SC2034
                STRICT_CONFIGS=true
                ;;
            all) mapfile -t ids < <(registry_ids) ;;
            --*) log_error "Невідомий параметр: $1"; return 2 ;;
            *) ids+=("$1") ;;
        esac
        shift
    done
    if [[ "${SYNC_DELETE:-false}" == true && "${SETUP_BACKUP_ENABLED:-true}" != true ]]; then
        log_error '--sync-delete вимагає захисного backup; приберіть --no-backup.'
        return 2
    fi
    ((${#ids[@]})) || { packages_help; return 2; }
    for choice in "${ids[@]}"; do registry_valid "$choice" || { log_error "Немає модуля: $choice"; return 2; }; done
    for choice in "${ids[@]}"; do packages_run_module "$choice" || return 1; done
}
packages_help() {
    print_header "Допомога: Installer"
    printf '%s\n' './setup.sh packages --list' './setup.sh packages cli shell' './setup.sh packages --dry-run all' './setup.sh packages --configs-only cli' './setup.sh packages --configs-only --no-backup cli' './setup.sh packages --configs-only --sync-delete --dry-run cli' './setup.sh packages --configs-only --sync-delete --yes cli' './setup.sh packages --help'
}
