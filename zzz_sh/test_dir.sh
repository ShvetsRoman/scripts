#!/usr/bin/env bash

set -Eeuo pipefail

# Кольори
readonly RED='\033[31m'
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly BLUE='\033[34m'
readonly CYAN='\033[36m'
readonly NC='\033[0m'

# LOGGING
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }   # FIX: warnings → stderr
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }        # FIX: errors → stderr

log_title() {
    echo
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

readonly LOCAL_DIR_1="$HOME/test_1"
readonly LOCAL_DIR_2="$HOME/test_2"


readonly BACKUP_DIRS=(
    "00_setup"
    "01_project"
    "03_work"
    "Documents"
    "Music"
    "Pictures"
    "Videos"
)

# Тоді виклик:
# mk_dirs "$LOCAL_DIR" BACKUP_DIRS
mk_dirs() {
    # $1 — базовий каталог
    # $2 — ім'я масиву
    local base_dir="$1"
    local -n dirs="$2"

    for dir in "${dirs[@]}"; do
        local target="$base_dir/$dir"
        if [[ ! -d "$target" ]]; then
            log_error "Каталог не існує: $target"
            mkdir -p "$target"
            log_success "Створено: $target"
        else
            log_info "Каталог ІСНУЄ: $target"
        fi
    done
}

mk_dirs "$LOCAL_DIR_1" BACKUP_DIRS
mk_dirs "$LOCAL_DIR_2" BACKUP_DIRS
