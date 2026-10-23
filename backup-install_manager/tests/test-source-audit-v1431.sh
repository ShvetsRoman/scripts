#!/usr/bin/env bash
# Статичний аудит залежностей окремих процесів без виконання hooks.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT_DIR" <<'PYINNER'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
bootstrap = (root / "src/core/bootstrap.sh").read_text()
runtime = (root / "src/hooks/hook_runtime.sh").read_text()

# Перелік статичних бібліотек bootstrap_modules(): кожна рівно один раз.
match = re.search(r"for module in (.*?)\s*; do", bootstrap, re.S)
if match is None:
    sys.exit("[FAIL] Відсутній список залежностей bootstrap_modules")
modules = re.findall(r"src/[a-z_]+/[a-z_]+", match.group(1))
if not modules or len(modules) != len(set(modules)):
    sys.exit("[FAIL] Порожній список або повторні модулі bootstrap")
for module in modules:
    if not (root / f"{module}.sh").is_file():
        sys.exit(f"[FAIL] Відсутня залежність: {module}.sh")

# Перевірити статичні джерела та межі між двома Bash-процесами.
for path in ("src/core/path.sh", "src/core/version.sh"):
    if not (root / path).is_file():
        sys.exit(f"[FAIL] Відсутній статичний файл: {path}")
if 'source "$ROOT_DIR/src/core/path.sh"' not in bootstrap:
    sys.exit("[FAIL] bootstrap не завантажує path.sh")
if 'source "$ROOT_DIR/src/core/path.sh"' not in runtime:
    sys.exit("[FAIL] hook runtime не завантажує path.sh")
if 'source "$hook_file"' not in runtime:
    sys.exit("[FAIL] hook runtime не завантажує призначений hook")
if 'source "$(path_project "$module.sh")"' not in bootstrap:
    sys.exit("[FAIL] bootstrap не завантажує модулі")
print(f"[PASS] Залежності bootstrap: {len(modules)}; контракт hook runtime на місці")
PYINNER
