#!/usr/bin/env bash
# Регресія форматування й безпеки dry-run без pacman/sudo/реального HOME.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/dotfiles/.config/fzf" "$TMP/home/.config/fzf" "$TMP/bin"
printf 'new\n' > "$TMP/dotfiles/.config/fzf/settings"
printf 'old\n' > "$TMP/home/.config/fzf/settings"
cat > "$TMP/bin/rsync" <<'MOCK'
#!/usr/bin/env bash
printf '[MOCK RSYNC] %s\n' "$*"
MOCK
chmod +x "$TMP/bin/rsync"
export PATH="$TMP/bin:$PATH"
export HOME="$TMP/home"
export TEST_ROOT="$ROOT" TEST_TMP="$TMP"
bash -c '
set -Eeuo pipefail
ROOT_DIR="$TEST_ROOT/install-packages"
DOTFILES_DIR="$TEST_TMP/dotfiles"
BACKUP_ROOT="$TEST_TMP/backups"
DRY_RUN=true CONFIG_BACKUP=true SYNC_DELETE=false STRICT_CONFIGS=true INSTALL_CONFIGS=true
BLUE="" GREEN="" YELLOW="" RED="" MAGENTA="" NC=""
source "$TEST_ROOT/lib/ui.sh"
    source "$ROOT_DIR/lib/common.sh"
source "$TEST_ROOT/lib/core.sh"
source "$ROOT_DIR/lib/configs.sh"
declare -A CONFIG_MAP=([fzf]="cli|home|.config/fzf|.config/fzf")
copy_config_path home .config/fzf .config/fzf fzf
' > "$TMP/output"
grep -q 'Backup конфігу: fzf' "$TMP/output"
grep -q 'Копіювання конфігу: fzf' "$TMP/output"
grep -q '\[DRY-RUN\] Конфіг: fzf буде скопійовано.' "$TMP/output"
if grep -q 'Конфіг встановлено:' "$TMP/output"; then echo 'FAIL: dry-run повідомляє про встановлення' >&2; exit 1; fi
if grep -q '\[DRY-RUN\] mkdir -p' "$TMP/output"; then echo 'FAIL: зайвий mkdir' >&2; exit 1; fi
[[ ! -e "$TMP/backups" ]]
[[ "$(cat "$TMP/home/.config/fzf/settings")" == 'old' ]]
printf '[PASS] Вивід конфігів, backup, dry-run без змін\n'
