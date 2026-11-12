# Реєстр джерел Dotfiles

`config/dotfiles.conf` визначає, що з домашнього каталогу або системних шляхів зіставляється з репозиторієм `dotfiles/`. Для коректного синтаксису орієнтуйтеся на наявний файл реєстру; парсер перевіряє його при `sources validate`.

```bash
./backup-install_manager.sh sources list                # поточний реєстр джерел
./backup-install_manager.sh sources validate            # перевірка схеми реєстру
./backup-install_manager.sh sources doctor              # чи існують шляхи на диску
./backup-install_manager.sh sources scan                # що є у $HOME поза реєстром
./backup-install_manager.sh dotfiles groups             # перелік груп реєстру
./backup-install_manager.sh dotfiles status --group cli # статус лише групи cli
```

Для додавання використовуйте `sources add NAME TYPE PATH GROUP`; доступні типи `home` та `system`, а також порожнє поле для абсолютного шляху. Для видалення запису з реєстру: `sources remove NAME` (перевірте результат перед іншими операціями).

Об'єкти `[UNTRACKED]` уже лежать у репозиторії, але не описані реєстром. `[NEW]` — присутні у HOME; `[DEL]` — у сховищі dotfiles. Не виконуйте `--sync-delete`, доки не розберете всі такі елементи.
