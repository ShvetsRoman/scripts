#!/usr/bin/env bash
set -Eeuo pipefail

readonly VERSION="3.2.3"
SCRIPT_NAME="$(basename -- "$0")"
readonly SCRIPT_NAME

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR

# shellcheck source=lib/globals.sh
source "$ROOT_DIR/lib/globals.sh"

DRY_RUN=false
YES=false
VERBOSE=false
COMMAND=""
COMMAND_ARGS=()
LOCK_FD=""

# shellcheck source=lib/logging.sh
source "$ROOT_DIR/lib/logging.sh"
# shellcheck source=lib/utils.sh
source "$ROOT_DIR/lib/utils.sh"
# shellcheck source=lib/config.sh
source "$ROOT_DIR/lib/config.sh"
# shellcheck source=lib/validation.sh
source "$ROOT_DIR/lib/validation.sh"
# shellcheck source=lib/status.sh
source "$ROOT_DIR/lib/status.sh"
# shellcheck source=lib/backup.sh
source "$ROOT_DIR/lib/backup.sh"
# shellcheck source=lib/restore.sh
source "$ROOT_DIR/lib/restore.sh"
# shellcheck source=lib/diff.sh
source "$ROOT_DIR/lib/diff.sh"
# shellcheck source=lib/recovery.sh
source "$ROOT_DIR/lib/recovery.sh"
# shellcheck source=lib/verify.sh
source "$ROOT_DIR/lib/verify.sh"
# shellcheck source=lib/archive.sh
source "$ROOT_DIR/lib/archive.sh"
# shellcheck source=lib/help.sh
source "$ROOT_DIR/lib/help.sh"

error_handler() {
    local exit_code="$?"
    local line_number="${1:-?}"
    local command="${2:-невідома команда}"

    log_error "Помилка у рядку ${line_number}."
    log_error "Команда: ${command}"
    log_error "Код завершення: ${exit_code}"
    exit "$exit_code"
}

trap 'error_handler "${LINENO}" "$BASH_COMMAND"' ERR

cleanup() {
    if [[ -n "${LOCK_FD:-}" ]]; then
        eval "exec ${LOCK_FD}>&-" 2>/dev/null || true
        LOCK_FD=""
    fi
}

trap cleanup EXIT

parse_arguments() {
    local parsing_options=true
    local arg

    while (($#)); do
        arg="$1"
        shift

        if [[ "$parsing_options" == true ]]; then
            case "$arg" in
                --)
                    parsing_options=false
                    ;;
                --dry-run)
                    DRY_RUN=true
                    ;;
                --yes|-y)
                    YES=true
                    ;;
                --verbose|-v)
                    VERBOSE=true
                    ;;
                --help|-h)
                    show_help
                    exit 0
                    ;;
                --version|-V)
                    echo "$VERSION"
                    exit 0
                    ;;
                -*)
                    log_error "Невідома опція: $arg"
                    exit 2
                    ;;
                *)
                    parsing_options=false
                    COMMAND="$arg"
                    ;;
            esac
        else
            COMMAND_ARGS+=("$arg")
        fi
    done
}

acquire_lock() {
    exec {LOCK_FD}>"$LOCK_FILE"

    if ! flock -n "$LOCK_FD"; then
        log_error "Інший екземпляр $SCRIPT_NAME вже виконується."
        exit 1
    fi
}

