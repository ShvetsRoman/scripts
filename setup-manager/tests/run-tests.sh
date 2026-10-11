#!/usr/bin/env bash
# Локальні регресійні тести без встановлення програм і запису в $HOME.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
if bash -n "$ROOT/setup.sh"; then
    pass 'Синтаксис setup.sh'
else
    fail 'Синтаксис'
fi
if bash "$ROOT/setup.sh" --help | grep -q 'Smart Setup'; then
    pass 'Довідка'
else
    fail 'Довідка'
fi
if [[ -f "$ROOT/install-packages/modules/cli.sh" ]]; then
    pass 'Модулі'
else
    fail 'Модулі'
fi
if [[ -f "$ROOT/dotfiles-manager/config/dotfiles.conf" ]]; then
    pass 'Окремий реєстр dotfiles'
else
    fail 'Реєстр'
fi
if [[ -f "$ROOT/install-packages/config/installer.conf" ]]; then
    pass 'Окремий реєстр installer'
else
    fail 'Реєстр'
fi
if bash "$ROOT/setup.sh" smart --dry-run no_such_module >/dev/null 2>&1; then
    fail 'Валідація невідомих модулів'
else
    pass 'Валідація невідомих модулів'
fi
if bash "$ROOT/setup.sh" status not_a_component >/dev/null 2>&1; then
    fail 'Валідація підсистем'
else
    pass 'Валідація підсистем'
fi

if bash "$ROOT/tests/test-core.sh"; then
    pass "Спільний backup/restore core"
else
    fail "Unified core"
fi

if bash "$ROOT/tests/test-output.sh"; then
    pass "Формат виводу та dry-run"
else
    fail "Вивід dry-run"
fi

if bash "$ROOT/tests/test-module-messages.sh"; then
    pass "Заголовки модулів та джерела пакетів"
else
    fail "Вивід модулів"
fi

bash "$ROOT/tests/test-config-paths.sh"

bash "$ROOT/tests/test-doctor-format.sh"

bash "$ROOT/tests/test-maintenance.sh"

bash "$ROOT/tests/test-smart-no-backup.sh"

bash "$ROOT/tests/test-comparison.sh"

# Спільні кольори та API логування
if bash "$ROOT/tests/test-unified-ui.sh"; then
    pass "Спільний UI"
else
    fail "Спільний UI"
fi
bash "$ROOT/tests/test-ui-streams.sh"

# Усі заголовки інтерактивних меню через print_header
bash "$ROOT/tests/test-menu-headers.sh"
bash "$ROOT/tests/test-menu-navigation.sh"
bash "$ROOT/tests/test-package-availability.sh"

if command -v shellcheck >/dev/null 2>&1; then
    bash "$ROOT/tests/test-shellcheck.sh"
else
    printf '[WARN] ShellCheck пропущено — не встановлений\n'
fi

printf '\n[PASS] Усі тести Setup Manager пройдено\n'
