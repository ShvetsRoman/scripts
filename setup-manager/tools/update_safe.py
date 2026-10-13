#!/usr/bin/env python3
"""Code-only archive updater. Never touches user data/config."""
import os
import pathlib
import shutil
import sys
import tarfile
import tempfile
from datetime import datetime

MAX_FILES = 2000
MAX_BYTES = 50 * 1024 * 1024
ALLOWED_TOP = {'setup.sh', 'README.md'}
ALLOWED_DIRS = {'lib', 'modules', 'tests', 'tools', 'docs'}
EXECUTABLE = {'setup.sh'}


# allowed — чи дозволено оновлювати цей відносний шлях.
def allowed(path):
    parts = pathlib.PurePosixPath(path).parts
    if not parts or any(p in ('', '.', '..') for p in parts):
        return False
    if len(parts) == 1:
        return parts[0] in ALLOWED_TOP
    return parts[0] in ALLOWED_DIRS


# _check_no_symlink — перевіряє, що в шляху target немає symlink.
def _check_no_symlink(target, root):
    for parent in [target, *target.parents]:
        if parent == root.parent:
            break
        if parent.is_symlink():
            raise ValueError(f'Символьне посилання у шляху: {target}')


# _stage_archive — розпаковує дозволені файли у staging.
def _stage_archive(tf, stage):
    members = tf.getmembers()
    if len(members) > MAX_FILES:
        raise ValueError('Забагато файлів')
    candidates = []
    seen = set()
    total = 0
    for m in members:
        parts = pathlib.PurePosixPath(m.name).parts
        if (not parts or m.name.startswith('/') or '\\' in m.name
                or '\x00' in m.name
                or any(p in ('.', '..') for p in m.name.split('/'))):
            raise ValueError(f'Некоректний шлях: {m.name}')
        relative = '/'.join(parts[1:]) if parts[0].startswith('setup-manager') else m.name
        if not relative:
            continue
        if not allowed(relative):
            continue
        if not (m.isfile() or m.isdir()):
            raise ValueError(f'Недозволений тип: {relative}')
        if m.isdir():
            continue
        if relative in seen:
            raise ValueError(f'Повтор: {relative}')
        seen.add(relative)
        total += m.size
        if total > MAX_BYTES:
            raise ValueError('Завеликий обсяг')
        candidates.append((m, relative))
    if not any(p == 'setup.sh' for _, p in candidates):
        raise ValueError('Немає setup.sh')
    for m, relative in candidates:
        dst = stage / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        with tf.extractfile(m) as src, open(dst, 'xb') as out:
            shutil.copyfileobj(src, out)
        os.chmod(dst, 0o755 if relative in EXECUTABLE else 0o644)
    return candidates


# _apply — атомарно застосовує staged файли з rollback.
def _apply(stage, root, candidates, backup):
    updated = []
    try:
        for _, relative in candidates:
            target = root / relative
            _check_no_symlink(target, root)
            if target.exists() and not target.is_file():
                raise ValueError(f'Не файл: {relative}')
            had_old = target.exists()
            if had_old:
                old = backup / relative
                old.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, old)
            target.parent.mkdir(parents=True, exist_ok=True)
            tmp = target.with_name(f'{target.name}.updating-{os.getpid()}')
            shutil.copy2(stage / relative, tmp)
            os.replace(tmp, target)
            updated.append((relative, had_old))
    except Exception:
        for relative, had_old in reversed(updated):
            target = root / relative
            try:
                if had_old:
                    shutil.copy2(backup / relative, target)
                else:
                    target.unlink(missing_ok=True)
            except OSError:
                pass
        raise


# run — головна логіка оновлення.
def run(archive, root, dry):
    root_path = pathlib.Path(root).resolve(strict=True)
    for name in ('dotfiles', 'backups', 'archives', 'logs'):
        if (root_path / name).is_symlink():
            raise ValueError(f'symlink: {name}')
    with tarfile.open(archive, 'r:gz') as tf:
        with tempfile.TemporaryDirectory(prefix='.update-', dir=root_path) as stage_name:
            stage = pathlib.Path(stage_name)
            candidates = _stage_archive(tf, stage)
            print(f'[INFO] Оновлення: {len(candidates)} файлів')
            if dry:
                for _, rel in candidates:
                    print(f'[INFO] [DRY-RUN] {rel}')
                return
            backup_root = root_path / 'backups' / 'updates'
            backup_root.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(prefix='.code-backup-', dir=backup_root) as b:
                backup = pathlib.Path(b)
                _apply(stage, root_path, candidates, backup)
                saved = backup_root / ('code-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
                os.replace(backup, saved)
                print(f'[OK] Код оновлено; backup: {saved}')


# main — CLI-обгортка.
def main(argv):
    if len(argv) not in (3, 4):
        print('Використання: update_safe.py ARCHIVE PROJECT [--dry-run]', file=sys.stderr)
        return 2
    dry = len(argv) == 4 and argv[3] == '--dry-run'
    if len(argv) == 4 and not dry:
        print(f'Невідомий прапорець: {argv[3]}', file=sys.stderr); return 2
    try:
        run(argv[1], argv[2], dry)
    except (OSError, ValueError, tarfile.TarError) as e:
        print(f'[ERROR] {e}', file=sys.stderr); return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
