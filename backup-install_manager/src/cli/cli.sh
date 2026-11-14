#!/usr/bin/env bash
# CLI.

# cli_parse — витягує всі прапорці у змінні, залишає позиційні у CLI_ARGS.
# Прапорці можуть бути у будь-якій позиції.
# Глобальні прапорці використовуються в інших файлах core/*.sh, packages/*.sh, dotfiles/*.sh, recovery/*.sh, src/cli/*.sh після source.
# ShellCheck перевіряє кожен файл окремо та не бачить міжмодульних читань.
# shellcheck disable=SC2034
cli_parse() {
    CLI_ARGS=()
    while (($#)); do
        case "$1" in
            --dry-run)         DRY_RUN=true; export DRY_RUN ;;
            --yes|-y)          SETUP_ASSUME_YES=true; export SETUP_ASSUME_YES ;;
            --no-color)        export NO_COLOR=1 ;;
            --verbose|-v)      export SETUP_VERBOSE=true ;;
            --delete)          SYNC_DELETE=true ;;
            --backup)          SETUP_BACKUP_ENABLED=true ;;
            --configs-only)    CONFIGS_ONLY=true ;;
            --no-configs)      NO_CONFIGS=true ;;
            --strict-configs)  STRICT_CONFIGS=true ;;
            --all)             CLI_ARGS+=(all) ;;
            --) shift; CLI_ARGS+=("$@"); break ;;
            *) CLI_ARGS+=("$1") ;;
        esac
        shift
    done
    ui_init_colors
}

# Єдина довідка для підкоманд dotfiles: використовується і в --help,
# і в `dotfiles --help`, і для повідомлення про невідому команду,
# щоб перелік не застарівав. Змінюйте обережно: тести шукають
# підрядки 'dotfiles backup changed' (tests/run-tests.sh, test-cli-contract-v1439.sh).
cli_dotfiles_help() {
    cat <<'EOT'
  ./backup-install_manager.sh dotfiles backup [ШЛЯХ...]         Скопіювати HOME → dotfiles (Enter = усі)
  ./backup-install_manager.sh dotfiles backup changed [ШЛЯХ...] Лише змінені файли
  ./backup-install_manager.sh dotfiles restore [ШЛЯХ...]        Відновити dotfiles → HOME
  ./backup-install_manager.sh dotfiles status [ШЛЯХ...]         Порівняти HOME ↔ dotfiles (читання)
  ./backup-install_manager.sh dotfiles verify [ШЛЯХ...]         Перевірка розбіжностей
  ./backup-install_manager.sh dotfiles plan backup [ШЛЯХ...]    План backup без дій
  ./backup-install_manager.sh dotfiles plan restore [ШЛЯХ...]   План restore без дій
  ./backup-install_manager.sh dotfiles diff [ШЛЯХ...]           Пофайлові відмінності
  ./backup-install_manager.sh dotfiles groups                   Перелік груп реєстру
  Додайте --group НАЗВА до будь-якого режиму Dotfiles.
EOT
}

