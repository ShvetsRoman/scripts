#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_TEST="$(mktemp -d)"
trap 'rm -rf -- "${TMP_TEST:?}"' EXIT
ROOT_DIR="$TMP_TEST/project"
HOME="$TMP_TEST/home"
mkdir -p "$ROOT_DIR/dotfiles/.config/app" "$HOME/.config/app"
# shellcheck source=../lib/ui.sh
source "$PROJECT_ROOT/lib/ui.sh"
# shellcheck source=../lib/core.sh
source "$PROJECT_ROOT/lib/core.sh"
# shellcheck source=../lib/configs.sh
source "$PROJECT_ROOT/lib/configs.sh"
# Дозволяємо автоматичне підтвердження виключно в ізольованому тесті.
setup_confirm() { return 0; }
DRY_RUN=false
SYNC_DELETE=false
SETUP_BACKUP_ENABLED=true
STRICT_CONFIGS=true
entry='app|home|.config/app|.config/app'
printf 'new\n' > "$ROOT_DIR/dotfiles/.config/app/config"
printf 'old\n' > "$HOME/.config/app/config"
printf 'obsolete\n' > "$HOME/.config/app/obsolete"
# Однакові розмір і час: примусово перевірити checksum у копіюванні.
touch -r "$HOME/.config/app/config" "$ROOT_DIR/dotfiles/.config/app/config"
configs_install "$entry" >/dev/null
[[ "$(cat "$HOME/.config/app/config")" == new && -f "$HOME/.config/app/obsolete" ]] || exit 1
printf '[PASS] Звичайне копіювання зберігає зайві файли\n'
[[ -n "$(find "$ROOT_DIR/backups/installer" -type f -name obsolete -print -quit)" ]] || exit 1
printf '[PASS] Захисний backup перед копіюванням\n'
# Повертаємо старий файл та виконуємо dry-run з видаленням.
DRY_RUN=true
SYNC_DELETE=true
configs_install "$entry" >/dev/null
[[ -f "$HOME/.config/app/obsolete" ]] || exit 1
printf '[PASS] --sync-delete --dry-run не видаляє\n'
DRY_RUN=false
configs_install "$entry" >/dev/null
[[ ! -e "$HOME/.config/app/obsolete" ]] || exit 1
core_compare "$ROOT_DIR/dotfiles/.config/app" "$HOME/.config/app" || exit 1
printf '[PASS] --sync-delete видаляє зайве та забезпечує повний збіг\n'
backup_obsolete="$(find "$ROOT_DIR/backups/installer" -type f -name obsolete -print -quit)"
[[ -n "$backup_obsolete" && "$(cat "$backup_obsolete")" == obsolete ]] || exit 1
printf '[PASS] Видалений файл збережено в backup\n'
SETUP_BACKUP_ENABLED=false
if configs_install "$entry" >/dev/null 2>&1; then
    printf '[FAIL] Відсутній backup не зупинив --sync-delete\n' >&2
    exit 1
fi
printf '[PASS] --sync-delete --no-backup відхиляється\n'
