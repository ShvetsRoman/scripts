#!/usr/bin/env bash
# CLI.

# cli_parse — витягує всі прапорці у змінні, залишає позиційні у CLI_ARGS.
# Прапорці можуть бути у будь-якій позиції.
# Глобальні прапорці використовуються в інших файлах lib/*.sh після source.
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
            --sync-delete)     SYNC_DELETE=true ;;
            --no-backup)       SETUP_BACKUP_ENABLED=false ;;
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
# і для повідомлення про невідому команду, щоб перелік не застарівав.
cli_dotfiles_help() {
    cat <<'EOT'
  ./setup.sh dotfiles backup [ШЛЯХ...]
  ./setup.sh dotfiles backup changed [ШЛЯХ...]
  ./setup.sh dotfiles restore [ШЛЯХ...]
  ./setup.sh dotfiles status [ШЛЯХ...]
  ./setup.sh dotfiles verify [ШЛЯХ...]
  ./setup.sh dotfiles plan backup [ШЛЯХ...]
  ./setup.sh dotfiles plan restore [ШЛЯХ...]
  ./setup.sh dotfiles diff [ШЛЯХ...]
EOT
}

# cli_help — довідка.
cli_help() {
    header "Setup Manager $SETUP_VERSION"
    cat <<'EOT'
Загальне:
  ./setup.sh                      Інтерактивне меню
  ./setup.sh --version
  ./setup.sh --help

Installer:
  ./setup.sh installer --list
  ./setup.sh installer cli shell
  ./setup.sh installer --all
  ./setup.sh installer --dry-run all
  ./setup.sh installer --configs-only --sync-delete --yes cli

Dotfiles:
EOT
    cli_dotfiles_help
    cat <<'EOT'

Backup з довільного місця:
  ./setup.sh backup-src SRC REPO_SUB
  ./setup.sh restore-src REPO_SUB [TARGET]

Реєстр джерел:
  ./setup.sh sources list
  ./setup.sh sources doctor
  ./setup.sh sources validate
  ./setup.sh sources scan
  ./setup.sh sources add NAME MODE SRC DST [GROUP]
  ./setup.sh sources add MODE SRC DST          # старий синтаксис
  ./setup.sh sources remove NAME

Архіви / Recovery:
  ./setup.sh archive list|create|restore NAME
  ./setup.sh recovery list|verify ID|plan ID|restore ID [ШЛЯХ...]|delete ID
  ./setup.sh backups list GROUP
  ./setup.sh backups verify GROUP ID

Інше:
  ./setup.sh smart [--dry-run] [модулі...]
  ./setup.sh doctor
  ./setup.sh maintenance [--dry-run] menu|disk|cleanup TYPE|rotate TYPE KEEP
  ./setup.sh logs path|tail [N]
  ./setup.sh update RELEASE.tar.gz [--dry-run]
  ./setup.sh test
EOT
}

# cli_dispatch — диспетчер команд.
cli_dispatch() {
    cli_parse "$@"
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
        installer|packages) [[ "${1:-}" != --list && "${1:-}" != list && "${1:-}" != --help && "${1:-}" != -h && "${1:-}" != help ]] ;;
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
        installer|packages)   packages_main "$@" ;;
        smart)                smart_main "$@" ;;
        dotfiles)
            case "${1:-status}" in
                backup)   shift; if [[ "${1:-}" == changed ]]; then shift; sync_run backup --changed "$@"; else sync_run backup "$@"; fi ;;
                restore)  shift; sync_run restore "$@" ;;
                status)   shift; sync_status "$@" ;;
                verify)   shift; sync_verify "$@" ;;
                plan)     shift; sync_plan "$@" ;;
                diff)     shift; sync_diff "$@" ;;
                help|--help|-h) cli_dotfiles_help ;;
                *)
                    log error "Невідома команда dotfiles: $1"
                    printf '\nВикористання:\n' >&2
                    cli_dotfiles_help >&2
                    return 2
                    ;;
            esac ;;
        backup-src)  [[ -n "${1:-}" && -n "${2:-}" ]] || { log error 'backup-src SRC REPO_SUB'; return 2; }; sync_backup_src "$1" "$2" ;;
        restore-src) [[ -n "${1:-}" ]] || { log error 'restore-src REPO_SUB [TARGET]'; return 2; }; sync_restore_src "$1" "${2:-$HOME/$1}" ;;
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
        status) sync_status "$@" ;;
        verify) sync_verify "$@" ;;
        plan) sync_plan "$@" ;;
        diff)        sync_diff "$@" ;;
        test)        SETUP_TEST_MODE=true bash "$ROOT_DIR/tests/run-tests.sh" ;;
        *) log error "Невідома команда: $cmd"; cli_help; return 2 ;;
    esac
}
