#!/usr/bin/env bash
# Smart Copy: не копіюємо однаковий вміст і не робимо зайвий backup.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/dotfiles/.config/starship" "$TMP/home/.config/starship"
printf 'same\n' > "$TMP/dotfiles/.config/starship/config.toml"
cp "$TMP/dotfiles/.config/starship/config.toml" "$TMP/home/.config/starship/config.toml"
chmod 600 "$TMP/home/.config/starship/config.toml"
touch -t 202001010000 "$TMP/home/.config/starship/config.toml"
export TEST_ROOT="$ROOT" TEST_TMP="$TMP" HOME="$TMP/home" NO_COLOR=1
bash -c '
set -Eeuo pipefail
ROOT_DIR="$TEST_ROOT/install-packages"
DOTFILES_DIR="$TEST_TMP/dotfiles"
BACKUP_ROOT="$TEST_TMP/backups"
DRY_RUN=false CONFIG_BACKUP=true SYNC_DELETE=false STRICT_CONFIGS=true INSTALL_CONFIGS=true
source "$TEST_ROOT/lib/ui.sh"
source "$ROOT_DIR/lib/common.sh"
source "$TEST_ROOT/lib/core.sh"
source "$ROOT_DIR/lib/configs.sh"
copy_config_path home .config/starship .config/starship starship
' > "$TMP/unchanged.log"
grep -Fq 'вже синхронізовано, пропускаю.' "$TMP/unchanged.log"
[[ ! -e "$TMP/backups" ]]
[[ "$(cat "$TMP/home/.config/starship/config.toml")" == same ]]

printf 'updated\n' > "$TMP/dotfiles/.config/starship/config.toml"
bash -c '
set -Eeuo pipefail
ROOT_DIR="$TEST_ROOT/install-packages"
DOTFILES_DIR="$TEST_TMP/dotfiles"
BACKUP_ROOT="$TEST_TMP/backups"
DRY_RUN=true CONFIG_BACKUP=true SYNC_DELETE=false STRICT_CONFIGS=true INSTALL_CONFIGS=true
source "$TEST_ROOT/lib/ui.sh"
source "$ROOT_DIR/lib/common.sh"
source "$TEST_ROOT/lib/core.sh"
source "$ROOT_DIR/lib/configs.sh"
copy_config_path home .config/starship .config/starship starship
' > "$TMP/dry.log"
grep -Fq 'буде скопійовано' "$TMP/dry.log"
[[ ! -e "$TMP/backups" ]]
[[ "$(cat "$TMP/home/.config/starship/config.toml")" == same ]]

bash -c '
set -Eeuo pipefail
ROOT_DIR="$TEST_ROOT/install-packages"
DOTFILES_DIR="$TEST_TMP/dotfiles"
BACKUP_ROOT="$TEST_TMP/backups"
DRY_RUN=false CONFIG_BACKUP=true SYNC_DELETE=false STRICT_CONFIGS=true INSTALL_CONFIGS=true
source "$TEST_ROOT/lib/ui.sh"
source "$ROOT_DIR/lib/common.sh"
source "$TEST_ROOT/lib/core.sh"
source "$ROOT_DIR/lib/configs.sh"
copy_config_path home .config/starship .config/starship starship
' > "$TMP/changed.log"
[[ "$(cat "$TMP/home/.config/starship/config.toml")" == updated ]]
compgen -G "$TMP/backups/*/home/.config/starship/config.toml" >/dev/null
if grep -q '^\.d..t' "$TMP/changed.log"; then
    printf '[FAIL] Сирий rsync-вивід у Smart Copy\n' >&2
    exit 1
fi
printf '[PASS] Smart Copy: однакові/змінені, backup та dry-run\n'
