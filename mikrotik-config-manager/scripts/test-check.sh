#!/usr/bin/env bash
# Перевірка синтаксису runner та наявності необхідних файлів.
set -Eeuo pipefail
bash -n scripts/check.sh
[[ ! -e routers/chr ]]
grep -q 'PROJECT_VERSION=' scripts/check.sh
grep -q "run_stage 'TOML documentation' python3 tests/check_toml_documentation.py" scripts/check.sh
for file in Cargo.toml src/main.rs src/app.rs src/config.rs src/i18n.rs src/logging.rs src/routeros.rs src/modules/mod.rs src/modules/network.rs src/modules/dhcp.rs src/modules/dns.rs src/modules/firewall.rs routers/test/dns.toml routers/test/firewall.toml locales/uk.lang locales/en.lang; do
    [[ -f "$file" ]]
done
while IFS= read -r -d '' shfile; do
    [[ -x "$shfile" ]]
done < <(find scripts -type f -name '*.sh' -print0)
printf '[PASS] Необхідні файли та Bash syntax\n'
