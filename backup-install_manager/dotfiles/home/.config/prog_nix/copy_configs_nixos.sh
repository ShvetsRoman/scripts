#!/usr/bin/env bash
set -Eeuo pipefail

# КОЛЬОРИ
readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'
 
# LOGGING
log_info() { echo -e "\n${BLUE}[INFO]${NC} $1\n"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1\n"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1\n"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
 
log_info "Резервне копіювання nixos configs..."
if [[ -d "/etc/nixos" ]]; then
    cp /etc/nixos/* "${HOME}"/00_setup/scripts_bash/inst/prog_nix/conf_nix/etc_nixos/
    log_success "Копіювання закінчене nixos configs..."
else
    log_error "Папки nixos не має !!!"
fi
