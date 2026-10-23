# Реєстр джерел Dotfiles

`config/dotfiles.conf` визначає, що з домашнього каталогу або системних шляхів зіставляється з репозиторієм `dotfiles/`. Для коректного синтаксису орієнтуйтеся на наявний файл реєстру; парсер перевіряє його при `sources validate`.

```bash
./backup-install_manager.sh sources list
./backup-install_manager.sh sources validate
./backup-install_manager.sh sources doctor
./backup-install_manager.sh sources scan
./backup-install_manager.sh dotfiles groups
./backup-install_manager.sh dotfiles status --group cli
```

Для додавання використовуйте `sources add NAME TYPE PATH GROUP`; доступні типи `home` та `system`, а також порожнє поле для абсолютного шляху. Для видалення запису з реєстру: `sources remove NAME` (перевірте результат перед іншими операціями).

Об'єкти `[UNTRACKED]` уже лежать у репозиторії, але не описані реєстром. `[NEW]` — присутні у HOME; `[DEL]` — у сховищі dotfiles. Не виконуйте `--sync-delete`, доки не розберете всі такі елементи.
