#!/usr/bin/env python3
"""Code-only archive updater. Never writes user data/config or symlinks."""
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


def allowed(path):
    parts = pathlib.PurePosixPath(path).parts
    return (len(parts) == 1 and parts[0] in ALLOWED_TOP or
            len(parts) >= 2 and parts[0] in ALLOWED_DIRS and
            all(p not in ('', '.', '..') for p in parts))


def run(archive, root, dry):
    root = pathlib.Path(root).resolve(strict=True)
    if (root / 'dotfiles').is_symlink() or (root / 'backups').is_symlink():
        raise ValueError('Небезпечні шляхи в проєкті')
    with tarfile.open(archive, 'r:gz') as tf:
        members = tf.getmembers()
        if len(members) > MAX_FILES:
            raise ValueError('Забагато файлів')
        candidates = []
        seen = set()
        total = 0
        for m in members:
            parts = pathlib.PurePosixPath(m.name).parts
            if not parts or m.name.startswith('/') or '\\' in m.name or any(p in ('.', '..') for p in m.name.split('/')):
                raise ValueError('Некоректний шлях архіву')
            # Accept archives with one outer project directory.
            relative = '/'.join(parts[1:]) if parts[0].startswith('setup-manager') else m.name
            if not relative:
                continue
            if not allowed(relative):
                # Data/config entries are deliberately ignored (never installed).
                continue
            if not (m.isfile() or m.isdir()):
                raise ValueError(f'Недозволений тип: {relative}')
            if m.isdir():
                continue
            if relative in seen:
                raise ValueError('Повтор файлу')
            seen.add(relative)
            total += m.size
            if total > MAX_BYTES:
                raise ValueError('Завеликий обсяг коду')
            candidates.append((m, relative))
        if not any(p == 'setup.sh' for _, p in candidates):
            raise ValueError('В архіві немає setup.sh')
        print(f'[INFO] Оновлення коду: {len(candidates)} файлів')
        if dry:
            print('[INFO] [DRY-RUN] Користувацькі дані не змінюються')
            return
        backup_root = root / 'backups' / 'updates'
        backup_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.update-', dir=root) as stage_name:
            stage = pathlib.Path(stage_name)
            for member, relative in candidates:
                dst = stage / relative
                dst.parent.mkdir(parents=True, exist_ok=True)
                with tf.extractfile(member) as source, open(dst, 'xb') as output:
                    shutil.copyfileobj(source, output)
                os.chmod(dst, 0o755 if relative == 'setup.sh' else 0o644)
            with tempfile.TemporaryDirectory(prefix='.code-backup-', dir=backup_root) as backup_name:
                backup = pathlib.Path(backup_name)
                updated = []
                try:
                    for _, relative in candidates:
                        target = root / relative
                        # Reject symlinks at any destination parent.
                        for parent in [target, *list(target.parents)]:
                            if parent == root.parent:
                                break
                            if parent.is_symlink():
                                raise ValueError(f'Символьне посилання у шляху: {relative}')
                        if target.exists() and not target.is_file():
                            raise ValueError(f'Шлях не є файлом: {relative}')
                        had_old = target.exists()
                        old = backup / relative
                        if had_old:
                            old.parent.mkdir(parents=True, exist_ok=True)
                            shutil.copy2(target, old)
                        target.parent.mkdir(parents=True, exist_ok=True)
                        temp_target = target.with_name(target.name + '.updating-' + str(os.getpid()))
                        shutil.copy2(stage / relative, temp_target)
                        os.replace(temp_target, target)
                        updated.append((relative, had_old))
                except Exception:
                    for relative, had_old in reversed(updated):
                        target = root / relative
                        if had_old:
                            shutil.copy2(backup / relative, target)
                        else:
                            target.unlink(missing_ok=True)
                    raise
                # Persist a backup for restoring previously existing code.
                saved = backup_root / ('code-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
                os.replace(backup, saved)
                print(f'[OK] Код оновлено; попередній код: {saved}')
                print('[INFO] dotfiles/, backups/, archives/, logs/ і config/ не змінено')


if __name__ == '__main__':
    try:
        if len(sys.argv) not in (3, 4):
            raise ValueError('Використання: update_safe.py ARCHIVE PROJECT [--dry-run]')
        run(sys.argv[1], sys.argv[2], len(sys.argv) == 4 and sys.argv[3] == '--dry-run')
    except (OSError, ValueError, tarfile.TarError) as error:
        print(f'[ERROR] Оновлення: {error}', file=sys.stderr)
        sys.exit(1)
