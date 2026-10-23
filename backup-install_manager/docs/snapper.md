# Snapper у Backup Install Manager

Модуль `snapper` описано у `config/packages.conf` і він встановлює `snapper`, `snap-pac`, `grub-btrfs`; hook розташований у `hooks/snapper.sh`.

```bash
./backup-install_manager.sh packages --dry-run snapper
./backup-install_manager.sh packages snapper
./backup-install_manager.sh doctor
```

Перед запуском перегляньте `hooks/snapper.sh`: hook може змінювати системну конфігурацію, політики снапшотів та systemd-таймери. Для Btrfs перевірте існуючі конфігурації Snapper і систему монтування subvolume. Не вмикайте новий розклад автоматично, якщо у вас уже діють користувацькі таймери.
