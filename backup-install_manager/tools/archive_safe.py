#!/usr/bin/env python3
"""Strict TAR validator and safe extractor for dotfiles archives."""
import os, pathlib, shutil, sys, tarfile

MAX_TOTAL = 2 * 1024**3
MAX_FILES = 100000


# inspect — перевіряє всі записи архіву.
def inspect(tf):
    seen, total = set(), 0
    members = tf.getmembers()
    if len(members) > MAX_FILES:
        raise ValueError('Забагато записів')
    for m in members:
        parts = pathlib.PurePosixPath(m.name).parts
        if (not parts or parts[0] != 'dotfiles'
                or any(p in ('..', '.') for p in m.name.split('/'))
                or m.name.startswith('/') or '\\' in m.name or '\x00' in m.name
                or not (m.isfile() or m.isdir())):
            raise ValueError(f'Недозволений запис: {m.name}')
        key = m.name.rstrip('/')
        if key in seen:
            raise ValueError(f'Дубль: {m.name}')
        seen.add(key)
        if m.isfile():
            total += m.size
            if total > MAX_TOTAL:
                raise ValueError('Завеликий архів')
    if 'dotfiles' not in seen:
        raise ValueError('Немає dotfiles/')
    return members


# main — точка входу: verify або extract.
def main():
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in ('verify', 'extract'):
        raise ValueError('verify ARCHIVE | extract ARCHIVE STAGING')
    action, filename = sys.argv[1:3]
    with tarfile.open(filename, 'r:gz') as tf:
        members = inspect(tf)
        if action == 'extract':
            if len(sys.argv) != 4:
                raise ValueError('Потрібен staging')
            stage = pathlib.Path(sys.argv[3])
            if not stage.is_dir() or stage.is_symlink():
                raise ValueError('Некоректний staging')
            for m in members:
                parts = pathlib.PurePosixPath(m.name).parts
                dst = stage.joinpath(*parts)
                if m.isdir():
                    dst.mkdir(parents=True, exist_ok=True); continue
                dst.parent.mkdir(parents=True, exist_ok=True)
                with tf.extractfile(m) as src, open(dst, 'xb') as out:
                    shutil.copyfileobj(src, out)
                os.chmod(dst, m.mode & 0o777)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, tarfile.TarError) as e:
        print(f'[ERROR] {e}', file=sys.stderr); sys.exit(1)
