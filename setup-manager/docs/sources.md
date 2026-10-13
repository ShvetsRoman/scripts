# Формат config/sources.conf

Один рядок = одне джерело. Поля розділені символом вертикальної риски.

    mode | src | dst | group

Поля:

  mode   home (src відносно $HOME) або abs (src абсолютний)
  src    шлях-джерело
  dst    шлях у dotfiles/<dst>
  group  підкаталог backups/<group>/ (dotfiles або recovery)

Пробіли навколо полів ігноруються. Рядки, що починаються з # — коментарі.

## Приклади

    home | .zshrc          | .zshrc          | dotfiles
    home | .config/nvim    | .config/nvim    | dotfiles
    abs  | /etc/nginx      | nginx-conf      | dotfiles

## Правила безпеки

  src при mode=home — має бути відносним і без ..
  src при mode=abs  — має бути абсолютним і без symlink у батьках
  dst               — має бути відносним без ..
  Дублікат dst      — заборонено

## Runtime

Програма читає ЛИШЕ цей файл. Ніяких евристик під час backup.
Команди scan і seed — лише допомагають редагувати файл вручну.

## Категорії, які ніколи не додаються автоматично

.ssh, .gnupg, .wireguard, .pki, .cache, .cargo, .npm, .zsh_history,
.bash_history, .config/google-chrome, Downloads, Videos, Pictures,
Documents, Music, .steam, .lmstudio.
