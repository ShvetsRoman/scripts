#!/usr/bin/env bash
# ============================================================
# Universal Bash Logger (v2)
#
# Можливості:
#   - Кольоровий вивід ANSI
#   - Автоматичне визначення TTY
#   - NO_COLOR / FORCE_COLOR support
#   - LOG_COLOR: auto / always / never
#   - Рівні: TRACE / DEBUG / INFO / WARNING / ERROR / FATAL
#   - STEP / SUCCESS
#   - Опціональні часові мітки (true / false / printf-формат)
#   - Розділення stdout / stderr
#   - Безпечне відображення команд через printf %q
#   - Підтримка перенаправлення та tee
#   - Без підоболонок на гарячому шляху (bash 4.x+)
#
# Сумісність: bash 4.2+ (5.x — швидший таймстамп без форку)
#
# Підключення:
#   source "/path/to/logger.sh"
# ============================================================

# ============================================================
# ЗАХИСТ ВІД ПРЯМОГО ЗАПУСКУ / ПОВТОРНОГО ПІДКЛЮЧЕННЯ
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf 'logger.sh: цей файл треба підключати через source\n' >&2
    exit 1
fi

if [[ -n "${_LOGGER_SH_LOADED:-}" ]]; then
    return 0
fi
readonly _LOGGER_SH_LOADED=1

# ============================================================
# КОЛЬОРИ (не readonly — дозволяємо перевизначення палітри)
# ============================================================
BLUE=${BLUE:-$'\033[0;34m'}
GREEN=${GREEN:-$'\033[0;32m'}
YELLOW=${YELLOW:-$'\033[1;33m'}
RED=${RED:-$'\033[0;31m'}
CYAN=${CYAN:-$'\033[0;36m'}
MAGENTA=${MAGENTA:-$'\033[0;35m'}
BOLD=${BOLD:-$'\033[1m'}
NC=${NC:-$'\033[0m'}

# ============================================================
# НАЛАШТУВАННЯ ЗА ЗАМОВЧУВАННЯМ
# ============================================================
# Рівень: TRACE / DEBUG / INFO / WARNING / ERROR / FATAL
# Порожній = INFO (або DEBUG, якщо VERBOSE=true)
: "${LOG_LEVEL:=}"

# Режим кольорів: auto / always / never
: "${LOG_COLOR:=auto}"

# Часові мітки:
#   false         — вимкнено
#   true          — [%Y-%m-%d %H:%M:%S]
#   <printf-формат> — напр. '%H:%M:%S' або '%F %T'
: "${LOG_TIMESTAMP:=false}"

# Діагностика
: "${VERBOSE:=false}"

# ============================================================
# ВНУТРІШНІ КОНСТАНТИ (асоціативний масив — без підоболонок)
# ============================================================
declare -gA _LOG_LEVELS=(
    [TRACE]=10
    [DEBUG]=20
    [INFO]=30
    [WARNING]=40
    [ERROR]=50
    [FATAL]=60
)

# Ефективний мінімальний рівень (обчислюється один раз при старті)
if [[ -n "${LOG_LEVEL:-}" ]]; then
    _LOG_MIN_LEVEL=${_LOG_LEVELS[${LOG_LEVEL^^}]:-30}
else
    if [[ "${VERBOSE:-false}" == true ]]; then
        _LOG_MIN_LEVEL=20 # DEBUG
    else
        _LOG_MIN_LEVEL=30 # INFO
    fi
fi

# ============================================================
# ПЕРЕВІРКА ПІДТРИМКИ КОЛЬОРІВ
# ============================================================
_log_use_color() {
    local fd="$1"

    # FORCE_COLOR (CI) — найвищий пріоритет
    if [[ -n "${FORCE_COLOR:-}" ]]; then
        return 0
    fi

    # NO_COLOR — вимикає кольори
    if [[ -n "${NO_COLOR:-}" ]]; then
        return 1
    fi

    case "${LOG_COLOR:-auto}" in
        never)
            return 1
            ;;
        always)
            return 0
            ;;
        auto | *)
            [[ "${TERM:-}" != dumb ]] && [[ -t "$fd" ]]
            return
            ;;
    esac
}

