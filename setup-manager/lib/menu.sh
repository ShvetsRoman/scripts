#!/usr/bin/env bash
# Усі інтерактивні меню мають спільне оформлення та правила навігації.
# 0 — назад (на головному рівні вихід), 00 — завершити програму.
menu_header() {
    printf '\n%s========== %s ==========%s\n\n' "$CYAN" "$1" "$NC"
}
menu_item() {
    printf '%-4s %-18s %s\n' "$1)" "$2" "$3"
}
menu_footer() {
    printf '\n'
    printf '0)  Назад\n00) Вихід\n'
}
menu_read() {
    MENU_CHOICE=''
    printf '\n'
    printf 'Виберіть дію: '
    read -r MENU_CHOICE || MENU_CHOICE=00
}
menu_exit() {
    log_info 'Завершення Setup Manager'
    exit 0
}
menu_path_prompt() {
    MENU_PATH=''
    read -r -p "$1" MENU_PATH || return 1
}
packages_menu() {
    local id index choice
    local -a ids=()
    mapfile -t ids < <(registry_ids)
    while :; do
        menu_header 'INSTALLER'
        index=1
        for id in "${ids[@]}"; do
            # Назва з перевіреного декларативного модуля, без виконання install hooks.
            choice="$(
                # Декларативний модуль вибрано з реєстру.
                # shellcheck disable=SC1090
                source "$ROOT_DIR/modules/$id.sh"
                printf '%s' "${MODULE_TITLE:-$id}"
            )"
            menu_item "$index" "$id" "Встановлення модуля $choice"
            ((index+=1))
        done
        printf '\n'
        menu_item a 'all' 'Встановлення всіх модулів'
        menu_footer
        menu_read
        case "$MENU_CHOICE" in
            0) return 0 ;;
            00) menu_exit ;;
            a|A) packages_main all || : ;;
            *)
                if [[ "$MENU_CHOICE" =~ ^[0-9]+$ ]] && ((10#$MENU_CHOICE >= 1 && 10#$MENU_CHOICE <= ${#ids[@]})); then
                    index=$((10#$MENU_CHOICE - 1))
                    packages_main "${ids[index]}" || :
                elif registry_valid "$MENU_CHOICE"; then
                    packages_main "$MENU_CHOICE" || :
                else
                    log_warn 'Невідомий модуль або пункт меню'
                fi
                ;;
        esac
    done
}
dotfiles_menu() {
    while :; do
        menu_header 'DOTFILES'
        menu_item 1 'Backup' 'Зберегти HOME → dotfiles'
        menu_item 2 'Restore' 'Відновити dotfiles → HOME'
        menu_item 3 'Status' 'Стан конфігурацій'
        menu_item 4 'Diff' 'Відмінності у вмісті'
        menu_item 5 'Verify' 'Перевірити синхронізацію'
        menu_item 6 'Archive' 'Створення та відновлення архівів'
        menu_item 7 'Recovery' 'Захисні копії та відновлення'
        menu_footer
        menu_read
        case "$MENU_CHOICE" in
            1)
                menu_path_prompt 'Шлях (порожньо = усі): ' || continue
                if [[ -n "$MENU_PATH" ]]; then dotfiles_main backup "$MENU_PATH" || :
                else dotfiles_main backup || :; fi
                ;;
            2)
                menu_path_prompt "Шлях для відновлення (обов’язково): " || continue
                if [[ -n "$MENU_PATH" ]]; then dotfiles_main restore "$MENU_PATH" || :
                else log_warn 'Вкажи конкретний шлях для відновлення'; fi
                ;;
            3) dotfiles_main status || : ;;
            4)
                menu_path_prompt 'Шлях (порожньо = усі): ' || continue
                if [[ -n "$MENU_PATH" ]]; then dotfiles_main diff "$MENU_PATH" || :
                else dotfiles_main diff || :; fi
                ;;
            5) dotfiles_main verify || : ;;
            6) archive_menu ;;
            7) recovery_menu ;;
            0) return 0 ;;
            00) menu_exit ;;
            *) log_warn 'Невідома дія' ;;
        esac
    done
}
archive_menu() {
    while :; do
        menu_header 'ARCHIVE'
        menu_item 1 'Create' 'Створити архів dotfiles'
        menu_item 2 'List' 'Переглянути архіви'
        menu_item 3 'Restore' 'Відновити архів'
        menu_footer
        menu_read
        case "$MENU_CHOICE" in
            1) archive_main create || : ;;
            2) archive_main list || : ;;
            3)
                menu_path_prompt 'Назва архіву: ' || continue
                if [[ -n "$MENU_PATH" ]]; then archive_main restore "$MENU_PATH" || :
                else log_warn 'Вкажи назву архіву'; fi
                ;;
            0) return 0 ;;
            00) menu_exit ;;
            *) log_warn 'Невідома дія' ;;
        esac
    done
}
recovery_menu() {
    while :; do
        menu_header 'RECOVERY'
        menu_item 1 'List' 'Переглянути Recovery-копії'
        menu_item 2 'Restore' 'Відновити Recovery-копію'
        menu_item 3 'Delete' 'Видалити Recovery-копію'
        menu_footer
        menu_read
        case "$MENU_CHOICE" in
            1) recovery_main list || : ;;
            2|3)
                menu_path_prompt 'ID Recovery: ' || continue
                if [[ -z "$MENU_PATH" ]]; then log_warn 'Вкажи ID Recovery'
                elif [[ "$MENU_CHOICE" == 2 ]]; then recovery_main restore "$MENU_PATH" || :
                else recovery_main delete "$MENU_PATH" || :; fi
                ;;
            0) return 0 ;;
            00) menu_exit ;;
            *) log_warn 'Невідома дія' ;;
        esac
    done
}
menu_main() {
    while :; do
        menu_header 'SETUP MANAGER'
        menu_item 1 'Installer' 'Встановлення програм і конфігів'
        menu_item 2 'Dotfiles' 'Резервне копіювання, відновлення, порівняння та перевірка'
        menu_item 3 'Smart Setup' 'Майстер встановлення'
        menu_item 4 'Status' 'Загальний стан'
        menu_item 5 'Verify' 'Загальна перевірка'
        menu_item 6 'Doctor' 'Діагностика'
        menu_item 7 'Maintenance' 'Архіви, точки відновлення та очищення'
        menu_item 8 'Tests' 'Тестування проєкту'
        menu_item 9 'Help' 'Допомога'
        menu_footer
        menu_read
        case "$MENU_CHOICE" in
            1) packages_menu ;;
            2) dotfiles_menu ;;
            3) smart_main || : ;;
            4) dotfiles_status || : ;;
            5) dotfiles_status || : ;;
            6) doctor_main || : ;;
            7) maintenance_main || : ;;
            8) bash "$ROOT_DIR/tests/run-tests.sh" || : ;;
            9) setup_help ;;
            0|00) return 0 ;;
            *) log_warn 'Невідома дія' ;;
        esac
    done
}
