#!/usr/bin/env bash
# Один движок меню.
# Пункт: "key|label|desc".
# Підменю: menu_sub_<key>; дії: menu_action_<key>.
# Пауза Enter — лише після дій.

# ─────────────────────────────────────────────────────────────────────────────
# Движок
# ─────────────────────────────────────────────────────────────────────────────

# Лише дії, що змінюють дані, потребують ексклюзивного доступу.
menu_is_mutating() {
    case "${1:-}" in
        all|dotfiles_backup|dotfiles_backup_changed|dotfiles_backup_src|        dotfiles_restore|dotfiles_restore_changed|dotfiles_restore_src|        sources_add|sources_remove|archive_create|archive_restore|        recovery_restore|recovery_delete|cleanup_logs|cleanup_installer|        cleanup_dotfiles|cleanup_recovery|rotate_dotfiles) return 0 ;;
        *) return 1 ;;
    esac
}

# menu_run TITLE ITEMS...
# menu_run TITLE --provider FUNC
menu_run() {
    local title="$1"; shift
    local provider=""
    if [[ "${1:-}" == "--provider" ]]; then
        provider="$2"; shift 2
    fi

    while :; do
        ui_clear
        printf '\n%s========== %s ==========%s\n\n' "$C_HEAD" "$title" "$C_OFF"

        local -a items=()
        if [[ -n "$provider" ]]; then
            mapfile -t items < <("$provider")
        else
            items=("$@")
        fi

        local i=1 item
        for item in "${items[@]}"; do
            local key label desc
            IFS='|' read -r key label desc <<< "$item"
            printf '%-4s %-18s %s\n' "$i)" "$label" "$desc"
            ((i+=1))
        done
        printf '\n0)  Назад\n00) Вихід\n\nВиберіть дію: '

        local choice
        read -r choice || choice=00

        case "$choice" in
            0)  return 0 ;;
            00) log info 'Завершення'; exit 0 ;;
        esac

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            local item="${items[choice-1]}" key
            IFS='|' read -r key _ _ <<< "$item"

            if declare -F "menu_sub_$key" >/dev/null; then
                "menu_sub_$key"
                continue
            fi
            if declare -F "menu_action_$key" >/dev/null; then
                ui_clear
                local rc=0
                if menu_is_mutating "$key"; then
                    setup_with_lock "menu_action_$key" || rc=$?
                else
                    "menu_action_$key" || rc=$?
                fi
                (( rc == 0 )) || log error "Дія $key завершилась із кодом $rc"
                printf '\n%s── Enter, щоб продовжити ──%s' "$C_HEAD" "$C_OFF"
                read -r _ || true
            elif [[ "$title" == INSTALLER ]] && registry_valid "$key"; then
                local rc=0
                setup_with_lock packages_main "$key" || rc=$?
                (( rc == 0 )) || log error "Модуль $key завершився із кодом $rc"
                printf '\n%s── Enter, щоб продовжити ──%s' "$C_HEAD" "$C_OFF"
                read -r _ || true
            else
                log warn "Немає обробника: $key"
                printf '\nНатисніть Enter...'
                read -r _ || true
            fi
        else
            log warn "Невідома дія: $choice"
            printf '\nНатисніть Enter...'
            read -r _ || true
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Провайдер Installer
# ─────────────────────────────────────────────────────────────────────────────
installer_items() {
    local id title
    while IFS= read -r id; do
        title="$(registry_title "$id")"
        printf '%s|%s|%s\n' "$id" "$title" "Модуль $id"
    done < <(registry_ids)
    printf 'all|all|Встановити всі модулі\n'
}

# ─────────────────────────────────────────────────────────────────────────────
# Підменю
# ─────────────────────────────────────────────────────────────────────────────
menu_sub_installer()   { menu_run 'INSTALLER'   --provider installer_items; }
menu_sub_dotfiles()    { menu_run 'DOTFILES'    "${DOTFILES_MENU[@]}"; }
menu_sub_sources()     { menu_run 'SOURCES'     "${SOURCES_MENU[@]}"; }
menu_sub_archive()     { menu_run 'ARCHIVE'     "${ARCHIVE_MENU[@]}"; }
menu_sub_recovery()    { menu_run 'RECOVERY'    "${RECOVERY_MENU[@]}"; }
menu_sub_maintenance() { menu_run 'MAINTENANCE' "${MAINTENANCE_MENU[@]}"; }

