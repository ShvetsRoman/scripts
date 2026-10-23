# Безпека, Backup та Recovery

## Основні запобіжники

1. Збережіть резервну копію каталогу перед оновленнями.
2. Для змін спершу `--dry-run` або `dotfiles plan`.
3. Не використовуйте `--sync-delete` без перевірки того, що буде видалено.
4. `--no-backup` вимикає захисні копії; rollback поточного об'єкта може стати недоступним.
5. Не запускайте Backup Install Manager з root без необхідності. Для системних шляхів перевіряйте права окремо.
6. Команди змін використовують lock `.setup-manager.lock`; код 75 означає конфлікт блокування/очікування.

## Послідовність відновлення

```bash
./backup-install_manager.sh recovery list
./backup-install_manager.sh recovery verify ID
./backup-install_manager.sh recovery plan ID
./backup-install_manager.sh recovery restore ID
./backup-install_manager.sh backups list dotfiles
./backup-install_manager.sh backups verify dotfiles ID
```

`recovery verify` використовує manifest та SHA-256, де вони є. Код 3 для старих копій без сум дозволяє визначити legacy, але не підтверджує цілісність. Відновлення не є гарантією атомарного відкату всього набору файлів. `recovery delete ID` незворотний.

## Архіви та оновлення

```bash
./backup-install_manager.sh archive list
./backup-install_manager.sh archive create
./backup-install_manager.sh update /шлях/release.tar.gz --dry-run
```

Перевіряйте джерело, вміст і хеш архіву до оновлення. Runtime-каталоги (`backups/`, `logs/`, `archives/`) та користувацькі конфігурації необхідно зберігати. Ніколи не розпаковуйте реліз поверх налаштувань без резервної копії.
