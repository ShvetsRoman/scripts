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
    ./setup.sh dotfiles backup changed [шлях...]
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
    ./setup.sh sources add zsh home .zshrc .zshrc
    ./setup.sh sources add nginx system /etc/nginx nginx-conf
    ./setup.sh sources remove zsh

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

### Reliability (v1.1.0)

- `./setup.sh sources validate` — перевірка всього реєстру.
- Код виходу `75` — інший процес Setup Manager вже виконує запис; `SETUP_LOCK_TIMEOUT=0..300` — очікування lock.

## v1.2.0: планування, перевірки та відновлення

```bash
./setup.sh dotfiles plan backup             # лише план HOME → dotfiles
./setup.sh dotfiles plan restore nvim       # лише план dotfiles → HOME
./setup.sh --sync-delete dotfiles plan restore nvim  # показати можливі DELETE
./setup.sh dotfiles verify                  # усього реєстру, без запису
./setup.sh dotfiles verify nvim             # лише вибраний шлях
./setup.sh recovery list
./setup.sh recovery verify ID              # цілісність контрольних сум
./setup.sh recovery restore ID             # спочатку verify, потім підтвердження
SETUP_NO_CLEAR=true ./setup.sh dotfiles status
./setup.sh test                             # clear автоматично вимкнено
```

`dotfiles status`, `dotfiles diff`, `dotfiles verify`: код 0 — перевірку виконано (зокрема коли файли різні або відсутні); код 2 — помилка. Для обробки розбіжностей у скриптах аналізуй мітки `[CHANGED]`, `[NEW]`, `[DEL]`, `[MISSING]`.
`recovery verify`: 0 — контрольні суми збігаються, 3 — попередня версія без checksums, 1/2 — пошкодження/помилка.

## v1.3.0 — Stability & Logging

```bash
./setup.sh dotfiles backup changed           # усі нові / змінені
./setup.sh dotfiles backup changed nvim zsh  # лише nvim та zsh
./setup.sh --dry-run dotfiles backup changed
./setup.sh dotfiles plan backup              # план (читання)

./setup.sh backups list dotfiles
./setup.sh backups verify dotfiles ID
./setup.sh recovery plan ID
./setup.sh recovery plan ID zsh              # точне ім'я із manifest.tsv
./setup.sh recovery restore ID zsh           # підтвердження й відновлення тільки zsh

./setup.sh --dry-run maintenance rotate dotfiles 10
./setup.sh maintenance rotate dotfiles 10
./setup.sh logs path
./setup.sh logs tail 100
```

- `backup changed`: якщо джерело відсутнє, запис позначається MISSING і пропускається; помилки порівняння не замовчуються. Підсумок — **кількість записів**, а не фізичних файлів.
- `backups verify` — 0 (підтверджено), 1/2 (помилка), 3 (legacy без перевірених контрольних сум). Перевірка SHA-256 **не є цифровим підписом**.
- `recovery plan` не створює lock, нічого не змінює. `recovery restore` виконується під lock, але rollback діє лише на поточний об'єкт.
- `maintenance rotate` доступний для `dotfiles`, `recovery`, `installer` і зберігає принаймні один backup.
- Коди завершення: 0 — успіх; 1 — помилка / розбіжності; 2 — некоректний виклик/небезпечний шлях; 3 — legacy backup без checksum; 75 — зайнятий lock.
