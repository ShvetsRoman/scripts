#!/usr/bin/env bash
# Doctor показує одночасно синтаксичні помилки й помилки посилань.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/project" "$tmp/bin"
for cmd in pacman paru; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$cmd"
    chmod +x "$tmp/bin/$cmd"
done
export PATH="$tmp/bin:$PATH"
cp -a -- "$ROOT_DIR/backup-install_manager.sh" "$ROOT_DIR/src" "$ROOT_DIR/dotfiles" "$ROOT_DIR/config" "$ROOT_DIR/hooks" "$ROOT_DIR/tools" "$ROOT_DIR/tests" "$tmp/project/"
cat > "$tmp/project/config/packages.conf" <<'INI'
[base]
title = Base
pacman = git
unknown = bad
configs = missing-config
configs_group = missing-group
INI
# Усі три помилки мають бути в одному звіті.
status=0
output="$(SETUP_TEST_MODE=true bash "$tmp/project/backup-install_manager.sh" doctor 2>&1)" || status=$?
((status != 0)) || { printf '[FAIL] Doctor прийняв помилки\n' >&2; exit 1; }
for needle in 'packages.conf:4:' 'base.configs: невідомий запис missing-config (рядок 5)' 'base.configs_group: невідома група missing-group (рядок 6)' 'Модулів: 1, помилок: 3'; do
    [[ "$output" == *"$needle"* ]] || { printf '[FAIL] Немає %s:\n%s\n' "$needle" "$output" >&2; exit 1; }
done
# Заборонити навіть dry-run інсталятора — без виводу етапу Install.
status=0
output="$(SETUP_TEST_MODE=true bash "$tmp/project/backup-install_manager.sh" packages --dry-run --yes base 2>&1)" || status=$?
((status == 2)) || { printf '[FAIL] Installer повернув %s замість 2\n' "$status" >&2; exit 1; }
[[ "$output" != *'Install: Base'* ]] || { printf '[FAIL] Installer почав виконання\n' >&2; exit 1; }
printf '[PASS] test-packages-unified-doctor-v1418\n'
