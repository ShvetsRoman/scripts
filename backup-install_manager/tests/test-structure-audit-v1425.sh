#!/usr/bin/env bash
# Аудит актуальної документації, структури та механізму hooks.
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf '[FAIL] test-structure-audit-v1425: %s\n' "$1" >&2
    exit 1
}

for dir in core cli packages dotfiles recovery hooks diagnostics; do
    [[ -d "$root/src/$dir" ]] || fail "Відсутній каталог src/$dir"
done

for dir in lib app core packages recovery scripts; do
    [[ ! -e "$root/$dir" && ! -L "$root/$dir" ]] || fail "Застарілий шлях у корені: $dir"
done

[[ -f "$root/src/hooks/hook_runtime.sh" ]] || fail 'Відсутній src/hooks/hook_runtime.sh'
[[ -f "$root/docs/architecture.md" ]] || fail 'Відсутній docs/architecture.md'
[[ -f "$root/docs/CHANGELOG.md" ]] || fail 'Відсутній docs/CHANGELOG.md'

# Поточну версію беремо з одного джерела.
# shellcheck source=../src/core/version.sh
source "$root/src/core/version.sh"
grep -Fq -- "$SETUP_VERSION" "$root/docs/architecture.md" || fail "docs/architecture.md не містить версію $SETUP_VERSION"
grep -Fq -- "$SETUP_VERSION" "$root/docs/CHANGELOG.md" || fail "docs/CHANGELOG.md не містить версію $SETUP_VERSION"

if grep -Eq '^[[:space:]]+lib/|bash hooks/snapper.sh' "$root/README.md"; then
    fail 'README містить застарілу структуру або прямий запуск hook'
fi

for file in "$root"/hooks/*.sh; do
    [[ -f "$file" ]] || fail 'У каталозі hooks немає .sh файлів'
    grep -Eq '^hook_main\(\)' "$file" || fail "Відсутня функція hook_main у ${file#"$root"/}"
done

for file in archive_safe.py recovery_safe.py update_safe.py migrate-dotfiles-v1410.sh; do
    [[ -f "$root/tools/$file" ]] || fail "Відсутній tools/$file"
done

printf '[PASS] test-structure-audit-v1425\n'
