#!/usr/bin/env bash
set -Eeuo pipefail

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
# shellcheck source=lib/rsync.sh
source "$SCRIPT_DIR/lib/rsync.sh"
# shellcheck source=lib/verify.sh
source "$SCRIPT_DIR/lib/verify.sh"
# shellcheck source=lib/cleanup.sh
source "$SCRIPT_DIR/lib/cleanup.sh"

main() {
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
            confirm_sync
            run_sync_all
            ;;
        verify)
            run_verify_all
            ;;
        cleanup)
            cleanup_logs
            ;;
        *)
            log_error "Невідома команда: $COMMAND"
            ;;
    esac

    print_final_summary
}

main "$@"
