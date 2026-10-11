#!/usr/bin/env bash
# Регресія виводу модулів і розділення джерел пакетів.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$(mktemp)"
trap 'rm -f -- "$OUTPUT"' EXIT

# Перевіряємо заголовки без реального встановлення.
bash -c '
set -Eeuo pipefail
ROOT_DIR="$1/install-packages"
source "$ROOT_DIR/lib/menu.sh"
declare -A MODULE_TITLES=([docker]="Docker")
log_step() { printf "[STEP] %s\n" "$*"; }
log_ok() { printf "[OK] %s\n" "$*"; }
install_registered_module() { :; }
run_module docker
' _ "$ROOT" > "$OUTPUT"
grep -Fxq '[STEP] Встановлення модуля: docker — Docker' "$OUTPUT"
grep -Fxq '[OK] Завершено встановлення модуля: docker — Docker' "$OUTPUT"

# Підставляємо безпечні mock-функції, щоб перевірити порядок виводу.
bash -c '
set -Eeuo pipefail
ROOT_DIR="$1/install-packages"
source "$ROOT_DIR/lib/modules.sh"
declare -A MODULE_PACMAN_ARRAYS=([cli]="CLI_PACMAN")
declare -A MODULE_AUR_ARRAYS=([cli]="CLI_AUR")
declare -A MODULE_GITHUB_ARRAYS=([cli]="CLI_GITHUB")
CLI_PACMAN=()
CLI_AUR=()
CLI_GITHUB=(superfile)
log_info() { printf "[INFO] %s\n" "$*"; }
log_step() { printf "[STEP] %s\n" "$*"; }
log_error() { printf "[ERROR] %s\n" "$*"; }
install_pacman() { :; }
install_paru() { :; }
install_github_package() { printf "[INFO] %s вже встановлено.\n" "$1"; }
install_module_packages cli
' _ "$ROOT" > "$OUTPUT"
grep -Fxq '[INFO] AUR-пакетів для модуля немає.' "$OUTPUT"
grep -Fxq '[STEP] Перевірка та встановлення зовнішніх/GitHub-програм:' "$OUTPUT"
grep -Fxq '[INFO] superfile вже встановлено.' "$OUTPUT"
python - "$OUTPUT" <<'PYTEST'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert s.index('AUR-пакетів') < s.index('зовнішніх/GitHub-програм:') < s.index('superfile вже встановлено.')
PYTEST
printf '[PASS] Заголовки модулів і розділення AUR/GitHub\n'
