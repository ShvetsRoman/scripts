#!/usr/bin/env bash
# Setup Manager V4 — повністю нова реалізація з одним CLI.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
# shellcheck source=config/setup.conf
source "$ROOT_DIR/config/setup.conf"
# shellcheck source=lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=lib/core.sh
source "$ROOT_DIR/lib/core.sh"
# shellcheck source=lib/registry.sh
source "$ROOT_DIR/lib/registry.sh"
# shellcheck source=lib/configs.sh
source "$ROOT_DIR/lib/configs.sh"
# shellcheck source=lib/packages.sh
source "$ROOT_DIR/lib/packages.sh"
# shellcheck source=lib/dotfiles.sh
source "$ROOT_DIR/lib/dotfiles.sh"
# shellcheck source=lib/recovery.sh
source "$ROOT_DIR/lib/recovery.sh"
# shellcheck source=lib/archive.sh
source "$ROOT_DIR/lib/archive.sh"
# shellcheck source=lib/hooks.sh
source "$ROOT_DIR/lib/hooks.sh"
# shellcheck source=lib/git.sh
source "$ROOT_DIR/lib/git.sh"
# shellcheck source=lib/menu.sh
source "$ROOT_DIR/lib/menu.sh"
# shellcheck source=lib/maintenance.sh
source "$ROOT_DIR/lib/maintenance.sh"
# shellcheck source=lib/update.sh
source "$ROOT_DIR/lib/update.sh"
# shellcheck source=lib/doctor.sh
source "$ROOT_DIR/lib/doctor.sh"
DRY_RUN=false
setup_confirm() {
    local reply
    if [[ "${SETUP_ASSUME_YES:-false}" == true ]]; then return 0; fi
    [[ -t 0 ]] || { log_error "Потрібне інтерактивне підтвердження (або SETUP_ASSUME_YES=true)"; return 1; }
    read -r -p "$1 [y/N]: " reply || return 1
    [[ "$reply" == y || "$reply" == Y ]]
}

setup_help() {
    print_header "Setup Manager $SETUP_VERSION — Допомога"
    printf '%s\n' './setup.sh' './setup.sh --version' './setup.sh packages --list' './setup.sh packages cli shell' './setup.sh packages --dry-run all' './setup.sh packages --configs-only --sync-delete --dry-run cli' './setup.sh dotfiles backup' './setup.sh dotfiles backup changed' './setup.sh dotfiles restore .zshrc' './setup.sh dotfiles status' './setup.sh dotfiles diff' './setup.sh smart --dry-run cli' './setup.sh archive create|list|restore NAME' './setup.sh recovery list|restore ID|delete ID' './setup.sh git status|log|diff' './setup.sh maintenance disk|cleanup logs|installer|dotfiles|recovery' './setup.sh maintenance --dry-run cleanup dotfiles' './setup.sh doctor' './setup.sh maintenance' './setup.sh test' './setup.sh update RELEASE.tar.gz --dry-run' './setup.sh update RELEASE.tar.gz'
}
main() {
    local cmd="${1:-}"; if (($#)); then shift; fi
    case "$cmd" in
        ''|menu) menu_main ;;
        --version|-V|version) printf '%s\n' "$SETUP_VERSION" ;;
        --help|-h|help) setup_help ;;
        packages) packages_main "$@" ;;
        dotfiles) dotfiles_main "$@" ;;
        smart) smart_main "$@" ;;
        status|verify) dotfiles_status ;;
        diff) dotfiles_diff "$@" ;;
        archive) archive_main "$@" ;;
        recovery) recovery_main "$@" ;;
        git) git_main "$@" ;;
        doctor) doctor_main ;;
        maintenance) maintenance_main "$@" ;;
        update) setup_update "$@" ;;
        test) bash "$ROOT_DIR/tests/run-tests.sh" ;;
        *) log_error "Невідома команда: $cmd"; setup_help; return 2 ;;
    esac
}
main "$@"
