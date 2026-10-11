Модульний менеджер dotfiles для Arch Linux/Linux.

## Основні команди

```bash
./dotfiles-manager config list
./dotfiles-manager status

./dotfiles-manager backup
./dotfiles-manager backup .config/nvim
./dotfiles-manager backup changed

./dotfiles-manager restore .zshrc
./dotfiles-manager diff .config/nvim
./dotfiles-manager verify

./dotfiles-manager archive create
./dotfiles-manager archive list ./dotfiles-backup-YYYY-MM-DD_HH-MM-SS.tar.gz
./dotfiles-manager archive restore ./dotfiles-backup-YYYY-MM-DD_HH-MM-SS.tar.gz

## Тести

```bash
./tests/run-tests.sh
```
або:

```bash
make test
make shellcheck
```
