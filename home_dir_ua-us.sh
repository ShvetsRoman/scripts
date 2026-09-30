 #!/bin/bash

rm -r "$HOME"/Відео
rm -r "$HOME"/Документи
rm -r "$HOME"/Завантaжене
rm -r "$HOME"/Картинки
rm -r "$HOME"/Музика
rm -r "$HOME"/Загальне
rm -r "$HOME"/Стільниця
rm -r "$HOME"/Шаблони

rm "$HOME"/.config/user-dirs.dirs

LC_ALL=C xdg-user-dirs-update --force
