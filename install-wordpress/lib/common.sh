#!/usr/bin/env bash

if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly MAGENTA='\033[0;35m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly MAGENTA=''
    readonly BOLD=''
    readonly NC=''
fi

log_info()    { printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$*"; }
log_success() { printf '%b[OK]%b %s\n' "$GREEN" "$NC" "$*"; }
log_warning() { printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
log_error()   { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2; }
log_step()    { printf '%b[STEP]%b %s\n' "$MAGENTA" "$NC" "$*"; }

die() {
    log_error "$*"
    exit 1
}

print_banner() {
    printf '%b' "$BOLD"
    cat <<EOF

============================================================
 WordPress Production Stack Installer
 Version ${VERSION}
 Traefik + Nginx + PHP-FPM + MySQL
============================================================

EOF
    printf '%b' "$NC"
}

generate_password() {
    openssl rand -hex 24
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    local command_name="$1"

    if ! command_exists "$command_name"; then
        die "Не знайдено команду: $command_name"
    fi
}

create_dir() {
    local path="$1"
    local mode="${2:-0750}"

    mkdir -p -- "$path"
    chmod "$mode" "$path"
}

handle_error() {
    local line="$1"
    local command="$2"
    local exit_code="$3"

    log_error "Помилка виконання."
    log_error "Рядок: $line"
    log_error "Команда: $command"
    log_error "Exit code: $exit_code"
}

cleanup() {
    :
}
