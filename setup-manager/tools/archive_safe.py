#!/usr/bin/env python3
"""Strict TAR validator and safe staging extractor for dotfiles archives."""
import os
import pathlib
import shutil
import sys
import tarfile

MAX_TOTAL = 2 * 1024**3
MAX_FILES = 100000


def inspect(tf):
    seen = set()
    total = 0
    members = tf.getmembers()
    if len(members) > MAX_FILES:
        raise ValueError('Забагато записів')
    for item in members:
        name = item.name
        parts = pathlib.PurePosixPath(name).parts
        if (not parts or parts[0] != 'dotfiles' or
                any(part in ('..', '.') for part in name.split('/')) or
                name.startswith('/') or '\\' in name or '\x00' in name or
                not (item.isfile() or item.isdir())):
            raise ValueError(f'Недозволений запис: {name}')
        key = name.rstrip('/')
        if key in seen:
            raise ValueError(f'Дубльований запис: {name}')
        seen.add(key)
        if item.isfile():
            total += item.size
            if total > MAX_TOTAL:
                raise ValueError('Архів завеликий')
    if 'dotfiles' not in seen:
        raise ValueError('Відсутній каталог dotfiles')
    return members


def main():
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in ('verify', 'extract'):
        raise ValueError('Використання: archive_safe.py verify ARCHIVE | extract ARCHIVE STAGING')
    action, filename = sys.argv[1:3]
    with tarfile.open(filename, mode='r:gz') as tf:
        members = inspect(tf)
        if action == 'extract':
            if len(sys.argv) != 4:
                raise ValueError('Потрібен каталог staging')
            stage = pathlib.Path(sys.argv[3])
            if not stage.is_dir() or stage.is_symlink():
                raise ValueError('Некоректний staging')
            for item in members:
                parts = pathlib.PurePosixPath(item.name).parts
                dst = stage.joinpath(*parts)
                if item.isdir():
                    dst.mkdir(parents=True, exist_ok=True)
                    continue
                dst.parent.mkdir(parents=True, exist_ok=True)
                with tf.extractfile(item) as src, open(dst, 'xb') as out:
                    shutil.copyfileobj(src, out)
                os.chmod(dst, 0o600)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, tarfile.TarError) as exc:
        print(f'[ERROR] Перевірка архіву: {exc}', file=sys.stderr)
        sys.exit(1)
