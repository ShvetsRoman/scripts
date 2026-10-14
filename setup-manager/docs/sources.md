# Реєстр `config/sources.conf`

Формат рядка: `name | mode | src | dst | group`.

- `name`: унікальний ID `[A-Za-z0-9._-]+`;
- `mode`: `home` (src відносно `$HOME`), `abs` або `system` (src абсолютний);
- `src`: шлях до оригінального файлу чи каталогу;
- `dst`: безпечний відносний шлях усередині `dotfiles/`;
- `group`: безпечний ID групи для backups (типово `dotfiles`).

```text
zsh | home | .zshrc | .zshrc | dotfiles
nvim | home | .config/nvim | .config/nvim | dotfiles
samba | system | /etc/samba/smb.conf | etc/samba/smb.conf | dotfiles
```

Додавання: `./setup.sh sources add NAME MODE SRC DST [GROUP]`.
Для сумісності також приймається `sources add MODE SRC DST` (NAME = basename DST).
Видалення: `./setup.sh sources remove NAME`.
Перегляд: `./setup.sh sources list`, `sources doctor`, `sources scan`.

Валідація виконується при читанні реєстру: рівно 5 полів, безпечний синтаксис шляхів, унікальні NAME/DST. Файлові symlink у джерелах для копіювання поки не підтримуються.
