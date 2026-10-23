# Посібник користувача

## Запуск

```bash
cd ~/Documents/backup-install_manager
./backup-install_manager.sh --version
./backup-install_manager.sh --help
./backup-install_manager.sh
```

Запуск без аргументів відкриває інтерактивне меню. У меню `0` повертає назад, `00` завершує роботу. Для операцій зворотного копіювання/видалення уважно читайте підтвердження.

## Перед першою роботою

1. Перегляньте `config/setup.conf`, `config/packages.conf`, `config/dotfiles.conf`.
2. Перевірте джерела: `./backup-install_manager.sh sources validate` та `./backup-install_manager.sh sources doctor`.
3. Запустіть `./backup-install_manager.sh doctor` і `./tests/run-tests.sh`.
4. Перевірте статус: `./backup-install_manager.sh dotfiles status`.
5. Перш ніж копіювати, запустіть `./backup-install_manager.sh dotfiles plan backup`.

## Практичні приклади

```bash
# Подивитися модулі, потім сухий прогін пакета
./backup-install_manager.sh packages --list
./backup-install_manager.sh packages --dry-run cli

# Порівняти конфіги HOME та репозиторію
./backup-install_manager.sh dotfiles status
./backup-install_manager.sh dotfiles diff nvim
./backup-install_manager.sh dotfiles verify --group cli

# Запланувати та виконати backup лише змінених
./backup-install_manager.sh dotfiles plan backup
./backup-install_manager.sh dotfiles backup changed

# Спочатку переглянути відновлення
./backup-install_manager.sh dotfiles plan restore
./backup-install_manager.sh dotfiles restore nvim

# Діагностика
./backup-install_manager.sh doctor
./backup-install_manager.sh report summary
./backup-install_manager.sh logs tail 50
```

`backup` копіює HOME → `dotfiles/`, а `restore` — у зворотному напрямку. За замовчуванням **не** використовуйте `--sync-delete`, доки не перевірите перелік змін.

## Які файли не варто замінювати оновленням

Зберігайте власні `config/`, `dotfiles/`, `backups/`, `archives/`, `logs/`. Оновлення релізного коду не повинно підміняти ці локальні дані. Зробіть окрему копію каталогу перед `update`.
