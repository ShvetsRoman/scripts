#!/usr/bin/env bash
# Єдине логування.

# _ui_tty — чи підтримує потік $1 кольори.
# Враховує NO_COLOR, TERM=dumb, SETUP_COLOR=always|never|auto.
_ui_tty() {
    [[ -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]] || return 1
    case "${SETUP_COLOR:-auto}" in
        always) return 0 ;;
        never)  return 1 ;;
        *)      [[ -t "$1" ]] ;;
    esac
}

if _ui_tty 1; then
    C_INFO=$'\033[0;34m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[1;33m'
    C_STEP=$'\033[0;35m'; C_HEAD=$'\033[0;36m'; C_OFF=$'\033[0m'
else C_INFO=''; C_OK=''; C_WARN=''; C_STEP=''; C_HEAD=''; C_OFF=''; fi
if _ui_tty 2; then C_ERR=$'\033[0;31m'; C_ERR_OFF=$'\033[0m'; else C_ERR=''; C_ERR_OFF=''; fi

# log — єдина функція логування.
# Аргументи: $1 — рівень (info/ok/warn/step/error/state), далі — текст.
# Пише у stdout (info/ok/warn/step/state) або stderr (error).
# Дублює у SETUP_LOG_FILE без ANSI-кодів.
log() {
    local level="$1"; shift
    local color stream label
    case "$level" in
        info)  color="$C_INFO"; stream=stdout; label=INFO ;;
        ok)    color="$C_OK";   stream=stdout; label=OK ;;
        warn)  color="$C_WARN"; stream=stdout; label=WARN ;;
        step)  color="$C_STEP"; stream=stdout; label=STEP ;;
        error) color="$C_ERR";  stream=stderr; label=ERROR ;;
        state) color="$C_HEAD"; stream=stdout; label="$1"; shift ;;
        *)     color='';        stream=stdout; label="$level" ;;
    esac

    # A. У dry-run міняємо мітку info/ok/step на DRY-RUN (error/warn/state — без змін).
    if [[ "${DRY_RUN:-false}" == true ]]; then
        case "$level" in
            info|ok|step) label=DRY-RUN ;;
        esac
    fi
    if [[ "$stream" == stderr ]]; then
        printf '%s[%s]%s %s\n' "$color" "$label" "$C_ERR_OFF" "$*" >&2
    else
        printf '%s[%s]%s %s\n' "$color" "$label" "$C_OFF" "$*"
    fi
    if [[ -n "${SETUP_LOG_FILE:-}" ]]; then
        printf '[%s] %s\n' "$label" "$*" >> "$SETUP_LOG_FILE" 2>/dev/null || true
    fi
}

# log_info / log_ok / log_warn / log_step / log_error — обгортки для читабельності.
log_info()  { log info  "$@"; }
log_ok()    { log ok    "$@"; }
log_warn()  { log warn  "$@"; }
log_error() { log error "$@"; }
log_step()  { log step  "$@"; }

# log_state — статус порівняння: OK / CHANGED / NEW / DEL / MISSING.
log_state() { local s="$1"; shift; log state "$s" "$@"; }

# header — заголовок блоку виводу.
header() { printf '%s=== %s ===%s\n' "$C_HEAD" "$*" "$C_OFF"; }

# stage — заголовок етапу без порожнього рядка після.
stage() { printf '%s── %s ──%s
' "$C_STEP" "$*" "$C_OFF"; }
