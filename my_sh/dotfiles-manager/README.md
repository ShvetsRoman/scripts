# dotfiles-manager 3.0

Модульний менеджер dotfiles для Arch Linux/Linux.

## Можливості

- модульна Bash-структура;
- окремий `config/dotfiles.conf`;
- Smart Status: `OK`, `CHANGED`, `MISSING`, `NEW`;
- backup всього або конкретного шляху;
- `backup changed`;
- restore всього або конкретного шляху;
- recovery snapshots;
- verify;
- tar.gz archive;
- ShellCheck-тести;
- `--dry-run`, `--yes`, `--verbose`;
- блокування через `flock`.

## Встановлення

```bash
chmod +x dotfiles-manager tests/*.sh
sudo pacman -S rsync diffutils findutils util-linux git tar shellcheck
```

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

./dotfiles-manager git init
./dotfiles-manager git save "update nvim"
./dotfiles-manager git status
./dotfiles-manager git log
```

## Тести

```bash
./tests/run-tests.sh
```

або:

```bash
make test
make shellcheck
```
