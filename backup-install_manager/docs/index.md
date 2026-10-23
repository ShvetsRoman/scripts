# Документація Backup Install Manager

Це документація до Backup Install Manager v2.0.2. Перед використанням команд перейдіть до кореня проєкту: `cd ~/Documents/backup-install_manager`.

- [Початок роботи та типові сценарії](guide.md)
- [Повний довідник CLI-команд](commands.md)
- [Конфігураційні файли](configuration.md)
- [Реєстр джерел Dotfiles](sources.md)
- [Backup, Recovery та захист даних](security.md)
- [Архітектура й структура](architecture.md)
- [Snapper](snapper.md)
- [Тести, діагностика та проблеми](troubleshooting.md)
- [Історія документації](CHANGELOG.md)

**Безпека:** спочатку запускайте `--dry-run` чи `plan` для операцій запису. `--yes` пропускає запити підтвердження. `--sync-delete` може видаляти зайві файли на цільовій стороні. Remote Sync (ПК ↔ сервер) **не входить** до цієї версії й не документується як доступна команда.

- [Аудит поточного архіву](audit-2026-10-22.md)

- [Стабільна база v2.0.1 та обсяг v2.0.2](stable-baseline-v202.md)
