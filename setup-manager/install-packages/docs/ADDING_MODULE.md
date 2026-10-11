# Як додати програму або модуль (V2.0 — Unified Modules)

1. Для нової програми в існуючому модулі відкрийте `modules/cli.sh` (або інший потрібний файл).
2. Додайте пакет до `PACMAN_PACKAGES` або `AUR_PACKAGES`.
3. За потреби додайте `CONFIG_ITEMS`: `"ID|home|.config/app|.config/app"` (джерело з `DOTFILES_DIR`) або `"ID|system|etc/app.conf|/etc/app.conf"`.
4. Для нового модуля скопіюйте `templates/module.sh` до `modules/mytools.sh` і змініть `MODULE_ID`, `MODULE_TITLE`, `MODULE_ORDER` та масиви. Інших файлів змінювати не треба.
5. Для особливої дії допишіть у **цей самий файл** функцію `configure_mytools()` і задайте `MODULE_POST_HOOK="configure_mytools"`. Виконуйте змінювальні команди через `run_cmd`, щоб підтримати `--dry-run`.
6. Запустіть `bash tests/run-tests.sh`, `./install.sh --list`, `./install.sh --dry-run mytools`.

**Зовнішні програми:** у `GITHUB_ITEMS` формат `ID|TYPE|URL|CHECK_COMMAND[|DEST|EXEC_REL]`. Типи: `script`, `git`, `binary`. Уважно перевіряйте URL і код сторонніх інсталяторів; за можливості використовуйте контрольні суми і закріплені версії.

**Важливо:** файли `modules/*.sh` виконуються через `source` при побудові реєстру. Команди з побічними діями не розміщуйте на верхньому рівні; лише всередині post-install функцій. Нестандартні hooks повинні перевіряти `DRY_RUN` або використовувати `run_cmd`.
