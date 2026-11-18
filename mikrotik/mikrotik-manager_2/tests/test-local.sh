#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/routers/hap-ac"
cp "$ROOT/setup.sh" "$TMP/setup.sh"
cp "$ROOT/routers/hap-ac/config.rsc" "$TMP/routers/hap-ac/config.rsc"
sed -i \
  -e 's/ЗАМІНІТЬ_ПАРОЛЬ_АДМІНА/TestAdminPass-2026!/' \
  -e 's/ЗАМІНІТЬ_ПАРОЛЬ_WIFI/TestWifiPass-2026!/' \
  -e 's/ЗАМІНІТЬ_ПАРОЛЬ_ГОСТЯ/TestGuestPass-2026!/' \
  -e 's/ЗАМІНІТЬ_ПАРОЛЬ_IOT/TestIotPass-2026!/' \
  -e 's/ЗАМІНІТЬ_КЛЮЧ_WG/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=/' \
  "$TMP/routers/hap-ac/config.rsc"
bash -n "$TMP/setup.sh"
python3 "$ROOT/tests/test-rsc-static.py"
"$TMP/setup.sh" --name hap-ac --dry-run >/dev/null

# Другий профіль також проходить локальні перевірки setup.sh (dry-run
# дозволяє плейсхолдери, бо не виконує мережевих дій).
mkdir -p "$TMP/routers/vbox-test"
cp "$ROOT/routers/vbox-test/config.rsc" "$TMP/routers/vbox-test/config.rsc"
"$TMP/setup.sh" --name vbox-test --dry-run >/dev/null
if "$TMP/setup.sh" --name '../hap-ac' --dry-run >/dev/null 2>&1; then
  echo "FAIL: invalid router name accepted" >&2; exit 1
fi
sed -i 's/:global routerSshPort 22/:global routerSshPort 70000/' "$TMP/routers/hap-ac/config.rsc"
if "$TMP/setup.sh" --name hap-ac --dry-run >/dev/null 2>&1; then
  echo "FAIL: invalid SSH port accepted" >&2; exit 1
fi
# Усі три явні варіанти драйвера приймаються локальним setup.sh.
for driver in legacy wifi-qcom-ac wifi-qcom; do
  cp "$ROOT/routers/hap-ac/config.rsc" "$TMP/routers/hap-ac/config.rsc"
  sed -i "s/:global wifiDriver \"legacy\"/:global wifiDriver \"$driver\"/" "$TMP/routers/hap-ac/config.rsc"
  "$TMP/setup.sh" --name hap-ac --dry-run >/dev/null
 done

# Невідомий драйвер відхиляється, коли Wi-Fi увімкнений.
cp "$ROOT/routers/hap-ac/config.rsc" "$TMP/routers/hap-ac/config.rsc"
sed -i 's/:global wifiDriver "legacy"/:global wifiDriver "unknown"/' "$TMP/routers/hap-ac/config.rsc"
if "$TMP/setup.sh" --name hap-ac --dry-run >/dev/null 2>&1; then
  echo "FAIL: невідомий Wi-Fi драйвер прийнято" >&2; exit 1
fi

# Коли обидва діапазони вимкнені, драйвер не перевіряється та Wi-Fi секрети не потрібні.
cp "$ROOT/routers/hap-ac/config.rsc" "$TMP/routers/hap-ac/config.rsc"
sed -i \
  -e 's/:global enableWifi2Ghz true/:global enableWifi2Ghz false/' \
  -e 's/:global enableWifi5Ghz true/:global enableWifi5Ghz false/' \
  -e 's/:global wifiDriver "legacy"/:global wifiDriver "ignored-when-disabled"/' \
  "$TMP/routers/hap-ac/config.rsc"
DRY_OUTPUT="$("$TMP/setup.sh" --name hap-ac --dry-run 2>&1)"
if grep -Eq 'wifiPassword|guestPassword|iotPassword' <<<"$DRY_OUTPUT"; then
  echo "FAIL: Wi-Fi secrets required while both bands are disabled" >&2; exit 1
fi
if ! grep -q 'Wi-Fi: вимкнений' <<<"$DRY_OUTPUT"; then
  echo "FAIL: dry-run не повідомив про вимкнений Wi-Fi" >&2; exit 1
fi

printf '%s\n' "PASS: local setup.sh tests"
