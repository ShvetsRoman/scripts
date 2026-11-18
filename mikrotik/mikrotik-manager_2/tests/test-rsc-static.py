#!/usr/bin/env python3
"""Статичні структурні перевірки RouterOS script (не замінюють імпорт у CHR)."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
profiles = sorted((root / "routers").glob("*/config.rsc"))
if not profiles:
    raise SystemExit("FAIL: не знайдено жодного профілю routers/*/config.rsc")


def strip_code(source: str) -> str:
    # Спочатку видаляємо рядки в лапках, потім коментарі: інакше "#" усередині
    # значення (наприклад, пароля) обріже код і спотворить результат.
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    code = "\n".join(line.split("#", 1)[0] for line in code.splitlines())
    return code


# Плейсхолдери, які очікуються в профілях і обробляються check_secret у setup.sh.
ALLOWED_PLACEHOLDERS = {
    "ЗАМІНІТЬ_ПАРОЛЬ_АДМІНА", "ЗАМІНІТЬ_ПАРОЛЬ_WIFI", "ЗАМІНІТЬ_ПАРОЛЬ_ГОСТЯ",
    "ЗАМІНІТЬ_ПАРОЛЬ_IOT", "ЗАМІНІТЬ_КЛЮЧ_WG",
    "ЗАМІНІТЬ_НА_ПАРОЛЬ_SSH", "ЗАМІНІТЬ_НА_ПАРОЛЬ_ADMIN",
}

# Профільно-специфічні перевірки hap-ac: застарілі блоки, драйвери Wi-Fi,
# режими WireGuard та обов'язкові блоки (vbox-test живиться іншою схемою).
HAP_AC_OBSOLETE = (
    "enableBackup", "backupStartTime", "enableNightLed", "nightLedInterval",
    "backup-daily", "/system scheduler", "/ip firewall raw",
    "/ip firewall connection tracking",
)
HAP_AC_REQUIRED_TEXT = (
    "/interface wireless", "/interface wifi", "datapath.client-isolation=yes",
)
# Вибір драйвера звіряється без прив'язки до відступів.
HAP_AC_WIFI_GUARD = re.compile(
    r':if\s+\(\(\$enableWifi2Ghz = true\) or \(\$enableWifi5Ghz = true\)\) do=\{'
    r'\s*:if\s+\(\$wifiDriver = "legacy"\) do=\{',
    re.S,
)

for path in profiles:
    profile = path.parent.name
    source = path.read_text(encoding="utf-8")
    code = strip_code(source)

    for opening, closing in (("{", "}"), ("(", ")")):
        depth = 0
        for char in code:
            if char == opening:
                depth += 1
            elif char == closing:
                depth -= 1
            if depth < 0:
                raise SystemExit(f"FAIL [{profile}]: зайва закривальна дужка {closing}")
        if depth:
            raise SystemExit(f"FAIL [{profile}]: незбалансовані дужки {opening}{closing}: {depth}")

    globals_declared = set(re.findall(r"^:global\s+([A-Za-z][A-Za-z0-9]*)", source, re.M))
    globals_declared |= set(re.findall(r"^\s*:local\s+([A-Za-z][A-Za-z0-9]*)", source, re.M))
    variables_used = set(re.findall(r"\$([A-Za-z][A-Za-z0-9]*)", code))
    missing = sorted(variables_used - globals_declared - {"p"})
    if missing:
        raise SystemExit(f"FAIL [{profile}]: невизначені змінні: " + ", ".join(missing))

    placeholders = set(re.findall(r"ЗАМІНІТЬ_[A-ZА-ЯІЇЄ_0-9]+", source))
    unknown = sorted(placeholders - ALLOWED_PLACEHOLDERS)
    if unknown:
        raise SystemExit(
            f"FAIL [{profile}]: незнайомі плейсхолдери (додайте обробку в setup.sh): "
            + ", ".join(unknown)
        )

    # Порти служб задаються змінними, а доступ через WG — тумблерами:
    # жорсткий порт 8291 або безумовний wgNet у available-from — регресія.
    if re.search(r"set winbox port=8291", code):
        raise SystemExit(f"FAIL [{profile}]: жорсткий порт 8291 у /ip service set winbox")
    if "available-from=$netLan,$wgNet" in code:
        raise SystemExit(f"FAIL [{profile}]: безумовний wgNet у available-from")

    if profile == "hap-ac":
        for obsolete in HAP_AC_OBSOLETE:
            if obsolete in source:
                raise SystemExit(f"FAIL [hap-ac]: залишився застарілий блок: {obsolete}")
        for required in HAP_AC_REQUIRED_TEXT:
            if required not in source:
                raise SystemExit(f"FAIL [hap-ac]: відсутній обов'язковий фрагмент: {required}")
        if not HAP_AC_WIFI_GUARD.search(source):
            raise SystemExit("FAIL [hap-ac]: відсутній блок вибору Wi-Fi драйвера legacy")
        for driver in ('"legacy"', '"wifi-qcom-ac"', '"wifi-qcom"'):
            if driver not in source:
                raise SystemExit(f"FAIL [hap-ac]: відсутній Wi-Fi драйвер {driver}")
        for mode in ('"ip"', '"mikrotik-ddns"', '"disabled"'):
            if mode not in source:
                raise SystemExit(f"FAIL [hap-ac]: відсутній режим WireGuard {mode}")

print(f"PASS: структура RSC, змінні, плейсхолдери для {len(profiles)} профілів")