# cli_help — довідка.
# Структура: Загальне → Швидкі команди → Пакети → Dotfiles → Джерела → Архіви → Інше.
# Швидкі команди — top-level псевдоніми без префікса `dotfiles`, які приймає
# диспетчер (cli_execute). Тести шукають у тексті підрядки 'sources add',
# 'recovery list|verify', 'dotfiles plan' — не видаляйте ці фрагменти.
cli_help() {
    header "Setup Manager $SETUP_VERSION"
    cat <<'EOT'
Загальне:
  ./backup-install_manager.sh                       Інтерактивне меню
  ./backup-install_manager.sh --version             Версія (src/core/version.sh)
  ./backup-install_manager.sh --help                Ця довідка

Швидкі команди (без префікса `dotfiles`):
  ./backup-install_manager.sh status [ШЛЯХ...]      Порівняти HOME ↔ dotfiles (читання)
  ./backup-install_manager.sh verify [ШЛЯХ...]      Перевірка розбіжностей
  ./backup-install_manager.sh diff [ШЛЯХ...]        Пофайлові відмінності
  ./backup-install_manager.sh plan backup|restore [ШЛЯХ...]   План дій без виконання

Пакети (config/packages.conf: INI, порядок секцій; hooks = локальні Bash-скрипти):
  ./backup-install_manager.sh packages --list                   Перелік пакетів без встановлення
  ./backup-install_manager.sh packages cli shell                Встановити пакети модулів
  ./backup-install_manager.sh packages --all                    Усі модулі реєстру
  ./backup-install_manager.sh packages --dry-run all            Сухий прогін без дій
  ./backup-install_manager.sh packages --configs-only --delete --yes cli
  ./backup-install_manager.sh packages --help                   Довідка Packages (поля реєстру, порядок етапів)

Dotfiles:
EOT
    cli_dotfiles_help
    cat <<'EOT'

Backup з довільного місця:
  ./backup-install_manager.sh backup-src SRC REPO_SUB           Разовий бекап шляху у сховище
  ./backup-install_manager.sh restore-src REPO_SUB [TARGET]     Повернути його назад

Реєстр джерел:
  ./backup-install_manager.sh sources list                      Поточний реєстр джерел
  ./backup-install_manager.sh sources doctor                    Чи існують шляхи на диску
  ./backup-install_manager.sh sources validate                  Перевірка схеми реєстру
  ./backup-install_manager.sh sources scan                      Що є у $HOME поза реєстром
  ./backup-install_manager.sh sources add NAME TYPE PATH GROUP  Додати запис
  TYPE: home (~/ або ${HOME}/), system (/etc/...), порожній (абсолютний PATH)
  ./backup-install_manager.sh sources remove NAME               Видалити запис

Архіви / Recovery:
  ./backup-install_manager.sh archive list|create|restore NAME  Архіви каталогу dotfiles/
  ./backup-install_manager.sh recovery list|verify ID|plan ID|restore ID [ШЛЯХ...]|delete ID
  ./backup-install_manager.sh backups list GROUP                Резервні копії групи
  ./backup-install_manager.sh backups verify GROUP ID           Перевірка цілісності резервної копії

Інше:
  ./backup-install_manager.sh smart [--dry-run] [модулі...]     «Розумний» прогін модулів
  ./backup-install_manager.sh doctor                            Діагностика середовища
  ./backup-install_manager.sh report summary|modules            Звіти
  ./backup-install_manager.sh modules list|info ID|deps ID|reverse ID|stats|plan   Граф модулів (не встановлює)
  ./backup-install_manager.sh maintenance [--dry-run] menu|disk|cleanup TYPE|rotate TYPE KEEP   Обслуговування
  ./backup-install_manager.sh logs path|tail [N]                Журнал виконання
  ./backup-install_manager.sh update RELEASE.tar.gz [--sha256 HASH] [--dry-run]  Оновлення з релізного архіву
  ./backup-install_manager.sh test                              Регресійні тести
EOT
}

# cli_dispatch — диспетчер команд.
cli_dispatch() {
    fs_guard_delete || return 2
    set -- "${CLI_ARGS[@]}"
    local cmd="${1:-}"; (($#)) && shift
    # Єдина точка розподілу lock: читання не блокуємо.
    if cli_is_mutating "$cmd" "$@"; then
        setup_with_lock cli_execute "$cmd" "$@"
    else
        cli_execute "$cmd" "$@"
    fi
}

# Визначаємо, чи команда може модифікувати систему або репозиторій.
cli_is_mutating() {
    local cmd="${1:-}"; (($#)) && shift
    case "$cmd" in
        packages) [[ "${1:-}" != --list && "${1:-}" != list && "${1:-}" != --help && "${1:-}" != -h && "${1:-}" != help ]] ;;
        smart) (($# > 0)) ;;
        backup-src|restore-src|update) return 0 ;;
        dotfiles) [[ "${1:-status}" == backup || "${1:-status}" == restore ]] ;;
        sources) [[ "${1:-list}" == add || "${1:-list}" == remove ]] ;;
        archive) [[ "${1:-list}" == create || "${1:-list}" == restore ]] ;;
        recovery) [[ "${1:-list}" == restore || "${1:-list}" == delete ]] ;;
        maintenance) [[ "${1:-menu}" == cleanup || "${1:-menu}" == rotate ]] ;;
        *) return 1 ;;
    esac
}

