# Фізичні інтерфейси, Bridge, LAN та WAN

`interfaces.toml` описує **лише фізично наявні порти**, якими потрібно керувати. Наявні назви мають формат `etherN`, `sfpN`, `wlanN` (додатне `N`, без жорсткого верхнього обмеження). Автоматичного виявлення обладнання немає.

Для Ethernet/SFP `enabled = true` відповідає `disabled=no`, `enabled = false` — `disabled=yes`. Перейменування відбувається за RouterOS `default-name`. Для `wlanN` команди формує окремий Wireless-модуль, а не `/interface ethernet`.

`hap-ac`: WAN `ether1`, LAN `ether2`–`ether5`, Wi-Fi `wlan1`/`wlan2`, фізичний `sfp1` вимкнений. `test`: WAN `ether1`, LAN `ether2`–`ether5`, Wi-Fi і SFP не налаштовуються. Це лише поточні приклади профілів, **не** зашиті в код правила.

`bridge.toml` визначає `bridge.lan` і його фізичні порти; посилання мають відповідати оголошеним та активним інтерфейсам. `network.toml` задає IP LAN, WAN і Management. Поточна Management-адреса використовується на LAN bridge. WAN і критичний Management не слід вимикати.

```bash
cargo run -- plan hap-ac interfaces
cargo run -- plan hap-ac bridge
cargo run -- plan hap-ac network
```

Перевірка `plan` — статична: вона не доводить, що заводський `default-name` справді існує на пристрої. До встановлення звірте фактичні порти RouterOS.
