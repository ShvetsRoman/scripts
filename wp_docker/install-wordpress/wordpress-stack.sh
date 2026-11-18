#!/usr/bin/env bash
# ============================================================
# WordPress Production Stack Installer
# VERSION is defined in config/defaults.conf (single source).
# ============================================================

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd -P
)"
readonly SCRIPT_DIR

# shellcheck source=config/defaults.conf
source "$SCRIPT_DIR/config/defaults.conf"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/args.sh
source "$SCRIPT_DIR/lib/args.sh"
# shellcheck source=lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"
# shellcheck source=lib/security.sh
source "$SCRIPT_DIR/lib/security.sh"
# shellcheck source=lib/docker.sh
source "$SCRIPT_DIR/lib/docker.sh"
# shellcheck source=lib/proxy.sh
source "$SCRIPT_DIR/lib/proxy.sh"
# shellcheck source=lib/wordpress.sh
source "$SCRIPT_DIR/lib/wordpress.sh"
# shellcheck source=lib/summary.sh
source "$SCRIPT_DIR/lib/summary.sh"

trap 'handle_error "$LINENO" "$BASH_COMMAND" "$?"' ERR
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

main() {
    print_banner

    init_runtime_defaults
    parse_args "$@"
    validate_args

    if [[ "$INIT_PROXY" == true ]]; then
        run_proxy_flow
        return 0
    fi

    check_system
    check_dependencies
    resolve_runtime_defaults
    check_docker_access
    validate_privilege_requirements
    prepare_install_path
    check_disk_space
    preflight_domain_dns
    resolve_frontend_subnet
    ensure_proxy_network

    create_project_structure
    create_env_file
    install_templates
    create_traefik_config
    create_real_ip_config
    configure_compose_mode
    create_gitignore
    create_readme
    fix_install_ownership

    if [[ "$MANAGE_FIREWALL" == true ]]; then
        setup_nftables
    fi

    if [[ "$ENABLE_FAIL2BAN" == true ]]; then
        setup_fail2ban
    fi

    if [[ "$ENABLE_CRON" == true ]]; then
        schedule_cron_tasks
    fi

    validate_project

    if [[ "$NO_START" == false ]]; then
        start_services
        wait_for_services
        normalize_wordpress_permissions
        install_wordpress
        normalize_wordpress_permissions
        run_healthcheck
    fi

    show_final_info
}

main "$@"
