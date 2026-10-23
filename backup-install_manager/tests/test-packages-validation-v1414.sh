#!/usr/bin/env bash
# Перевірка єдиного валідатора та його зв'язку з Doctor.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/core/path.sh
source "$ROOT_DIR/src/core/path.sh"
# shellcheck source=../src/packages/registry.sh
source "$ROOT_DIR/src/packages/registry.sh"
# shellcheck source=../src/dotfiles/sources.sh
source "$ROOT_DIR/src/dotfiles/sources.sh"
# shellcheck source=../src/packages/packages_validation.sh
source "$ROOT_DIR/src/packages/packages_validation.sh"
# shellcheck source=../src/diagnostics/doctor.sh
source "$ROOT_DIR/src/diagnostics/doctor.sh"
log() { :; }
packages_load "$ROOT_DIR/config/packages.conf"
sources_load
packages_validate_references
# Doctor має викликати єдиний валідатор, а не дублювати його правила.
declare -f doctor_main | grep -Fq 'packages_validate_references'
! declare -F doctor_packages_validate >/dev/null
PACKAGE_CONFIGS_GROUP[base]='unknown_group_v1414'
if packages_validate_references; then exit 1; fi
packages_load "$ROOT_DIR/config/packages.conf"
PACKAGE_CONFIGS[base]='unknown_config_v1414'
if packages_validate_references; then exit 1; fi
packages_load "$ROOT_DIR/config/packages.conf"
PACKAGE_AUR[base]="${PACKAGE_PACMAN[base]%% *}"
if packages_validate_references; then exit 1; fi
printf '[PASS] test-packages-validation-v1414\n'
