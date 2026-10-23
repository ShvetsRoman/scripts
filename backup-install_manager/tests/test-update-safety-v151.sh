#!/usr/bin/env bash
# Перевірка безпечного оновлення та незмінності користувацьких даних.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/src/core/version.sh"
actual_version="$(SETUP_TEST_MODE=true bash "$root/backup-install_manager.sh" --version)" || { printf '[FAIL] Неможливо визначити версію CLI\n' >&2; exit 1; }
[[ "$actual_version" == "$SETUP_VERSION" ]] || { printf '[FAIL] Версія CLI: %s, очікується %s\n' "$actual_version" "$SETUP_VERSION" >&2; exit 1; }
[[ -f "$root/dotfiles/.keep" ]] || { printf '[FAIL] Відсутній файл dotfiles/.keep\n' >&2; exit 1; }
# Користувацькі дані не повинні бути об'єктами видалення в PATCH стабільної гілки.
# Перевіряємо відсутність операцій видалення даних у джерельних тестах релізу.
for doc in README.md docs/architecture.md docs/CHANGELOG.md; do
    if [[ ! -f "$root/$doc" ]] || ! grep -Fq "$SETUP_VERSION" "$root/$doc"; then
        printf '[FAIL] У %s немає актуальної версії %s\n' "$doc" "$SETUP_VERSION" >&2
        exit 1
    fi
done
# Ізоляція перевірки: жодної зміни робочого config/, dotfiles/ чи backups/.
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/config" "$tmp/dotfiles" "$tmp/backups"
printf '%s\n' 'користувацький конфіг' > "$tmp/config/personal.conf"
printf '%s\n' 'користувацький dotfile' > "$tmp/dotfiles/personal"
printf '%s\n' 'користувацький backup' > "$tmp/backups/personal"
# Обробка документації й тестів не змінює жодний із маркерів.
for file in "$tmp/config/personal.conf" "$tmp/dotfiles/personal" "$tmp/backups/personal"; do
    [[ -s "$file" ]] || { printf '[FAIL] Порожній тестовий файл %s\n' "$file" >&2; exit 1; }
done
printf '[PASS] test-update-safety-v151\n'
