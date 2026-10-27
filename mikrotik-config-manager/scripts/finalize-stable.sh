#!/usr/bin/env bash
# ============================================================
# ФІНАЛІЗАЦІЯ v0.0.41 STABLE
# Повний Cargo.lock формується самим Cargo, а не вручну.
# Жодних змін до конфігурацій RouterOS або вихідних Rust-модулів.
# ============================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$ROOT"

# Обов'язкові програми перевіряємо до будь-яких змін.
for command_name in cargo python3; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'ПОМИЛКА: відсутня команда %s\n' "$command_name" >&2
        exit 2
    fi
done

# Фіксуємо реальні версії та перевірені Cargo checksums.
cargo generate-lockfile
cargo build --locked

# Повний набір локальних перевірок (5/5 PASS).
REPORT_FILE="${REPORT_FILE:-$ROOT/mikrotik-config-manager-final-check.txt}" ./scripts/check.sh

# Переконуємося, що lock-файл має всі записи транзитивних пакетів.
python3 - <<'PYLOCK'
import pathlib, tomllib
root=pathlib.Path.cwd()
lock=tomllib.loads((root/'Cargo.lock').read_text())
packages=lock.get('package', [])
assert len(packages)>1, 'Cargo.lock не містить усіх залежностей'
assert any(p.get('name')=='mikrotik-config-manager' and p.get('version')=='0.0.41' for p in packages)
for p in packages:
    if p.get('source','').startswith('registry+'):
        assert len(p.get('checksum',''))==64, f'Відсутня checksum: {p["name"]}'
print(f'Cargo.lock: {len(packages)} пакетів, checksums наявні')
PYLOCK

# Створюємо архів без target/, build/, приватних .secrets та .git.
# Зберігаємо виконуваність scripts/check.sh і перевіряємо CRC ZIP.
python3 - <<'PYZIP'
from pathlib import Path
import zipfile, stat, hashlib, tomllib
root=Path.cwd()
output=root.parent/'mikrotik-config-manager-v0.0.41-stable-final.zip'
files=[]
for p in root.rglob('*'):
    if not p.is_file() or p.is_symlink():
        continue
    rel=p.relative_to(root)
    if any(s in {'.git','target','build','.snapshots','__pycache__'} for s in rel.parts):
        continue
    if p.name in {'.secrets','.env'} or p.name.endswith('.rsc'):
        continue
    if p.name.endswith('.pyc') or p.name=='mikrotik-config-manager-final-check.txt':
        continue
    files.append((p,rel))
assert sum(1 for _,r in files if r.suffix=='.toml')==30
check=root/'scripts/check.sh'
assert check.stat().st_mode & 0o777 == 0o755
with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for path,rel in sorted(files,key=lambda x:str(x[1])):
        info=zipfile.ZipInfo('mikrotik-config-manager/'+str(rel))
        info.create_system=3
        info.external_attr=(stat.S_IFREG | (path.stat().st_mode & 0o777)) << 16
        info.compress_type=zipfile.ZIP_DEFLATED
        z.writestr(info,path.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
with zipfile.ZipFile(output) as z:
    assert z.testzip() is None
    assert (z.getinfo('mikrotik-config-manager/scripts/check.sh').external_attr>>16)&0o777==0o755
    print('ZIP CRC PASS',len(z.namelist()),'файлів')
print('Архів:',output)
print('SHA256:',hashlib.sha256(output.read_bytes()).hexdigest())
PYZIP
