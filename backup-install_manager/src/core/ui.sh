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

# Ініціалізуємо палітру після обробки --no-color у cli_parse().
# Для tty — кольори, для pipe/redirect і NO_COLOR — звичайний текст.
ui_init_colors() {
    if _ui_tty 1; then
        C_INFO=$'\033[0;34m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[1;33m'
        C_STEP=$'\033[0;35m'; C_HEAD=$'\033[0;36m'; C_OFF=$'\033[0m'
        C_NEW=$'\033[1;36m'; C_CHANGED=$'\033[1;33m'; C_DEL=$'\033[1;31m'
        C_SKIP=$'\033[0;90m'
    else
        C_INFO=''; C_OK=''; C_WARN=''; C_STEP=''; C_HEAD=''; C_OFF=''
        C_NEW=''; C_CHANGED=''; C_DEL=''; C_SKIP=''
    fi
    if _ui_tty 2; then
        C_ERR=$'\033[0;31m'; C_ERR_OFF=$'\033[0m'
    else
        C_ERR=''; C_ERR_OFF=''
    fi
}

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
        state)
            stream=stdout; label="$1"; shift
            case "$label" in
                OK)                  color="$C_OK" ;;
                NEW|COPY)            color="$C_NEW" ;;
                CHANGED|UPDATE)      color="$C_CHANGED" ;;
                DEL|DELETE|MISSING)  color="$C_DEL" ;;
                SKIP|KEEP_EXTRA)     color="$C_SKIP" ;;
                *)                   color="$C_HEAD" ;;
            esac ;;
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
    if [[ -n "${SETUP_LOG_FILE:-}" && -d "$(dirname -- "$SETUP_LOG_FILE")" ]]; then
        printf '[%s] [pid=%s] [run=%s] [%s] %s\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$$" "${SETUP_RUN_ID:-manual}" \
            "$label" "$*" >> "$SETUP_LOG_FILE" 2>/dev/null || true
    fi
}

# Запускає Python-перевірку recovery та виводить її статуси через спільний log().
# Зберігає оригінальний код завершення (зокрема 3 для legacy recovery).
recovery_helper_run() {
    local helper="$1" output line level rc=0
    shift
    output="$(python3 "$helper" "$@" 2>&1)" || rc=$?
    [[ -n "$output" ]] || return "$rc"
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            '[OK] '*)    level=ok;    line="${line#'[OK] '}" ;;
            '[WARN] '*)  level=warn;  line="${line#'[WARN] '}" ;;
            '[ERROR] '*) level=error; line="${line#'[ERROR] '}" ;;
            *) if (( rc != 0 )); then level=error; else level=info; fi ;;
        esac
        log "$level" "$line"
    done <<< "$output"
    return "$rc"
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

# Очищення екрана лише в інтерактивних сценаріях, але не під час тестів.
ui_clear() {
    [[ "${SETUP_TEST_MODE:-false}" == true || "${SETUP_NO_CLEAR:-false}" == true ]] && return 0
    clear 2>/dev/null || true
}

# Перегляд журналу поточного дня (без змін файлів).
logs_main() {
    local action="${1:-path}" file="${SETUP_LOG_FILE:-$(path_logs)/setup-$(date +%Y%m%d).log}"
    case "$action" in
        path) printf '%s\n' "$file" ;;
        tail)
            local n="${2:-50}"
            [[ "$n" =~ ^[0-9]{1,4}$ ]] && (( 10#$n > 0 )) || {
                log error 'N повинно бути цілим числом від 1 до 9999'; return 2;
            }
            path_ok_abs "$file" || { log error 'Небезпечний log-файл'; return 2; }
            [[ -f "$file" ]] || { log info 'Журнал порожній'; return 0; }
            tail -n "$((10#$n))" -- "$file" ;;
        *) log error 'logs path|tail [N]'; return 2 ;;
    esac
}
