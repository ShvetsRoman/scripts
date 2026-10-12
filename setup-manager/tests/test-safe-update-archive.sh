#!/usr/bin/env bash
set -Eeuo pipefail
project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
python3 - "$fixture" "$project" <<'PY'
import io
import pathlib
import subprocess
import sys
import tarfile

base = pathlib.Path(sys.argv[1])
project = pathlib.Path(sys.argv[2])
helper = project / 'tools' / 'archive_safe.py'
for kind in ('good', 'traversal', 'symlink', 'duplicate'):
    path = base / (kind + '.tar.gz')
    with tarfile.open(path, 'w:gz') as tf:
        d = tarfile.TarInfo('dotfiles/')
        d.type = tarfile.DIRTYPE
        tf.addfile(d)
        content = b'first\n'
        f = tarfile.TarInfo('dotfiles/example')
        f.size = len(content)
        tf.addfile(f, io.BytesIO(content))
        if kind == 'traversal':
            f = tarfile.TarInfo('dotfiles/../../escape')
            f.size = 1
            tf.addfile(f, io.BytesIO(b'!'))
        if kind == 'symlink':
            f = tarfile.TarInfo('dotfiles/link')
            f.type = tarfile.SYMTYPE
            f.linkname = '/etc/passwd'
            tf.addfile(f)
        if kind == 'duplicate':
            f = tarfile.TarInfo('dotfiles/example')
            f.size = 1
            tf.addfile(f, io.BytesIO(b'!'))
    result = subprocess.run(['python3', str(helper), 'verify', str(path)], capture_output=True)
    if (result.returncode == 0) != (kind == 'good'):
        raise SystemExit('Archive validation failed: ' + kind)
print('[PASS] Archive: небезпечні, дубльовані й символьні записи відхилено')

root = base / 'installed'
for name in ('dotfiles', 'backups', 'archives', 'logs', 'config', 'lib'):
    (root / name).mkdir(parents=True)
for name in ('dotfiles/.zshrc', 'config/setup.conf', 'backups/data', 'archives/data', 'logs/data'):
    (root / name).write_text('keep-original\n')
(root / 'setup.sh').write_text('old-code\n')
(root / 'lib/core.sh').write_text('old-library\n')
release = base / 'release.tar.gz'
with tarfile.open(release, 'w:gz') as tf:
    for name, content in [('setup.sh','new-code\n'), ('lib/core.sh','new-library\n'),
                          ('dotfiles/.zshrc','overwrite\n'), ('config/setup.conf','overwrite\n'),
                          ('backups/data','overwrite\n')]:
        payload = content.encode()
        item = tarfile.TarInfo('setup-manager-v4.0-fresh/' + name)
        item.size = len(payload)
        tf.addfile(item, io.BytesIO(payload))
cmd = ['python3', str(project / 'tools' / 'update_safe.py'), str(release), str(root)]
subprocess.run(cmd + ['--dry-run'], check=True, capture_output=True)
assert (root / 'setup.sh').read_text() == 'old-code\n'
subprocess.run(cmd, check=True, capture_output=True)
assert (root / 'setup.sh').read_text() == 'new-code\n'
assert (root / 'lib/core.sh').read_text() == 'new-library\n'
for name in ('dotfiles/.zshrc', 'config/setup.conf', 'backups/data', 'archives/data', 'logs/data'):
    assert (root / name).read_text() == 'keep-original\n', name
assert list((root / 'backups' / 'updates').glob('code-*/setup.sh'))
print('[PASS] Update: код оновлено, дані й налаштування збережено, попередній код захищено')
PY
