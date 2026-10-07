#!/usr/bin/env bash

# ============================================================
# ЗАГАЛЬНІ ДОПОМІЖНІ ФУНКЦІЇ
# ============================================================

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${MAGENTA}[STEP]${NC} $*"; }

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "============================================"
    echo " $*"
    echo "============================================"
    echo -e "${NC}"
}

error_handler() {
    local exit_code="$1"
    local line="$2"
    log_error "Помилка у рядку $line. Код завершення: $exit_code"
}

require_arch() {
    if [[ ! -f /etc/arch-release ]]; then
        log_error "Installer Packages V1.6 призначений для Arch Linux."
        exit 1
    fi
}

require_non_root() {
    if ((EUID == 0)); then
        log_error "Не запускай installer від root. Запускай звичайним користувачем; sudo буде викликано автоматично."
        exit 1
    fi
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        log_error "Не знайдено необхідну команду: $command_name"
        exit 1
    fi
}

confirm() {
    local message="${1:-Продовжити?}"

    if [[ "$ASSUME_YES" == true ]]; then
        return 0
    fi

    local answer
    read -r -p "$message [y/N]: " answer
    [[ "$answer" =~ ^[YyТт]$ ]]
}

pause() {
    [[ "$ASSUME_YES" == true ]] && return 0

    echo
    read -r -p "Натисни Enter для продовження..." _
}

# ------------------------------------------------------------
# Виконання команди з підтримкою --dry-run.
# ------------------------------------------------------------
run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '[DRY-RUN]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

# ------------------------------------------------------------
# Ініціалізація журналу поточного запуску.
# ------------------------------------------------------------
init_logging() {
    [[ "$LOG_ENABLED" == true ]] || return 0
    [[ "$DRY_RUN" == true ]] && return 0

    mkdir -p "$LOG_ROOT"

    local timestamp
    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    LOG_FILE="$LOG_ROOT/run-$timestamp.log"

    # Весь подальший stdout/stderr одночасно показуємо в терміналі
    # та записуємо у файл журналу.
    exec > >(tee -a "$LOG_FILE") 2>&1

    log_info "Журнал: $LOG_FILE"
}
