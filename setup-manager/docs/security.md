# Безпека

## Шляхи

  path_ok_rel — забороняє .., ., абсолютні шляхи, ./, нові рядки
  path_ok_abs — забороняє .. і symlink у будь-якому компоненті шляху
  safe_dir    — те саме для каталогів перед очищенням

## Файлові операції

  fs_copy    використовує --safe-links
  fs_protect завжди без --delete
  apply      перед записом робить backup у backups/<group>/
  --sync-delete без --no-backup заборонено

## Архіви

Перед restore архів проходить archive_safe.py verify:

  - перший компонент шляху — dotfiles/
  - відсутність .., ., абсолютних шляхів, зворотних слешів, NUL
  - відсутність symlink і hardlink
  - відсутність дублікатів
  - сумарний розмір не більше 2 ГБ, кількість не більше 100k

Перед заміною dotfiles/ створюється захисний архів поточного стану.

## Оновлення коду

update_safe.py оновлює ЛИШЕ:

  setup.sh, README.md — верхній рівень
  lib/, modules/, tests/, tools/, docs/ — каталоги

Ніколи не торкається dotfiles/, backups/, archives/, logs/, config/.
Атомарний запис через os.replace, повний rollback при помилці,
бекап старого коду у backups/updates/code-<timestamp>/.
