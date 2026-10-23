#!/usr/bin/env python3
"""Integrity index for Setup Manager recovery snapshots (sha256, file size, tree)."""
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

INDEX = 'checksums.json'
MAX_ENTRIES = 100000
MAX_INDEX_SIZE = 20 * 1024 * 1024


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def records_of(data):
    if data.is_symlink() or not data.is_dir():
        raise ValueError('Відсутній або небезпечний data/')
    result = []
    for root, dirs, files in os.walk(data, followlinks=False):
        for name in sorted(dirs + files):
            path = Path(root) / name
            relative = path.relative_to(data).as_posix()
            if any(c in relative for c in ('\x00', '\n', '\r', '\t')):
                raise ValueError('Керувальні символи у назві: ' + repr(relative))
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                result.append({'path': relative, 'type': 'symlink', 'target': os.readlink(path)})
            elif stat.S_ISDIR(mode):
                result.append({'path': relative, 'type': 'dir'})
            elif stat.S_ISREG(mode):
                result.append({'path': relative, 'type': 'file',
                               'size': path.stat().st_size, 'sha256': checksum(path)})
            else:
                raise ValueError('Непідтримуваний тип у recovery: ' + relative)
            if len(result) > MAX_ENTRIES:
                raise ValueError('Забагато об’єктів у recovery')
    return sorted(result, key=lambda r: r['path'])


def snapshot_info(snapshot):
    if snapshot.is_symlink() or not snapshot.is_dir():
        raise ValueError('Некоректний каталог recovery')
    manifest = snapshot / 'manifest.tsv'
    if manifest.is_symlink() or not manifest.is_file():
        raise ValueError('Немає безпечного manifest.tsv')
    return {
        'version': 1,
        'manifest_sha256': checksum(manifest),
        'entries': records_of(snapshot / 'data'),
    }


def create(snapshot):
    payload = snapshot_info(snapshot)
    path = snapshot / INDEX
    if path.exists() or path.is_symlink():
        raise ValueError('checksums.json уже існує')
    temp = snapshot / f'.checksums.{os.getpid()}.tmp'
    try:
        with temp.open('x', encoding='utf-8') as stream:
            json.dump(payload, stream, ensure_ascii=False, sort_keys=True, indent=2)
            stream.write('\n')
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)
    print(f'[OK] Recovery integrity: {len(payload["entries"])} об’єктів')


def verify(snapshot):
    path = snapshot / INDEX
    if path.is_symlink():
        raise ValueError('Symlink checksums.json')
    if not path.exists():
        print('[WARN] Legacy recovery без checksums.json: цілісність не підтверджена')
        return 3
    if path.stat().st_size > MAX_INDEX_SIZE:
        raise ValueError('Завеликий файл checksums.json')
    with path.open(encoding='utf-8') as stream:
        expected = json.load(stream)
    current = snapshot_info(snapshot)
    if not isinstance(expected, dict) or expected != current:
        raise ValueError('Невідповідність SHA-256, маніфесту або списку файлів')
    print(f'[OK] Recovery integrity: {len(current["entries"])} об’єктів')
    return 0


def main(argv):
    if len(argv) != 3 or argv[1] not in ('create', 'verify'):
        print('Використання: recovery_safe.py create|verify SNAPSHOT', file=sys.stderr)
        return 2
    try:
        snapshot = Path(argv[2])
        if argv[1] == 'create':
            create(snapshot)
            return 0
        return verify(snapshot)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print('[ERROR] Recovery integrity: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
