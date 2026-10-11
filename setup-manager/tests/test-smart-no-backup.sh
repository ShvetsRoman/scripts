#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT_DIR" <<'PYTEST'
from pathlib import Path
import sys
s=(Path(sys.argv[1])/'setup.sh').read_text()
assert ' --no-backup) no_backup=true ;;'.strip() in s
assert 'run_installer --dry-run "${args[@]}" "${modules[@]}"' in s
assert 'if [[ "$no_backup" == true ]]; then args+=(--no-backup); fi' in s
assert 'Захисні backups Installer: ВИМКНЕНО' in s
print('PASS: smart --no-backup pass-through')
PYTEST
