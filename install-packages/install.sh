#!/usr/bin/env bash
# ShellCheck не може статично визначити ROOT_DIR для dynamic source.
# shellcheck disable=SC1091
set -Eeuo pipefail

# ============================================================
# INSTALLER PACKAGES V1.6
# ============================================================
#
# Призначення:
# - встановлення пакетів через pacman та paru;
# - модульне встановлення груп програм;
# - автоматичне вирішення залежностей модулів;
# - копіювання готових конфігів із ../dotfiles-manager/dotfiles;
# - backup існуючих конфігів;
# - status та verify пакетів/конфігів/сервісів;
# - інтерактивне меню та CLI;
# - --dry-run, --yes, --configs-only, --no-configs;
# - журналювання запусків та ShellCheck-тести.
# ============================================================

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR

source "$ROOT_DIR/config/installer.conf"
source "$ROOT_DIR/config/packages.conf"
source "$ROOT_DIR/config/modules.conf"
source "$ROOT_DIR/config/configs.conf"
source "$ROOT_DIR/lib/colors.sh"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/cleanup.sh"
source "$ROOT_DIR/lib/configs.sh"
source "$ROOT_DIR/lib/modules.sh"
source "$ROOT_DIR/lib/package-manager.sh"
source "$ROOT_DIR/lib/services.sh"
source "$ROOT_DIR/lib/status.sh"
source "$ROOT_DIR/lib/ui.sh"

trap 'error_handler $? $LINENO' ERR

validate_project() {
    build_module_configs
    validate_config_map

    local module
    for module in "${MODULES[@]}"; do
        [[ -f "$ROOT_DIR/modules/$module.sh" ]] || {
            log_error "Відсутній файл модуля: modules/$module.sh"
            return 1
        }
        validate_module_metadata "$module"
    done
}

main() {
    parse_arguments "$@"

    require_arch
    require_non_root
    require_command sudo
    require_command rsync
    require_command pacman
    require_command getent
    require_command readlink

    validate_project

    # Для встановлення конфігів попереджаємо про відсутній dotfiles-dir.
    # Status/verify самі покажуть source error для відповідних mapping.
    if [[ "$COMMAND" == install && "$INSTALL_CONFIGS" == true ]]; then
        validate_dotfiles_dir || [[ "$STRICT_CONFIGS" != true ]]
    fi

    init_logging

    case "$COMMAND" in
        install)
            if ((${#REQUESTED_MODULES[@]})); then
                run_requested_modules
            else
                show_main_menu
            fi
            ;;
        status)
            run_status_command || true
            ;;
        verify)
            run_verify_command
            ;;
        *)
            log_error "Невідома команда: $COMMAND"
            return 1
            ;;
    esac
}

main "$@"
