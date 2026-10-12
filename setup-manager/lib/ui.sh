#!/usr/bin/env bash
# Один UI для всіх команд. Пишемо журнал без ANSI-кодів.
_ui_color() {
    [[ -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]] || return 1
    case "${SETUP_COLOR:-auto}" in
        always) return 0 ;;
        never) return 1 ;;
        *) [[ -t "$1" ]] ;;
    esac
}
_UI_OUT_NC='' _UI_ERR_NC=''
if _ui_color 1; then
    BLUE=$'\033[0;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; MAGENTA=$'\033[0;35m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'
else BLUE=''; GREEN=''; YELLOW=''; MAGENTA=''; CYAN=''; NC=''; fi
if _ui_color 2; then ERROR_COLOR=$'\033[0;31m'; ERROR_NC=$'\033[0m'; else ERROR_COLOR=''; ERROR_NC=''; fi
_ui_emit() {
    local level="$1" color="$2" stream="$3"; shift 3
    local message="$*"
    if [[ "$stream" == stderr ]]; then
        printf '%s[%s]%s %s\n' "$color" "$level" "$ERROR_NC" "$message" >&2
    else
        printf '%s[%s]%s %s\n' "$color" "$level" "$NC" "$message"
    fi
    if [[ -n "${SETUP_LOG_FILE:-}" ]]; then
        if ! printf '[%s] %s\n' "$level" "$message" >> "$SETUP_LOG_FILE"; then
            printf '[WARN] Запис до журналу не вдався.\n' >&2
        fi
    fi
}
log_info()  { _ui_emit INFO "$BLUE" stdout "$@"; }
log_ok()    { _ui_emit OK "$GREEN" stdout "$@"; }
log_warn()  { _ui_emit WARN "$YELLOW" stdout "$@"; }
log_error() { _ui_emit ERROR "$ERROR_COLOR" stderr "$@"; }
log_step()  { _ui_emit STEP "$MAGENTA" stdout "$@"; }
log_debug() { if [[ "${SETUP_VERBOSE:-false}" == true ]]; then _ui_emit DEBUG "$CYAN" stdout "$@"; fi; }
print_header() { printf '\n%s=== %s ===%s\n' "$CYAN" "$*" "$NC"; }

# Статуси порівняння: лише один префікс, без дублювання [OK] [OK].
log_state() {
    local state="$1" color
    shift
    case "$state" in
        OK) color="$GREEN" ;;
        CHANGED|DEL) color="$YELLOW" ;;
        NEW) color="$BLUE" ;;
        *) log_error "Невідомий статус: $state"; return 2 ;;
    esac
    _ui_emit "$state" "$color" stdout "$@"
}
