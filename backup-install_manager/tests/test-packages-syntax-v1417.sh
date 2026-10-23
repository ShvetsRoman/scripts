#!/usr/bin/env bash
# Виявлення всіх синтаксичних помилок і заборона часткового завантаження.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/packages/registry.sh
source "$ROOT_DIR/src/packages/registry.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$tmpdir"' EXIT
cat > "$tmpdir/packages.conf" <<'INI'
[base]
title = Base
pacman = git git
unknown = bad
broken line
configs_group = bad!
[base]
title = Duplicated
[cli]
title = CLI
pacman = curl
hook.curl = BAD!
INI
if output="$(packages_load "$tmpdir/packages.conf" 2>&1)"; then
    printf '[FAIL] Некоректний INI прийнято\n' >&2
    exit 1
fi
for expected in 'packages.conf:3:' 'packages.conf:4:' 'packages.conf:5:' 'packages.conf:6:' 'packages.conf:7:' 'packages.conf:12:' 'синтаксичних помилок: 7'; do
    if [[ "$output" != *"$expected"* ]]; then
        printf '[FAIL] Очікувалося %s:\n%s\n' "$expected" "$output" >&2
        exit 1
    fi
done
# Не допустити продовження після помилки парсера.
if packages_load "$tmpdir/packages.conf" >/dev/null 2>&1; then exit 1; fi
((${#PACKAGE_IDS[@]} == 0))
packages_load "$ROOT_DIR/config/packages.conf"
((${#PACKAGE_IDS[@]} > 0))
printf '[PASS] test-packages-syntax-v1417\n'
