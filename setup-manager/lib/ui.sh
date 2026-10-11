#!/usr/bin/env bash
# ============================================================
# SETUP MANAGER — ЄДИНІ КОЛЬОРИ ТА ПОВІДОМЛЕННЯ
# Підключати через source у всіх трьох точках входу.
# ============================================================
# Кольори визначаємо незалежно для stdout та stderr.
# SETUP_COLOR=auto (типово) — лише для TTY.
# SETUP_COLOR=always — кольори навіть у pipe/redirect (для діагностики).
# SETUP_COLOR=never — повністю без кольорів.
# NO_COLOR і TERM=dumb мають пріоритет: вимикають ANSI.
_ui_color_enabled() {
    local fd="$1"
    local mode="${SETUP_COLOR:-auto}"

    if [[ -n "${NO_COLOR:-}" || "${TERM:-dumb}" == dumb ]]; then
        return 1
    fi

    case "$mode" in
        always) return 0 ;;
        never) return 1 ;;
        auto | '') [[ -t "$fd" ]] ;;
        *) [[ -t "$fd" ]] ;;
    esac
}

if _ui_color_enabled 1; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    MAGENTA=$'\033[0;35m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    BOLD=''
    NC=''
fi

if _ui_color_enabled 2; then
    _UI_STDERR_RED=$'\033[0;31m'
    _UI_STDERR_YELLOW=$'\033[1;33m'
    _UI_STDERR_NC=$'\033[0m'
else
    _UI_STDERR_RED=''
    _UI_STDERR_YELLOW=''
    _UI_STDERR_NC=''
fi

_ui_emit() {
    local level="$1"
    local color="$2"
    local stream="$3"
    shift 3

    local message="$*"

    if [[ "$stream" == stderr ]]; then
        printf '%s[%s]%s %s\n' "$_UI_STDERR_RED" "$level" "$_UI_STDERR_NC" "$message" >&2
    else
        printf '%s[%s]%s %s\n' "$color" "$level" "$NC" "$message"
    fi

    # Журнал необов'язковий. Помилка запису не повинна переривати
    # встановлення або маскувати початкове повідомлення.
    # Не викликаємо log_warn тут, щоб не спричинити рекурсію sink.
    if declare -F _setup_log_sink >/dev/null; then
        if ! _setup_log_sink "$level" "$message"; then
            printf '%s[WARN]%s Не вдалося записати повідомлення до журналу Setup Manager.\n' \
                "$_UI_STDERR_YELLOW" "$_UI_STDERR_NC" >&2
        fi
    fi
}

log_info() {
    _ui_emit INFO "$BLUE" stdout "$@"
}
log_ok() {
    _ui_emit OK "$GREEN" stdout "$@"
}
log_warn() {
    _ui_emit WARN "$YELLOW" stdout "$@"
}
log_error() {
    _ui_emit ERROR "$RED" stderr "$@"
}
log_step() {
    _ui_emit STEP "$MAGENTA" stdout "$@"
}
log_debug() {
    if [[ "${VERBOSE:-false}" == true ]]; then
        _ui_emit DEBUG "$CYAN" stdout "$@"
    fi
}

print_header() {
    printf '\n%s%s============================================%s\n' "$CYAN" "$BOLD" "$NC"
    printf '%s%s           %s%s\n' "$CYAN" "$BOLD" "$*" "$NC"
    printf '%s%s============================================%s\n' "$CYAN" "$BOLD" "$NC"
}
