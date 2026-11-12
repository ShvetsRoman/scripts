# Безпека, Backup та Recovery

## Основні запобіжники

1. Збережіть резервну копію каталогу перед оновленнями.
2. Для змін спершу `--dry-run` або `dotfiles plan`.
3. Не використовуйте `--sync-delete` без перевірки того, що буде видалено. `--sync-delete` працює навіть при вимкнених захисних копіях (`SETUP_BACKUP_ENABLED=false`), але тоді автоматичний відкат недоступний — у журналі з'явиться попередження.
4. `--no-backup` вимикає захисні копії; rollback поточного об'єкта може стати недоступним.
5. Не запускайте Backup Install Manager з root без необхідності. Для системних шляхів перевіряйте права окремо. System restore до `/etc` завжди створює власну захисну копію й не підтримує `--sync-delete`.
6. Команди змін використовують lock `.setup-manager.lock`; код 75 означає конфлікт блокування/очікування. Відновлення знімків recovery з `--sync-delete` вимагає `SETUP_RECOVERY_ENABLED=true`.

## Послідовність відновлення

```bash
./backup-install_manager.sh recovery list              # перелік захисних знімків
./backup-install_manager.sh recovery verify ID         # перевірка manifest і SHA-256
./backup-install_manager.sh recovery plan ID           # що буде відновлено (без дій)
./backup-install_manager.sh recovery restore ID        # реальне відновлення знімка
./backup-install_manager.sh backups list dotfiles      # резервні копії групи dotfiles
./backup-install_manager.sh backups verify dotfiles ID # перевірка цілісності резервної копії
```

`recovery verify` використовує manifest та SHA-256, де вони є. Код 3 для старих копій без сум дозволяє визначити legacy, але не підтверджує цілісність. Відновлення не є гарантією атомарного відкату всього набору файлів. `recovery delete ID` незворотний.

## Архіви та оновлення

```bash
./backup-install_manager.sh archive list                   # перелік архівів dotfiles/
./backup-install_manager.sh archive create                 # створити архів dotfiles/
./backup-install_manager.sh update /шлях/release.tar.gz --dry-run   # оновлення: спершу сухий прогін
```

Перевіряйте джерело, вміст і хеш архіву до оновлення. Runtime-каталоги (`backups/`, `logs/`, `archives/`) та користувацькі конфігурації необхідно зберігати. Ніколи не розпаковуйте реліз поверх налаштувань без резервної копії.
