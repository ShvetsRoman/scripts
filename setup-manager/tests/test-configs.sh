#!/usr/bin/env bash
# Регресійна перевірка встановлення конфігів незалежно від HOME користувача.
set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_TEST="$(mktemp -d)"
trap 'rm -rf -- "${TMP_TEST:?}"' EXIT
ROOT_DIR="$TMP_TEST/project"
HOME="$TMP_TEST/home"
mkdir -p "$ROOT_DIR/dotfiles/.config" "$HOME/.config"
# shellcheck source=../lib/ui.sh
source "$PROJECT_ROOT/lib/ui.sh"
# shellcheck source=../lib/core.sh
source "$PROJECT_ROOT/lib/core.sh"
# shellcheck source=../lib/configs.sh
source "$PROJECT_ROOT/lib/configs.sh"
DRY_RUN=false
SETUP_BACKUP_ENABLED=false
STRICT_CONFIGS=false
entry='sample|home|.config/sample|.config/sample'
output="$(configs_install "$entry")"
[[ "$output" == *'не знайдено'* ]] || { printf '[FAIL] Відсутнє джерело не розпізнано\n' >&2; exit 1; }
[[ ! -e "$HOME/.config/sample" ]] || { printf '[FAIL] Створено неіснуючий конфіг\n' >&2; exit 1; }
printf 'first\n' > "$ROOT_DIR/dotfiles/.config/sample"
printf 'first\n' > "$HOME/.config/sample"
output="$(configs_install "$entry")"
[[ "$output" == *'вже синхронізовано'* ]] || { printf '[FAIL] Однаковий вміст не пропущено\n' >&2; exit 1; }
printf 'changed\n' > "$ROOT_DIR/dotfiles/.config/sample"
DRY_RUN=true
output="$(configs_install "$entry")"
[[ "$output" == *'[DRY-RUN]'* ]] || { printf '[FAIL] Dry-run не повідомив про копіювання\n' >&2; exit 1; }
[[ "$(cat "$HOME/.config/sample")" == first ]] || { printf '[FAIL] Dry-run змінив HOME\n' >&2; exit 1; }
DRY_RUN=false
output="$(configs_install "$entry")"
[[ "$output" == *'скопійовано'* ]] || { printf '[FAIL] Копіювання не підтверджено\n' >&2; exit 1; }
[[ "$(cat "$HOME/.config/sample")" == changed ]] || { printf '[FAIL] Не скопійовано новий вміст\n' >&2; exit 1; }
printf '[PASS] Configs: missing / equal / changed / dry-run\n'