cli_execute() {
    local cmd="${1:-}"; (($#)) && shift
    case "$cmd" in
        ''|menu)              menu_main ;;
        --version|-V|version) printf '%s\n' "$SETUP_VERSION" ;;
        --help|-h|help)       cli_help ;;
        packages)   packages_main "$@" ;;
        smart)                smart_main "$@" ;;
        dotfiles) cli_dotfiles_execute "$@" ;;
        backup-src)  [[ -n "${1:-}" && -n "${2:-}" ]] || { log error 'backup-src SRC REPO_SUB'; return 2; }; sync_backup_src "$1" "$2" ;;
        restore-src) [[ -n "${1:-}" ]] || { log error 'restore-src REPO_SUB [TARGET]'; return 2; }; sync_restore_src "$1" "${2:-$(path_home_relative "$1")}" ;;
        sources)
            case "${1:-list}" in
                list)   sources_list ;;
                doctor) sources_doctor ;;
                validate) sources_validate ;;
                scan)   sources_scan ;;
                add)    shift; sources_add "$@" ;;
                remove) shift; [[ -n "${1:-}" ]] || { log error 'sources remove NAME'; return 2; }; sources_remove "$1" ;;
                *) log error 'sources list|doctor|validate|scan|add|remove'; return 2 ;;
            esac ;;
        archive)     archive_main "$@" ;;
        recovery)    recovery_main "$@" ;;
        backups)     backups_main "$@" ;;
        logs)        logs_main "$@" ;;
        maintenance) maintenance_main "$@" ;;
        update)      setup_update "$@" ;;
        doctor)      doctor_main ;;
        modules)     report_modules "$@" ;;
        report)      report_main "$@" ;;
        status) sync_status "$@" ;;
        verify) sync_verify "$@" ;;
        plan) sync_plan "$@" ;;
        diff)        sync_diff "$@" ;;
        test)        SETUP_TEST_MODE=true bash "$(path_tests run-tests.sh)" ;;
        *) log error "Невідома команда: $cmd"; cli_help; return 2 ;;
    esac
}

# Спільний селектор групи для всіх режимів Dotfiles.
# Фільтруємо список імен, а не змінюємо реєстр або групу Recovery.
cli_dotfiles_execute() {
    local action="${1:-status}"
    (($#)) && shift
    if [[ "$action" == help || "$action" == --help || "$action" == -h ]]; then
        cli_dotfiles_help
        return 0
    fi
    if [[ "$action" == groups ]]; then
        (($# == 0)) || { log error 'dotfiles groups не приймає аргументів'; return 2; }
        sources_groups
        return $?
    fi
    local group="" arg
    local -a args=() members=() selected=()
    while (($#)); do
        case "$1" in
            --group)
                (($# >= 2)) && [[ -n "$2" && "$2" != --* ]] || {
                    log error 'Потрібно вказати назву після --group'; return 2;
                }
                [[ -z "$group" ]] || { log error 'Повторний --group'; return 2; }
                group="$2"; shift 2 ;;
            *) args+=("$1"); shift ;;
        esac
    done
    if [[ -n "$group" ]]; then
        sources_load || return 2
        local found=false row member filter good
        for arg in "${DOTFILES_GROUPS[@]}"; do
            [[ "$arg" == "$group" ]] && found=true
        done
        [[ "$found" == true ]] || { log error "Невідома група Dotfiles: $group"; return 2; }
        for row in "${SRC_ROWS[@]}"; do
            sources_parse "$row"
            [[ "${DOTFILES_ITEM_GROUP[$S_NAME]}" == "$group" ]] && members+=("$S_NAME")
        done
        ((${#members[@]})) || { log error "Група $group порожня"; return 2; }
        local -a prefix=()
        case "$action" in
            plan)
                ((${#args[@]})) || { log error 'plan потребує backup або restore'; return 2; }
                prefix=("${args[0]}")
                args=("${args[@]:1}") ;;
            backup|restore)
                if [[ "${args[0]:-}" == changed ]]; then
                    prefix=(changed)
                    args=("${args[@]:1}")
                fi ;;
        esac
        if ((${#args[@]})); then
            for filter in "${args[@]}"; do
                good=false
                for member in "${members[@]}"; do
                    sources_find "$member" || return 2
                    if sync_row_selected "$filter"; then
                        good=true
                        selected+=("$member")
                        break
                    fi
                done
                [[ "$good" == true ]] || {
                    log error "Запис не належить групі $group: $filter"; return 2;
                }
            done
        else
            selected=("${members[@]}")
        fi
        args=("${prefix[@]}" "${selected[@]}")
    fi
    case "$action" in
        backup)
            if [[ "${args[0]:-}" == changed ]]; then
                args=("${args[@]:1}")
                sync_run backup --changed "${args[@]}"
            else
                sync_run backup "${args[@]}"
            fi ;;
        restore)
            if [[ "${args[0]:-}" == changed ]]; then
                args=("${args[@]:1}")
                sync_run restore --changed "${args[@]}"
            else
                sync_run restore "${args[@]}"
            fi ;;
        status) sync_status "${args[@]}" ;;
        verify) sync_verify "${args[@]}" ;;
        plan) sync_plan "${args[@]}" ;;
        diff) sync_diff "${args[@]}" ;;
        *) log error "Невідома команда dotfiles: $action"; cli_dotfiles_help >&2; return 2 ;;
    esac
}
