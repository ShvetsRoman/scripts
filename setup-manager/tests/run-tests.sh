#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
while IFS= read -r -d '' file; do bash -n "$file" || fail "Синтаксис $file"; done < <(find "$ROOT_DIR" -name '*.sh' -type f -print0)
pass 'Синтаксис Bash'
expected_version="$(bash -c 'source "$1/config/setup.conf"; printf "%s" "$SETUP_VERSION"' bash "$ROOT_DIR")"
[[ -n "$expected_version" && "$(bash "$ROOT_DIR/setup.sh" --version)" == "$expected_version" ]] || fail 'Номер версії'
pass 'Версія з конфігурації'
[[ "$(bash "$ROOT_DIR/setup.sh" packages --list | wc -l)" -eq 12 ]] || fail '12 модулів'
pass 'Реєстр пакетів'
bash "$ROOT_DIR/setup.sh" dotfiles --help | grep -q './setup.sh dotfiles' || fail 'Допомога dotfiles'
pass 'Єдина точка входу'
bash "$ROOT_DIR/setup.sh" packages --dry-run invalid-module >/dev/null 2>&1 && fail 'Валідація'
pass 'Невідомі модулі відхиляються'
[[ ! -e "$ROOT_DIR/.gitignore" ]] || fail '.gitignore повинен бути рівнем вище'
pass '.gitignore поза каталогом Setup Manager'
bash "$ROOT_DIR/tests/test-core.sh" || fail 'Файлове ядро'
pass 'Файлове ядро'
bash "$ROOT_DIR/tests/test-configs.sh" || fail 'Конфігурації'
pass 'Smart Copy конфігів'
bash "$ROOT_DIR/tests/test-dotfiles-status.sh" || fail 'Dotfiles Status'
bash "$ROOT_DIR/tests/test-dotfiles-sync.sh" || fail 'Dotfiles Sync'
bash "$ROOT_DIR/tests/test-sync-delete.sh" || fail 'Sync Delete'
pass 'Sync Delete'
bash "$ROOT_DIR/tests/test-maintenance.sh" || fail "Maintenance"
bash "$ROOT_DIR/tests/test-menus.sh" || fail "Меню"
pass "Maintenance"
bash "$ROOT_DIR/tests/test-features.sh" || fail 'Розширені модулі'
bash "$ROOT_DIR/tests/test-archive-collision.sh" || fail "Колізії архівів"
bash "$ROOT_DIR/tests/test-safe-update-archive.sh" || fail "Безпечне оновлення й архіви"
bash "$ROOT_DIR/tests/test-empty-lists.sh" || fail "Порожні списки" 
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' -t files < <(find "$ROOT_DIR" -name '*.sh' -type f -print0)
    shellcheck -x --source-path=SCRIPTDIR -S style "${files[@]}" || fail 'ShellCheck'
    pass 'ShellCheck'
else printf '[SKIP] ShellCheck не встановлено\n'; fi
printf '\n[PASS] Усі перевірки завершені\n'
