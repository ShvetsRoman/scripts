# Backup-Sync V2.0

Модульний rsync/SSH backup/sync для PC <-> SERVER.

## Основні можливості

- `up` — PC -> SERVER
- `down` — SERVER -> PC
- `--dry-run`
- `--host` для SSH alias
- `--yes`
- recovery перед overwrite/delete при UP
- `--delete-delay`
- verify через rsync + checksum
- excludes
- partial transfers
- XDG logs
- `flock` від паралельного запуску
- SSH keepalive/timeouts
- local/remote preflight
- remote rsync check
- free-space check (за замовчуванням увімкнено)
- `--no-space-check` для вимкнення перевірки disk space
- log/recovery cleanup
- підсумок і правильний exit code
- syntax/ShellCheck tests

## Запуск

```bash
chmod +x backup-sync.sh tests/run-tests.sh

./backup-sync.sh up --dry-run
./backup-sync.sh up
./backup-sync.sh up --host serv
./backup-sync.sh up --no-space-check
./backup-sync.sh down
./backup-sync.sh verify up
./backup-sync.sh verify both
./backup-sync.sh cleanup
./backup-sync.sh help
```

## Безпека

`up` є mirror-напрямком і використовує `--delete-delay`.
При `RECOVERY_ENABLED=true` старі/видалені remote-файли перед цим переміщуються у:

```text
$REMOTE_DIR/.backup-sync-recovery/YYYY-MM-DD_HH-MM-SS/
```

`down` за замовчуванням **не видаляє** зайві локальні файли.
