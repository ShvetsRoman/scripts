#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/packages/registry.sh
source "$ROOT_DIR/src/core/path.sh"
source "$ROOT_DIR/src/packages/registry.sh"
# shellcheck source=../src/dotfiles/sources.sh
source "$ROOT_DIR/src/dotfiles/sources.sh"
# shellcheck source=../src/packages/packages_validation.sh
source "$ROOT_DIR/src/packages/packages_validation.sh"
log() { :; }
path_ok_abs() { [[ "$1" == /* ]]; }
path_ok_rel() { [[ -n "$1" && "$1" != /* ]]; }
path_syntax_abs() { [[ "$1" == /* ]]; }
packages_load "$ROOT_DIR/config/packages.conf"
# Тестуємо реальні назви з dotfiles.conf без виконання системних операцій.
sources_load
packages_validate_references
# Невідомий конфіг повинен бути помилкою.
PACKAGE_CONFIGS[shell]='nonexistent_config_1234'
if packages_validate_references; then exit 1; fi
packages_load "$ROOT_DIR/config/packages.conf"
# Один пакет одночасно в pacman та AUR має бути помилкою.
PACKAGE_AUR[shell]='zsh'
if packages_validate_references; then exit 1; fi
# Дублікати в списках мають відхилятися ще під час завантаження INI.
tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT
printf '[test]\ntitle = Test\npacman = zsh zsh\n' > "$tmp"
if (packages_load "$tmp") 2>/dev/null; then exit 1; fi
printf '[test]\ntitle = Test\nhooks = snapper snapper\n' > "$tmp"
if (packages_load "$tmp") 2>/dev/null; then exit 1; fi
printf '[PASS] test-packages-doctor-v141\n'
