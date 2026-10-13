#!/usr/bin/env bash
# CLI.

# cli_parse — витягує всі прапорці у змінні, залишає позиційні у CLI_ARGS.
# Прапорці можуть бути у будь-якій позиції.
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
  ./setup.sh dotfiles backup [ШЛЯХ...]      # порожньо = усі
  ./setup.sh dotfiles restore [ШЛЯХ...]     # порожньо = усі
  ./setup.sh dotfiles status
  ./setup.sh dotfiles diff [ШЛЯХ...]

Backup з довільного місця:
  ./setup.sh backup-src SRC REPO_SUB
  ./setup.sh restore-src REPO_SUB [TARGET]

Реєстр джерел:
  ./setup.sh sources list
  ./setup.sh sources doctor
  ./setup.sh sources scan
  ./setup.sh sources add MODE SRC DST
  ./setup.sh sources remove DST

Архіви / Recovery:
  ./setup.sh archive list|create|restore NAME
  ./setup.sh recovery list|restore ID|delete ID

Інше:
  ./setup.sh smart [--dry-run] [модулі...]
  ./setup.sh doctor
  ./setup.sh maintenance [--dry-run] menu|disk|cleanup TYPE
  ./setup.sh update RELEASE.tar.gz [--dry-run]
  ./setup.sh test
EOT
}

# cli_dispatch — диспетчер команд.
cli_dispatch() {
    cli_parse "$@"
    set -- "${CLI_ARGS[@]:-}"
    local cmd="${1:-}"; (($#)) && shift
    case "$cmd" in
        ''|menu)              menu_main ;;
        --version|-V|version) printf '%s\n' "$SETUP_VERSION" ;;
        --help|-h|help)       cli_help ;;
        installer|packages)   packages_main "$@" ;;
        smart)                smart_main "$@" ;;
        dotfiles)
            case "${1:-status}" in
                backup)   shift; sync_run backup "$@" ;;
                restore)  shift; sync_run restore "$@" ;;
                status|verify) sync_status ;;
                diff)     shift; sync_diff "$@" ;;
                *) log error 'dotfiles backup|restore|status|diff'; return 2 ;;
            esac ;;
        backup-src)  [[ -n "${1:-}" && -n "${2:-}" ]] || { log error 'backup-src SRC REPO_SUB'; return 2; }; sync_backup_src "$1" "$2" ;;
        restore-src) [[ -n "${1:-}" ]] || { log error 'restore-src REPO_SUB [TARGET]'; return 2; }; sync_restore_src "$1" "${2:-$HOME/$1}" ;;
        sources)
            case "${1:-list}" in
                list)   sources_list ;;
                doctor) sources_doctor ;;
                scan)   sources_scan ;;
                add)    shift; [[ $# -ge 3 ]] || { log error 'sources add MODE SRC DST'; return 2; }; sources_add "$1" "$2" "$3" ;;
                remove) shift; [[ -n "${1:-}" ]] || { log error 'sources remove DST'; return 2; }; sources_remove "$1" ;;
                *) log error 'sources list|doctor|scan|add|remove'; return 2 ;;
            esac ;;
        archive)     archive_main "$@" ;;
        recovery)    recovery_main "$@" ;;
        maintenance) maintenance_main "$@" ;;
        update)      setup_update "$@" ;;
        doctor)      doctor_main ;;
        status|verify) sync_status ;;
        diff)        sync_diff "$@" ;;
        test)        bash "$ROOT_DIR/tests/run-tests.sh" ;;
        *) log error "Невідома команда: $cmd"; cli_help; return 2 ;;
    esac
}
