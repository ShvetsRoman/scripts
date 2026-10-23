#!/usr/bin/env bash
# Єдина ініціалізація головного процесу Setup Manager.

bootstrap_root() {
    ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
    readonly ROOT_DIR
    [[ ! -L "$ROOT_DIR" ]] || {
        printf '[ERROR] ROOT_DIR не може бути symlink\n' >&2
        return 1
    }
}

bootstrap_modules() {
    # shellcheck source=path.sh
    source "$ROOT_DIR/src/core/path.sh"
    # shellcheck source=../config/setup.conf
    source "$(path_setup_conf)"
    # shellcheck source=version.sh
    source "$(path_project src/core/version.sh)"
    local module
    for module in \
        src/core/ui src/core/lock src/core/fs \
        src/dotfiles/apply src/recovery/system_restore src/dotfiles/backups \
        src/dotfiles/sources src/dotfiles/sources_seed src/dotfiles/sync \
        src/packages/registry src/packages/packages_validation src/packages/packages \
        src/packages/configs src/hooks/hooks \
        src/recovery/archive src/recovery/recovery \
        src/core/maintenance src/diagnostics/doctor src/diagnostics/reports src/core/update src/cli/menu src/cli/cli; do
        # shellcheck source=/dev/null
        source "$(path_project "$module.sh")"
    done
}

bootstrap_runtime() {
    # Параметри CLI розбираються один раз, перш ніж відкривається журнал.
    cli_parse "$@"
    SETUP_RUN_ID="$(date +%Y%m%dT%H%M%S)-$$"
    export SETUP_RUN_ID
    if [[ "${DRY_RUN:-false}" != true && -z "${SETUP_LOG_FILE:-}" && -w "$ROOT_DIR" ]]; then
        SETUP_LOG_FILE="$(path_logs)/setup-$(date +%Y%m%d).log"
        mkdir -p -- "$(dirname -- "$SETUP_LOG_FILE")"
        : >> "$SETUP_LOG_FILE" || SETUP_LOG_FILE=''
    fi
    export SETUP_LOG_FILE
}

# Підтвердження із загальним станом CLI.
setup_confirm() {
    local reply
    [[ "${SETUP_ASSUME_YES:-false}" == true ]] && return 0
    [[ -t 0 ]] || { log error 'Потрібне інтерактивне підтвердження (або --yes)'; return 1; }
    read -r -p "$1 [y/N]: " reply || return 1
    [[ "$reply" == [yY] ]]
}

bootstrap_main() {
    bootstrap_root || return 1
    bootstrap_modules
    bootstrap_runtime "$@"

    # Doctor збирає всі доступні помилки; інші команди блокуються до змін.
    if [[ "${CLI_ARGS[0]:-}" == doctor ]]; then
        SETUP_PACKAGES_SYNTAX_REPORT="$(mktemp)"
        trap 'rm -f -- "$SETUP_PACKAGES_SYNTAX_REPORT"' EXIT
        packages_load "$(path_package_conf)" --collect 2> "$SETUP_PACKAGES_SYNTAX_REPORT" || :
    else
        packages_load "$(path_package_conf)" || return 2
    fi
    cli_dispatch "${CLI_ARGS[@]}"
}
