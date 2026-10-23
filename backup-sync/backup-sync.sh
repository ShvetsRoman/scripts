#!/usr/bin/env bash
set -Eeuo pipefail

# printf '%(...)T' (4.2), wait на process substitution (4.4), порожні масиви під set -u (4.4).
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
    printf '[ERROR] Потрібен bash >= 4.4 (зараз %s).\n' "$BASH_VERSION" >&2
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CONFIG_FILE="${BACKUP_SYNC_CONFIG:-$SCRIPT_DIR/config/config.conf}"

# shellcheck source=lib/globals.sh
source "$SCRIPT_DIR/lib/globals.sh"
# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
# shellcheck source=lib/utils.sh
source "$SCRIPT_DIR/lib/utils.sh"
# shellcheck source=lib/args.sh
source "$SCRIPT_DIR/lib/args.sh"
# shellcheck source=lib/ssh.sh
source "$SCRIPT_DIR/lib/ssh.sh"
# shellcheck source=lib/remote_lock.sh
source "$SCRIPT_DIR/lib/remote_lock.sh"
# shellcheck source=lib/rsync.sh
source "$SCRIPT_DIR/lib/rsync.sh"
# shellcheck source=lib/verify.sh
source "$SCRIPT_DIR/lib/verify.sh"
# shellcheck source=lib/cleanup.sh
source "$SCRIPT_DIR/lib/cleanup.sh"

main() {
    # Жодна неочікувана помилка не завершує скрипт мовчки.
    trap 'on_err "$?" "$LINENO" "$BASH_COMMAND"' ERR

    parse_args "$@"

    if [[ "$COMMAND" == help ]]; then
        print_help
        return 0
    fi

    check_local_dependencies
    load_config
    init_runtime
    configure_mode
    init_logging
    acquire_lock
    configure_ssh
    preflight
    print_mode_summary

    case "$COMMAND" in
        up|down)
            build_rsync_opts
            require_confirmation_possible
            if scan_needed; then
                scan_changes
            fi
            check_space_for_run
            confirm_sync
            ensure_remote_dir
            acquire_remote_lock
            run_sync_all
            auto_cleanup_recovery
            ;;
        verify)
            run_verify_all
            ;;
        cleanup)
            acquire_remote_lock
            cleanup_logs
            ;;
        *)
            die "Невідома команда: $COMMAND"
            ;;
    esac

    print_final_summary
    exit "$FINAL_RC"
}

main "$@"