show_menu() {
    local choice
    local path

    while true; do
        echo
        echo "1) Backup all        Backup всього"
        echo "2) Backup path       Backup конкретного шляху"
        echo "3) Backup changed    Backup лише змінених шляхів"
        echo "4) Restore all       Відновлення всього"
        echo "5) Restore path      Відновлення конкретного шляху"
        echo "6) Diff              Показати відмінності між оригіналами і dotfiles"
        echo "7) Status            Показати стан оригіналів відносно dotfiles"
        echo "8) Verify sync       Перевірити повну відповідність оригіналів і dotfiles"
        echo "9) Archive create    Створити archive ${ARCHIVE_PREFIX}_Y-m-d_H-M-S.tar.gz в ${ARCHIVE_DIR##*/}"
        echo
        echo "10) Help             Допомога"
        echo
        echo "0) Exit              Вихід"
        echo

        read -r -p "Виберіть дію: " choice

        case "$choice" in
            1)
                backup_all
                ;;
            2)
                read -r -p "PATH: " path
                backup_path "$path"
                ;;
            3)
                backup_changed
                ;;
            4)
                restore_all
                ;;
            5)
                read -r -p "PATH: " path
                restore_path "$path"
                ;;
            6)
                diff_all
                ;;
            7)
                show_status
                ;;
            8)
                if verify_all; then
                    log_debug "Verify завершено успішно."
                else
                    log_debug "Verify виявив невідповідності."
                fi
                ;;
            9)
                archive_create ""
                ;;
            10)
                show_help
                return 0
                ;;
            0)
                return 0
                ;;
            *)
                log_warning "Невірний вибір."
                ;;
        esac
    done
}

run_command() {
    case "$COMMAND" in
        backup)
            if [[ "${COMMAND_ARGS[0]:-}" == "changed" ]]; then
                backup_changed
            elif ((${#COMMAND_ARGS[@]})); then
                backup_path "${COMMAND_ARGS[0]}"
            else
                backup_all
            fi
            ;;
        restore)
            if ((${#COMMAND_ARGS[@]})); then
                restore_path "${COMMAND_ARGS[0]}"
            else
                restore_all
            fi
            ;;
        diff)
            if ((${#COMMAND_ARGS[@]})); then
                diff_path "${COMMAND_ARGS[0]}"
            else
                diff_all
            fi
            ;;
        status)
            show_status
            ;;
        verify)
            if ((${#COMMAND_ARGS[@]})); then
                verify_path "${COMMAND_ARGS[0]}"
            else
                verify_all
            fi
            ;;
        clean)
            clean_backup
            ;;
        clean-all)
            clean_all
            ;;
        recovery)
            case "${COMMAND_ARGS[0]:-}" in
                list)
                    recovery_list
                    ;;
                restore)
                    recovery_restore "${COMMAND_ARGS[1]:-}"
                    ;;
                delete)
                    recovery_delete "${COMMAND_ARGS[1]:-}"
                    ;;
                cleanup)
                    cleanup_recovery_snapshots
                    ;;
                *)
                    log_error "Використання: recovery {list|restore|delete|cleanup}"
                    exit 2
                    ;;
            esac
            ;;
        archive)
            case "${COMMAND_ARGS[0]:-}" in
                create)
                    archive_create "${COMMAND_ARGS[1]:-}"
                    ;;
                list)
                    archive_list "${COMMAND_ARGS[1]:-}"
                    ;;
                restore)
                    archive_restore "${COMMAND_ARGS[1]:-}"
                    ;;
                *)
                    log_error "Використання: archive {create|list|restore}"
                    exit 2
                    ;;
            esac
            ;;
        config)
            if [[ "${COMMAND_ARGS[0]:-}" != "list" ]]; then
                log_error "Використання: config list"
                exit 2
            fi
            show_config
            ;;
        menu)
            show_menu
            ;;
        "")
            show_menu
            ;;
        *)
            log_error "Невідома команда: $COMMAND"
            exit 2
            ;;
    esac
}

check_dependencies() {
    local command

    for command in rsync diff cmp readlink find flock git tar; do
        if ! command -v "$command" >/dev/null 2>&1; then
            log_error "Не знайдено залежність: $command"
            exit 1
        fi
    done
}

main() {
    parse_arguments "$@"
    check_dependencies
    load_config
    validate_backup_paths
    ensure_directories
    acquire_lock
    run_command
}

main "$@"
