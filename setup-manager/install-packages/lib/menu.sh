#!/usr/bin/env bash

# ============================================================
# ДИНАМІЧНЕ МЕНЮ, CLI ТА ЗАЛЕЖНОСТІ МОДУЛІВ
# ============================================================
#
# У V2.0 меню формується автоматично з MODULES і MODULE_TITLES.
# Додавати case-пункти для нового модуля більше не потрібно.
# ============================================================

REQUESTED_MODULES=()
RESOLVED_MODULES=()
COMMAND="install"

declare -Ag _RESOLVE_VISITING=()
declare -Ag _RESOLVE_DONE=()

show_help() {
    cat <<'HELP'
Installer Packages V2.0 — Arch Linux

ЗАПУСК
  ./install.sh                 Інтерактивне меню
  ./install.sh cli shell       Встановити вибрані модулі
  ./install.sh all             Установити всі модулі
  ./install.sh status all      Інформаційний стан
  ./install.sh verify cli      Перевірка (код 1 при невідповідності)

ПАРАМЕТРИ
  --list                       Перелік модулів
  --list-configs               Перелік конфігурацій
  --dry-run                    Попередній перегляд без змін
  --yes, -y                    Підтверджувати встановлення
  --configs-only              Тільки копіювання конфігів
  --no-configs                 Без копіювання конфігів
  --no-backup                  Без backup перед заміною
  --strict-configs             Помилка, якщо немає source
  --sync-delete                Видаляти зайве в destination (ОБЕРЕЖНО!)
  --no-deps                    Не встановлювати залежності
  --help, -h                   Довідка

ДОДАВАННЯ ПРОГРАМИ
  Відкрити modules/cli.sh і додати назву в PACMAN_PACKAGES
  або AUR_PACKAGES. Конфіг додати в CONFIG_ITEMS того ж файлу.
  Новий модуль = новий modules/name.sh. Реєстрація автоматична.
  Дивись README.md та docs/ADDING_MODULE.md.

УВАГА
  Запускати звичайним користувачем, без sudo.
  Файли modules/*.sh є Bash-кодом, не підключайте недовірені.
HELP
}

module_exists() {
    local candidate="$1" module
    for module in "${MODULES[@]}"; do
        [[ "$candidate" == "$module" ]] && return 0
    done
    return 1
}

list_modules() {
    local module deps i=1
    printf '%-4s %-16s %-16s %s\n' "№" "МОДУЛЬ" "НАЗВА" "ЗАЛЕЖНОСТІ"
    printf '%-4s %-16s %-16s %s\n' "---" "----------------" "----------------" "------------------------------"

    for module in "${MODULES[@]}"; do
        deps="${MODULE_DEPENDENCIES[$module]-}"
        printf '%-4d %-16s %-16s %s\n' \
            "$i" "$module" "${MODULE_TITLES[$module]:-$module}" "${deps:--}"
        ((i += 1))
    done
}

add_requested_module() {
    local candidate="$1" existing
    for existing in "${REQUESTED_MODULES[@]}"; do
        [[ "$existing" == "$candidate" ]] && return 0
    done
    REQUESTED_MODULES+=("$candidate")
}

# shellcheck disable=SC2034
parse_arguments() {
    while (($#)); do
        case "$1" in
            status | verify)
                COMMAND="$1"
                ;;
            --dry-run) DRY_RUN=true ;;
            --yes | -y) ASSUME_YES=true ;;
            --no-configs) INSTALL_CONFIGS=false ;;
            --configs-only)
                CONFIGS_ONLY=true
                INSTALL_CONFIGS=true
                ;;
            --no-backup) CONFIG_BACKUP=false ;;
            --strict-configs) STRICT_CONFIGS=true ;;
            --sync-delete) SYNC_DELETE=true ;;
            --no-deps) INSTALL_DEPENDENCIES=false ;;
            --list)
                list_modules
                exit 0
                ;;
            --list-configs)
                list_config_mappings
                exit 0
                ;;
            --help | -h | help)
                show_help
                exit 0
                ;;
            all)
                REQUESTED_MODULES=("${MODULES[@]}")
                ;;
            --*)
                log_error "Невідома опція: $1"
                exit 1
                ;;
            *)
                module_exists "$1" || {
                    log_error "Невідомий модуль: $1"
                    exit 1
                }
                add_requested_module "$1"
                ;;
        esac
        shift
    done

    # status/verify без списку модулів перевіряє все.
    if [[ "$COMMAND" != install && ${#REQUESTED_MODULES[@]} -eq 0 ]]; then
        REQUESTED_MODULES=("${MODULES[@]}")
    fi
}

resolve_module_recursive() {
    local module="$1" dep

    [[ -n "${_RESOLVE_DONE[$module]-}" ]] && return 0
    [[ -z "${_RESOLVE_VISITING[$module]-}" ]] || {
        log_error "Циклічна залежність модулів біля: $module"
        return 1
    }

    _RESOLVE_VISITING[$module]=1

    if [[ "$INSTALL_DEPENDENCIES" == true ]]; then
        for dep in ${MODULE_DEPENDENCIES[$module]-}; do
            module_exists "$dep" || {
                log_error "Модуль '$module' залежить від невідомого модуля '$dep'."
                return 1
            }
            resolve_module_recursive "$dep"
        done
    fi

    unset '_RESOLVE_VISITING[$module]'
    _RESOLVE_DONE[$module]=1
    RESOLVED_MODULES+=("$module")
}

resolve_requested_modules() {
    RESOLVED_MODULES=()
    _RESOLVE_VISITING=()
    _RESOLVE_DONE=()

    local module
    for module in "${REQUESTED_MODULES[@]}"; do
        resolve_module_recursive "$module"
    done
}

run_module() {
    local module="$1"
    # Файл модуля вже завантажений реєстром один раз.
    # Тут виконуємо лише універсальний інсталятор і post-install hook.
    echo
    log_step "Встановлення модуля: $module — ${MODULE_TITLES[$module]:-$module}"
    install_registered_module "$module"
    log_ok "Завершено встановлення модуля: $module — ${MODULE_TITLES[$module]:-$module}"
}

run_requested_modules() {
    resolve_requested_modules

    if [[ "$INSTALL_DEPENDENCIES" == true ]]; then
        echo
        log_info "Порядок виконання: ${RESOLVED_MODULES[*]}"
    fi

    local module
    for module in "${RESOLVED_MODULES[@]}"; do
        run_module "$module"
    done
}

run_status_command() {
    status_modules "${REQUESTED_MODULES[@]}"
}

run_verify_command() {
    verify_modules "${REQUESTED_MODULES[@]}"
}

# Динамічний вибір декількох модулів.
multi_select() {
    echo
    echo "Введи номери модулів через пробіл:"

    local i=1 module
    for module in "${MODULES[@]}"; do
        printf '  %d) %s\n' "$i" "${MODULE_TITLES[$module]:-$module}"
        ((i += 1))
    done
    echo

    local input=() item index
    read -r -a input
    REQUESTED_MODULES=()

    for item in "${input[@]}"; do
        [[ "$item" =~ ^[0-9]+$ ]] || {
            log_warn "Невідомий пункт: $item"
            continue
        }

        index=$((item - 1))
        if ((index < 0 || index >= ${#MODULES[@]})); then
            log_warn "Невідомий пункт: $item"
            continue
        fi

        add_requested_module "${MODULES[$index]}"
    done

    ((${#REQUESTED_MODULES[@]})) && run_requested_modules
}

# Друкує меню та повертає номери службових пунктів через глобальні
# змінні MENU_*; усі номери залежать від кількості MODULES.
render_main_menu() {
    local i=1 module

    for module in "${MODULES[@]}"; do
        printf ' %2d) %s\n' "$i" "${MODULE_TITLES[$module]:-$module}"
        ((i += 1))
    done

    MENU_INSTALL_ALL=$i
    MENU_MULTI=$((i + 1))
    MENU_STATUS=$((i + 2))
    MENU_VERIFY=$((i + 3))
    MENU_CONFIGS=$((i + 4))
    MENU_DEPS=$((i + 5))
    MENU_CLEANUP=$((i + 6))
    MENU_HELP=$((i + 7))

    echo
    printf ' %2d) Встановити всі модулі\n' "$MENU_INSTALL_ALL"
    printf ' %2d) Вибрати декілька модулів\n' "$MENU_MULTI"
    echo
    printf ' %2d) Status — детальний стан усіх модулів\n' "$MENU_STATUS"
    printf ' %2d) Verify — строга перевірка всіх модулів\n' "$MENU_VERIFY"
    echo
    printf ' %2d) Показати mapping конфігів\n' "$MENU_CONFIGS"
    printf ' %2d) Показати залежності модулів\n' "$MENU_DEPS"
    echo
    printf ' %2d) Обслуговування\n' "$MENU_CLEANUP"
    printf ' %2d) Допомога\n' "$MENU_HELP"
    echo
    echo "  0) Назад"
    echo " 00) Вихід"
    echo
}

show_main_menu() {
    while true; do
        clear
        print_header "INSTALLER PACKAGES V2.0"
        render_main_menu

        local choice
        read -r -p "Вибір: " choice

        # Пункти модулів обробляються без окремого case.
        if [[ "$choice" =~ ^[0-9]+$ ]] &&
            ((choice >= 1 && choice <= ${#MODULES[@]})); then
            REQUESTED_MODULES=("${MODULES[$((choice - 1))]}")
            run_requested_modules
            pause
            continue
        fi

        case "$choice" in
            "$MENU_INSTALL_ALL")
                if confirm "Встановити всі модулі?"; then
                    REQUESTED_MODULES=("${MODULES[@]}")
                    run_requested_modules
                fi
                pause
                ;;
            "$MENU_MULTI")
                multi_select
                pause
                ;;
            "$MENU_STATUS")
                status_modules "${MODULES[@]}"
                pause
                ;;
            "$MENU_VERIFY")
                verify_modules "${MODULES[@]}" || true
                pause
                ;;
            "$MENU_CONFIGS")
                list_config_mappings
                pause
                ;;
            "$MENU_DEPS")
                list_modules
                pause
                ;;
            "$MENU_CLEANUP")
                maintenance_menu
                ;;
            "$MENU_HELP")
                show_help
                pause
                ;;
            0)
                return 0
                ;;
            00)
                if [[ "${SETUP_MENU_CHILD:-0}" == 1 ]]; then
                    exit 90
                fi
                exit 0
                ;;
            *)
                log_error "Невірний вибір."
                pause
                ;;
        esac
    done
}

maintenance_menu() {
    local choice

    while true; do
        clear

        print_header "ОБСЛУГОВУВАННЯ"
        echo "  1) Видалити всі backups"
        echo "  2) Залишити останні 3 backups"
        echo "  3) Видалити backups старші за 30 днів"
        echo
        echo "  4) Видалити всі logs"
        echo "  5) Залишити останні 10 logs"
        echo "  6) Видалити logs старші за 30 днів"
        echo
        echo "  0) Назад"
        echo " 00) Вихід"
        echo

        read -rp "Вибір: " choice

        case "$choice" in
            1)
                cleanup_all_backups
                pause
                ;;

            2)
                cleanup_keep_last_backups
                pause
                ;;

            3)
                cleanup_old_backups
                pause
                ;;

            4)
                cleanup_all_logs
                pause
                ;;

            5)
                cleanup_keep_last_logs
                pause
                ;;

            6)
                cleanup_old_logs
                pause
                ;;

            0)
                return 0
                ;;
            00)
                if [[ "${SETUP_MENU_CHILD:-0}" == 1 ]]; then
                    exit 90
                fi
                exit 0
                ;;

            *)
                log_error "Невірний вибір."
                pause
                ;;
        esac
    done
}
