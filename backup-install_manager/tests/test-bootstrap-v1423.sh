#!/usr/bin/env bash
# Перевірка єдиної ініціалізації та відокремлення предметних модулів.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
expected_version="$(bash -c 'source "$1/src/core/version.sh"; printf "%s" "$SETUP_VERSION"' bash "$root")"
for dir in src/core src/cli src/packages src/dotfiles src/recovery src/hooks src/diagnostics hooks tests tools config dotfiles; do
    [[ -d "$root/$dir" ]] || { printf '[FAIL] Немає каталогу %s\n' "$dir" >&2; exit 1; }
done
[[ ! -e "$root/lib" ]] || { printf '[FAIL] Старий каталог lib/ залишився\n' >&2; exit 1; }
[[ -f "$root/src/core/bootstrap.sh" ]]
[[ -f "$root/src/hooks/hook_runtime.sh" ]]
[[ "$(cd /tmp && bash "$root/backup-install_manager.sh" --version)" == "$expected_version" ]]
[[ "$(bash "$root/backup-install_manager.sh" --no-color --version)" == "$expected_version" ]]
[[ "$(bash "$root/backup-install_manager.sh" --version --dry-run)" == "$expected_version" ]]
[[ $(grep -c 'cli_parse "\$@"' "$root/src/core/bootstrap.sh") -eq 1 ]]
! grep -Eq '^[[:space:]]*cli_parse "\$@"' "$root/src/cli/cli.sh"
for hook in "$root"/hooks/*.sh; do
    grep -Eq '^hook_main\(\)' "$hook"
    ! grep -Eq '^[[:space:]]*source ' "$hook"
done
printf '[PASS] test-bootstrap-v1423\n'
