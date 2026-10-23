#!/usr/bin/env bash
# Перевірка статичних залежностей і порядку завантаження без виконання системних команд.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
from pathlib import Path
import re
import sys
root = Path(sys.argv[1])
bootstrap = (root / 'src/core/bootstrap.sh').read_text()
match = re.search(r'for module in\s+\\\n(.*?)\s*; do', bootstrap, re.S)
if not match:
    sys.exit('[FAIL] Не знайдено список bootstrap_modules')
modules = re.findall(r'src/[a-z_]+/[a-z_]+', match.group(1))
if len(modules) != 22 or len(modules) != len(set(modules)):
    sys.exit('[FAIL] Список модулів змінено або є дублікати')
positions = {name: i for i, name in enumerate(modules)}
constraints = [
    ('src/core/ui', 'src/cli/menu'),
    ('src/core/fs', 'src/dotfiles/apply'),
    ('src/packages/registry', 'src/packages/packages'),
    ('src/packages/packages_validation', 'src/packages/packages'),
    ('src/packages/packages', 'src/cli/cli'),
    ('src/hooks/hooks', 'src/cli/cli'),
    ('src/recovery/archive', 'src/recovery/recovery'),
    ('src/cli/menu', 'src/cli/cli'),
]
for before, after in constraints:
    if before not in positions or after not in positions or positions[before] >= positions[after]:
        sys.exit(f'[FAIL] Порядок залежностей: {before} має бути перед {after}')
for module in modules:
    if not (root / (module + '.sh')).is_file():
        sys.exit(f'[FAIL] Відсутній модуль: {module}')
if bootstrap.index('source "$ROOT_DIR/src/core/path.sh"') >= bootstrap.index('source "$(path_setup_conf)"'):
    sys.exit('[FAIL] path.sh має завантажуватися перед setup.conf')
if bootstrap.index('source "$(path_setup_conf)"') >= bootstrap.index('source "$(path_project src/core/version.sh)"'):
    sys.exit('[FAIL] Порушено порядок config і version')
print('[PASS] Порядок завантаження і залежності src/')
PY