# ─────────────────────────────────────────────────────────────────────────────
# Верхній рівень
# ─────────────────────────────────────────────────────────────────────────────
menu_action_status() { sync_status; }
menu_action_doctor() { doctor_main; }
menu_action_tests()  { SETUP_TEST_MODE=true bash "$ROOT_DIR/tests/run-tests.sh"; }
menu_action_help()   { cli_help; }

# ─────────────────────────────────────────────────────────────────────────────
# Dotfiles
# ─────────────────────────────────────────────────────────────────────────────
menu_action_dotfiles_backup() {
    local p
    read -r -p 'Шлях (порожньо = усі, Enter): ' p || return 0
    if [[ -n "$p" ]]; then sync_run backup "$p"; else sync_run backup; fi
}

menu_action_dotfiles_backup_changed() {
    # Однакова логіка для меню та CLI.
    sync_run backup --changed
}

menu_action_dotfiles_restore() {
    local p
    read -r -p 'Шлях (порожньо = усі, Enter): ' p || return 0
    if [[ -n "$p" ]]; then sync_run restore "$p"; else sync_run restore; fi
}

menu_action_dotfiles_restore_changed() {
    local -a changed=()
    local row
    sources_load || return 2
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        local h r
        h="$(sources_abs "$S_MODE" "$S_SRC")"
        r="$ROOT_DIR/dotfiles/$S_DST"
        [[ -e "$r" || -L "$r" ]] || continue
        fs_compare "$h" "$r" 2>/dev/null || changed+=("$S_NAME")
    done
    ((${#changed[@]})) || { log info 'Немає змінених.'; return 0; }
    sync_run restore "${changed[@]}"
}

menu_action_dotfiles_status() { sync_status; }
menu_action_dotfiles_verify() { sync_verify; }
menu_action_dotfiles_plan_backup() { sync_plan backup; }
menu_action_dotfiles_plan_restore() { sync_plan restore; }

menu_action_dotfiles_diff() {
    local p
    read -r -p 'Шлях (порожньо=усі): ' p || return 0
    sync_diff ${p:-}
}

menu_action_dotfiles_backup_src() {
    local s r
    read -r -p 'SRC (абс, напр. /etc/nginx): ' s || return 0
    read -r -p 'REPO_SUB (/ у кінці = каталог): ' r || return 0
    [[ -n "$s" && -n "$r" ]] && sync_backup_src "$s" "$r"
}

menu_action_dotfiles_restore_src() {
    local r t
    read -r -p 'REPO_SUB (напр. .zshrc): ' r || return 0
    read -r -p 'TARGET (/ у кінці = каталог): ' t || return 0
    [[ -n "$r" ]] && sync_restore_src "$r" "${t:-$HOME/$r}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Sources
# ─────────────────────────────────────────────────────────────────────────────
menu_action_sources_list()   { sources_list; }
menu_action_sources_doctor() { sources_doctor; }
menu_action_sources_validate() { sources_validate; }
menu_action_sources_scan()   { sources_scan; }
menu_action_sources_add() {
    local name mode src dst group
    read -r -p 'NAME: ' name || return 0
    read -r -p 'MODE (home|abs|system): ' mode || return 0
    read -r -p 'SRC: ' src || return 0
    read -r -p 'DST (в dotfiles): ' dst || return 0
    read -r -p 'GROUP [dotfiles]: ' group || return 0
    [[ -n "$name" && -n "$mode" && -n "$src" && -n "$dst" ]] || return 0
    sources_add "$name" "$mode" "$src" "$dst" "${group:-dotfiles}"
}
menu_action_sources_remove() {
    local d
    read -r -p 'NAME: ' d || return 0
    [[ -n "$d" ]] && sources_remove "$d"
}

# ─────────────────────────────────────────────────────────────────────────────
# Archive
# ─────────────────────────────────────────────────────────────────────────────
menu_action_archive_create()  { archive_create; }
menu_action_archive_list()    { archive_list; }

menu_action_archive_restore() {
    local n
    read -r -p 'Назва: ' n || return 0
    [[ -n "$n" ]] && archive_restore "$n"
}

# ─────────────────────────────────────────────────────────────────────────────
# Recovery
# ─────────────────────────────────────────────────────────────────────────────
menu_action_recovery_list()    { recovery_list; }
menu_action_recovery_verify() {
    local id
    read -r -p 'ID: ' id || return 0
    [[ -n "$id" ]] && recovery_verify "$id"
}

menu_action_recovery_restore() {
    local i
    read -r -p 'ID: ' i || return 0
    [[ -n "$i" ]] && recovery_restore "$i"
}

menu_action_recovery_plan() {
    local i
    read -r -p 'ID: ' i || return 0
    [[ -n "$i" ]] && recovery_plan "$i"
}

menu_action_recovery_delete() {
    local i
    read -r -p 'ID: ' i || return 0
    [[ -n "$i" ]] && recovery_delete "$i"
}

# ─────────────────────────────────────────────────────────────────────────────
# Maintenance
# ─────────────────────────────────────────────────────────────────────────────
menu_action_cleanup_logs()      { maintenance_cleanup logs; }
menu_action_cleanup_installer() { maintenance_cleanup installer; }
menu_action_cleanup_dotfiles()  { maintenance_cleanup dotfiles; }
menu_action_cleanup_recovery()  { maintenance_cleanup recovery; }
menu_action_disk()              { maintenance_usage; }

menu_action_rotate_dotfiles() {
    local keep
    read -r -p 'Скільки копій залишити? (1..9999): ' keep || return 0
    maintenance_rotate dotfiles "$keep"
}

# ─────────────────────────────────────────────────────────────────────────────
# Installer all
# ─────────────────────────────────────────────────────────────────────────────
menu_action_all() { packages_main all; }

# ─────────────────────────────────────────────────────────────────────────────
# Опис меню
# ─────────────────────────────────────────────────────────────────────────────
DOTFILES_MENU=(
    "dotfiles_backup|Backup|HOME → dotfiles (порожньо = усі)"
    "dotfiles_backup_changed|Backup Changed|Лише змінені"
    "dotfiles_backup_src|Backup SRC|З довільного місця"
    "dotfiles_restore|Restore|dotfiles → HOME (порожньо = усі)"
    "dotfiles_restore_changed|Restore Changed|Лише змінені"
    "dotfiles_restore_src|Restore SRC|У довільне місце"
    "dotfiles_status|Status|Стан"
    "dotfiles_diff|Diff|Відмінності"
    "dotfiles_verify|Verify|Перевірка відповідності"
    "dotfiles_plan_backup|Plan Backup|План резервного копіювання"
    "dotfiles_plan_restore|Plan Restore|План відновлення"
    "sources|Sources|Реєстр джерел"
    "archive|Archive|Архіви dotfiles"
    "recovery|Recovery|Захисні копії"
)
SOURCES_MENU=(
    "sources_list|List|Показати реєстр"
    "sources_doctor|Doctor|Перевірити існування src/dst"
    "sources_validate|Validate|Перевірити схему реєстру"
    "sources_scan|Scan|Що є у \$HOME (dry)"
    "sources_add|Add|Додати один шлях"
    "sources_remove|Remove|Видалити шлях"
)
ARCHIVE_MENU=(
    "archive_create|Create|Створити архів"
    "archive_list|List|Показати архіви"
    "archive_restore|Restore|Відновити архів"
)
RECOVERY_MENU=(
    "recovery_list|List|Показати копії"
    "recovery_verify|Verify|Перевірити цілісність"
    "recovery_plan|Plan|Показати, що відновиться"
    "recovery_restore|Restore|Відновити"
    "recovery_delete|Delete|Видалити"
)
MAINTENANCE_MENU=(
    "archive_create|Archive Create|Створити архів"
    "archive_list|Archive List|Архіви"
    "archive_restore|Archive Restore|Відновити"
    "recovery_list|Recovery List|Копії"
    "recovery_verify|Recovery Verify|Перевірка цілісності"
    "recovery_plan|Recovery Plan|Перегляд плану"
    "recovery_restore|Recovery Restore|Відновити"
    "recovery_delete|Recovery Delete|Видалити"
    "cleanup_logs|Logs Cleanup|Журнали"
    "cleanup_installer|Installer Cleanup|Installer"
    "cleanup_dotfiles|Dotfiles Cleanup|Dotfiles"
    "rotate_dotfiles|Backup Rotation|Залишити N найновіших dotfiles backup"
    "cleanup_recovery|Recovery Cleanup|Recovery"
    "disk|Disk Usage|Диск"
)
MAIN_MENU=(
    "installer|Installer|Встановлення програм і конфігів"
    "dotfiles|Dotfiles|Backup / Restore / Status / Diff"
    "sources|Sources|Реєстр джерел"
    "archive|Archive|Архіви dotfiles"
    "recovery|Recovery|Захисні копії"
    "maintenance|Maintenance|Очищення та стан"
    "status|Status|Загальний стан"
    "doctor|Doctor|Діагностика"
    "tests|Tests|Тестування"
    "help|Help|Довідка"
)

# menu_main — точка входу меню.
menu_main() { menu_run 'SETUP MANAGER' "${MAIN_MENU[@]}"; }
