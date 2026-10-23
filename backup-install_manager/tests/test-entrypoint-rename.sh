#!/usr/bin/env bash
# Контракт актуальної точки входу та безпечного оновлювача.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -x "$root/backup-install_manager.sh" ]]
[[ ! -e "$root/setup-manager.sh" ]]
expected="$(bash -c 'source "$1/src/core/version.sh"; printf "%s" "$SETUP_VERSION"' bash "$root")"
[[ "$(bash "$root/backup-install_manager.sh" --version)" == "$expected" ]]
[[ "$(bash "$root/backup-install_manager.sh" --help)" == *'backup-install_manager.sh'* ]]
if grep -Rn --include='*.md' --include='*.sh' --include='*.py' 'setup-manager\.sh' "$root/src" "$root/tools" "$root/docs" "$root/README.md" > /dev/null; then
    printf '[FAIL] Знайдено стару назву запускного файлу в наступних місцях:\n' >&2
    grep -Rn --include='*.md' --include='*.sh' --include='*.py' 'setup-manager\.sh' "$root/src" "$root/tools" "$root/docs" "$root/README.md" >&2
    exit 1
fi
python - "$root" <<'PY'
import importlib.util
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('update_safe', root / 'tools' / 'update_safe.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.allowed('src/core/version.sh')
assert module.allowed('backup-install_manager.sh')
assert not module.allowed('config/setup.conf')
assert not module.allowed('dotfiles/personal.conf')
assert not module.allowed('backups/personal.tar.gz')
PY
printf '[PASS] test-entrypoint-rename\n'
