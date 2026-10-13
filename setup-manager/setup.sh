#!/usr/bin/env bash
# Setup Manager — єдина точка входу.
set -Eeuo pipefail
umask 077

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
[[ -L "$ROOT_DIR" ]] && { printf '[ERROR] ROOT_DIR не може бути symlink\n' >&2; exit 1; }

# shellcheck source=config/setup.conf
source "$ROOT_DIR/config/setup.conf"

for lib in ui path fs apply sources sources_seed sync registry packages configs hooks \
           archive recovery maintenance doctor update menu cli; do
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/$lib.sh"
done

DRY_RUN=false

# Журнал за замовчуванням.
if [[ -z "${SETUP_LOG_FILE:-}" && -w "$ROOT_DIR" ]]; then
    SETUP_LOG_FILE="$ROOT_DIR/logs/setup-$(date +%Y%m%d).log"
    mkdir -p -- "$(dirname -- "$SETUP_LOG_FILE")"
    : >> "$SETUP_LOG_FILE" || SETUP_LOG_FILE=''
fi
export SETUP_LOG_FILE

# setup_confirm — універсальне підтвердження.
setup_confirm() {
    local reply
    [[ "${SETUP_ASSUME_YES:-false}" == true ]] && return 0
    [[ -t 0 ]] || { log error 'Потрібне інтерактивне підтвердження (або --yes)'; return 1; }
    read -r -p "$1 [y/N]: " reply || return 1
    [[ "$reply" == [yY] ]]
}

cli_dispatch "$@"
