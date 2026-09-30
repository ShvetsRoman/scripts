#!/usr/bin/env bash
# ============================================================
# WordPress Production Stack Installer
# Version: 2.0.0
# ============================================================

set -Eeuo pipefail

readonly SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd -P
)"
readonly VERSION="2.0.0"

source "$SCRIPT_DIR/config/defaults.conf"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/args.sh"
source "$SCRIPT_DIR/lib/system.sh"
source "$SCRIPT_DIR/lib/project.sh"
source "$SCRIPT_DIR/lib/security.sh"
source "$SCRIPT_DIR/lib/docker.sh"
source "$SCRIPT_DIR/lib/wordpress.sh"
source "$SCRIPT_DIR/lib/summary.sh"

trap 'handle_error "$LINENO" "$BASH_COMMAND" "$?"' ERR
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

main() {
    print_banner

    parse_args "$@"
    validate_args

    check_root
    check_system
    check_dependencies

    create_project_structure
    create_env_file
    install_templates
    create_traefik_config
    configure_compose_mode
    configure_php_mode
    create_gitignore
    create_readme

    if [[ "$MANAGE_FIREWALL" == true ]]; then
        setup_nftables
    fi

    if [[ "$ENABLE_FAIL2BAN" == true ]]; then
        setup_fail2ban
    fi

    validate_project

    if [[ "$NO_START" == false ]]; then
        start_services
        wait_for_services
        install_wordpress
        run_healthcheck
    fi

    show_final_info
}

main "$@"
