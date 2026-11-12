# Документація Backup Install Manager

Документація до Backup Install Manager v2.0.2 — інсталятора Arch Linux, менеджера dotfiles і бекапів.

> **Де запускати команди.** Усі приклади виконуються з кореня проєкту — каталогу, де лежить `backup-install_manager.sh` (у цьому середовищі: `~/00_setup/scripts_bash/backup-install_manager`).

## Основні документи

| Документ | Призначення |
|---|---|
| [guide.md](guide.md) | Початок роботи та типові сценарії |
| [commands.md](commands.md) | Повний довідник CLI-команд |
| [configuration.md](configuration.md) | Конфігураційні файли (`setup.conf`, `packages.conf`, `dotfiles.conf`) |
| [sources.md](sources.md) | Реєстр джерел Dotfiles |
| [security.md](security.md) | Backup, Recovery та захист даних |
| [architecture.md](architecture.md) | Архітектура й структура каталогів |
| [snapper.md](snapper.md) | Модуль Snapper (снапшоти Btrfs) |
| [troubleshooting.md](troubleshooting.md) | Тести, діагностика та проблеми |
| [CHANGELOG.md](CHANGELOG.md) | Історія документації |

## Додаткові звіти

| Документ | Призначення |
|---|---|
| [audit-2026-10-22.md](audit-2026-10-22.md) | Аудит поточного архіву |
| [stable-baseline-v202.md](stable-baseline-v202.md) | Стабільна база v2.0.1 та обсяг v2.0.2 |

## Безпека

Спочатку запускайте `--dry-run` чи `plan` для операцій запису. `--yes` пропускає запити підтвердження. `--sync-delete` може видаляти зайві файли на цільовій стороні. Remote Sync (ПК ↔ сервер) **не входить** до цієї версії й не документується як доступна команда.
