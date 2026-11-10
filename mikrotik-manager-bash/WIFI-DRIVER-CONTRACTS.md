# Wi-Fi Driver Contracts

Документ фіксує контракт між TOML-профілем, валідатором та генератором RouterOS RSC.

## 1. Загальні правила

- `wireless.driver` у `[wireless]` файлу `profiles/<profile>/config.toml` — єдине джерело вибору драйвера. CLI-перемикача та автоматичного визначення за моделлю немає.
- Дозволені значення: `legacy`, `wifi-qcom-ac`, `wifi-qcom`; `none` означає вимкнену Wi-Fi підсистему та не є активним драйвером.
- Конфігурація повністю ID-free: окремого поля `id` немає ні в секціях, ні в схемі, ні в генераторі.
- Посилання мають формат `@section.path`, наприклад `@interfaces.wlan1` або `@security.wifi`; шлях повний і чутливий до регістру.
- Ім’я секції є ключем пошуку об’єкта. SSH key ідентифікується fingerprint (SHA256 тіла ключа); `key-owner` не використовується. Тимчасовий файл називається на основі імені користувача.
- Псевдонім `wifi` не підтримується: драйвер має бути визначений однозначно.
- `wireless.enabled = true` і активний Wi-Fi driver потрібні для генерації Wi-Fi інтерфейсів.
- Кожен активний `[wireless.<radio>]` потребує `interface`, `ssid`, `band`, `security`.
- SSID має містити 1–32 байти UTF-8.
- `frequency = "auto"` не генерує параметр частоти. Інші частоти проходять driver-specific перевірку.
- Назва країни передається як `configuration.country` у новому Wi-Fi stack і `country` у legacy.
- Можливості конкретного радіо залежать від моделі пристрою та регуляторного домену; статична схема не може гарантувати, що будь-який дозволений band підтримується конкретним радіо.

## 2. Driver `legacy`

RouterOS menu: `/interface wireless`.

### Дозволені band

- 2.4 GHz: `2ghz-b`, `2ghz-b/g`, `2ghz-b/g/n`, `2ghz-g/n`, `2ghz-onlyg`, `2ghz-onlyn`.
- 5 GHz: `5ghz-a`, `5ghz-a/n`, `5ghz-onlyn`, `5ghz-a/n/ac`, `5ghz-onlyac`, `5ghz-n/ac`.

### Дозволені channel width

Legacy extension-channel syntax зберігається без перетворень: `20mhz`, `10mhz`, `5mhz`, `40mhz-turbo`, `20/40mhz-*`, `20/40/80mhz-*`, `20/40/80/160mhz-*` з підтримуваними RouterOS extension layouts.

### Security

PSK only: `wpa-psk`, `wpa2-psk` або їх комбінація. Пароль 8–63 символи. Пароль генерується через `/interface wireless security-profiles`.

### Bridge

Основний Wi-Fi та guest VAP додаються до bridge окремою командою `/interface bridge port add`.

## 3. Driver `wifi-qcom-ac`

RouterOS menu: `/interface wifi`. Призначений для сумісних 802.11ac пристроїв із пакетом `wifi-qcom-ac`.

### Дозволені band

`2ghz-g`, `2ghz-n`, `5ghz-a`, `5ghz-an`, `5ghz-ac`.

AX та 6 GHz заборонені цим контрактом.

### Дозволені channel width

`20mhz`, `20/40mhz`, `20/40mhz-Ce`, `20/40mhz-eC`, `20/40/80mhz`.

Ширина 160 MHz і 80+80 MHz заборонена.

### Security

PSK only: `wpa2-psk`, `wpa3-psk` або їх комбінація. Пароль 8–63 символи. Параметри передаються inline: `security.authentication-types` та `security.passphrase`.

### Bridge

`datapath.bridge` додає Wi-Fi інтерфейс до bridge автоматично. Дублюючий `/interface bridge port add` не генерується.

## 4. Driver `wifi-qcom`

RouterOS menu: `/interface wifi`. Призначений для сумісних 802.11ax пристроїв із пакетом `wifi-qcom`.

### Дозволені band

`2ghz-g`, `2ghz-n`, `2ghz-ax`, `5ghz-a`, `5ghz-an`, `5ghz-ac`, `5ghz-ax`, `6ghz-ax`.

### Дозволені channel width

`20mhz`, `20/40mhz`, `20/40mhz-Ce`, `20/40mhz-eC`, `20/40/80mhz`, `20/40/80+80mhz`, `20/40/80/160mhz`.

### Security та bridge

Такий самий PSK-контракт і bridge-поведінка, як у `wifi-qcom-ac`.

## 5. Guest Wi-Fi

- `wireless.guest.masters` має містити щонайменше одне унікальне посилання на активне Wi-Fi радіо.
- Guest VAP створюється окремою командою для відповідного меню драйвера.
- Для `legacy` після створення VAP створюється bridge port.
- Для `wifi-qcom-ac` і `wifi-qcom` команда створення VAP містить `datapath.bridge=<guest bridge>`; окремий bridge port не створюється.
- Guest security має власний PSK secret і проходить той самий driver-specific authentication contract.

## 6. Межі гарантій

Тести перевіряють TOML validation, RSC text generation, збереження точних band/width значень і відсутність дублюючих bridge port команд. Вони не замінюють перевірку на конкретному RouterOS пристрої. Перед застосуванням потрібно звірити фактичні можливості радіо через `/interface wifi radio print detail` та перевірити сумісність пакета з архітектурою/моделлю пристрою.
