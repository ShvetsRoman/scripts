#!/usr/bin/env bash
# Регресійні перевірки спільної бібліотеки UI.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Тест текстового формату не має залежати від налаштувань користувача.
export NO_COLOR=1
export SETUP_COLOR=never
# shellcheck source=../lib/ui.sh
source "$ROOT/lib/ui.sh"

assert_equals() {
    local expected="$1"
    local actual="$2"
    local name="$3"
    if [[ "$actual" != "$expected" ]]; then
        printf '[FAIL] %s: очікувалося %q, отримано %q\n' "$name" "$expected" "$actual" >&2
        return 1
    fi
}

assert_exists() {
    local file="$1"
    local name="$2"
    if [[ ! -e "$file" ]]; then
        printf '[FAIL] %s: відсутній %s\n' "$name" "$file" >&2
        return 1
    fi
}

assert_absent() {
    local file="$1"
    local name="$2"
    if [[ -e "$file" ]]; then
        printf '[FAIL] %s: зайвий файл %s\n' "$name" "$file" >&2
        return 1
    fi
}

assert_equals '[OK] test' "$(log_ok test)" 'log_ok'
assert_equals '[WARN] test' "$(log_warn test)" 'log_warn'

header="$(print_header TEST)"
if [[ "$header" != *TEST* ]]; then
    printf '[FAIL] print_header: відсутній заголовок TEST\n' >&2
    exit 1
fi

result="$(NO_COLOR=1 SETUP_COLOR=never TERM=xterm bash -c 'source "$1/lib/ui.sh"; log_step test' bash "$ROOT")"
assert_equals '[STEP] test' "$result" 'log_step'

if grep -q '^log_info()' "$ROOT/install-packages/lib/common.sh"; then
    printf '[FAIL] Повторне оголошення log_info в Installer\n' >&2
    exit 1
fi

assert_absent "$ROOT/dotfiles-manager/lib/logging.sh" 'застаріла бібліотека logging.sh'
assert_absent "$ROOT/install-packages/lib/colors.sh" 'застаріла бібліотека colors.sh'
assert_exists "$ROOT/install-packages/lib/menu.sh" 'меню Installer'

printf '[PASS] Unified UI\n'
