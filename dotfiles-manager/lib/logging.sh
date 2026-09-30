#!/usr/bin/env bash

readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

log_info() {
    printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$*"
}

log_success() {
    printf '%b[OK]%b %s\n' "$GREEN" "$NC" "$*"
}

log_warning() {
    printf '%b[WARNING]%b %s\n' "$YELLOW" "$NC" "$*"
}

log_error() {
    printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2
}

log_debug() {
    if [[ "${VERBOSE:-false}" == true ]]; then
        printf '%b[DEBUG]%b %s\n' "$CYAN" "$NC" "$*"
    fi
}

log_step() {
    printf '%b[STEP]%b %s\n' "$MAGENTA" "$NC" "$*"
}
