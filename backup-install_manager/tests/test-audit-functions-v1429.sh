#!/usr/bin/env bash
# Перевірка відсутності дубльованих імен функцій у програмному коді.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT_DIR" <<'PYINNER'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
names = {}
for file in (root / "src").rglob("*.sh"):
    for number, line in enumerate(file.read_text().splitlines(), 1):
        match = re.match(r"^([a-zA-Z_][a-zA-Z_0-9]*)\(\)\s*\{", line)
        if match:
            names.setdefault(match.group(1), []).append(f"{file.relative_to(root)}:{number}")
errors = {name: locations for name, locations in names.items() if len(locations) > 1}
for name, locations in sorted(errors.items()):
    print(f"[FAIL] Повторна функція {name}: {', '.join(locations)}", file=sys.stderr)
if errors:
    sys.exit(1)
print("[PASS] Функції src/ мають унікальні імена")
PYINNER
