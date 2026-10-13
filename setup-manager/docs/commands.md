# Команди

## Installer

    ./setup.sh installer --list
    ./setup.sh installer cli shell
    ./setup.sh installer --all
    ./setup.sh installer --dry-run all
    ./setup.sh installer --configs-only cli
    ./setup.sh installer --no-backup cli
    ./setup.sh installer --sync-delete --yes cli

## Dotfiles

    ./setup.sh dotfiles backup [шлях...]
    ./setup.sh dotfiles restore [шлях...]
    ./setup.sh dotfiles status
    ./setup.sh dotfiles diff [шлях...]

## Ad-hoc backup

    ./setup.sh backup-src /etc/nginx nginx-conf
    ./setup.sh restore-src nginx-conf /tmp/nginx
    ./setup.sh restore-src nginx-conf

## Sources

    ./setup.sh sources list
    ./setup.sh sources doctor
    ./setup.sh sources scan
    ./setup.sh sources add home .zshrc .zshrc
    ./setup.sh sources add abs /etc/nginx nginx-conf
    ./setup.sh sources remove .zshrc

## Archive / Recovery

    ./setup.sh archive create
    ./setup.sh archive list
    ./setup.sh archive restore NAME
    ./setup.sh recovery list
    ./setup.sh recovery restore ID
    ./setup.sh recovery delete ID

## Maintenance

    ./setup.sh maintenance menu
    ./setup.sh maintenance disk
    ./setup.sh maintenance --dry-run cleanup logs
    ./setup.sh maintenance cleanup dotfiles
    ./setup.sh maintenance cleanup installer
    ./setup.sh maintenance cleanup recovery

## Інше

    ./setup.sh doctor
    ./setup.sh smart [--dry-run] [модулі...]
    ./setup.sh update ARCHIVE.tar.gz [--dry-run]
    ./setup.sh test

## Загальні прапорці

| Прапорець | Ефект |
|---|---|
| --dry-run | Нічого не змінювати, лише показати план |
| --yes / -y | Автоматична згода |
| --no-color | Вимкнути кольори |
| --verbose / -v | Детальні логи |
| --sync-delete | Видаляти зайве (потребує backup) |
| --no-backup | Не робити захисний backup |
| --configs-only | Тільки конфіги |
| --no-configs | Тільки пакети |
| --strict-configs | Відсутній конфіг = помилка |
| --all | Усі модулі |
