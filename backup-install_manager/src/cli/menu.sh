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
        all|dotfiles_backup|dotfiles_backup_changed|dotfiles_backup_group|dotfiles_backup_src|\
        dotfiles_restore|dotfiles_restore_changed|dotfiles_restore_group|dotfiles_restore_src|\
        sources_add|sources_remove|archive_create|archive_restore|\
        recovery_restore|recovery_delete|cleanup_logs|cleanup_packages|\
        cleanup_dotfiles|cleanup_recovery|rotate_dotfiles) return 0 ;;
        *) return 1 ;;
    esac
}
# Зчитування номера або Esc. Esc працює без натискання Enter.
# Результат зберігається в MENU_CHOICE, щоб уникнути subshell.
menu_read_choice() {
    local first rest
    MENU_CHOICE=''
    IFS= read -r -n 1 first || return 1
    if [[ "$first" == $'\e' ]]; then
        MENU_CHOICE='0'
        return 0
    fi
    if [[ -z "$first" ]]; then
        return 0
    fi
    IFS= read -r rest || rest=''
    MENU_CHOICE="${first}${rest}"
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

        # Короткі пояснення для операцій із резервними копіями.
        # Це лише підказки інтерфейсу: правила архівування не змінюються.
        case "$title" in
            'Резервні копії')
                printf '%s\n' 'Архіви — копії dotfiles/ проєкту, не всього HOME.'
                printf '%s\n\n' 'Recovery — захисні копії, створені під час файлових операцій.'
                ;;
            'Архіви')
                printf '%s\n' 'Архів містить dotfiles/ проєкту, а не весь домашній каталог.'
                printf '%s\n\n' 'Символьні та жорсткі посилання в архіві не підтримуються.'
                ;;
            'Recovery')
                printf '%s\n\n' 'Тут лише захисні копії операцій; порожній список — це нормально.'
                ;;
        esac

        local -a items=()
        if [[ -n "$provider" ]]; then
            mapfile -t items < <("$provider")
        else
            items=("$@")
        fi

        # all завжди окремим рядком після порожнього відступу.
        local i=1 item key label desc
        local -a regular_items=()
        local all_item=''
        for item in "${items[@]}"; do
            IFS='|' read -r key label desc <<< "$item"
            if [[ "$key" == all ]]; then
                all_item="$item"
            else
                regular_items+=("$item")
            fi
        done
        if command -v column >/dev/null 2>&1; then
            {
                for item in "${regular_items[@]}"; do
                    IFS='|' read -r key label desc <<< "$item"
                    printf '%s\t%s\t%s\n' "$i)" "$label" "$desc"
                    ((i+=1))
                done
            } | column -t -s $'\t' -o '  '
        else
            for item in "${regular_items[@]}"; do
                IFS='|' read -r key label desc <<< "$item"
                printf '%2d) %s — %s\n' "$i" "$label" "$desc"
                ((i+=1))
            done
        fi
        if [[ -n "$all_item" ]]; then
            # Лічильник у конвеєрі column змінювався в дочірньому процесі.
            # Номер all визначаємо незалежно від способу форматування.
            i=$(( ${#regular_items[@]} + 1 ))
            IFS='|' read -r key label desc <<< "$all_item"
            printf '\n%d)  %s  %s\n' "$i" "$label" "$desc"
        fi
        printf '\n0)  Назад (Esc)\n00) Вихід\n\nВиберіть дію: '

        local choice
        menu_read_choice || MENU_CHOICE=00
        choice="$MENU_CHOICE"

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
                MENU_NAV_BACK=0
                if menu_is_mutating "$key"; then
                    setup_with_lock "menu_action_$key" || rc=$?
                else
                    "menu_action_$key" || rc=$?
                fi
                (( rc == 0 )) || log error "Дія $key завершилась із кодом $rc"
                if [[ "$MENU_NAV_BACK" == 1 ]]; then
                    continue
                fi
                printf '\n%s── Enter, щоб продовжити ──%s' "$C_HEAD" "$C_OFF"
                read -r _ || true
            elif [[ -n "$provider" ]] && registry_valid "$key"; then
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
# Провайдер Пакети
# ─────────────────────────────────────────────────────────────────────────────
packages_items() {
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
menu_sub_packages_choose() { menu_run 'Встановлення модулів' --provider packages_items; }
menu_sub_dotfiles() { menu_run 'Dotfiles' "${DOTFILES_MENU[@]}"; }
menu_sub_sources()     { menu_run 'Реєстр джерел' "${SOURCES_MENU[@]}"; }
menu_sub_archive()     { menu_run 'Архіви' "${ARCHIVE_MENU[@]}"; }
menu_sub_recovery()    { menu_run 'Recovery' "${RECOVERY_MENU[@]}"; }
menu_sub_maintenance() { menu_run 'Обслуговування' "${MAINTENANCE_MENU[@]}"; }
menu_sub_packages()    { menu_run 'Пакети' "${PACKAGES_MENU[@]}"; }
menu_sub_backups()     { menu_run 'Резервні копії' "${BACKUPS_MENU[@]}"; }
menu_sub_system()      { menu_run 'Система' "${SYSTEM_MENU[@]}"; }
menu_sub_settings()    { menu_run 'Налаштування' "${SETTINGS_MENU[@]}"; }

# ─────────────────────────────────────────────────────────────────────────────
# Верхній рівень
# ─────────────────────────────────────────────────────────────────────────────
menu_action_status() { sync_status; }
menu_action_doctor() { doctor_main; }
menu_action_tests()  { SETUP_TEST_MODE=true bash "$(path_tests run-tests.sh)"; }
menu_action_help()   { cli_help; }

# ─────────────────────────────────────────────────────────────────────────────
# Dotfiles
# ─────────────────────────────────────────────────────────────────────────────
# Для групових дій використовується той самий CLI, що й для звичайних операцій.
# Спочатку вибір, потім перегляд, і лише після явного підтвердження — виконання.
menu_dotfiles_group_action() {
    local action="$1" title group choice i row count total
    local -a names=() modes=() paths=() group_names=() group_counts=()
    sources_load || return 2
    group_names=("${DOTFILES_GROUPS[@]}")
    total=${#SRC_ROWS[@]}
    for group in "${group_names[@]}"; do
        count=0
        for row in "${SRC_ROWS[@]}"; do
            sources_parse "$row" || return 2
            [[ "${DOTFILES_ITEM_GROUP[$S_NAME]}" == "$group" ]] && ((count+=1))
        done
        group_counts+=("$count")
    done
    if [[ "$action" == backup ]]; then
        title='Резервувати групу'
    else
        title='Відновити групу'
    fi
    while :; do
        ui_clear
        printf '\n%s========== %s ==========%s\n\n' "$C_HEAD" "$title" "$C_OFF"

        for i in "${!group_names[@]}"; do
            printf '%d) %s (%d)\n' "$((i+1))" "${group_names[i]}" "${group_counts[i]}"
        done
        printf '\n%d) all (%d) — Усі конфігурації\n' "$(( ${#group_names[@]}+1 ))" "$total"
        printf '\n0) Назад (Esc)\n00) Вихід\n\nВибір: '
        menu_read_choice || return 0
        choice="$MENU_CHOICE"
        case "$choice" in
            0) MENU_NAV_BACK=1; return 0 ;;
            00) log info 'Завершення'; exit 0 ;;
        esac
        [[ "$choice" =~ ^[0-9]+$ ]] && (( 10#$choice >= 1 && 10#$choice <= ${#group_names[@]}+1 )) || {
            log warn "Невідома група: $choice"
            continue
        }
        if (( 10#$choice == ${#group_names[@]}+1 )); then
            group=all
        else
            group="${group_names[10#$choice-1]}"
        fi
        while :; do
            ui_clear
            printf '\n%s========== %s: %s ==========%s\n\n' "$C_HEAD" "$title" "$group" "$C_OFF"
            names=(); modes=(); paths=()
            for row in "${SRC_ROWS[@]}"; do
                sources_parse "$row" || return 2
                if [[ "$group" == all || "${DOTFILES_ITEM_GROUP[$S_NAME]}" == "$group" ]]; then
                    names+=("$S_NAME"); modes+=("${S_MODE:--}"); paths+=("$S_SRC")
                fi
            done
            if command -v column >/dev/null 2>&1; then
                {
                    printf '№\tКОНФІГ\tTYPE\tШЛЯХ\n'
                    for i in "${!names[@]}"; do
                        printf '%d\t%s\t%s\t%s\n' "$((i+1))" "${names[i]}" "${modes[i]}" "${paths[i]}"
                    done
                } | column -t -s $'\t' -o '  '
            else
                printf '%s\n' '№  КОНФІГ | TYPE | ШЛЯХ'
                for i in "${!names[@]}"; do
                    printf '%d) %s | %s | %s\n' "$((i+1))" "${names[i]}" "${modes[i]}" "${paths[i]}"
                done
            fi
            printf '\nУсього: %d конфігурацій\n' "${#names[@]}"
            printf '\n1) Виконати\n2) Вибрати іншу групу\n\n0) Назад (Esc)\n00) Вихід\n\nВибір: '
            menu_read_choice || return 0
        choice="$MENU_CHOICE"
            case "$choice" in
                1)
                    if [[ "$group" == all ]]; then
                        cli_dotfiles_execute "$action"
                    else
                        cli_dotfiles_execute "$action" --group "$group"
                    fi
                    return $? ;;
                2) break ;;
                0) MENU_NAV_BACK=1; return 0 ;;
                00) log info 'Завершення'; exit 0 ;;
                *) log warn "Невідома дія: $choice" ;;
            esac
        done
    done
}

menu_action_dotfiles_backup_group() { menu_dotfiles_group_action backup; }
menu_action_dotfiles_restore_group() { menu_dotfiles_group_action restore; }
menu_action_dotfiles_backup() { cli_dotfiles_execute backup; }
menu_action_dotfiles_backup_changed() { cli_dotfiles_execute backup changed; }
menu_action_dotfiles_restore() { cli_dotfiles_execute restore; }
menu_action_dotfiles_restore_changed() { cli_dotfiles_execute restore changed; }
menu_action_dotfiles_status() { cli_dotfiles_execute status; }
menu_action_dotfiles_verify() { cli_dotfiles_execute verify; }
menu_action_dotfiles_plan_backup() { cli_dotfiles_execute plan backup; }
menu_action_dotfiles_plan_restore() { cli_dotfiles_execute plan restore; }
menu_action_dotfiles_diff() { cli_dotfiles_execute diff; }

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
    [[ -n "$r" ]] && sync_restore_src "$r" "${t:-$(path_home_relative "$r")}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Sources
# ─────────────────────────────────────────────────────────────────────────────
menu_action_sources_list()   { sources_list; }
menu_action_sources_doctor() { sources_doctor; }
menu_action_sources_validate() { sources_validate; }
menu_action_sources_scan()   { sources_scan; }
menu_action_sources_add() {
    local name mode src group
    read -r -p 'ID: ' name || return 0
    read -r -p 'TYPE (home|system|порожній): ' mode || return 0
    read -r -p 'PATH (~/, ${HOME}/ або /): ' src || return 0
    read -r -p 'Група (має бути останньою в dotfiles.conf): ' group || return 0
    [[ -n "$name" && -n "$src" && -n "$group" ]] || return 0
    sources_add "$name" "$mode" "$src" "$group"
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
menu_action_cleanup_packages() { maintenance_cleanup packages; }
menu_action_cleanup_dotfiles()  { maintenance_cleanup dotfiles; }
menu_action_cleanup_recovery()  { maintenance_cleanup recovery; }
menu_action_disk()              { maintenance_usage; }

menu_action_rotate_dotfiles() {
    local keep
    read -r -p 'Скільки копій залишити? (1..9999): ' keep || return 0
    maintenance_rotate dotfiles "$keep"
}

# ─────────────────────────────────────────────────────────────────────────────
# Пакети all
# ─────────────────────────────────────────────────────────────────────────────
menu_action_all() { packages_main all; }

# ─────────────────────────────────────────────────────────────────────────────
# Опис меню
# ─────────────────────────────────────────────────────────────────────────────
# Кожна дія присутня лише в одному логічному розділі.
DOTFILES_MENU=(
    "dotfiles_status|Стан|Порівняння HOME і dotfiles"
    "dotfiles_backup|Резервувати|HOME → dotfiles"
    "dotfiles_backup_changed|Резервувати змінені|Лише нові та змінені"
    "dotfiles_backup_group|Резервувати групу|Вибір, перегляд і підтвердження"
    "dotfiles_backup_src|Резервувати шлях|Довільне джерело"
    "dotfiles_plan_backup|План резервування|Без запису файлів"
    "dotfiles_restore|Відновити|dotfiles → HOME"
    "dotfiles_restore_changed|Відновити змінені|Лише змінені"
    "dotfiles_restore_group|Відновити групу|Вибір, перегляд і підтвердження"
    "dotfiles_restore_src|Відновити шлях|Довільне призначення"
    "dotfiles_plan_restore|План відновлення|Без запису файлів"
    "dotfiles_verify|Перевірити|Перевірка відповідності"
    "dotfiles_diff|Порівняти|Показати відмінності"
)
SOURCES_MENU=(
    "sources_list|Список|Показати реєстр"
    "sources_doctor|Діагностика|Перевірити джерела"
    "sources_validate|Валідація|Перевірити записи"
    "sources_scan|Сканування|Знайти конфігурації"
    "sources_add|Додати|Новий запис"
    "sources_remove|Видалити|Прибрати запис"
)
ARCHIVE_MENU=(
    "archive_create|Створити|Новий архів"
    "archive_list|Список|Переглянути архіви"
    "archive_restore|Відновити|Із архіву"
)
RECOVERY_MENU=(
    "recovery_list|Список|Захисні копії"
    "recovery_verify|Перевірити|Контроль цілісності"
    "recovery_plan|План|Попередній перегляд"
    "recovery_restore|Відновити|Із захисної копії"
    "recovery_delete|Видалити|Непотрібну копію"
)
MAINTENANCE_MENU=(
    "cleanup_logs|Очистити журнали|Старі записи"
    "cleanup_packages|Очистити Пакети|Тимчасові файли"
    "cleanup_dotfiles|Очистити Dotfiles|Службові файли"
    "cleanup_recovery|Очистити Recovery|Старі знімки"
    "disk|Використання диска|Вільне місце"
)
PACKAGES_MENU=(
    "packages_choose|Встановлення модулів|Вибрати модуль або всі"
)
BACKUPS_MENU=(
    "archive|Архіви dotfiles|Створити, переглянути, відновити"
    "recovery|Захисні копії|Перевірити, відновити, видалити"
    "rotate_dotfiles|Ротація копій|Залишити N останніх"
)
SYSTEM_MENU=(
    "doctor|Діагностика|Стан системи"
    "maintenance|Обслуговування|Очищення та диск"
    "tests|Тести|Перевірка Setup Manager"
)
SETTINGS_MENU=(
    "sources|Реєстр джерел|Керування dotfiles.conf"
    "help|Довідка|Команди та параметри"
)
MAIN_MENU=(
    "packages|Пакети|Встановлення програм"
    "dotfiles|Dotfiles|Конфігурації HOME"
    "backups|Резервні копії|Архіви й Recovery"
    "system|Система|Діагностика й обслуговування"
    "settings|Налаштування|Джерела та довідка"
)

# menu_main — точка входу меню.
menu_main() { menu_run 'Головне меню' "${MAIN_MENU[@]}"; }
