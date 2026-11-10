#!/usr/bin/env bash
# Комплексні локальні тести MikroTik Manager Bash.
set -uo pipefail
if (( $# )); then
  printf 'Помилка: run-tests.sh не приймає аргументи. Параметри --build/--upload/--reset належать mikrotik-manager.sh.\n' >&2
  exit 2
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.ssh"
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeTestPublicKeyOnly mikrotik-manager-test' > "$TMP/home/.ssh/id_mikrotik_lab.pub"
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeTestRomanKey roman-test' > "$TMP/home/.ssh/roman.pub"
printf '%s\n' 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQFakeBackupKey backup-test' > "$TMP/home/.ssh/backup.pub"
export HOME="$TMP/home"
# Python engine використовує лише стандартну бібліотеку; -S прискорює багаторазові
# тестові запуски, не завантажуючи сторонні site-packages з тестового середовища.
REAL_PYTHON3=$(command -v python3)
mkdir -p "$TMP/test-bin"
cat > "$TMP/test-bin/python3" <<EOF
#!/bin/sh
exec "$REAL_PYTHON3" -S "\$@"
EOF
chmod 755 "$TMP/test-bin/python3"
export PATH="$TMP/test-bin:$PATH"
PASS=0; FAIL=0; SKIP=0; TOTAL=0

# Визначення тестових профілів за можливостями конфігурації, а не за назвою каталогу.
CHR_PROFILE=""; HOME_PROFILE=""
for _d in "$ROOT/profiles"/*; do
  [[ -d $_d && -f $_d/config.toml ]] || continue
  _n=${_d##*/}
  if grep -Eq '^supported = false([[:space:]]|$)' "$_d/config.toml" && grep -q '^\[interfaces\.ether6\]' "$_d/config.toml"; then
    CHR_PROFILE=$_n
  elif grep -q '^\[wireless\]' "$_d/config.toml"; then
    HOME_PROFILE=$_n
  fi
done

pass() { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf 'FAIL: %s\n' "$1"; }
skip() { SKIP=$((SKIP+1)); TOTAL=$((TOTAL+1)); printf 'SKIP: %s — %s\n' "$1" "$2"; }
run_ok() { "$@" >/dev/null 2>&1; }
run_fail() { ! "$@" >/dev/null 2>&1; }
check() { local label=$1; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
not_contains() { ! grep -Fq "$2" "$1"; }

# Створюємо синтетичні секрети лише в тимчасових копіях проєкту.
# Тестовий набір не залежить від приватних .secrets користувача або релізного архіву.
seed_test_secrets() {
  python3 - "$1/profiles" <<'PYSECRETS'
import pathlib, sys, tomllib
root = pathlib.Path(sys.argv[1])
for profile in root.iterdir():
    config = profile / "config.toml"
    if not profile.is_dir() or not config.is_file():
        continue
    data = tomllib.loads(config.read_text(encoding="utf-8"))
    keys = set()
    def walk(value):
        if isinstance(value, dict):
            if value.get("password_file") == ".secrets" and value.get("password_key"):
                keys.add(value["password_key"])
            for child in value.values(): walk(child)
        elif isinstance(value, list):
            for child in value: walk(child)
    walk(data)
    if keys:
        target = profile / ".secrets"
        target.write_text("".join(f"{key}=TestOnly-{key}-Password\n" for key in sorted(keys)), encoding="utf-8")
        target.chmod(0o600)
PYSECRETS
}

printf '%s\n' '=== MikroTik Manager Bash — test suite ==='
printf '%s\n' '[1] Syntax and runtime requirements'
check 'Bash syntax' bash -n "$ROOT/mikrotik-manager.sh"
check 'Python syntax' env PYTHONPYCACHEPREFIX="$TMP/pycache" python3 -m py_compile "$ROOT/lib/toml_engine.py" "$ROOT/lib/routeros_verify.py"
check 'Python 3.11+ tomllib available' python3 -c 'import sys,tomllib; assert sys.version_info >= (3,11)'
check 'CLI help' run_ok "$ROOT/mikrotik-manager.sh" --help
check 'CLI help documents physical MikroTik setup' bash -c 'help=$("$1" --help); grep -q "Фізичний MikroTik" <<< "$help"' _ "$ROOT/mikrotik-manager.sh"
check 'CLI help documents VirtualBox CHR setup' bash -c 'help=$("$1" --help); grep -q "VirtualBox" <<< "$help"' _ "$ROOT/mikrotik-manager.sh"
check 'CLI help documents --profile' bash -c 'help=$("$1" --help); grep -q -- "--profile PROFILE" <<< "$help"' _ "$ROOT/mikrotik-manager.sh"
check 'CLI help documents upload-only behavior' bash -c 'help=$("$1" --help); grep -q "не генерує та не імпортує" <<< "$help"' _ "$ROOT/mikrotik-manager.sh"
check 'CLI help documents local read-only verification' bash -c 'help=$("$1" --help); grep -q -- "--verify" <<< "$help"' _ "$ROOT/mikrotik-manager.sh"
check 'schema.json is valid JSON' run_ok python3 -m json.tool "$ROOT/lib/schema.json"
# Кожен каталог profiles/ з config.toml має валідуватися основним CLI.
ALL_PROFILES_OK=1
for _d in "$ROOT/profiles"/*; do
  _n=${_d##*/}
  [[ -d $_d && -f $_d/config.toml ]] || continue
  "$ROOT/mikrotik-manager.sh" --validate --profile "$_n" >/dev/null 2>&1 || ALL_PROFILES_OK=0
done
check 'all discovered profiles validate with CLI' test "$ALL_PROFILES_OK" -eq 1
check 'CLI help is concise and delegates setup details to README' bash -c 'lines=$("$1" --help | wc -l); (( lines <= 70 ))' _ "$ROOT/mikrotik-manager.sh"
check 'sample profiles use optional path/backup/reset defaults' bash -c '! grep -Eq "^\[(paths|backup|reset|ipv6)\]$" "$1" "$2"' _ "$ROOT/profiles/$HOME_PROFILE/config.toml" "$ROOT/profiles/$CHR_PROFILE/config.toml"
check 'test suite discovers the lab profile by capabilities' test -n "$CHR_PROFILE"
check 'test suite discovers the physical profile' test -n "$HOME_PROFILE"
# Назви каталогів профілів не є частиною конфігураційних посилань.
mkdir -p "$TMP/renamed-project"
cp -a "$ROOT"/. "$TMP/renamed-project/"
seed_test_secrets "$TMP/renamed-project"
mv "$TMP/renamed-project/profiles/$CHR_PROFILE" "$TMP/renamed-project/profiles/lab_router"
mv "$TMP/renamed-project/profiles/$HOME_PROFILE" "$TMP/renamed-project/profiles/main_router"
check 'profiles validate and build after directory rename' bash -c '"$1/mikrotik-manager.sh" --validate --profile lab_router >/dev/null && "$1/mikrotik-manager.sh" --validate --profile main_router >/dev/null && "$1/mikrotik-manager.sh" --build --profile lab_router >/dev/null && "$1/mikrotik-manager.sh" --build --profile main_router >/dev/null && test -s "$1/profiles/lab_router/output/lab_router.rsc" && test -s "$1/profiles/main_router/output/main_router.rsc"' _ "$TMP/renamed-project"
# Конфігурація повністю ID-free: усі зв’язки адресують реальні TOML-секції.
check 'profiles are ID-free and every @section.path target exists' python3 - "$ROOT/profiles" <<'PYID'
import pathlib, sys, tomllib
root = pathlib.Path(sys.argv[1])
for path in sorted(root.glob("*/config.toml")):
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    sections, refs, ids = set(), [], []
    def walk(value, path_part=""):
        if isinstance(value, dict):
            if "id" in value: ids.append(path_part)
            if path_part: sections.add(path_part)
            for key, child in value.items():
                walk(child, f"{path_part}.{key}" if path_part else key)
        elif isinstance(value, list):
            for child in value: walk(child, path_part)
        elif isinstance(value, str) and value.startswith("@"):
            refs.append(value[1:])
    walk(data)
    missing = sorted(set(refs) - sections)
    if ids or missing: raise SystemExit(f"{path}: id_fields={ids}, missing_refs={missing}")
PYID
check 'Wi-Fi driver is selected only by wireless.driver in TOML' bash -c 'grep -q "drv=\$(cfg wireless.driver none)" "$1" && ! grep -q -- "--driver" "$1"' _ "$ROOT/mikrotik-manager.sh"
INTEGRITY_FILE=$(printf '.integrity%skey' '.')
INTEGRITY_NEEDLE=$(printf 'integrity%skey' '.')
check 'no integrity key files remain' bash -c '! find "$1" -name "$2" -print -quit | grep -q .' _ "$ROOT" "$INTEGRITY_FILE"
check 'integrity key implementation is absent' bash -c '! grep -FRqi "$2" "$1" --exclude="*.pyc" --exclude="run-tests.sh" --exclude="TEST-REPORT.md"' _ "$ROOT" "$INTEGRITY_NEEDLE"
check 'profile names with spaces are rejected' run_fail "$ROOT/mikrotik-manager.sh" --validate --profile 'lab profile'
check 'profile names with Ukrainian letters are rejected' run_fail "$ROOT/mikrotik-manager.sh" --validate --profile 'домашній'
check 'profile names with path separators are rejected' run_fail "$ROOT/mikrotik-manager.sh" --validate --profile '../chr'
check 'test runner rejects manager operation arguments' bash -c '"$1" --build --upload --profile sample -reset >/dev/null 2>&1; rc=$?; [[ $rc -eq 2 ]]' _ "$ROOT/tests/run-tests.sh"
check 'standalone launcher replaces Makefile' test ! -e "$ROOT/Makefile"
# Перевіряємо відсутність повністю видаленого VPN-модуля в коді, схемі, профілях і документації.
VPN_NEEDLE=$(printf 'wire%s' 'guard')
check 'removed VPN module absent from project sources' bash -c '! grep -Rqi "$1" "$2" --exclude=run-tests.sh --exclude="*.pyc"' _ "$VPN_NEEDLE" "$ROOT"
check 'canonical product name appears in CLI help' bash -c 'help=$("$1" --help); grep -q "MikroTik Manager Bash" <<< "$help"' _ "$ROOT/mikrotik-manager.sh"

printf '%s\n' '[2] TOML engine and schema'
check 'physical profile schema' run_ok python3 "$ROOT/lib/toml_engine.py" validate "$ROOT/profiles/$HOME_PROFILE/config.toml"
# Перевіряємо окремий legacy band, який не можна відхиляти через помилку в allowlist.
sed 's/band = "2ghz-b\/g\/n"/band = "2ghz-g\/n"/' "$ROOT/profiles/$HOME_PROFILE/config.toml" > "$TMP/legacy-g-n.toml"
check 'legacy accepts 2ghz-g/n band' run_ok python3 "$ROOT/lib/toml_engine.py" validate "$TMP/legacy-g-n.toml"
check 'chr schema' run_ok python3 "$ROOT/lib/toml_engine.py" validate "$ROOT/profiles/$CHR_PROFILE/config.toml"
cp "$ROOT/profiles/$CHR_PROFILE/config.toml" "$TMP/valid.toml"
sed 's/^enabled = false$/enabled = "false"/' "$TMP/valid.toml" > "$TMP/wrong-type.toml"
check 'negative: invalid TOML type rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/wrong-type.toml"
{ printf 'unknown_root_option = true\n'; cat "$TMP/valid.toml"; } > "$TMP/unknown-key.toml"
check 'negative: unknown key rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/unknown-key.toml"
cat "$TMP/valid.toml" > "$TMP/unknown-nested.toml"
printf '\n[interfaces.ether1.hidden]
not_a_real_option = true\n' >> "$TMP/unknown-nested.toml"
check 'negative: unknown nested table rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/unknown-nested.toml"
sed 's/^interface = "@interfaces.ether1"$/interface = "@does_not_exist"/' "$TMP/valid.toml" > "$TMP/unknown-ref.toml"
sed '/^name = /a id = \"legacy_id\"' "$TMP/valid.toml" > "$TMP/legacy-id.toml"
check 'negative: legacy id property rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/legacy-id.toml"
check 'negative: unknown @section.path reference rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/unknown-ref.toml"
sed '/^\[identity\]/,/^\[/ { /^name = /d; }' "$TMP/valid.toml" > "$TMP/missing-required.toml"
check 'negative: required parameter rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/missing-required.toml"
printf 'schema_version = "1.0"\n[broken\n' > "$TMP/bad-syntax.toml"
check 'negative: malformed TOML rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/bad-syntax.toml"
check 'schema contains no id fields' bash -c '! grep -q "\"id\"" "$1"' _ "$ROOT/lib/schema.json"
sed 's/address = "192.168.88.2"/address = "192.168.88.100"/' "$ROOT/profiles/$HOME_PROFILE/config.toml" > "$TMP/overlap-lease.toml"
check 'negative: static lease overlapping DHCP pool rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/overlap-lease.toml"
sed 's/interface = "@interfaces.ether1"/interface = "@network.lan"/' "$TMP/valid.toml" > "$TMP/reference-cycle.toml"
check 'negative: incompatible self-reference rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/reference-cycle.toml"
sed '/^port = 22$/d' "$ROOT/profiles/$CHR_PROFILE/config.toml" > "$TMP/service-without-port.toml"
check 'negative: active service without port rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/service-without-port.toml"
sed 's/start = "192.168.88.100"/start = "192.168.88.220"/; s/end = "192.168.88.200"/end = "192.168.88.100"/' "$TMP/valid.toml" > "$TMP/bad-pool.toml"
check 'negative: reversed DHCP pool rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/bad-pool.toml"
sed 's/start = "192.168.88.100"/start = "192.168.88.1"/; s/end = "192.168.88.200"/end = "192.168.88.20"/' "$TMP/valid.toml" > "$TMP/pool-includes-router.toml"
check 'negative: DHCP pool cannot include router LAN address' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/pool-includes-router.toml"
sed 's/address = "192.168.88.2"/address = "192.168.88.1"/' "$ROOT/profiles/$HOME_PROFILE/config.toml" > "$TMP/lease-router-address.toml"
check 'negative: static lease cannot reuse router LAN address' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/lease-router-address.toml"
sed 's/brute_force_ports = "22,8291"/brute_force_ports = "22,65536"/' "$ROOT/profiles/$CHR_PROFILE/config.toml" > "$TMP/brute-force-invalid-port.toml"
check 'negative: brute-force port above 65535 rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/brute-force-invalid-port.toml"
sed 's/brute_force_ports = "22,8291"/brute_force_ports = "22-21"/' "$ROOT/profiles/$CHR_PROFILE/config.toml" > "$TMP/brute-force-reversed-range.toml"
check 'negative: reversed brute-force port range rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/brute-force-reversed-range.toml"
sed 's/brute_force_ports = "22,8291"/brute_force_ports = "22-23,8291"/' "$ROOT/profiles/$CHR_PROFILE/config.toml" > "$TMP/brute-force-valid-range.toml"
check 'positive: valid brute-force port ranges accepted' run_ok python3 "$ROOT/lib/toml_engine.py" validate "$TMP/brute-force-valid-range.toml"
cp "$ROOT/profiles/$HOME_PROFILE/config.toml" "$TMP/encrypted-backup-no-key.toml"
printf '\n[backup]\nencrypt = true\npassword_file = ".secrets"\n' >> "$TMP/encrypted-backup-no-key.toml"
check 'negative: encrypted backup without secret key rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/encrypted-backup-no-key.toml"
sed -e 's/create = false/create = true/' -e '/^password_file/d' -e '/^password_key/d' "$TMP/valid.toml" > "$TMP/create-without-password.toml"
check 'negative: create=true without password rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/create-without-password.toml"
sed 's/name = "admin"/name = "roman"/' "$TMP/valid.toml" > "$TMP/duplicate-user-name.toml"
cat >> "$TMP/duplicate-user-name.toml" <<'EOF'

[users.test]
name = "roman"
enabled = true
create = false
group = "full"
EOF
check 'negative: duplicate RouterOS usernames rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/duplicate-user-name.toml"
sed '/^supported = false/a upgrade = true' "$TMP/valid.toml" > "$TMP/routerboard-unsupported-upgrade.toml"
check 'negative: RouterBOARD upgrade rejected when unsupported' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/routerboard-unsupported-upgrade.toml"
sed '/^\[users.admin\]/,/^\[/ { /^enabled = /d; }' "$TMP/valid.toml" > "$TMP/user-missing-enabled.toml"
check 'negative: required users.enabled rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/user-missing-enabled.toml"
sed 's/ssh_keys = \["~\/.ssh\/id_mikrotik_lab.pub"\]/ssh_keys = "not-a-list"/' "$TMP/valid.toml" > "$TMP/user-ssh-keys-wrong-type.toml"
check 'negative: users.ssh_keys must be a string array' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/user-ssh-keys-wrong-type.toml"
# Схема є обов'язковим єдиним джерелом правил; резервного TABLES більше немає.
mkdir -p "$TMP/no-schema/lib"
cp "$ROOT/lib/toml_engine.py" "$TMP/no-schema/lib/toml_engine.py"
check 'negative: missing schema reports explicit error' bash -c 'out=$(python3 "$1" validate "$2" 2>&1 || true); grep -q "ERROR: TOML schema not found" <<< "$out"' _ "$TMP/no-schema/lib/toml_engine.py" "$TMP/valid.toml"
sed 's/^\[ports\.ether5\]/[ports.ether99]/' "$TMP/valid.toml" > "$TMP/port-without-interface.toml"
check 'negative: ports entry without interfaces entry rejected by TOML engine' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/port-without-interface.toml"
sed 's/bridge = "@bridge.lan"/bridge = "@interfaces.ether1"/' "$TMP/valid.toml" > "$TMP/wrong-reference-type.toml"
check 'negative: @section.path target type mismatch rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/wrong-reference-type.toml"
cat "$TMP/valid.toml" > "$TMP/unsafe-table-key.toml"
printf '\n[interfaces."sfp1] ; :log error pwned ;"]\nid = "if_pwned"\nname = "pwned"\nenabled = true\n' >> "$TMP/unsafe-table-key.toml"
check 'negative: RouterOS table key injection rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/unsafe-table-key.toml"
# TOML допускає escaped newline; RSC serializer має відхилити його перед генерацією команд.
python3 - "$TMP/valid.toml" "$TMP/control-character.toml" <<'PYTEST'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
needle = 'comment = "physical_port"'
if needle not in src:
    raise SystemExit('test fixture has no physical_port comment')
pathlib.Path(sys.argv[2]).write_text(src.replace(needle, 'comment = "line1\\nline2"', 1))
PYTEST
sed '/^\[identity\]/,/^\[/ s/^name = .*/name = "@fw_policy"/' "$TMP/valid.toml" > "$TMP/untyped-reference.toml"
check 'negative: @section.path in untyped field rejected' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/untyped-reference.toml"
sed 's/user = "roman"/user = "-admin"/' "$TMP/valid.toml" > "$TMP/ssh-user-option.toml"
check 'negative: SSH username cannot begin with hyphen' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/ssh-user-option.toml"
sed 's/host = "192.168.56.2"/host = "-192.168.56.2"/' "$TMP/valid.toml" > "$TMP/ssh-host-option.toml"
check 'negative: SSH host cannot begin with hyphen' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/ssh-host-option.toml"
sed '/^\[backup\]/,/^\[reset\]/ { /password_file/d; /password_key/d; }' "$ROOT/profiles/$HOME_PROFILE/config.toml" > "$TMP/unencrypted-backup-no-secret.toml"
check 'backup.encrypt=false validates without password_file/password_key' run_ok python3 "$ROOT/lib/toml_engine.py" validate "$TMP/unencrypted-backup-no-secret.toml"

printf '%s\n' '[3] Profile isolation and generation'
cp -a "$ROOT" "$TMP/project"
seed_test_secrets "$TMP/project"
rm -f "$TMP/project"/profiles/*/output/*.rsc
M="$TMP/project/mikrotik-manager.sh"
printf '%s\n' '[3a] RouterOS read-only verification command preview'
VERIFY_BIN="$TMP/verify-bin"
mkdir -p "$VERIFY_BIN"
cat > "$VERIFY_BIN/ssh" <<'EOF'
#!/bin/sh
printf 'ssh was called\n' >> "$VERIFY_TRANSPORT_LOG"
exit 99
EOF
cat > "$VERIFY_BIN/scp" <<'EOF'
#!/bin/sh
printf 'scp was called\n' >> "$VERIFY_TRANSPORT_LOG"
exit 99
EOF
chmod 755 "$VERIFY_BIN/ssh" "$VERIFY_BIN/scp"
export VERIFY_TRANSPORT_LOG="$TMP/verify-transport.log"
: > "$VERIFY_TRANSPORT_LOG"
HOME_VERIFY="$TMP/home-router-verify.stdout"
CHR_VERIFY="$TMP/chr-verify.stdout"
check 'read-only verification prints physical profile commands' bash -c 'PATH="$1:$PATH" "$2" --verify --profile "$3" > "$4"' _ "$VERIFY_BIN" "$M" "$HOME_PROFILE" "$HOME_VERIFY"
check 'read-only verification prints CHR profile commands' bash -c 'PATH="$1:$PATH" "$2" --verify --profile "$3" > "$4"' _ "$VERIFY_BIN" "$M" "$CHR_PROFILE" "$CHR_VERIFY"
check 'verification output covers interfaces, bridge, DHCP, DNS, firewall, NAT and users' python3 - "$HOME_VERIFY" <<'PYVERIFY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
required = [
    '/interface print detail without-paging',
    '/interface bridge port print detail without-paging',
    '/ip dhcp-server lease print detail without-paging',
    '/ip dns print detail without-paging',
    '/ip firewall filter print detail without-paging',
    '/ip firewall nat print detail without-paging',
    '/user print detail without-paging',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f'missing commands: {missing}')
PYVERIFY
check 'verification output contains only read-only print commands' python3 - "$HOME_VERIFY" "$CHR_VERIFY" <<'PYVERIFY'
import pathlib, sys
for name in sys.argv[1:]:
    for line in pathlib.Path(name).read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith('#') or stripped.startswith(':put '):
            continue
        if not stripped.startswith('/') or not stripped.endswith(' print detail without-paging'):
            raise SystemExit(f'non-read-only command in {name}: {stripped}')
PYVERIFY
check 'verification does not create profile output files' bash -c '[[ ! -e "$1/profiles/$2/output/$2-verify.rsc" && ! -e "$1/profiles/$3/output/$3-verify.rsc" ]]' _ "$TMP/project" "$HOME_PROFILE" "$CHR_PROFILE"
check 'verification does not invoke SSH or SCP' test ! -s "$VERIFY_TRANSPORT_LOG"
check 'CHR preview explicitly skips unavailable Wi-Fi driver' grep -q 'SKIP: wireless.driver=none' "$CHR_VERIFY"
check 'legacy Wi-Fi preview uses wireless menu' grep -q '/interface wireless print detail without-paging' "$HOME_VERIFY"
check 'qcom-ac Wi-Fi preview uses wifi menu' bash -c 'python3 "$1" home-router wifi-qcom-ac | grep -q "/interface wifi security print detail without-paging"' _ "$ROOT/lib/routeros_verify.py"
check 'qcom Wi-Fi preview uses wifi menu' bash -c 'python3 "$1" home-router wifi-qcom | grep -q "/interface wifi datapath print detail without-paging"' _ "$ROOT/lib/routeros_verify.py"
check 'unknown Wi-Fi driver is rejected' run_fail python3 "$ROOT/lib/routeros_verify.py" home-router invalid-driver
check 'verification rejects mixed operation flags' run_fail "$M" --verify --build --profile "$CHR_PROFILE"
check 'verification rejects --name because it creates no artifact' run_fail "$M" --verify --profile "$CHR_PROFILE" --name custom-audit.rsc
check 'verification rejects --output because it creates no artifact' run_fail "$M" --verify --profile "$CHR_PROFILE" --output "$TMP/custom-verify"
check 'verification does not create requested output directory' test ! -e "$TMP/custom-verify"
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/control-character-original.toml"
python3 - "$TMP/project/profiles/$CHR_PROFILE/config.toml" <<'PYTEST'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = 'comment = "host_only_management"'
if old not in s:
    raise SystemExit('expected fixture comment not found')
p.write_text(s.replace(old, 'comment = "line1\\nline2"', 1))
PYTEST
check 'negative: RSC build rejects decoded control characters' run_fail "$M" --build --profile "$CHR_PROFILE" --name control-character.rsc
mv "$TMP/control-character-original.toml" "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'CLI validate physical profile' run_ok "$M" --validate --profile "$HOME_PROFILE"
check 'CLI validate chr profile' run_ok "$M" --validate --profile "$CHR_PROFILE"
check 'RouterOS string serializer rejects control characters' grep -q '\[\[ ! \$s =~ \[\[:cntrl:\]\] \]\]' "$M"
check 'CHR build' run_ok "$M" --build --profile "$CHR_PROFILE"
CHR_RSC="$TMP/project/profiles/$CHR_PROFILE/output/$CHR_PROFILE.rsc"
check 'CHR output exists' test -s "$CHR_RSC"
check 'CHR output mode 600' bash -c '[[ $(stat -c %a "$1") == 600 ]]' _ "$CHR_RSC"
CHR_OUTPUT_DIR="$(dirname "$CHR_RSC")"
CHR_OUTPUT_MODE_BEFORE=$(stat -c %a "$CHR_OUTPUT_DIR")
check 'CHR output directory mode remains unchanged' bash -c '[[ $(stat -c %a "$1") == "$2" ]]' _ "$CHR_OUTPUT_DIR" "$CHR_OUTPUT_MODE_BEFORE"
# --output не змінює права на вже наявному каталозі.
mkdir -p "$TMP/shared-output"
chmod 755 "$TMP/shared-output"
check '--output preserves permissions of existing directory' run_ok "$M" --build --profile "$CHR_PROFILE" --name shared.rsc --output "$TMP/shared-output"
check '--output existing directory remains mode 755' bash -c '[[ $(stat -c %a "$1") == 755 ]]' _ "$TMP/shared-output"
check '--output creates a new directory with mode 700' run_ok "$M" --build --profile "$CHR_PROFILE" --name fresh.rsc --output "$TMP/new-output"
check '--output newly created directory mode 700' bash -c '[[ $(stat -c %a "$1") == 700 ]]' _ "$TMP/new-output"
check 'CHR management IP is 192.168.56.2/24' grep -q 'address=192.168.56.2/24' "$CHR_RSC"
check 'CHR LAN is 192.168.88.1/24' grep -q 'address=192.168.88.1/24' "$CHR_RSC"
check 'CHR management firewall list is used' grep -q 'in-interface-list="MGMT"' "$CHR_RSC"
# RouterOS 7.24 перейменував address → available-from; CHR (7.24.6) має новий синтаксис.
check 'CHR SSH service is limited to management subnet (available-from syntax)' grep -q 'name=ssh.*available-from="192.168.56.0/24"' "$CHR_RSC"
check 'CHR no deprecated service address= keyword' bash -c '! grep -Eq "name=ssh.*address=\"192" "$1"' _ "$CHR_RSC"
check 'UPnP/proxy/socks/bandwidth-server deterministically disabled' bash -c 'g() { grep -c "$1" "$2"; }; [[ $(g "/ip upnp set enabled=no" "$1") -eq 1 && $(g "/ip proxy set enabled=no" "$1") -eq 1 && $(g "/ip socks set enabled=no" "$1") -eq 1 && $(g "/tool bandwidth-server set enabled=no" "$1") -eq 1 ]]' _ "$CHR_RSC"
check 'clock timezone autodetect disabled' grep -q 'time-zone-autodetect=no' "$CHR_RSC"
check 'CHR WAN DHCP client uses ether6' grep -q '/ip dhcp-client add interface="02_wan"' "$CHR_RSC"
check 'CHR WAN DHCP replies are accepted by firewall' grep -q 'src-port=67 dst-port=68 in-interface-list="WAN"' "$CHR_RSC"
check 'CHR WAN interface is included in WAN list' grep -q 'list="WAN" interface="02_wan"' "$CHR_RSC"
check 'CHR NAT masquerade is active' grep -q 'chain=srcnat action=masquerade out-interface-list="WAN"' "$CHR_RSC"
check 'CHR LAN-to-WAN forwarding is active' grep -q 'action=accept in-interface-list="LAN" out-interface-list="WAN"' "$CHR_RSC"
check 'CHR router DNS uses Cloudflare Family' grep -q 'servers=1.1.1.3,1.0.0.3 allow-remote-requests=yes' "$CHR_RSC"
check 'CHR DHCP clients use router DNS' grep -q 'dns-server=192.168.88.1' "$CHR_RSC"
check 'CHR wireless omitted' grep -q '^# wireless: driver none - skipped$' "$CHR_RSC"
check 'RouterOS errors are counted' grep -q ':set mgrErrors (\$mgrErrors + 1)' "$CHR_RSC"
check 'CHR skips unsupported RouterBOARD settings' grep -q 'mgr: SKIP: RouterBOARD settings are not supported' "$CHR_RSC"
# Октальний префікс: Python приймає /08 — bash зобов'язаний не падати і нормалізувати.
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/chr-config.octal"
sed 's|address = "192.168.88.1/24"|address = "192.168.88.1/08"|' "$TMP/chr-config.octal" > "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'leading-zero CIDR prefix validates' run_ok "$M" --validate --profile "$CHR_PROFILE"
check 'leading-zero CIDR prefix builds' run_ok "$M" --build --profile "$CHR_PROFILE" --name octal-test.rsc
check 'leading-zero CIDR prefix normalized' grep -q '192.0.0.0/8' "$TMP/project/profiles/$CHR_PROFILE/output/octal-test.rsc"
mv "$TMP/chr-config.octal" "$TMP/project/profiles/$CHR_PROFILE/config.toml"
# Leading-zero цілих у TOML неможливі (TOMLDecodeError), тож bash-арифметика
# цих полів недосяжна для значень типу «018» — негативний тест фіксує це.
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/chr-config.zero-lim"
sed 's/^icmp_limit_per_second = 10.*/icmp_limit_per_second = 010/' "$TMP/chr-config.zero-lim" > "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'negative: leading-zero integer in TOML rejected' run_fail "$M" --validate --profile "$CHR_PROFILE"
mv "$TMP/chr-config.zero-lim" "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'CHR does not execute RouterBOARD settings command' not_contains "$CHR_RSC" '/system routerboard settings set'
check 'CHR enabled user SSH key is imported' grep -q 'public-key-file=\"mgr-roman-1.pub\" user=\"roman\"' "$CHR_RSC"
check 'CHR admin key import uses SSH fingerprint' grep -Eq 'fingerprint="SHA256:[A-Za-z0-9+/=]{40,60}"' "$CHR_RSC"
check 'create=false does not emit user-add for admin' not_contains "$CHR_RSC" '/user add name="admin"'
check 'admin password is not changed when no secret is configured' not_contains "$CHR_RSC" '/user add name="admin" group='
check 'CHR admin key import is independent of create=false' grep -q 'user admin not found; create=false' "$CHR_RSC"
check 'CHR roman user is ensured before admin disable' bash -c 'u=$(grep -n -m1 "users: ensure roman" "$1" | cut -d: -f1); d=$(grep -n -m1 "users: disable admin (deferred)" "$1" | cut -d: -f1); [[ -n $u && -n $d && $u -lt $d ]]' _ "$CHR_RSC"
check 'CHR SSH key import precedes deferred admin disable' bash -c 'k=$(grep -n -m1 "sshkey: import roman#1" "$1" | cut -d: -f1); d=$(grep -n -m1 "users: disable admin (deferred)" "$1" | cut -d: -f1); [[ -n $k && -n $d && $k -lt $d ]]' _ "$CHR_RSC"
check 'admin disable is guarded by zero prior apply errors' grep -Fq ':if ($mgrErrors = 0) do=' "$CHR_RSC"
check 'SSH key is verified (no blind temporary file cleanup)' bash -c 'line=$(grep -n -m1 "sshkey: verify import roman#1" "$1" | cut -d: -f1); sed -n "${line}p" "$1" | grep -q "SSH key import verification failed" && ! sed -n "${line}p" "$1" | grep -qF "/file remove \$mgrKeyFile"' _ "$CHR_RSC"
check 'SSH import failure keeps temporary public key for diagnosis' grep -q 'SSH key import verification failed for roman' "$CHR_RSC"
check 'user operation errors have safe descriptive labels' grep -q 'mgr: FAILED: sshkey: import roman#1' "$CHR_RSC"
check 'SSH key re-add is idempotent (stale file removed by guarded lookup)' grep -q 'do={ /file remove \[/file find where name="mgr-roman-1.pub"\] }' "$CHR_RSC"
check 'SSH import steps are separate commands (localizable failure)' bash -c '[[ $(grep -c "FAILED: sshkey: " "$1") -ge 5 ]]' _ "$CHR_RSC"
check 'SSH import target-user check has its own labeled step' grep -q 'mgr: FAILED: sshkey: target user roman#1' "$CHR_RSC"
check 'apply-done is conditional on zero errors' grep -Fq ':if ($mgrErrors = 0) do=' "$CHR_RSC"

# Home profile test uses synthetic disposable secrets only in the temporary project copy.
cat > "$TMP/project/profiles/$HOME_PROFILE/.secrets" <<'EOF'
ADMIN_PASSWORD=TestOnly-Admin-Password
USER_ROMAN_PASSWORD=TestOnly-Roman-Password
WIFI_PASSWORD=TestOnly-Wifi-Password
EOF
chmod 600 "$TMP/project/profiles/$HOME_PROFILE/.secrets"
check 'physical profile build with temporary test secrets' run_ok "$M" --build --profile "$HOME_PROFILE"
HOME_RSC="$TMP/project/profiles/$HOME_PROFILE/output/$HOME_PROFILE.rsc"
# Home-профіль target 7.23.8 (< 7.24) → deprecated, але сумісний синтаксис address=.
check 'home profile RouterOS 7.23 uses legacy service address= syntax' grep -q 'name=ssh.*address="192.168.' "$HOME_RSC"
# На профілі з WAN перевіряємо порядок секцій, не підключаючись до RouterOS.
HOME_RSC_ORDER="$TMP/project/profiles/$HOME_PROFILE/output/$HOME_PROFILE.rsc"
USER_LINE=$(grep -n -m1 '/user ' "$HOME_RSC_ORDER" | cut -d: -f1)
SERVICE_LINE=$(grep -n -m1 '/ip service set' "$HOME_RSC_ORDER" | cut -d: -f1)
FIREWALL_LINE=$(grep -n -m1 '/ip firewall filter add' "$HOME_RSC_ORDER" | cut -d: -f1)
DNS_LINE=$(grep -n -m1 '/ip dns set' "$HOME_RSC_ORDER" | cut -d: -f1)
WAN_LINE=$(grep -n -m1 '/ip dhcp-client add' "$HOME_RSC_ORDER" | cut -d: -f1)
check 'users generated before firewall' bash -c '[[ $1 -lt $2 ]]' _ "$USER_LINE" "$FIREWALL_LINE"
check 'IP services hardened before firewall/WAN' bash -c '[[ $1 -lt $2 && $2 -lt $3 ]]' _ "$SERVICE_LINE" "$FIREWALL_LINE" "$WAN_LINE"
check 'firewall generated before DNS remote requests' bash -c '[[ $1 -lt $2 ]]' _ "$FIREWALL_LINE" "$DNS_LINE"
check 'WAN DHCP client generated after firewall and DNS' bash -c '[[ $1 -lt $2 && $2 -lt $3 ]]' _ "$FIREWALL_LINE" "$DNS_LINE" "$WAN_LINE"
check 'RSC includes SHA-256 of profile TOML inputs' grep -Eq '^# config-sha256: [0-9a-f]{64}$' "$HOME_RSC_ORDER"
check 'RSC includes unique apply-token' grep -Eq '^# apply-token: [0-9a-f]{20}$' "$HOME_RSC_ORDER"
check 'RSC includes SHA-256 of referenced secret files' grep -Eq '^# secrets-sha256: [0-9a-f]{64}$' "$HOME_RSC_ORDER"
check 'physical profile output exists' test -s "$HOME_RSC"
check '--secrets skips BACKUP_PASSWORD when backup.encrypt=false' run_ok bash -c '"$1" --secrets --profile "$2" </dev/null' _ "$M" "$HOME_PROFILE"
check 'all 16 static leases generated' bash -c '[[ $(grep -c "ip dhcp-server lease add" "$1") -eq 16 ]]' _ "$HOME_RSC"
check 'Wi-Fi generation retained in home profile' grep -q '/interface wireless set' "$HOME_RSC"
check 'NAT masquerade retained in home profile' grep -q 'action=masquerade' "$HOME_RSC"
check 'physical profile applies RouterBOARD settings' grep -q '/system routerboard settings set auto-upgrade=no' "$HOME_RSC"
check 'physical backup directory exists' test -d "$TMP/project/profiles/$HOME_PROFILE/backups"

# Guest Wi-Fi: VAP на обох радіо, окремий міст/DHCP, firewall у WAN без доступу до LAN.
cp "$TMP/project/profiles/$HOME_PROFILE/config.toml" "$TMP/home-config.base"
printf 'GUEST_WIFI_PASSWORD=LongEnoughGuestSecret\n' >> "$TMP/project/profiles/$HOME_PROFILE/.secrets"
cat >> "$TMP/project/profiles/$HOME_PROFILE/config.toml" <<'EOF'

[bridge.guest]
name = "bridge-guest"

[security.guest]
name = "guest-wifi-security"
authentication = "wpa2-psk"
password_file = ".secrets"
password_key = "GUEST_WIFI_PASSWORD"

[wireless.guest]
enabled = true
masters = ["@interfaces.wlan1", "@interfaces.wlan2"]
name_prefix = "guest"
ssid = "HOME-Guest"
security = "@security.guest"
bridge = "@bridge.guest"
address = "192.168.89.1/24"
pool_start = "192.168.89.100"
pool_end = "192.168.89.200"
dns_servers = ["192.168.89.1"]
EOF
check 'physical profile with guest Wi-Fi validates' run_ok "$M" --validate --profile "$HOME_PROFILE"
check 'physical profile with guest Wi-Fi builds' run_ok "$M" --build --profile "$HOME_PROFILE" --name guest-test.rsc
GUEST_RSC="$TMP/project/profiles/$HOME_PROFILE/output/guest-test.rsc"
check 'guest bridge is created' grep -q '/interface bridge add name="bridge-guest"' "$GUEST_RSC"
check 'guest security profile uses separate secret' grep -q 'name="guest-wifi-security".*wpa2-pre-shared-key="LongEnoughGuestSecret"' "$GUEST_RSC"
check 'guest VAP is created on master radio' grep -q 'name="guest-va1" master-interface="02_wifi_24GHz" mode=ap-bridge ssid="HOME-Guest"' "$GUEST_RSC"
check 'guest VAP is created on second radio' grep -q 'name="guest-va2" master-interface="02_wifi_5GHz"' "$GUEST_RSC"
check 'guest VAP joins guest bridge' grep -q 'bridge="bridge-guest" interface="guest-va1"' "$GUEST_RSC"
check 'guest DHCP pool and server are generated' bash -c 'grep -q "guest-pool\" ranges=192.168.89.100-192.168.89.200" "$1" && grep -q "add name=\"guest-dhcp\" interface=\"bridge-guest\" address-pool=\"guest-pool\"" "$1"' _ "$GUEST_RSC"
check 'guest DHCP network provides gateway and DNS' grep -q 'network add address=192.168.89.0/24 gateway=192.168.89.1 dns-server=192.168.89.1' "$GUEST_RSC"
check 'guest DHCP/ICMP input rules exist' bash -c 'grep -q "src-port=68 dst-port=67 in-interface=\"bridge-guest\"" "$1" && grep -q "protocol=icmp in-interface=\"bridge-guest\"" "$1"' _ "$GUEST_RSC"
check 'guest DNS input rules exist' bash -c 'grep -q "dst-port=53 in-interface=\"bridge-guest\"" "$1"' _ "$GUEST_RSC"
check 'guest forwarding goes only to WAN' grep -q 'chain=forward action=accept in-interface="bridge-guest" out-interface-list="WAN" comment="mgr: forward guest to wan"' "$GUEST_RSC"
check 'guest bridge is not in LAN list' not_contains "$GUEST_RSC" 'list="LAN" interface="bridge-guest"'
check 'guest-to-LAN isolation rule is generated' grep -q 'chain=forward action=drop in-interface="bridge-guest" out-interface-list="LAN" comment="mgr: forward guest block lan"' "$GUEST_RSC"
check 'guest-to-LAN drop precedes guest-to-WAN accept' bash -c 'drop=$(grep -n -m1 "forward guest block lan" "$1" | cut -d: -f1); allow=$(grep -n -m1 "forward guest to wan" "$1" | cut -d: -f1); [[ -n $drop && -n $allow && $drop -lt $allow ]]' _ "$GUEST_RSC"
# Ізоляція гостей не повинна залежати від глобального forward_default_drop.
cp "$TMP/project/profiles/$HOME_PROFILE/config.toml" "$TMP/guest-config.base"
sed 's/forward_default_drop = true/forward_default_drop = false/' "$TMP/project/profiles/$HOME_PROFILE/config.toml" > "$TMP/guest-no-global-forward-drop.toml"
python3 - "$TMP/guest-no-global-forward-drop.toml" "$TMP/project/profiles/$HOME_PROFILE/config.toml" <<'PYGUEST'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(source)
PYGUEST
check 'guest-to-LAN isolation remains when forward_default_drop=false' run_ok "$M" --build --profile "$HOME_PROFILE" --name guest-isolation.rsc
check 'guest isolation rule remains without global forward drop' grep -q 'forward guest block lan' "$TMP/project/profiles/$HOME_PROFILE/output/guest-isolation.rsc"
cp "$TMP/guest-config.base" "$TMP/project/profiles/$HOME_PROFILE/config.toml"
sed 's/address = "192.168.89.1\/24"/address = "192.168.88.1\/24"/' "$TMP/project/profiles/$HOME_PROFILE/config.toml" > "$TMP/guest-overlapping-lan.toml"
check 'negative: guest subnet cannot overlap main LAN' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/guest-overlapping-lan.toml"
sed 's/pool_start = "192.168.89.100"/pool_start = "192.168.89.1"/' "$TMP/project/profiles/$HOME_PROFILE/config.toml" > "$TMP/guest-pool-includes-router.toml"
check 'negative: guest DHCP pool cannot include guest router address' run_fail python3 "$ROOT/lib/toml_engine.py" validate "$TMP/guest-pool-includes-router.toml"
# негативний кейс: гостьовий профіль без обов'язкових параметрів відхиляється.
sed '/pool_start = "192.168.89.100"/d' "$TMP/project/profiles/$HOME_PROFILE/config.toml" > "$TMP/project/profiles/$HOME_PROFILE/config.toml.new"
mv "$TMP/project/profiles/$HOME_PROFILE/config.toml.new" "$TMP/project/profiles/$HOME_PROFILE/config.toml"
check 'negative: guest network without pool_start rejected' run_fail "$M" --validate --profile "$HOME_PROFILE"
mv "$TMP/home-config.base" "$TMP/project/profiles/$HOME_PROFILE/config.toml"

# Окремі контракти трьох Wi-Fi драйверів: генерація лише локальна, без RouterOS.
WIFI_BASE="$TMP/project/profiles/$HOME_PROFILE/config.toml"
cp "$WIFI_BASE" "$TMP/wifi-original.toml"
WIFI_SECRETS="$TMP/project/profiles/$HOME_PROFILE/.secrets"
cp "$WIFI_BASE" "$TMP/wifi-base.toml"
python3 - "$TMP/wifi-base.toml" "$WIFI_SECRETS" <<'PYWIFI'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('driver = "legacy"', 'driver = "wifi-qcom-ac"', 1)
s = s.replace('band = "2ghz-b/g/n"', 'band = "2ghz-n"', 1)
s = s.replace('band = "5ghz-a/n/ac"', 'band = "5ghz-ac"', 1)
s = s.replace('channel_width = "20/40/80mhz-XXXX"', 'channel_width = "20/40/80mhz"', 1)
p.write_text(s)
PYWIFI
cp "$TMP/wifi-base.toml" "$WIFI_BASE"
cat >> "$WIFI_BASE" <<'EOF'

[bridge.guest]
name = "bridge-guest"

[security.guest]
name = "guest-wifi-security"
authentication = "wpa2-psk"
password_file = ".secrets"
password_key = "GUEST_WIFI_PASSWORD"

[wireless.guest]
enabled = true
masters = ["@interfaces.wlan1", "@interfaces.wlan2"]
name_prefix = "guest"
ssid = "HOME-Guest"
security = "@security.guest"
bridge = "@bridge.guest"
address = "192.168.89.1/24"
pool_start = "192.168.89.100"
pool_end = "192.168.89.200"
dns_servers = ["192.168.89.1"]
EOF
check 'wifi-qcom-ac profile validates' run_ok "$M" --validate --profile "$HOME_PROFILE"
check 'wifi-qcom-ac profile builds locally' run_ok "$M" --build --profile "$HOME_PROFILE" --name wifi-qcom-ac.rsc
WIFI_AC_RSC="$TMP/project/profiles/$HOME_PROFILE/output/wifi-qcom-ac.rsc"
check 'wifi-qcom-ac uses native 2ghz-n band' grep -q 'channel.band=2ghz-n' "$WIFI_AC_RSC"
check 'wifi-qcom-ac uses native 5ghz-ac band' grep -q 'channel.band=5ghz-ac' "$WIFI_AC_RSC"
check 'wifi-qcom-ac preserves 80 MHz width' grep -q 'channel.width=20/40/80mhz' "$WIFI_AC_RSC"
check 'wifi-qcom-ac main datapath bridge is generated' grep -q 'datapath.bridge="bridge-lan"' "$WIFI_AC_RSC"
check 'wifi-qcom-ac main Wi-Fi ports are not added twice' bash -c '! grep -Fq "/interface bridge port add bridge=\"bridge-lan\" interface=\"02_wifi_24GHz\"" "$1" && ! grep -Fq "/interface bridge port add bridge=\"bridge-lan\" interface=\"02_wifi_5GHz\"" "$1"' _ "$WIFI_AC_RSC"
check 'wifi-qcom-ac guest VAP uses datapath bridge' grep -q 'datapath.bridge="bridge-guest"' "$WIFI_AC_RSC"
check 'wifi-qcom-ac guest VAP is not added twice to bridge' bash -c '! grep -Fq "/interface bridge port add bridge=\"bridge-guest\" interface=\"guest-va" "$1"' _ "$WIFI_AC_RSC"
check 'negative: wifi-qcom-ac rejects AX band' bash -c 'sed "s/band = \"5ghz-ac\"/band = \"5ghz-ax\"/" "$1" > "$2"; python3 "$3" validate "$2" >/dev/null 2>&1; test $? -ne 0' _ "$WIFI_BASE" "$TMP/wifi-qcom-ac-invalid-band.toml" "$ROOT/lib/toml_engine.py"
check 'negative: wifi-qcom-ac rejects 160 MHz width' bash -c 'sed "s/channel_width = \"20\/40\/80mhz\"/channel_width = \"20\/40\/80\/160mhz\"/" "$1" > "$2"; python3 "$3" validate "$2" >/dev/null 2>&1; test $? -ne 0' _ "$WIFI_BASE" "$TMP/wifi-qcom-ac-invalid-width.toml" "$ROOT/lib/toml_engine.py"
check 'negative: wifi-qcom-ac rejects Superchannel country' bash -c 'sed "s/country = \"ukraine\"/country = \"Superchannel\"/" "$1" > "$2"; python3 "$3" validate "$2" >/dev/null 2>&1; test $? -ne 0' _ "$WIFI_BASE" "$TMP/wifi-qcom-ac-superchannel.toml" "$ROOT/lib/toml_engine.py"

python3 - "$WIFI_BASE" <<'PYWIFI'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('driver = "wifi-qcom-ac"', 'driver = "wifi-qcom"', 1)
s = s.replace('band = "2ghz-n"', 'band = "2ghz-ax"', 1)
s = s.replace('band = "5ghz-ac"', 'band = "5ghz-ax"', 1)
s = s.replace('channel_width = "20/40/80mhz"', 'channel_width = "20/40/80/160mhz"', 1)
p.write_text(s)
PYWIFI
check 'wifi-qcom profile validates' run_ok "$M" --validate --profile "$HOME_PROFILE"
check 'wifi-qcom profile builds locally' run_ok "$M" --build --profile "$HOME_PROFILE" --name wifi-qcom.rsc
WIFI_AX_RSC="$TMP/project/profiles/$HOME_PROFILE/output/wifi-qcom.rsc"
check 'wifi-qcom preserves 2ghz-ax band' grep -q 'channel.band=2ghz-ax' "$WIFI_AX_RSC"
check 'wifi-qcom preserves 5ghz-ax band' grep -q 'channel.band=5ghz-ax' "$WIFI_AX_RSC"
check 'wifi-qcom preserves 160 MHz width' grep -q 'channel.width=20/40/80/160mhz' "$WIFI_AX_RSC"
check 'wifi-qcom main Wi-Fi ports are not added twice' bash -c '! grep -Fq "/interface bridge port add bridge=\"bridge-lan\" interface=\"02_wifi_24GHz\"" "$1" && ! grep -Fq "/interface bridge port add bridge=\"bridge-lan\" interface=\"02_wifi_5GHz\"" "$1"' _ "$WIFI_AX_RSC"
check 'wifi-qcom guest VAP uses datapath bridge' grep -q 'datapath.bridge="bridge-guest"' "$WIFI_AX_RSC"
check 'wifi-qcom guest VAP is not added twice to bridge' bash -c '! grep -Fq "/interface bridge port add bridge=\"bridge-guest\" interface=\"guest-va" "$1"' _ "$WIFI_AX_RSC"
cp "$WIFI_BASE" "$TMP/wifi-qcom-base.toml"
python3 - "$WIFI_BASE" <<'PYWIFI'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
start = s.index('[security.wifi]')
end = s.find('\n[', start + 1)
if end < 0: end = len(s)
section = s[start:end].replace('authentication = "wpa2-psk"', 'authentication = "wpa3-psk"', 1)
p.write_text(s[:start] + section + s[end:])
PYWIFI
check 'wifi-qcom accepts WPA3-PSK' run_ok "$M" --validate --profile "$HOME_PROFILE"
check 'wifi-qcom builds WPA3-PSK locally' run_ok "$M" --build --profile "$HOME_PROFILE" --name wifi-qcom-wpa3.rsc
check 'wifi-qcom WPA3 authentication reaches RSC' grep -q 'security.authentication-types=wpa3-psk' "$TMP/project/profiles/$HOME_PROFILE/output/wifi-qcom-wpa3.rsc"
cp "$TMP/wifi-qcom-base.toml" "$WIFI_BASE"
check 'negative: wifi-qcom rejects legacy channel-width syntax' bash -c 'sed "s/channel_width = \"20\/40\/80\/160mhz\"/channel_width = \"20\/40\/80\/160mhz-XXXX\"/" "$1" > "$2"; python3 "$3" validate "$2" >/dev/null 2>&1; test $? -ne 0' _ "$WIFI_BASE" "$TMP/wifi-qcom-invalid-width.toml" "$ROOT/lib/toml_engine.py"

# Повертаємо профіль до початкового стану до решти регресійних тестів.
cp "$TMP/wifi-base.toml" "$WIFI_BASE"
check 'negative: removed generic wifi driver alias rejected' bash -c 'sed "s/driver = \"wifi-qcom-ac\"/driver = \"wifi\"/" "$1" > "$2"; python3 "$3" validate "$2" >/dev/null 2>&1; test $? -ne 0' _ "$WIFI_BASE" "$TMP/wifi-alias.toml" "$ROOT/lib/toml_engine.py"
check 'negative: wireless.driver=none rejects active radio configuration' bash -c 'sed "s/driver = \"legacy\"/driver = \"none\"/" "$1" > "$2"; python3 "$3" validate "$2" >/dev/null 2>&1; test $? -ne 0' _ "$TMP/wifi-original.toml" "$TMP/wifi-none-active.toml" "$ROOT/lib/toml_engine.py"
check 'negative: legacy rejects WPA3-PSK' bash -c 'python3 - "$1" "$2" <<"PYWIFI"
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
start = src.index("[security.wifi]")
end = src.find("\n[", start + 1)
if end < 0: end = len(src)
section = src[start:end].replace("authentication = \"wpa2-psk\"", "authentication = \"wpa3-psk\"", 1)
pathlib.Path(sys.argv[2]).write_text(src[:start] + section + src[end:])
PYWIFI
python3 "$3" validate "$2" >/dev/null 2>&1; test $? -ne 0' _ "$TMP/wifi-original.toml" "$TMP/legacy-wpa3.toml" "$ROOT/lib/toml_engine.py"
cp "$TMP/wifi-original.toml" "$WIFI_BASE"

# UPnP: для стандартних профілів вимкнено детерміновано; з конфігом — увімкнено з інтерфейсами.
check 'UPnP disabled by default in generated RSC' grep -q '/ip upnp set enabled=no' "$CHR_RSC"
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/chr-config.upnp"
cat >> "$TMP/project/profiles/$CHR_PROFILE/config.toml" <<'EOF'

[upnp]
enabled = true
external = "@interfaces.ether6"
internal = "@bridge.lan"
EOF
check 'profile with UPnP validates' run_ok "$M" --validate --profile "$CHR_PROFILE"
check 'profile with UPnP builds' run_ok "$M" --build --profile "$CHR_PROFILE" --name upnp-test.rsc
UPNP_RSC="$TMP/project/profiles/$CHR_PROFILE/output/upnp-test.rsc"
check 'UPnP service is enabled' grep -q '/ip upnp set enabled=yes' "$UPNP_RSC"
check 'UPnP external interface is WAN' grep -q 'interfaces add interface="02_wan" type=external' "$UPNP_RSC"
check 'UPnP internal interface is LAN bridge' grep -q 'interfaces add interface="bridge-lan" type=internal' "$UPNP_RSC"
sed 's/internal = "@bridge.lan"/internal = "@interfaces.ether6"/' "$TMP/project/profiles/$CHR_PROFILE/config.toml" > "$TMP/project/profiles/$CHR_PROFILE/config.toml.new"
mv "$TMP/project/profiles/$CHR_PROFILE/config.toml.new" "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'negative: UPnP external==internal rejected' run_fail "$M" --validate --profile "$CHR_PROFILE"
mv "$TMP/chr-config.upnp" "$TMP/project/profiles/$CHR_PROFILE/config.toml"


# Перевірка кількох користувачів: два ключі у тестового користувача і disabled backup без імпорту ключа.
cat >> "$TMP/project/profiles/$CHR_PROFILE/config.toml" <<'EOF'

[users.disabled_existing]
name = "disabled-existing"
enabled = false
create = false
group = "read"
password_file = ".secrets"
password_key = "DISABLED_USER_PASSWORD"
EOF
cat >> "$TMP/project/profiles/$CHR_PROFILE/.secrets" <<'EOF'
TEST_ROMAN_PASSWORD=TestOnly-Roman-Password
TEST_BACKUP_PASSWORD=TestOnly-Backup-Password
EOF
cat >> "$TMP/project/profiles/$CHR_PROFILE/config.toml" <<'EOF'

[users.test_roman]
name = "test-roman"
enabled = true
create = true
group = "full"
password_file = ".secrets"
password_key = "TEST_ROMAN_PASSWORD"
ssh_keys = ["~/.ssh/roman.pub", "~/.ssh/id_mikrotik_lab.pub"]

[users.backup]
name = "backup"
enabled = false
create = true
group = "read"
password_file = ".secrets"
password_key = "TEST_BACKUP_PASSWORD"
ssh_keys = ["~/.ssh/backup.pub"]
EOF
check 'multi-user profile validates' run_ok "$M" --validate --profile "$CHR_PROFILE"
check 'multi-user profile builds' run_ok "$M" --build --profile "$CHR_PROFILE" --name users-test.rsc
# Lockout-контракт: connection.user має посилатися на активного користувача профілю.
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/chr-config.lockout"
sed 's/^user = "roman"$/user = "disabled-existing"/' "$TMP/chr-config.lockout" > "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'negative: connection.user pointing at disabled user rejected' run_fail "$M" --validate --profile "$CHR_PROFILE"
sed 's/^user = "roman"$/user = "nonexistent-user"/' "$TMP/chr-config.lockout" > "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'negative: unknown connection.user rejected' run_fail "$M" --validate --profile "$CHR_PROFILE"
mv "$TMP/chr-config.lockout" "$TMP/project/profiles/$CHR_PROFILE/config.toml"
# Allowlist: [services] приймає лише стандартні IP-служби RouterOS.
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/chr-config.services"
printf '\n[services.reverse-proxy]\nenabled = true\nport = 8118\nlimit_to_lan = true\n' >> "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'negative: non-standard service name rejected' run_fail "$M" --validate --profile "$CHR_PROFILE"
mv "$TMP/chr-config.services" "$TMP/project/profiles/$CHR_PROFILE/config.toml"
USERS_RSC="$TMP/project/profiles/$CHR_PROFILE/output/users-test.rsc"
check 'test user gets first configured SSH key' grep -q 'public-key-file=\"mgr-test-roman-1.pub\" user=\"test-roman\"' "$USERS_RSC"
check 'test user gets second configured SSH key' grep -q 'public-key-file=\"mgr-test-roman-2.pub\" user=\"test-roman\"' "$USERS_RSC"
check 'SSH key import includes stable fingerprint marker' grep -Eq 'fingerprint="SHA256:[A-Za-z0-9+/=]{40,60}"' "$USERS_RSC"
check 'test user account is generated enabled' grep -Fq '/user enable $mgrUserRef' "$USERS_RSC"
check 'backup account is created disabled' grep -Fq '/user add name="backup" group=read password="TestOnly-Backup-Password" disabled=yes' "$USERS_RSC"
check 'backup account disable is deferred' grep -Fq '/user disable $mgrDisableRef' "$USERS_RSC"
check 'disabled backup SSH key is not imported' not_contains "$USERS_RSC" 'mgr-backup-1.pub'
check 'disabled existing-only user builds without secret' run_ok "$M" --build --profile "$CHR_PROFILE" --name disabled-existing.rsc
DISABLED_RSC="$TMP/project/profiles/$CHR_PROFILE/output/disabled-existing.rsc"
check 'disabled existing-only user is not assigned a password' bash -c '! grep -F "user disabled-existing" "$1" | grep -q "password="' _ "$DISABLED_RSC"
check 'disabled existing-only user remains disabled' grep -Fq 'user disabled-existing not found; create=false' "$DISABLED_RSC"
check '--secrets skips disabled existing-only user secret' bash -c 'out=$("$1" --secrets --profile "$2" 2>&1); grep -q "create=false та enabled=false" <<< "$out"' _ "$M" "$CHR_PROFILE"
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/chr-config.base"
sed '/^\[updates\]/a auto_install = true\nauto_reboot = true\nauto_interval = "6h"' "$TMP/chr-config.base" > "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'configurable update scheduler interval' run_ok "$M" --build --profile "$CHR_PROFILE" --name update-test.rsc
check 'update scheduler uses TOML interval' grep -q 'interval=6h' "$TMP/project/profiles/$CHR_PROFILE/output/update-test.rsc"
mv "$TMP/chr-config.base" "$TMP/project/profiles/$CHR_PROFILE/config.toml"

printf '%s\n' '[4] Security and CLI contracts'
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/chr-config.good"
printf '\n[paths]\noutput_dir = "../escape"\nbackup_dir = "backups"\n' >> "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'negative: path traversal rejected' run_fail "$M" --build --profile "$CHR_PROFILE"
mv "$TMP/chr-config.good" "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'profile list' run_ok "$M" --list
mkdir -p "$TMP/project/profiles/test.v1"
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/project/profiles/test.v1/config.toml"
check '--profile accepts dot in profile name' run_ok "$M" --validate --profile test.v1
mkdir -p "$TMP/project/profiles/9_Lab-Profile.v2"
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/project/profiles/9_Lab-Profile.v2/config.toml"
check '--profile accepts uppercase, digits, underscore, hyphen and dot' run_ok "$M" --validate --profile 9_Lab-Profile.v2
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/project/profiles/standalone.v1.toml"
check 'single-file profile is supported' run_ok "$M" --validate --profile standalone.v1
rm -f "$TMP/project/profiles/standalone.v1.toml"
ln -s "$TMP/project/profiles/$CHR_PROFILE" "$TMP/project/profiles/symlink-profile"
check 'symlink profile directory is rejected' run_fail "$M" --validate --profile symlink-profile
rm "$TMP/project/profiles/symlink-profile"
mkdir -p "$TMP/project/profiles/symlink-config"
ln -s "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/project/profiles/symlink-config/config.toml"
check 'symlink TOML file is rejected' run_fail "$M" --validate --profile symlink-config
rm -rf "$TMP/project/profiles/symlink-config"
check 'secret error hints use flag-based --secrets syntax' bash -c '! grep -Eq "mikrotik-manager\.sh secrets \$\{PROFILE\}" "$1"' _ "$M"
check 'invalid CLI option rejected' run_fail "$M" --build --profile "$CHR_PROFILE" --unknown-option
check '--yes without --reset rejected' run_fail "$M" --upload --profile "$CHR_PROFILE" --yes
check 'legacy positional command rejected' run_fail "$M" build "$CHR_PROFILE"
check 'profile is required for profile operations' run_fail "$M" --build
check 'duplicate --profile rejected' run_fail "$M" --build --profile "$CHR_PROFILE" --profile "$HOME_PROFILE"
check '--reset without --upload rejected' run_fail "$M" --reset --profile "$CHR_PROFILE"
check '--name invalid extension rejected' run_fail "$M" --build --profile "$CHR_PROFILE" --name bad.txt
check '--name empty value rejected' run_fail "$M" --build --profile "$CHR_PROFILE" --name=
check '--output empty value rejected' run_fail "$M" --build --profile "$CHR_PROFILE" --output=
check '--output without build/upload rejected' run_fail "$M" --validate --profile "$CHR_PROFILE" --output ./dist
check '--name without build/upload rejected' run_fail "$M" --validate --profile "$CHR_PROFILE" --name bad.rsc
check 'backup path is profile-local in source' grep -q 'PROFILE_DIR/$(rel_dir_checked' "$M"
check 'environment overrides removed' bash -c '! grep -Eq "BACKUP_DIR=\$\{|OUTPUT_DIR=\$\{|REMOTE_DIR=\$\{|KEEP_RSC_ON_ROUTER=\$\{" "$1"' _ "$M"

# Mocked transport: verifies local-file selection and operation ordering without a router.
mkdir -p "$TMP/mock-bin" "$TMP/mock-output"
cat > "$TMP/mock-bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf 'ssh-argv %s\n' "$*" >> "$MOCK_TRANSPORT_LOG"
last=${!#}
if [[ $last == *@* && $last != *' '* ]]; then
  while IFS= read -r line; do printf 'ssh-stdin %s\n' "$line" >> "$MOCK_TRANSPORT_LOG"; done
fi
exit 0
EOF
cat > "$TMP/mock-bin/scp" <<'EOF'
#!/usr/bin/env bash
printf 'scp %s\n' "$*" >> "$MOCK_TRANSPORT_LOG"
args=("$@")
source_path=${args[${#args[@]}-2]}
destination=${args[${#args[@]}-1]}
# Імітація завантаження remote -> local для тесту backup; жодної мережі немає.
if [[ $source_path == *:* && $destination == */ ]]; then
  remote_file=${source_path#*:}
  : > "$destination/${remote_file##*/}"
fi
exit 0
EOF
chmod +x "$TMP/mock-bin/ssh" "$TMP/mock-bin/scp"
export MOCK_TRANSPORT_LOG="$TMP/transport.log"
export PATH="$TMP/mock-bin:$PATH"
: > "$MOCK_TRANSPORT_LOG"
check '--upload missing RSC fails without invoking scp' run_fail "$M" --upload --profile "$CHR_PROFILE" --name missing.rsc
check '--upload missing RSC performs no transport' bash -c '! grep -q "scp " "$1"' _ "$MOCK_TRANSPORT_LOG"
mkdir -p "$TMP/mock-output"
check 'build valid pre-existing upload fixture' run_ok "$M" --build --profile "$CHR_PROFILE" --name existing.rsc --output "$TMP/mock-output"
FIXTURE_HASH_BEFORE=$(sha256sum "$TMP/mock-output/existing.rsc" | awk '{print $1}')
: > "$MOCK_TRANSPORT_LOG"
check '--upload uses pre-existing --name/--output file' run_ok "$M" --upload --profile "$CHR_PROFILE" --name existing.rsc --output "$TMP/mock-output"
FIXTURE_HASH_AFTER=$(sha256sum "$TMP/mock-output/existing.rsc" | awk '{print $1}')
check '--upload does not alter pre-existing RSC' bash -c '[[ $1 == "$2" ]]' _ "$FIXTURE_HASH_BEFORE" "$FIXTURE_HASH_AFTER"
check '--upload transport references selected file' bash -c 'grep -Fq "$1" "$2"' _ "$TMP/mock-output/existing.rsc" "$MOCK_TRANSPORT_LOG"
# Зміни секретів/TOML після --build більше не блокують upload/reset —
# заголовки config/secrets-sha256 суто інформаційні; для застосування
# нових значень достатньо виконати новий --build.
cp "$TMP/project/profiles/$CHR_PROFILE/.secrets" "$TMP/chr-secrets.saved"
printf 'INTEGRITY_TEST=ChangedSecretValue\n' >> "$TMP/project/profiles/$CHR_PROFILE/.secrets"
: > "$MOCK_TRANSPORT_LOG"
check 'stale secrets do not block upload' run_ok "$M" --upload --profile "$CHR_PROFILE" --name existing.rsc --output "$TMP/mock-output"
mv "$TMP/chr-secrets.saved" "$TMP/project/profiles/$CHR_PROFILE/.secrets"
# Зміна TOML після --build не блокує upload; RESET перевіряється окремим mock-сценарієм.
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/chr-config.fingerprint"
sed 's/generated_for = "RouterOS 7.24.6"/generated_for = "RouterOS 7.24.7"/' "$TMP/chr-config.fingerprint" > "$TMP/project/profiles/$CHR_PROFILE/config.toml"
: > "$MOCK_TRANSPORT_LOG"
check 'stale RSC upload is allowed after TOML change' run_ok "$M" --upload --profile "$CHR_PROFILE" --name existing.rsc --output "$TMP/mock-output"
mv "$TMP/chr-config.fingerprint" "$TMP/project/profiles/$CHR_PROFILE/config.toml"
# Fingerprint включає кожен TOML-файл профілю, а не лише config.toml.
cat > "$TMP/project/profiles/$CHR_PROFILE/z-extra.toml" <<'EOF'
[interfaces.ether7]
name = "extra"
enabled = false
comment = "extra TOML input"
EOF
check 'build with multiple TOML inputs' run_ok "$M" --build --profile "$CHR_PROFILE" --name multi-toml.rsc --output "$TMP/mock-output"
rm -f "$TMP/project/profiles/$CHR_PROFILE/z-extra.toml"
check '--upload-only does not create missing RSC' test ! -e "$TMP/project/profiles/$CHR_PROFILE/output/missing.rsc"
: > "$MOCK_TRANSPORT_LOG"
if "$M" --upload --output "$TMP/mock-output" --profile "$CHR_PROFILE" --name combined.rsc --build > "$TMP/build-upload.output" 2>&1; then
  pass '--build --upload with --name/--output succeeds'
else
  fail '--build --upload with --name/--output succeeds'
fi
check '--build --upload creates selected output file' test -s "$TMP/mock-output/combined.rsc"
check '--build --upload calls scp after build output exists' bash -c 'grep -Fq "$1" "$2"' _ "$TMP/mock-output/combined.rsc" "$MOCK_TRANSPORT_LOG"
check '--build --upload invokes one scp transfer' bash -c '[[ $(grep -c "^scp " "$1") -eq 1 ]]' _ "$MOCK_TRANSPORT_LOG"
check '--build --upload generates exactly once' bash -c '[[ $(grep -c "Згенеровано:" "$1") -eq 1 ]]' _ "$TMP/build-upload.output"
: > "$MOCK_TRANSPORT_LOG"
check '--build-only does not invoke network transport' run_ok "$M" --build --profile "$CHR_PROFILE" --name local-only.rsc --output "$TMP/mock-output"
check '--build-only makes no SSH/SCP calls' test ! -s "$MOCK_TRANSPORT_LOG"
check '--verbose is accepted and prints selected RSC path' bash -c 'out=$("$1" --verbose --build --profile "$2" --name verbose.rsc 2>&1); grep -q "Каталог локального RSC" <<< "$out"' _ "$M" "$CHR_PROFILE"

# Backup is tested with mocked SSH/SCP and zero settle delay; no RouterOS is contacted.
sed '/^\[connection\]/a transfer_settle_seconds = 0' "$TMP/project/profiles/$CHR_PROFILE/config.toml" > "$TMP/chr-fast-backup.toml"
cp "$TMP/chr-fast-backup.toml" "$TMP/project/profiles/$CHR_PROFILE/config.toml"
check 'rebuild selected RSC after TOML fingerprint change' run_ok "$M" --build --profile "$CHR_PROFILE" --name combined.rsc --output "$TMP/mock-output"
: > "$MOCK_TRANSPORT_LOG"
check '--backup standalone succeeds through mocked transport' run_ok "$M" --backup --profile "$CHR_PROFILE"
check '--backup standalone creates local backup and export' bash -c 'compgen -G "$1/*.backup" >/dev/null && compgen -G "$1/*.rsc" >/dev/null' _ "$TMP/project/profiles/$CHR_PROFILE/backups"
check '--backup standalone does not reset router' bash -c '! grep -q "reset-configuration" "$1"' _ "$MOCK_TRANSPORT_LOG"
: > "$MOCK_TRANSPORT_LOG"
check '--backup --upload succeeds through mocked transport' run_ok "$M" --backup --upload --profile "$CHR_PROFILE" --name combined.rsc --output "$TMP/mock-output"
check '--backup --upload runs backup before RSC upload' bash -c 'backup=$(grep -n "system backup save" "$1" | head -n1 | cut -d: -f1); upload=$(grep -n "scp .*combined.rsc" "$1" | tail -n1 | cut -d: -f1); [[ -n $backup && -n $upload && $backup -lt $upload ]]' _ "$MOCK_TRANSPORT_LOG"
check '--backup --upload does not issue reset' bash -c '! grep -q "reset-configuration" "$1"' _ "$MOCK_TRANSPORT_LOG"
# Пароль backup має бути у stdin, а не в argv процесу ssh.
cp "$TMP/project/profiles/$CHR_PROFILE/config.toml" "$TMP/chr-config.backup"
printf '\n[backup]\nencrypt = true\npassword_file = ".secrets"\npassword_key = "BACKUP_PASSWORD"\n' >> "$TMP/project/profiles/$CHR_PROFILE/config.toml"
printf 'BACKUP_PASSWORD=MockBackupSecret-Only\n' >> "$TMP/project/profiles/$CHR_PROFILE/.secrets"
chmod 600 "$TMP/project/profiles/$CHR_PROFILE/.secrets"
: > "$MOCK_TRANSPORT_LOG"
check 'encrypted backup mock succeeds' run_ok "$M" --backup --profile "$CHR_PROFILE"
check 'backup password is not present in SSH argv' bash -c '! grep -F MockBackupSecret-Only "$1" | grep -q "^ssh-argv "' _ "$MOCK_TRANSPORT_LOG"
check 'backup password is delivered through SSH stdin' grep -Fq 'ssh-stdin /system backup save name=' "$MOCK_TRANSPORT_LOG"
check 'backup password appears only in SSH stdin payload' bash -c 'grep -F MockBackupSecret-Only "$1" | grep -q "^ssh-stdin " && ! grep -F MockBackupSecret-Only "$1" | grep -q "^ssh-argv "' _ "$MOCK_TRANSPORT_LOG"
mv "$TMP/chr-config.backup" "$TMP/project/profiles/$CHR_PROFILE/config.toml"

# Мок reset: імітуємо SSH 255 під час reboot, preflight проходить успішно.
mkdir -p "$TMP/reset-bin"
cat > "$TMP/reset-bin/ssh" <<'EOF'
#!/usr/bin/env bash
args="$*"
printf 'reset-mock-ssh %s\n' "$args" >> "$MOCK_RESET_LOG"
if [[ $args == *reset-configuration* ]]; then exit 255; fi
exit 0
EOF
cat > "$TMP/reset-bin/scp" <<'EOF'
#!/usr/bin/env bash
printf 'reset-mock-scp %s\n' "$*" >> "$MOCK_RESET_LOG"
exit 0
EOF
chmod 755 "$TMP/reset-bin/ssh" "$TMP/reset-bin/scp"
export MOCK_RESET_LOG="$TMP/reset-transport.log"
export PATH="$TMP/reset-bin:$TMP/test-bin:$PATH"
"$M" --build --profile "$CHR_PROFILE" --name reset-test.rsc >/dev/null 2>&1
: > "$MOCK_RESET_LOG"
check 'mock reset tolerates SSH 255 mid-reboot' run_ok "$M" --upload --reset --yes --profile "$CHR_PROFILE" --name reset-test.rsc
check 'mock reset sends only one reset command' bash -c '[[ $(grep -c reset-configuration "$1") -eq 1 ]]' _ "$MOCK_RESET_LOG"
check 'mock reset runs read-only preflight before reset' bash -c "p=\$(grep -n 'mgr-preflight-ok' \"\$1\" | head -n1 | cut -d: -f1); r=\$(grep -n reset-configuration \"\$1\" | head -n1 | cut -d: -f1); [[ -n \$p && -n \$r && \$p -lt \$r ]]" _ "$MOCK_RESET_LOG"
: > "$MOCK_RESET_LOG"
check 'same RSC/apply-token is not blocked by one-time state' run_ok "$M" --upload --reset --yes --profile "$CHR_PROFILE" --name reset-test.rsc
check 'repeated reset is sent to mock transport' grep -q reset-configuration "$MOCK_RESET_LOG"
check 'RESET creates no one-time marker sidecar' test ! -e "$TMP/project/profiles/$CHR_PROFILE/output/reset-test.rsc.reset-attempted"
# Негативний сценарій: SSH-канал недоступний — reset НЕ відправляється з кодом 0.
mkdir -p "$TMP/down-bin"
cat > "$TMP/down-bin/ssh" <<'EOF'
#!/usr/bin/env bash
args="$*"
printf 'down-mock-ssh %s\n' "$args" >> "$MOCK_RESET_LOG"
if [[ $args == *reset-configuration* ]]; then exit 255; fi
exit 1
EOF
cat > "$TMP/down-bin/scp" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 755 "$TMP/down-bin/ssh" "$TMP/down-bin/scp"
: > "$MOCK_RESET_LOG"
check 'SSH unavailable before reset aborts run' run_fail env PATH="$TMP/down-bin:$TMP/test-bin:/usr/bin:/bin" "$M" --upload --reset --yes --profile "$CHR_PROFILE" --name reset-test.rsc
check 'SSH unavailable aborts without sending reset' bash -c '! grep -q reset-configuration "$1"' _ "$MOCK_RESET_LOG"
check 'fresh build creates a new reset correlation token' run_ok "$M" --build --profile "$CHR_PROFILE" --name reset-test.rsc
check 'fresh build creates a new reset correlation token' run_ok "$M" --build --profile "$CHR_PROFILE" --name reset-test.rsc
printf '%s\n' '[5] Router integration'
skip 'SSH upload' 'не виконувалось: не підключаємося до роутера в локальному тестовому прогоні'
skip 'backup/reset/run-after-reset' 'не виконувалось: операції змінюють конфігурацію CHR'
skip 'fingerprint import semantics' 'потрібен фактичний імпорт SSH public key на лабораторному RouterOS; локально перевірено лише генерацію команди'
skip 'RouterOS .rsc runtime' 'потрібен імпорт у CHR; цей тест навмисно не запускався'

printf '\n=== SUMMARY ===\nPASS: %d\nFAIL: %d\nSKIP: %d\nTOTAL: %d\n' "$PASS" "$FAIL" "$SKIP" "$TOTAL"
(( FAIL == 0 ))