# ============================================================
# ФОРМУВАННЯ ЧАСОВОЇ МІТКИ
#   printf -v у змінну, без підоболонок
# ============================================================
_log_build_timestamp() {
    local __out_var="$1"
    local fmt="${LOG_TIMESTAMP:-false}"

    if [[ "$fmt" == false || -z "$fmt" ]]; then
        printf -v "$__out_var" '%s' ''
        return 0
    fi

    if [[ "$fmt" == true ]]; then
        # bash 5+: вбудований %(...)T без форку date
        if ((BASH_VERSINFO[0] >= 5)); then
            printf -v "$__out_var" '[%(%Y-%m-%d %H:%M:%S)T] ' -1
        else
            printf -v "$__out_var" '[%s] ' "$(date '+%Y-%m-%d %H:%M:%S')"
        fi
        return 0
    fi

    # Кастомний printf-формат
    if ((BASH_VERSINFO[0] >= 5)); then
        printf -v "$__out_var" "[%($fmt)T] " -1
    else
        printf -v "$__out_var" '[%s] ' "$(date "+$fmt")"
    fi
}

# ============================================================
# ОСНОВНА ФУНКЦІЯ ЛОГУВАННЯ
#   _log <level> <color> <fd> <message...>
# ============================================================
_log() {
    local level="$1"
    local color="$2"
    local fd="$3"

    # Швидка фільтрація — до побудови $*
    local cur=${_LOG_LEVELS[${level^^}]:-30}
    ((cur < _LOG_MIN_LEVEL)) && return 0

    shift 3

    local ts=""
    local reset=""

    _log_build_timestamp ts

    if _log_use_color "$fd"; then
        reset="$NC"
    else
        color=""
    fi

    printf '%s%s[%s]%s %s\n' \
        "$ts" "$color" "$level" "$reset" "$*" >&"$fd"
}

# ============================================================
# РІВНІ
# ============================================================
log_trace() { _log "TRACE" "$CYAN" 1 "$@"; }
log_debug() { _log "DEBUG" "$CYAN" 1 "$@"; }
log_info() { _log "INFO" "$BLUE" 1 "$@"; }
log_step() { _log "STEP" "$MAGENTA" 1 "$@"; }
log_success() { _log "SUCCESS" "$GREEN" 1 "$@"; }
log_warning() { _log "WARNING" "$YELLOW" 2 "$@"; }
log_error() { _log "ERROR" "$RED" 2 "$@"; }

# FATAL — лише логує. НЕ завершує скрипт (бібліотека не має вбивати процес).
log_fatal() { _log "FATAL" "${BOLD}${RED}" 2 "$@"; }

# ============================================================
# DIE — логує FATAL і завершує скрипт
#   die [код] <message...>
# ============================================================
die() {
    local code=1
    if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
        code="$1"
        shift
    fi
    log_fatal "$@"
    exit "$code"
}

# ============================================================
# TITLE — заголовок етапу
# ============================================================
log_title() {
    local line="============================================================"
    _log "STEP" "$MAGENTA" 1 "$line"
    _log "STEP" "$MAGENTA" 1 "$*"
    _log "STEP" "$MAGENTA" 1 "$line"
}

# ============================================================
# COMMAND — безпечне відображення argv (НЕ виконує)
# ============================================================
log_command() {
    if (($# == 0)); then
        log_error "log_command: не вказано команду"
        return 2
    fi

    local rendered
    printf -v rendered '%q ' "$@"
    log_info "Виконання команди: ${rendered% }"
}

# ============================================================
# ЗРУЧНІ ХЕЛПЕРИ
# ============================================================

# log_error_exit <code> <message...> — логує помилку і повертає код
log_error_exit() {
    local code="${1:-1}"
    shift || true
    log_error "$@"
    return "$code"
}

# log_assert <condition> <message...> — якщо condition != 0, логує і повертає 1
log_assert() {
    local cond="$1"
    shift || true
    if ((! cond)); then
        log_error "$@"
        return 1
    fi
    return 0
}
