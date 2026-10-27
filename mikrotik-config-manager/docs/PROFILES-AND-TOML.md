# Профілі та TOML

Проєкт виявляє профілі в `routers/` за наявністю повного набору конфігураційних файлів. Назви `test` та `hap-ac` не мають особливих правил обробки; конфігурації мають визначати все необхідне для конкретного маршрутизатора.

У корені проєкту `config/manager.toml` керує параметрами менеджера; у кожного профілю окремі `interfaces.toml`, `bridge.toml`, `network.toml`, `dhcp.toml`, `dns.toml`, `firewall.toml`, `nat.toml`, `lists.toml`, `wireless.toml`, `wireguard.toml`, `system.toml`, `services.toml`, `ipv6.toml`, `connection.toml`.

## Приклади чинної схеми

```toml
[interfaces.ether1]
name = "00_wan"
enabled = true
comment = "physical_port"

[interfaces.sfp1]
name = "SFP"
enabled = false
comment = "unused"
```

```toml
[network.lan]
interface = "@bridge.lan"
address = "192.168.88.1/24"

[management]
interface = "@bridge.lan"
address = "192.168.88.1/24"
```

Поля та вкладені таблиці **не можна вигадувати**: конфігурація проходить сувору десеріалізацію Serde. Зберігайте існуючі секції, типи, назви ресурсів і посилання `@...`; перевіряйте зміни командою `./scripts/check.sh`. Для нового пристрою скопіюйте повний набір файлів профілю й налаштуйте їх під фактичні фізичні порти, LAN і WAN.

Логічні ID (`ether1`, `bridge.lan`) відділені від RouterOS-імен (`00_wan`, `bridge-lan`), тому перейменування не потребує зміни всіх посилань.
