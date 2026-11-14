#!/usr/bin/env bash
# ============================================================
# mikrotik-manager.sh — менеджер профілів MikroTik (RouterOS 7)
#   TOML-профіль → .rsc → scp на роутер → (опційно) reset + автозастосування
# Потрібно: bash >= 4.4, ssh, scp (OpenSSH), стандартні coreutils.
# ============================================================
set -Eeuo pipefail
shopt -s nullglob

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
  echo "Потрібен bash >= 4.4 (macOS: brew install bash)" >&2; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="$SCRIPT_DIR/profiles"
TOML_ENGINE="$SCRIPT_DIR/lib/toml_engine.py"
VERIFY_ENGINE="$SCRIPT_DIR/lib/routeros_verify.py"


RSC_TMP=""
trap '[[ -n $RSC_TMP ]] && rm -f "$RSC_TMP"; true' EXIT
trap 'printf "ПОМИЛКА: рядок %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# ------------------------------------------------------------
# Утиліти
# ------------------------------------------------------------
die()  { printf 'ПОМИЛКА: %s\n' "$*" >&2; exit 1; }
warn() { printf 'УВАГА: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*" >&2; }

usage() {
  local self=${0##*/}
  cat <<EOF
MikroTik Manager Bash — домашнє керування RouterOS 7 (1–3 маршрутизатори).

ВИКОРИСТАННЯ
  $self --list
  $self --validate --profile PROFILE
  $self --build --profile PROFILE [--name FILE.rsc] [--output DIR]
  $self --verify --profile PROFILE
  $self --upload --profile PROFILE [--name FILE.rsc] [--output DIR]
  $self --backup --profile PROFILE
  $self --secrets --profile PROFILE

ОПЕРАЦІЇ
  --list                 Список профілів та адрес.
  --validate             Локальна перевірка TOML і посилань.
  --build                Локальна генерація RSC; до роутера не підключається.
  --verify               Показати read-only команди RouterOS у терміналі; без файлів і мережі.
  --upload               Передати наявний RSC через SCP; не генерує та не імпортує його.
  --backup               Завантажити backup та export у каталог профілю.
  --secrets              Інтерактивно створити або доповнити .secrets.

ПАРАМЕТРИ
  --profile PROFILE      Назва профілю (латиниця, цифри, крапка, _ та -).
  --name FILE.rsc        Ім'я RSC для build/upload.
  --output DIR           Каталог RSC; типово profiles/PROFILE/output.
  --verbose, -v          Додаткові повідомлення.
  --reset                Після upload виконати руйнівний reset із run-after-reset.
  --yes, -y              Не питати підтвердження; лише разом із --reset.
  -h, --help             Ця довідка.

КОМБІНАЦІЇ
  --build --upload       Згенерувати RSC, потім завантажити його.
  --backup --upload      Спочатку backup/export, потім завантажити RSC.
  --backup --upload --reset
                         Backup → upload → reset із run-after-reset.

ВАЖЛИВО
  • --upload окремо передає лише вже наявний RSC і не змінює локальний файл.
  • Для застосування без reset імпортуйте завантажений RSC вручну з RouterOS.
  • --reset видаляє поточну конфігурацію; потрібне підтвердження або --yes.
  • --backup за замовчуванням не шифрує .backup; зберігайте backups/ приватно.
  • .secrets і згенеровані RSC можуть містити паролі; права файлів — 600.
  • Назви профілів із пробілами, українськими літерами або шляхами заборонені.

ПЕРШЕ ПІДКЛЮЧЕННЯ
  Фізичний MikroTik: спочатку налаштуйте IP та SSH через локальну консоль.
  VirtualBox CHR: використовуйте Host-only vboxnet0 (приклад 192.168.56.2).
  Перед upload/backup перевірте ручний SSH-вхід і fingerprint host key.
  Детальні кроки та приклади TOML: README.md.

ВИМОГИ
  Bash >= 4.4, Python >= 3.11, OpenSSH (ssh/scp для мережевих операцій).

КОДИ ЗАВЕРШЕННЯ
  0 — успіх; 1 — помилка.
EOF
}
# ------------------------------------------------------------
# Дані профілю імпортуються зі строгого Python tomllib engine.
# ------------------------------------------------------------
declare -A CFG=() SEC_SEEN=()
SECTIONS=()

has()     { [[ -n ${CFG[$1]+x} ]]; }
cfg()     { printf '%s' "${CFG[$1]-${2-}}"; }
is_true() { [[ ${CFG[$1]-${2:-false}} == true ]]; }
need()    { local k; for k in "$@"; do has "$k" || die "У профілі '$PROFILE' відсутній параметр: $k"; done; }

# Прямі діти секції: children interfaces → ether1 ether2 …
children() {
  local s p="$1."
  for s in "${SECTIONS[@]}"; do
    if [[ $s == "$p"* && ${s#"$p"} != *.* ]]; then printf '%s\n' "${s#"$p"}"; fi
  done
  return 0
}

PFILES=()
profile_files() {
  local profile_path="$PROFILES_DIR/$1" file
  PFILES=()
  [[ ! -L $profile_path ]] || die "Каталог профілю не може бути символічним посиланням: $profile_path"
  [[ ! -L $profile_path.toml ]] || die "Файл профілю не може бути символічним посиланням: $profile_path.toml"
  if [[ -d $profile_path ]]; then
    for file in "$profile_path"/*.toml; do
      [[ ! -L $file ]] || die "TOML-файл профілю не може бути символічним посиланням: $file"
      [[ -f $file ]] && PFILES+=("$file")
    done
  elif [[ -f $profile_path.toml ]]; then
    PFILES=("$profile_path.toml")
  fi
  (( ${#PFILES[@]} )) || die "Профіль '$1' не знайдено ($profile_path/*.toml або $profile_path.toml)"
}

# Allowlist стандартних IP-служб RouterOS — єдине джерело: lib/schema.json
# (ключ service_allowlist). Читається ліниво, один раз на запуск.
SERVICE_ALLOWLIST_STR=""
service_allowed() {
  local key=$1 s
  if [[ -z $SERVICE_ALLOWLIST_STR ]]; then
    SERVICE_ALLOWLIST_STR=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1], encoding="utf-8"))["service_allowlist"]))' "$SCRIPT_DIR/lib/schema.json") \
      || die "Не вдалося прочитати service_allowlist із lib/schema.json"
  fi
  for s in $SERVICE_ALLOWLIST_STR; do [[ $s == "$key" ]] && return 0; done
  return 1
}

load_profile() {
  local f parsed
  PROFILE=$1; PROFILE_DIR="$PROFILES_DIR/$1"
  [[ $PROFILE =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "Недопустиме ім'я профілю: $PROFILE"
  CFG=(); SEC_SEEN=(); SECTIONS=()
  profile_files "$PROFILE"
  command -v python3 >/dev/null 2>&1 || die "Потрібен Python 3.11+ (tomllib у стандартній бібліотеці)"
  [[ $(python3 -c 'import sys; print(sys.version_info >= (3,11))') == True ]] || die "Потрібен Python 3.11+"
  parsed=$(python3 "$TOML_ENGINE" export "${PFILES[@]}") || die "TOML-профіль не пройшов перевірку схеми"
  # shellcheck disable=SC1090
  eval "$parsed"
  for f in "${SECTIONS[@]}"; do
    : "${SEC_SEEN[$f]:=1}"
  done
}

# ------------------------------------------------------------
# Посилання @section.path — без окремих ID у TOML.
# ------------------------------------------------------------
SEC=""; REF=""; REF_SEC=""
find_sec() {
  local r=${1#@}
  if [[ -n ${SEC_SEEN[$r]+x} ]]; then SEC=$r
  else die "Невідоме посилання @$r (немає секції [$r])"; fi
}
# Посилання → ім'я ресурсу RouterOS (name; для секцій з interface — слідуємо за ним)
ref_name() {
  local s
  if [[ $1 != @* ]]; then REF=$1; REF_SEC=""; return 0; fi
  find_sec "$1"; s=$SEC
  if   has "$s.name";      then REF=${CFG[$s.name]}; REF_SEC=$s
  elif has "$s.interface"; then ref_name "${CFG[$s.interface]}"
  else die "Посилання $1 (секція [$s]) не має параметра name"; fi
}
# Посилання → адреса (address)
ref_addr() {
  if [[ $1 == @* ]]; then
    find_sec "$1"
    has "$SEC.address" || die "Посилання $1 (секція [$SEC]) не має address"
    ref_addr "${CFG[$SEC.address]}"
  else REF=$1; fi
}

# ------------------------------------------------------------
# Валідатори й мережеві хелпери
# ------------------------------------------------------------
re_ip='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
is_ip() {
  local o x
  [[ $1 =~ $re_ip ]] || return 1
  IFS=. read -ra o <<<"$1"
  for x in "${o[@]}"; do (( 10#$x <= 255 )) || return 1; done
}
# 10# — арифметика без октальної інтерпретації ведучих нулів (напр. /08):
# Python-валідатор приймає префікс з нулем, тож bash не має падати аварійно.
is_cidr() { [[ $1 == */* ]] && is_ip "${1%/*}" && [[ ${1#*/} =~ ^[0-9]+$ ]] && (( 10#${1#*/} <= 32 )); }
is_mac()  { [[ $1 =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; }
is_port() { [[ $1 =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
ip2int()  { local a b c d; IFS=. read -r a b c d <<<"$1"; echo $(( (10#$a<<24) + (10#$b<<16) + (10#$c<<8) + 10#$d )); }
int2ip()  { local n=$1; echo "$(( (n>>24)&255 )).$(( (n>>16)&255 )).$(( (n>>8)&255 )).$(( n&255 ))"; }
cidr_net() {
  local ip=${1%/*} m n
  local p=$(( 10#${1#*/} ))
  m=$(( p == 0 ? 0 : (0xFFFFFFFF << (32 - p)) & 0xFFFFFFFF ))
  n=$(( $(ip2int "$ip") & m ))
  echo "$(int2ip "$n")/$p"
}

# Екранування рядка для RouterOS: \ " $ ?
q() {
  local s=$1
  [[ ! $s =~ [[:cntrl:]] ]] || die "Рядкове значення містить керівний символ, заборонений у RouterOS RSC"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//\$/\\\$}; s=${s//\?/\\\?}
  printf '"%s"' "$s"
}
yn()  { if [[ $1 == true ]]; then echo yes; else echo no; fi; }
dis() { if [[ $1 == true ]]; then echo no;  else echo yes; fi; }

EXP=""; PROFILE_DIR=""
# ~/x → $HOME/x; /abs → як є; відносний шлях → відносно каталогу профілю ($PROFILES_DIR/<profile>/)
expand_path() {
  EXP=$1
  if [[ $EXP == "~/"* ]]; then EXP="$HOME/${EXP#"~/"}"
  elif [[ $EXP != /* && -n $PROFILE_DIR ]]; then EXP="$PROFILE_DIR/$EXP"; fi
}

PW=""
# Значення ключа KEY з файлу KEY=VALUE (без source; без лапок; остання згадка виграє) → PW
lookup_key() {
  local f=$1 k=$2 line
  PW=""
  [[ -r $f ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    if [[ $line == "$k="* ]]; then PW=${line#"$k="}; fi
  done < "$f"
  [[ -n $PW ]]
}

read_pw() {  # read_pw <файл> <опис> [ключ]; без ключа — весь файл = один пароль
  local perm key=${3:-}
  expand_path "$1"
  [[ -r $EXP ]] || die "Файл секретів для $2 не знайдено або недоступний: $EXP (створити: ${0##*/} --secrets --profile $PROFILE)"
  perm=$(stat -c %a "$EXP" 2>/dev/null || stat -f %Lp "$EXP" 2>/dev/null || echo 600)
  [[ $perm == 600 || $perm == 400 ]] || warn "Файл секретів $EXP має права $perm; рекомендовано chmod 600"
  if [[ -n $key ]]; then
    lookup_key "$EXP" "$key" || die "У $EXP немає непорожнього значення $key (потрібне для $2; додати: ${0##*/} --secrets --profile $PROFILE)"
  else
    PW=$(head -n1 "$EXP" | tr -d '\r\n')
    [[ -n $PW ]] || die "Файл пароля для $2 порожній: $EXP"
  fi
}
read_pw_sec() { read_pw "${CFG[$1.password_file]}" "$1" "$(cfg "$1.password_key")"; }

check_secret_perms() {
  # Права всіх секрет-файлів, на які посилається профіль: лише 600/400 — інакше warn.
  local key perm
  for key in "${!CFG[@]}"; do
    [[ $key == *.password_file ]] || continue
    expand_path "${CFG[$key]}"
    [[ -f $EXP ]] || continue
    perm=$(stat -c %a "$EXP" 2>/dev/null || stat -f %Lp "$EXP" 2>/dev/null || echo 600)
    [[ $perm == 600 || $perm == 400 ]] || warn "Секрет-файл $key ($EXP) має права $perm; рекомендовано chmod 600"
  done
}

# ------------------------------------------------------------
# Вивід .rsc
# ------------------------------------------------------------
out() { printf '%s\n' "$*" >> "$RSC_TMP"; }
sec() { out ""; out "# ---- $* ----"; }
# rs: команда в обгортці — збій одного рядка пишеться в лог і НЕ зупиняє скрипт
rs() {
  local cmd=$1 label=${2:-} lbl
  # Мітка не містить секретів і дає зрозумілу причину помилки в журналі.
  if [[ -n $label ]]; then lbl=$label
  else lbl=$(printf '%s' "${cmd:0:60}" | tr -d '"$\\?[]{}'); fi
  printf ':do { %s } on-error={ :global mgrErrors; :set mgrErrors ($mgrErrors + 1); :log error "mgr: FAILED: %s" }\n' "$cmd" "$lbl" >> "$RSC_TMP"
}

LAN_ADDR=""; LAN_NET=""; WAN_L=""; LAN_L=""; LAN_IF=""

# ------------------------------------------------------------
# Генератори
# ------------------------------------------------------------
gen_system() {
  local s n=0 max_servers auto_interval
  local -a L
  sec "System: identity / clock / NTP"
  need identity.name
  [[ $(cfg identity.name) != *[[:space:]]* ]] || die "identity.name не має містити пробілів"
  rs "/system identity set name=$(q "$(cfg identity.name)")"
  if has clock.timezone; then rs "/system clock set time-zone-autodetect=no time-zone-name=$(q "$(cfg clock.timezone)")"; fi
  if is_true ntp.enabled; then
    rs "/system ntp client set enabled=yes"
    mapfile -t L < <(cfg ntp.servers)
    max_servers=$(cfg ntp.max_servers 4)
    [[ $max_servers =~ ^[0-9]+$ ]] && (( max_servers >= 1 && max_servers <= 16 )) || die "ntp.max_servers має бути 1..16"
    for s in "${L[@]}"; do
      [[ -n $s ]] || continue
      n=$((n+1)); (( n <= max_servers )) || { warn "NTP: використано перші $max_servers серверів"; break; }
      rs "/system ntp client servers add address=$(q "$s")"
    done
  else
    rs "/system ntp client set enabled=no"
  fi
  sec "System: updates / routerboard"
  if has updates.channel; then rs "/system package update set channel=$(cfg updates.channel)"; fi
  if is_true updates.auto_install; then
    is_true updates.auto_reboot || die "updates.auto_install=true потребує updates.auto_reboot=true: RouterOS перезавантажується після встановлення пакета"
    need updates.auto_interval
    auto_interval=$(cfg updates.auto_interval)
    [[ $auto_interval =~ ^[0-9]+[smhdw]$ ]] || die "updates.auto_interval: очікується число з одиницею s/m/h/d/w"
    out ":do { /system scheduler add name=mgr-auto-update interval=$auto_interval on-event=\"/system package update check-for-updates once; :delay 15s; :if ([/system package update get status]=\\\"New version is available\\\") do={ /system package update install }\" } on-error={ :global mgrErrors; :set mgrErrors (\$mgrErrors + 1); :log error \"mgr: FAILED: scheduler\" }"
  fi
  if is_true routerboard.supported; then
    rs "/system routerboard settings set auto-upgrade=$(yn "$(cfg routerboard.upgrade false)")"
  else
    out ':log info "mgr: SKIP: RouterBOARD settings are not supported by this profile"'
    info "SKIP: RouterBOARD settings (routerboard.supported=false)"
  fi
}

gen_interfaces() {
  local key n en cm drv
  local -a L
  sec "Interfaces"
  drv=$(cfg wireless.driver none)
  mapfile -t L < <(children interfaces)
  for key in "${L[@]}"; do
    n=$(cfg "interfaces.$key.name"); [[ -n $n ]] || die "interfaces.$key.name порожнє"
    en=$(cfg "interfaces.$key.enabled" true); cm=$(cfg "interfaces.$key.comment")
    case $key in
      ether*|sfp*)
        rs "/interface ethernet set [find where default-name=$key] name=$(q "$n") comment=$(q "$cm") disabled=$(dis "$en")" ;;
      wlan*)
        case $drv in
          none)   out "# $key skipped (wireless driver = none)" ;;
          legacy) rs "/interface wireless set [find where default-name=$key] name=$(q "$n") comment=$(q "$cm")" ;;
          wifi*)  rs "/interface wifi set [find where default-name=wifi${key#wlan}] name=$(q "$n") comment=$(q "$cm")" ;;
          *) die "Невідомий wireless.driver: $drv" ;;
        esac ;;
      *) die "Невідомий тип інтерфейсу: interfaces.$key (очікується ether*/sfp*/wlan*)" ;;
    esac
  done
}

gen_bridge() {
  local key br ifn en pm
  local -a L
  sec "Bridge"
  need bridge.lan.name
  # Головний LAN-міст; додаткові мости (напр. [bridge.guest]) створюються після нього.
  pm=$(cfg bridge.lan.protocol_mode rstp)
  [[ $pm =~ ^(none|stp|rstp|mstp)$ ]] || die "bridge.lan.protocol_mode: недопустиме значення '$pm'"
  rs "/interface bridge add name=$(q "$(cfg bridge.lan.name)") protocol-mode=$pm disabled=$(dis "$(cfg bridge.lan.enabled true)")"
  mapfile -t L < <(children bridge)
  for key in "${L[@]}"; do
    [[ $key == lan ]] && continue
    has "bridge.$key.name" || die "bridge.$key.name порожнє"
    pm=$(cfg "bridge.$key.protocol_mode" rstp)
    [[ $pm =~ ^(none|stp|rstp|mstp)$ ]] || die "bridge.$key.protocol_mode: недопустиме значення '$pm'"
    rs "/interface bridge add name=$(q "$(cfg "bridge.$key.name")") protocol-mode=$pm disabled=$(dis "$(cfg "bridge.$key.enabled" true)")"
  done
  mapfile -t L < <(children ports)
  for key in "${L[@]}"; do
    has "interfaces.$key.name" || die "ports.$key: немає інтерфейсу interfaces.$key"
    ifn=${CFG[interfaces.$key.name]}
    ref_name "$(cfg "ports.$key.bridge")"; br=$REF
    en=$(cfg "ports.$key.enabled" true)
    rs "/interface bridge port add bridge=$(q "$br") interface=$(q "$ifn") hw=$(yn "$(cfg "ports.$key.hw" false)") disabled=$(dis "$en")"
  done
}

gen_network() {
  local ifn a2 if2
  sec "LAN and management addresses"
  need network.lan.interface network.lan.address
  ref_name "${CFG[network.lan.interface]}"; LAN_IF=$REF
  ref_addr "${CFG[network.lan.address]}"; LAN_ADDR=$REF
  is_cidr "$LAN_ADDR" || die "network.lan.address: некоректний CIDR '$LAN_ADDR'"
  LAN_NET=$(cidr_net "$LAN_ADDR")
  rs "/ip address add address=$LAN_ADDR interface=$(q "$LAN_IF") comment=\"mgr: lan\""
  if has management.address; then
    ref_addr "${CFG[management.address]}"; a2=$REF
    ref_name "$(cfg management.interface "${CFG[network.lan.interface]}")"; if2=$REF
    is_cidr "$a2" || die "management.address: некоректний CIDR '$a2'"
    if [[ $a2 != "$LAN_ADDR" || $if2 != "$LAN_IF" ]]; then
      rs "/ip address add address=$a2 interface=$(q "$if2") comment=\"mgr: management\""
    fi
  fi
}

gen_wan() {
  # WAN вмикається останнім — лише після firewall, служб, DNS та LAN.
  local ifn
  sec "WAN activation (last)"
  if is_true wan.enabled true; then
    need wan.interface
    ref_name "${CFG[wan.interface]}"; ifn=$REF
    rs "/ip dhcp-client add interface=$(q "$ifn") add-default-route=$(yn "$(cfg wan.add_default_route true)") use-peer-dns=$(yn "$(cfg wan.use_peer_dns false)") disabled=no comment=\"mgr: wan\""
  else
    out "# WAN disabled in profile"
  fi
}

gen_lists() {
  local key n m
  local -a L M
  sec "Interface lists"
  mapfile -t L < <(children lists)
  for key in "${L[@]}"; do
    n=$(cfg "lists.$key.name"); [[ -n $n ]] || die "lists.$key.name порожнє"
    rs "/interface list add name=$(q "$n")"
    is_true "lists.$key.enabled" true || continue
    mapfile -t M < <(cfg "lists.$key.members")
    for m in "${M[@]}"; do
      [[ -n $m ]] || continue
      ref_name "$m"
      rs "/interface list member add list=$(q "$n") interface=$(q "$REF")"
    done
  done
  need lists.wan.name lists.lan.name
  WAN_L=${CFG[lists.wan.name]}; LAN_L=${CFG[lists.lan.name]}
}

gen_dns() {
  local s v
  local -a L
  sec "DNS"
  if is_true dns.enabled; then
    mapfile -t L < <(cfg dns.servers)
    v=""
    for s in "${L[@]}"; do
      [[ -n $s ]] || continue
      is_ip "$s" || die "dns.servers: некоректна IP '$s'"
      v+=${v:+,}$s
    done
    rs "/ip dns set servers=$v allow-remote-requests=$(yn "$(cfg dns.allow_remote_requests false)")"
  else
    rs "/ip dns set allow-remote-requests=no"
  fi
}

gen_dhcp() {
  local key a m c sv ip dns s
  local -A seen_ip=() seen_mac=()
  local -a L D
  sec "DHCP"
  need pool.lan.name pool.lan.start pool.lan.end server.lan.name server.lan.interface server.lan.pool
  is_ip "${CFG[pool.lan.start]}" && is_ip "${CFG[pool.lan.end]}" || die "pool.lan: некоректні start/end"
  rs "/ip pool add name=$(q "${CFG[pool.lan.name]}") ranges=${CFG[pool.lan.start]}-${CFG[pool.lan.end]}"
  ref_name "${CFG[server.lan.interface]}"; ip=$REF
  ref_name "${CFG[server.lan.pool]}"; m=$REF
  local lease_time; lease_time=$(cfg server.lan.lease_time 12h)
  [[ $lease_time =~ ^[0-9]+[smhdw]$ ]] || die "server.lan.lease_time: очікується число з одиницею s/m/h/d/w (напр. 12h)"
  rs "/ip dhcp-server add name=$(q "${CFG[server.lan.name]}") interface=$(q "$ip") address-pool=$(q "$m") lease-time=$lease_time disabled=$(dis "$(cfg server.lan.enabled true)")"
  need dhcp.network.lan.gateway
  is_ip "${CFG[dhcp.network.lan.gateway]}" || die "dhcp.network.lan.gateway: некоректна IP"
  mapfile -t D < <(cfg dhcp.network.lan.dns_servers)
  dns=""
  for s in "${D[@]}"; do [[ -n $s ]] || continue; is_ip "$s" || die "dhcp dns_servers: некоректна IP '$s'"; dns+=${dns:+,}$s; done
  rs "/ip dhcp-server network add address=$LAN_NET gateway=${CFG[dhcp.network.lan.gateway]}${dns:+ dns-server=$dns}"
  if is_true leases.enabled; then
    need leases.server
    ref_name "${CFG[leases.server]}"; sv=$REF
    mapfile -t L < <(children leases.devices)
    for key in "${L[@]}"; do
      a=$(cfg "leases.devices.$key.address"); m=$(cfg "leases.devices.$key.mac"); c=$(cfg "leases.devices.$key.comment")
      is_ip "$a"  || die "leases.devices #$key: некоректна address '$a'"
      is_mac "$m" || die "leases.devices #$key: некоректна mac '$m'"
      m=${m^^}
      [[ -z ${seen_ip[$a]+x}  ]] || die "Дублікат IP у leases: $a"
      [[ -z ${seen_mac[$m]+x} ]] || die "Дублікат MAC у leases: $m"
      seen_ip[$a]=1; seen_mac[$m]=1
      rs "/ip dhcp-server lease add address=$a mac-address=$m server=$(q "$sv") comment=$(q "$c")"
    done
  fi
}

# Чи активний Wi-Fi інтерфейс: wireless.enabled, wireless.<key>.enabled і interfaces.<wlanN>.enabled
wlan_active() {
  local key=$1 raw
  is_true wireless.enabled true || return 1
  is_true "wireless.$key.enabled" true || return 1
  has "wireless.$key.interface" || return 1
  find_sec "${CFG[wireless.$key.interface]}"; raw=${SEC##*.}
  is_true "interfaces.$raw.enabled" true
}

# Чи використовує хоч один АКТИВНИЙ Wi-Fi інтерфейс секцію захисту $1 (напр. security.wifi)
wifi_security_in_use() {
  local key
  local -a L
  [[ $(cfg wireless.driver none) != none ]] || return 1
  # Гостьовий профіль захисту використовується тоді, коли увімкнена гостьова мережа.
  if is_true "wireless.guest.enabled" false && has wireless.guest.security; then
    find_sec "$(cfg wireless.guest.security)"
    [[ $SEC == "$1" ]] && return 0
  fi
  mapfile -t L < <(children wireless)
  for key in "${L[@]}"; do
    wlan_active "$key" || continue
    has "wireless.$key.security" || continue
    find_sec "${CFG[wireless.$key.security]}"
    if [[ $SEC == "$1" ]]; then return 0; fi
  done
  return 1
}

gen_wireless() {
  local drv key raw dn menu sec_s auth ssid band cw fr ctry d br ifn wc wauth freq_arg
  local -a L S
  local -A need_sec=()
  sec "Wireless"
  drv=$(cfg wireless.driver none)
  if [[ $drv == none ]] || ! has wireless.driver; then out "# wireless: driver none - skipped"; return 0; fi
  case $drv in legacy|wifi-qcom-ac|wifi-qcom) ;; *) die "Невідомий wireless.driver: $drv" ;; esac
  if [[ $drv == legacy ]]; then menu=wireless; else menu=wifi; fi
  mapfile -t L < <(children wireless)
  # які профілі захисту потрібні (лише для активних інтерфейсів)
  for key in "${L[@]}"; do
    [[ $key == guest ]] && continue
    if wlan_active "$key"; then
      need "wireless.$key.security"
      find_sec "${CFG[wireless.$key.security]}"; need_sec[$SEC]=1
    fi
  done
  if (( ${#need_sec[@]} == 0 )); then
    out "# all Wi-Fi interfaces disabled: no security profile, no password required"
  fi
  if [[ $drv == legacy ]]; then
    mapfile -t S < <(children security)
    for key in "${S[@]}"; do
      [[ -n ${need_sec[security.$key]+x} ]] || continue
      need "security.$key.name" "security.$key.authentication" "security.$key.password_file"
      auth=${CFG[security.$key.authentication]}
      [[ $auth =~ ^(wpa-psk|wpa2-psk)(,(wpa-psk|wpa2-psk))*$ ]] || die "security.$key.authentication: для legacy дозволено wpa-psk,wpa2-psk"
      read_pw_sec "security.$key"
      (( ${#PW} >= 8 && ${#PW} <= 63 )) || die "Пароль Wi-Fi (security.$key) має бути 8..63 символи"
      rs "/interface wireless security-profiles add name=$(q "${CFG[security.$key.name]}") mode=dynamic-keys authentication-types=$auth wpa-pre-shared-key=$(q "$PW") wpa2-pre-shared-key=$(q "$PW") unicast-ciphers=aes-ccm group-ciphers=aes-ccm"
    done
  fi
  for key in "${L[@]}"; do
    [[ $key == guest ]] && continue
    need "wireless.$key.interface"
    ref_name "${CFG[wireless.$key.interface]}"; ifn=$REF; raw=${REF_SEC##*.}
    if [[ $drv == legacy ]]; then dn=$raw; else dn="wifi${raw#wlan}"; fi
    if ! wlan_active "$key"; then
      rs "/interface $menu set [find where default-name=$dn] disabled=yes"
      continue
    fi
    need "wireless.$key.ssid" "wireless.$key.band"
    ssid=${CFG[wireless.$key.ssid]}; band=${CFG[wireless.$key.band]}
    cw=$(cfg "wireless.$key.channel_width" 20mhz); fr=$(cfg "wireless.$key.frequency" auto)
    ctry=$(cfg "wireless.$key.country")
    [[ $band$cw$fr$ctry =~ ^[A-Za-z0-9/._+-]*$ ]] || die "wireless.$key: недопустимі символи в band/channel_width/frequency/country"
    d=no
    ref_name "${CFG[wireless.$key.security]}"; sec_s=$REF
    if [[ $drv == legacy ]]; then
      rs "/interface wireless set [find where default-name=$dn] mode=ap-bridge ssid=$(q "$ssid") band=$band channel-width=$cw frequency=$fr${ctry:+ country=$ctry frequency-mode=regulatory-domain} security-profile=$(q "$sec_s") disabled=$d"
      if has "wireless.$key.bridge"; then
        ref_name "${CFG[wireless.$key.bridge]}"; br=$REF
        rs "/interface bridge port add bridge=$(q "$br") interface=$(q "$ifn")"
      fi
    else
      # Новий Wi-Fi stack: band та width передаються без перетворень.
      # Сумісність значень із драйвером перевіряє TOML engine до генерації.
      find_sec "${CFG[wireless.$key.security]}"
      need "$SEC.authentication" "$SEC.password_file"
      wauth=${CFG[$SEC.authentication]}
      read_pw_sec "$SEC"
      (( ${#PW} >= 8 && ${#PW} <= 63 )) || die "Пароль Wi-Fi має бути 8..63 символи"
      wc=""
      if [[ -n $ctry ]]; then wc=" configuration.country=${ctry^}"; fi
      br=""
      if has "wireless.$key.bridge"; then ref_name "${CFG[wireless.$key.bridge]}"; br=" datapath.bridge=$(q "$REF")"; fi
      freq_arg=""
      [[ $fr == auto ]] || freq_arg=" channel.frequency=$fr"
      rs "/interface wifi set [find where default-name=$dn] configuration.mode=ap configuration.ssid=$(q "$ssid")$wc channel.band=$band channel.width=$cw$freq_arg security.authentication-types=$wauth security.passphrase=$(q "$PW")$br disabled=$d"
    fi
  done
}

# --- Guest Wi-Fi -------------------------------------------------------------

GUEST_BR=""; GUEST_NET=""; GUEST_ADDR=""; GUEST_DNS=""; GUEST_DNS_LOCAL=""
gen_wireless_guest() {
  # Гостьова мережа: Virtual AP на вказаних радіо + окремий міст + DHCP.
  local drv key m n prefix ssid sec_s secname wauth dn ifn raw N
  local -a MASTERS D
  GUEST_BR=""; GUEST_NET=""; GUEST_ADDR=""; GUEST_DNS=""; GUEST_DNS_LOCAL=0
  is_true wireless.guest.enabled false || return 0
  drv=$(cfg wireless.driver none)
  has wireless.driver || die "wireless.guest.enabled=true потребує wireless.driver"
  [[ $drv != none ]] || die "wireless.guest.enabled=true потребує wireless.driver != none"
  need wireless.guest.masters wireless.guest.ssid wireless.guest.security \
       wireless.guest.bridge wireless.guest.address \
       wireless.guest.pool_start wireless.guest.pool_end wireless.guest.dns_servers
  local start end lease_time
  prefix=$(cfg wireless.guest.name_prefix guest)
  [[ $prefix =~ ^[A-Za-z0-9_-]+$ ]] || die "wireless.guest.name_prefix: дозволено лише [A-Za-z0-9_-]"
  ssid=$(cfg wireless.guest.ssid)
  ref_name "$(cfg wireless.guest.bridge)"; GUEST_BR=$REF
  GUEST_ADDR=$(cfg wireless.guest.address)
  is_cidr "$GUEST_ADDR" || die "wireless.guest.address: некоректний CIDR '$GUEST_ADDR'"
  GUEST_NET=$(cidr_net "$GUEST_ADDR")
  start=$(cfg wireless.guest.pool_start); end=$(cfg wireless.guest.pool_end)
  is_ip "$start" && is_ip "$end" || die "wireless.guest: некоректні pool_start/pool_end"
  mapfile -t D < <(cfg wireless.guest.dns_servers)
  for n in "${D[@]}"; do
    [[ -n $n ]] || continue
    is_ip "$n" || die "wireless.guest.dns_servers: некоректна IP '$n'"
    GUEST_DNS+=${GUEST_DNS:+,}$n
    [[ $n == "${GUEST_ADDR%/*}" ]] && GUEST_DNS_LOCAL=1
  done
  [[ -n $GUEST_DNS ]] || die "wireless.guest.dns_servers не може бути порожнім"
  lease_time=$(cfg wireless.guest.lease_time 12h)
  [[ $lease_time =~ ^[0-9]+[smhdw]$ ]] || die "wireless.guest.lease_time: очікується число з одиницею s/m/h/d/w"

  # Профіль захисту гостей — окремий секрет, відмінний від основного Wi-Fi.
  find_sec "$(cfg wireless.guest.security)"; sec=$SEC
  need "$sec.name" "$sec.authentication" "$sec.password_file" "$sec.password_key"
  secname=${CFG[$sec.name]}
  wauth=${CFG[$sec.authentication]}
  read_pw_sec "$sec"
  (( ${#PW} >= 8 && ${#PW} <= 63 )) || die "Пароль Wi-Fi гостей ($sec) має бути 8..63 символи"
  sec "Guest Wi-Fi network"
  if [[ $drv == legacy ]]; then
    [[ $wauth =~ ^(wpa-psk|wpa2-psk)(,(wpa-psk|wpa2-psk))*$ ]] || die "$sec.authentication: для legacy дозволено wpa-psk,wpa2-psk"
    rs "/interface wireless security-profiles add name=$(q "$secname") mode=dynamic-keys authentication-types=$wauth wpa-pre-shared-key=$(q "$PW") wpa2-pre-shared-key=$(q "$PW") unicast-ciphers=aes-ccm group-ciphers=aes-ccm"
  fi

  # DHCP для гостей.
  rs "/ip pool add name=$(q "${prefix}-pool") ranges=${start}-${end}"
  rs "/ip dhcp-server add name=$(q "${prefix}-dhcp") interface=$(q "$GUEST_BR") address-pool=$(q "${prefix}-pool") lease-time=$lease_time disabled=no"
  rs "/ip dhcp-server network add address=$GUEST_NET gateway=${GUEST_ADDR%/*}${GUEST_DNS:+ dns-server=$GUEST_DNS}"

  # Virtual AP на кожному вказаному радіо.
  N=0
  mapfile -t MASTERS < <(cfg wireless.guest.masters)
  for m in "${MASTERS[@]}"; do
    [[ -n $m ]] || continue
    ref_name "$m"; ifn=$REF; raw=${REF_SEC##*.}
    wlan_active "$raw" || die "wireless.guest.masters: $m не є активним Wi-Fi радіо (вимкнено в профілі)"
    N=$((N + 1)); n="${prefix}-va${N}"
    if [[ $drv == legacy ]]; then
      rs "/interface wireless add name=$(q "$n") master-interface=$(q "$ifn") mode=ap-bridge ssid=$(q "$ssid") security-profile=$(q "$secname") disabled=no"
    else
      # datapath.bridge самостійно додає Wi-Fi інтерфейс до bridge.
      rs "/interface wifi add name=$(q "$n") master-interface=$(q "$ifn") configuration.mode=ap configuration.ssid=$(q "$ssid") security.authentication-types=$wauth security.passphrase=$(q "$PW") datapath.bridge=$(q "$GUEST_BR") disabled=no"
    fi
    # Для legacy bridge port створюється окремою командою; для нового Wi-Fi
    # stack це вже робить datapath.bridge, тому дублювати порт не можна.
    if [[ $drv == legacy ]]; then
      rs "/interface bridge port add bridge=$(q "$GUEST_BR") interface=$(q "$n")"
    fi
  done
  (( N > 0 )) || die "wireless.guest.masters не може бути порожнім"
}

# --- UPnP --------------------------------------------------------------------
gen_upnp() {
  local ext inn
  sec "UPnP"
  if has upnp.enabled && is_true upnp.enabled; then
    need upnp.external upnp.internal
    ref_name "$(cfg upnp.external)"; ext=$REF
    ref_name "$(cfg upnp.internal)"; inn=$REF
    [[ $ext != "$inn" ]] || die "upnp.external та upnp.internal мають бути різними інтерфейсами"
    rs "/ip upnp set enabled=yes"
    rs "/ip upnp interfaces add interface=$(q "$ext") type=external"
    rs "/ip upnp interfaces add interface=$(q "$inn") type=internal"
  else
    rs "/ip upnp set enabled=no"
  fi
}

# --- Firewall ---------------------------------------------------------------
fw()  { rs "/ip firewall filter add chain=$1 $2 comment=$(q "mgr: $3")"; }
fw6() { rs "/ipv6 firewall filter add chain=$1 $2 comment=$(q "mgr: $3")"; }

gen_firewall() {
  local W L key p lim ports burst blacklist_timeout stage_timeout fasttrack_hw
  local -a SV
  sec "IPv4 firewall"
  if ! is_true firewall.enabled true; then
    # Гостьова мережа без firewall не ізолюється: правила guest→LAN drop
    # генеруються лише тут, а політика filter без firewall = accept.
    if is_true wireless.guest.enabled; then
      die "wireless.guest.enabled=true потребує firewall.enabled=true: гостьова мережа без firewall не ізолюється від LAN"
    fi
    out "# firewall disabled in profile"; return 0
  fi
  W=$(q "$WAN_L"); L=$(q "$LAN_L")
  local MGMT_L="$LAN_L"
  if ! is_true management.on_lan true && has lists.management.name; then MGMT_L=$(cfg lists.management.name); fi
  local M; M=$(q "$MGMT_L")

  # --- INPUT ---
  fw input "action=accept connection-state=established,related,untracked" "input established"
  fw input "action=drop connection-state=invalid" "input invalid"
  # DHCP-відповіді від WAN-сервера потрібні DHCP-клієнту на ether6.
  if is_true wan.enabled true; then
    fw input "action=accept protocol=udp src-port=67 dst-port=68 in-interface-list=$W" "input dhcp client wan"
  fi
  if is_true firewall.brute_force_enabled; then
    need firewall.brute_force_ports firewall.brute_force_blacklist_timeout firewall.brute_force_stage_timeout
    ports=$(cfg firewall.brute_force_ports)
    blacklist_timeout=$(cfg firewall.brute_force_blacklist_timeout)
    stage_timeout=$(cfg firewall.brute_force_stage_timeout)
    [[ $ports =~ ^[0-9]+([,-][0-9]+)*$ ]] || die "firewall.brute_force_ports: некоректне значення '$ports'"
    [[ $blacklist_timeout =~ ^[0-9]+[smhdw]$ && $stage_timeout =~ ^[0-9]+[smhdw]$ ]] || die "Firewall brute-force timeouts: очікується число з одиницею s/m/h/d/w"
    local bf="protocol=tcp dst-port=$ports in-interface-list=$W"
    fw input "action=drop $bf src-address-list=mgr_bf_blacklist" "bf: drop blacklist"
    fw input "action=add-src-to-address-list address-list=mgr_bf_blacklist address-list-timeout=$blacklist_timeout $bf connection-state=new src-address-list=mgr_bf_stage3" "bf: stage3 -> blacklist"
    fw input "action=add-src-to-address-list address-list=mgr_bf_stage3 address-list-timeout=$stage_timeout $bf connection-state=new src-address-list=mgr_bf_stage2" "bf: stage2 -> stage3"
    fw input "action=add-src-to-address-list address-list=mgr_bf_stage2 address-list-timeout=$stage_timeout $bf connection-state=new src-address-list=mgr_bf_stage1" "bf: stage1 -> stage2"
    fw input "action=add-src-to-address-list address-list=mgr_bf_stage1 address-list-timeout=$stage_timeout $bf connection-state=new" "bf: new -> stage1"
  fi
  if is_true firewall.allow_icmp; then
    lim=$(cfg firewall.icmp_limit_per_second 0)
    [[ $lim =~ ^[0-9]+$ ]] || die "firewall.icmp_limit_per_second має бути числом"
    fw input "action=accept protocol=icmp in-interface-list=$L" "input icmp lan"
    if [[ $MGMT_L != "$LAN_L" ]]; then fw input "action=accept protocol=icmp in-interface-list=$M" "input icmp management"; fi
    if (( 10#$lim > 0 )); then
      burst=$(cfg firewall.icmp_burst 5)
      [[ $burst =~ ^[0-9]+$ ]] && (( 10#$burst >= 1 && 10#$burst <= 100 )) || die "firewall.icmp_burst має бути 1..100"
      fw input "action=accept protocol=icmp in-interface-list=$W limit=$lim,$burst:packet" "input icmp wan limited"
      fw input "action=drop protocol=icmp in-interface-list=$W" "input icmp wan over limit"
    else
      fw input "action=accept protocol=icmp in-interface-list=$W" "input icmp wan"
    fi
  fi
  if is_true firewall.allow_lan_dhcp; then
    fw input "action=accept protocol=udp src-port=68 dst-port=67 in-interface-list=$L" "input dhcp lan"
  fi
  if is_true dns.enabled && is_true dns.allow_remote_requests; then
    fw input "action=accept protocol=udp dst-port=53 in-interface-list=$L" "input dns udp lan"
    fw input "action=accept protocol=tcp dst-port=53 in-interface-list=$L" "input dns tcp lan"
  fi
  mapfile -t SV < <(children services)
  for key in "${SV[@]}"; do
    is_true "services.$key.enabled" || continue
    service_allowed "$key" || die "services.$key не входить у стандартну IP-службу RouterOS"
    p=$(cfg "services.$key.port")
    is_port "$p" || die "services.$key.port: активна служба потребує порт 1..65535"
    if is_true "services.$key.limit_to_lan" true; then
      fw input "action=accept protocol=tcp dst-port=$p in-interface-list=$M" "input $key management/lan"
    else
      fw input "action=accept protocol=tcp dst-port=$p" "input $key any"
    fi
  done
  # --- Гостьова мережа: DHCP/ICMP на роутер, forward лише в WAN ---
  if is_true wireless.guest.enabled; then
    local B
    B=$(q "$GUEST_BR")
    fw input "action=accept protocol=udp src-port=68 dst-port=67 in-interface=$B" "input dhcp guest"
    if is_true firewall.allow_icmp; then
      fw input "action=accept protocol=icmp in-interface=$B" "input icmp guest"
    fi
    if is_true dns.enabled && is_true dns.allow_remote_requests && (( GUEST_DNS_LOCAL )); then
      fw input "action=accept protocol=udp dst-port=53 in-interface=$B" "input dns udp guest"
      fw input "action=accept protocol=tcp dst-port=53 in-interface=$B" "input dns tcp guest"
    fi
    # Ізоляція гостей має діяти незалежно від глобального forward_default_drop.
    # Спочатку забороняємо вихід із guest у LAN та окрему management-мережу,
    # а вже потім дозволяємо guest → WAN.
    fw forward "action=drop in-interface=$B out-interface-list=$L" "forward guest block lan"
    if [[ $MGMT_L != "$LAN_L" ]]; then
      fw forward "action=drop in-interface=$B out-interface-list=$M" "forward guest block management"
    fi
    fw forward "action=accept in-interface=$B out-interface-list=$W" "forward guest to wan"
  fi
  if is_true firewall.input_default_drop; then
    fw input "action=drop" "input default drop"
  elif is_true firewall.drop_new_wan; then
    fw input "action=drop connection-state=new in-interface-list=$W" "input drop new wan"
  fi

  # --- FORWARD ---
  if is_true firewall.fasttrack; then
    fasttrack_hw=$(yn "$(cfg firewall.fasttrack_hw_offload true)")
    fw forward "action=fasttrack-connection connection-state=established,related hw-offload=$fasttrack_hw" "fasttrack"
  fi
  fw forward "action=accept connection-state=established,related,untracked" "forward established"
  fw forward "action=drop connection-state=invalid" "forward invalid"
  fw forward "action=accept connection-state=new connection-nat-state=dstnat" "forward dstnat"
  if is_true firewall.lan_to_wan; then
    fw forward "action=accept in-interface-list=$L out-interface-list=$W" "forward lan to wan"
  fi
  if is_true firewall.drop_new_wan; then
    fw forward "action=drop connection-state=new connection-nat-state=!dstnat in-interface-list=$W" "forward drop new wan"
  fi
  if is_true firewall.forward_default_drop; then
    fw forward "action=drop" "forward default drop"
  fi
}

gen_nat() {
  local key proto wp ta tp dst lim a sub br W
  local -a L
  sec "NAT"
  if ! is_true nat.enabled; then
    # [forward.*] без NAT мовчки втратилися б: dstnat-правила не генеруються.
    local -a ORPHAN_FWD
    mapfile -t ORPHAN_FWD < <(children forward)
    if (( ${#ORPHAN_FWD[@]} )); then
      die "nat.enabled=false, але є секції [forward.*] (${ORPHAN_FWD[*]}): правила dstnat не генеруються — увімкніть nat.enabled або видаліть forward"
    fi
    out "# nat disabled"; return 0
  fi
  W=$(q "$WAN_L")
  if is_true nat.masquerade; then
    rs "/ip firewall nat add chain=srcnat action=masquerade out-interface-list=$W comment=\"mgr: masquerade\""
  fi
  sub=$(cfg nat.hairpin_lan_subnet)
  if is_true nat.hairpin_enabled; then
    is_cidr "$sub" || die "nat.hairpin_lan_subnet обов'язковий і має бути CIDR при hairpin_enabled=true"
    ref_name "${CFG[network.lan.interface]}"; br=$REF
  fi
  mapfile -t L < <(children forward)
  for key in "${L[@]}"; do
    need "forward.$key.protocol" "forward.$key.wan_port" "forward.$key.to_address"
    proto=${CFG[forward.$key.protocol]}; wp=${CFG[forward.$key.wan_port]}; ta=${CFG[forward.$key.to_address]}
    tp=$(cfg "forward.$key.to_port" "$wp"); dst=$(cfg "forward.$key.dst_address"); lim=$(cfg "forward.$key.tcp_new_limit" 0)
    [[ $proto =~ ^(tcp|udp)$ ]] || die "forward.$key.protocol: tcp|udp"
    is_port "$wp" && is_port "$tp" || die "forward.$key: некоректний порт"
    is_ip "$ta" || die "forward.$key.to_address некоректна"
    [[ -z $dst ]] || is_ip "$dst" || die "forward.$key.dst_address некоректна"
    [[ $lim =~ ^[0-9]+$ ]] || die "forward.$key.tcp_new_limit має бути числом"
    a="chain=dstnat action=dst-nat protocol=$proto dst-port=$wp to-addresses=$ta to-ports=$tp in-interface-list=$W"
    [[ -z $dst ]] || a+=" dst-address=$dst"
    if [[ $proto == tcp ]] && (( 10#$lim > 0 )); then a+=" limit=$lim,$lim:packet"; fi
    rs "/ip firewall nat add $a comment=$(q "mgr: forward $key")"
    if is_true nat.hairpin_enabled; then
      if [[ -n $dst ]]; then
        rs "/ip firewall nat add chain=dstnat action=dst-nat protocol=$proto dst-address=$dst dst-port=$wp src-address=$sub to-addresses=$ta to-ports=$tp comment=$(q "mgr: hairpin $key")"
        rs "/ip firewall nat add chain=srcnat action=masquerade protocol=$proto src-address=$sub dst-address=$ta dst-port=$tp out-interface=$(q "$br") comment=$(q "mgr: hairpin $key")"
      else
        warn "forward.$key: hairpin пропущено (потрібна непорожня dst_address)"
      fi
    fi
  done
}

gen_ipv6() {
  local W L
  sec "IPv6"
  if ! is_true ipv6.enabled; then
    rs "/ipv6 settings set disable-ipv6=yes"
    return 0
  fi
  rs "/ipv6 settings set disable-ipv6=no"
  if is_true ipv6.firewall true; then
    W=$(q "$WAN_L"); L=$(q "$LAN_L")
    fw6 input "action=accept connection-state=established,related,untracked" "v6 input established"
    fw6 input "action=drop connection-state=invalid" "v6 input invalid"
    fw6 input "action=accept protocol=icmpv6" "v6 input icmpv6"
    fw6 input "action=accept protocol=udp dst-port=546 src-address=fe80::/10 in-interface-list=$W" "v6 input dhcpv6-client"
    fw6 input "action=accept in-interface-list=$L" "v6 input lan"
    fw6 input "action=drop" "v6 input default drop"
    fw6 forward "action=accept connection-state=established,related,untracked" "v6 forward established"
    fw6 forward "action=drop connection-state=invalid" "v6 forward invalid"
    fw6 forward "action=accept protocol=icmpv6" "v6 forward icmpv6"
    fw6 forward "action=accept in-interface-list=$L out-interface-list=$W" "v6 forward lan to wan"
    fw6 forward "action=drop" "v6 forward default drop"
  fi
}

gen_services() {
  local key en p addr
  local -a L
  sec "IP services / discovery / MAC access"
  mapfile -t L < <(children services)
  for key in "${L[@]}"; do
    en=$(cfg "services.$key.enabled" false)
    addr=""; p=""
    # Стандартний набір IP-служб RouterOS; ім'я йде у RSC без лапок.
    # Список служб — service_allowlist у lib/schema.json (спільно з toml_engine).
    service_allowed "$key" || die "services.$key не входить у стандартну IP-службу RouterOS"
    if [[ $en == true ]]; then
      need "services.$key.port" "services.$key.limit_to_lan"
      is_port "${CFG[services.$key.port]}" || die "services.$key.port некоректний"
      p=" port=${CFG[services.$key.port]}"
      local addr_param="" addr_kw
      addr_kw=$(service_addr_keyword)
      if is_true "services.$key.limit_to_lan" true; then
        if ! is_true management.on_lan true && has management.address; then
          ref_addr "${CFG[management.address]}"; addr="$(cidr_net "$REF")"
        else
          addr=$LAN_NET
        fi
        [[ -n $addr ]] || die "services.$key.limit_to_lan=true, але LAN-підмережу не обчислено: задайте [management].address або management.on_lan=true з [network.lan]"
        addr_param=" $addr_kw=\"$addr\""
      fi
      # Без limit_to_lan параметр адреси не друкується взагалі: порожнє
      # значення (address=""/available-from="") RouterOS може відхилити.
      rs "/ip service set [find where name=$key] disabled=no$p$addr_param"
    else
      rs "/ip service set [find where name=$key] disabled=yes"
    fi
  done
  if has discovery.interface_list; then
    ref_name "${CFG[discovery.interface_list]}"
    rs "/ip neighbor discovery-settings set discover-interface-list=$(q "$REF")"
  fi
  if has mac_access.interface_list; then
    ref_name "${CFG[mac_access.interface_list]}"
    local ml ms=none mw=none
    ml=$(q "$REF")
    is_true mac_access.mac_server && ms=$ml
    is_true mac_access.mac_winbox && mw=$ml
    rs "/tool mac-server set allowed-interface-list=$ms"
    rs "/tool mac-server mac-winbox set allowed-interface-list=$mw"
  fi
  rs "/ip ssh set strong-crypto=$(yn "$(cfg ssh.strong_crypto false)")"
  # Детерміноване вимкнення служб, якими профіль не керує:
  # у RouterOS вони вимкнені за замовчуванням, але стан не гарантує жодна версія.
  rs "/ip proxy set enabled=no"
  rs "/ip socks set enabled=no"
  rs "/tool bandwidth-server set enabled=no"
}

gen_users() {
  local key n g enabled create pw user_q cmd update add_cmd
  local key_path pub key_file key_index key_fp
  local -a L KEY_PATHS DEFERRED_DISABLES
  sec "Users"
  mapfile -t L < <(children users)
  DEFERRED_DISABLES=()
  for key in "${L[@]}"; do
    need "users.$key.name" "users.$key.enabled" "users.$key.create" "users.$key.group"
    n=${CFG[users.$key.name]}; g=${CFG[users.$key.group]}
    enabled=${CFG[users.$key.enabled]}; create=${CFG[users.$key.create]}
    [[ $g =~ ^[A-Za-z0-9_.-]+$ ]] || die "users.$key.group некоректна"
    [[ $n =~ ^[A-Za-z0-9_.-]+$ ]] || die "users.$key.name некоректне"
    has "users.$key.password_file" && has "users.$key.password_key" || {
      if has "users.$key.password_file" || has "users.$key.password_key"; then die "users.$key: password_file і password_key потрібно задавати разом"; fi
    }
    pw=""
    if [[ $create == true ]]; then
      has "users.$key.password_file" && has "users.$key.password_key" || die "users.$key.create=true потребує password_file та password_key"
      read_pw_sec "users.$key"; pw=$PW
    elif [[ $enabled == true ]] && has "users.$key.password_file"; then
      read_pw_sec "users.$key"; pw=$PW
    fi
    user_q=$(q "$n")
    update="/user set \$mgrUserRef group=$g"
    [[ -n $pw ]] && update+=" password=$(q "$pw")"
    if [[ $enabled == true ]]; then update+="; /user enable \$mgrUserRef"; fi
    cmd=":local mgrUserRef [/user find where name=$user_q]; "
    if [[ $create == true ]]; then
      add_cmd="/user add name=$user_q group=$g password=$(q "$pw") disabled=$(dis "$enabled"); :set mgrUserRef [/user find where name=$user_q]"
      cmd+=":if ([:len \$mgrUserRef] = 0) do={ $add_cmd }; "
    else
      cmd+=":if ([:len \$mgrUserRef] = 0) do={ :log warning \"mgr: user $n not found; create=false\" }; "
    fi
    cmd+=":if ([:len \$mgrUserRef] > 0) do={ $update }"
    rs "$cmd" "users: ensure $n"

    # Вимкнення відкладається, щоб спочатку створити нового адміністратора.
    if [[ $enabled != true ]]; then DEFERRED_DISABLES+=("$n"); continue; fi
    if ! has "users.$key.ssh_keys"; then continue; fi
    mapfile -t KEY_PATHS < <(cfg "users.$key.ssh_keys")
    key_index=0
    for key_path in "${KEY_PATHS[@]}"; do
      [[ -n $key_path ]] || continue
      key_index=$((key_index + 1)); expand_path "$key_path"
      [[ -r $EXP ]] || die "SSH public key для users.$key не знайдено: $EXP"
      IFS= read -r pub < "$EXP" || true
      [[ $pub =~ ^(ssh-ed25519|ssh-rsa|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-[a-z0-9-]+@openssh\.com|ecdsa-sha2-[a-z0-9-]+)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || die "Некоректний формат SSH public key: $EXP"
      key_file="mgr-${n}-${key_index}.pub"
      # Dedupe/верифікація — за fingerprint (SSH SHA256). Параметра key-owner
      # у /user ssh-keys import у RouterOS 7.24 немає ("bad parameter key-owner").
      # Fingerprint обчислюємо як SHA256 від декодованого тіла ключа; base64
      # беремо з паддінгом — саме в такому вигляді RouterOS зберігає fingerprint
      # (ssh-keygen -lf друкує значення без завершального '=', і find не збігається).
      key_fp=$(printf '%s' "$pub" | python3 -c '
import sys
try:
    _, body, *_ = sys.stdin.read().split()
    import base64, hashlib
    try:
        body += "=" * (-len(body) % 4)  # RouterOS зберігає fingerprint із паддінгом
        raw = base64.b64decode(body)
    except Exception:
        raw = body.encode()  # ключ із некоректним base64 (RouterOS такий не імпортує)
    digest = hashlib.sha256(raw).digest()
    print("SHA256:" + base64.b64encode(digest).decode())
except Exception:
    sys.exit(1)') || key_fp=""
      [[ $key_fp =~ ^SHA256:[A-Za-z0-9+/=]{40,60}$ ]] || die "Не вдалося обчислити SSH fingerprint: $EXP"
      # RouterOS 7.24.6 сам видаляє pub-файл після успішного імпорту, тому файл
      # тут не видаляємо: сліпий /file remove кидав «file does not exist»,
      # весь on-error блок падав у FAILED попри успішний імпорт.
      # Кожен крок — окремий rs() з власною міткою: RouterOS не віддає текст
      # помилки в on-error, тож окремі мітки локалізують крок відмови в журналі.
      rs ":if ([:len [/user find where name=$user_q]] = 0) do={ :error \"SSH target user $n missing\" }" "sshkey: target user $n#$key_index"
      rs ":if ([:len [/file find where name=$(q "$key_file")]] > 0) do={ /file remove [/file find where name=$(q "$key_file")] }" "sshkey: remove stale file $n#$key_index"
      rs "/file add name=$(q "$key_file") contents=$(q "$pub")" "sshkey: add file $n#$key_index"
      rs ":if ([:len [/file find where name=$(q "$key_file")]] = 0) do={ :error \"SSH public key file missing\" }" "sshkey: verify file $n#$key_index"
      rs ":if ([:len [/user ssh-keys find where user=$user_q and fingerprint=$(q "$key_fp")]] = 0) do={ /user ssh-keys import public-key-file=$(q "$key_file") user=$user_q }" "sshkey: import $n#$key_index"
      rs ":if ([:len [/user ssh-keys find where user=$user_q and fingerprint=$(q "$key_fp")]] = 0) do={ :error \"SSH key import verification failed for $n\" }" "sshkey: verify import $n#$key_index"
    done
  done
  # Лише після створення активних користувачів та імпорту їхніх ключів.
  for n in "${DEFERRED_DISABLES[@]}"; do
    user_q=$(q "$n")
    cmd=":if (\$mgrErrors = 0) do={ :local mgrDisableRef [/user find where name=$user_q]; :if ([:len \$mgrDisableRef] > 0) do={ /user disable \$mgrDisableRef } else={ :log warning \"mgr: cannot disable missing user $n\" } } else={ :log warning \"mgr: skip disabling $n because earlier apply steps failed\" }"
    rs "$cmd" "users: disable $n (deferred)"
  done
}

gen_all() {
  local rsc_remote=$1
  out "# RouterOS script generated by mikrotik-manager"
  out "# profile: $PROFILE   built: $(date '+%F %T')   target: $(cfg generated_for unknown)"
  out "# config-sha256: $RSC_CONFIG_SHA256"
  out "# secrets-sha256: $RSC_SECRETS_SHA256"
  out "# apply-token: $RSC_APPLY_TOKEN"
  out ":global mgrErrors 0"
  out ":log info \"mgr: apply start\""
  out ":delay 3s"
  gen_system
  gen_interfaces
  gen_bridge
  # LAN IP обчислюється/встановлюється до служб і firewall; WAN ще не активний.
  gen_network
  gen_lists
  # Спочатку автентифікація та закриття непотрібних служб.
  gen_users
  gen_services
  gen_wireless
  # Гостьова мережа (VAP + DHCP) — до firewall; firewall обмежує гості.
  gen_wireless_guest
  # Firewall повністю формується до запуску DNS remote та WAN DHCP.
  gen_firewall
  gen_ipv6
  gen_nat
  gen_upnp
  gen_dhcp
  gen_dns
  # Остання мережева операція — DHCP-клієнт WAN.
  gen_wan
  sec "Finish"
  out ':global mgrErrors'
  out ":if (\$mgrErrors = 0) do={ :log info \"mgr: apply done token=$RSC_APPLY_TOKEN\" } else={ :log error (\"mgr: apply failed token=$RSC_APPLY_TOKEN errors=\" . \$mgrErrors) }"
  if ! is_true paths.keep_rsc_on_router false; then
    out ":do { :delay 2s; /file remove [find where name=$(q "$rsc_remote")] } on-error={}"
  fi
}

# RouterOS 7.24 перейменував address → available-from у /ip service
# (backwards-compat через deprecation; згодом параметр address буде вилучено).
# Тому новий синтаксис генеруємо лише для версій target >= 7.24.
SERVICE_AVAIL_FROM_MIN="7.24"
target_routeros_version() {  # → "X.Y" або "" для unknown
  local raw; raw=$(cfg generated_for unknown)
  printf '%s' "$raw" | sed -n 's/[^0-9]*\([0-9]\{1,3\}\.[0-9]\{1,3\}\).*/\1/p'
}
ver_ge() {  # ver_ge <"X.Y"|""> <"X.Y"> → 0/1
  local v=${1:-} min=$2 vp vm mp mm
  [[ $v =~ ^[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  vp=${v%%.*}; vm=${v#*.}; mp=${min%%.*}; mm=${min#*.}
  (( 10#$vp != 10#$mp )) && (( 10#$vp > 10#$mp )) && return 0
  (( 10#$vp < 10#$mp )) && return 1
  (( 10#$vm >= 10#$mm ))
}
service_addr_keyword() {  # → доступний для generated_for версії параметр /ip service
  local v
  v=$(target_routeros_version)
  if ver_ge "$v" "$SERVICE_AVAIL_FROM_MIN"; then
    printf 'available-from'
  else
    if [[ -z $v ]]; then warn "generated_for не містить версії RouterOS; використовуємо старий синтаксис /ip service address="; fi
    printf 'address'
  fi
}
# ------------------------------------------------------------
# Команди
# ------------------------------------------------------------
RSC_OUT=""; RSC_NAME=""; RSC_REMOTE=""; RSC_CONFIG_SHA256=""; RSC_SECRETS_SHA256=""; RSC_APPLY_TOKEN=""
profile_config_sha256() {
  # SHA-256 усіх TOML-файлів профілю з урахуванням імен і вмісту.
  local file
  {
    for file in "${PFILES[@]}"; do
      printf '%s\0' "${file##*/}"
      cat -- "$file" || return 1
      printf '\0'
    done
  } | sha256sum | awk '{print $1}'
}

profile_secrets_sha256() {
  # SHA-256 усіх секрет-файлів, на які посилається профіль (імена + вміст).
  local key
  {
    for key in "${!CFG[@]}"; do
      [[ $key == *.password_file ]] || continue
      expand_path "${CFG[$key]}"
      [[ -f $EXP && -r $EXP ]] || continue
      printf '%s\0' "${EXP##*/}"
      cat -- "$EXP" || return 1
      printf '\0'
    done
  } | sha256sum | awk '{print $1}'
}

# ------------------------------------------------------------
# Спільні хелпери шляхів — єдине джерело правила для paths.*.
# ------------------------------------------------------------
rel_dir_checked() {  # rel_dir_checked <значення> <local|remote> <назва поля> → значення або die
  local v=$1 field=$3
  local kind=$2
  # "~" не розгортається тут: без перевірки створився б літеральний каталог "~".
  if [[ $kind == local ]]; then
    [[ $v != "~"* && $v != /* && $v != .. && $v != ../* && $v != */../* && $v != */.. ]] || die "$field має бути відносним каталогом профілю"
  else
    [[ $v != "~"* && $v != /* && $v != *".."* ]] || die "$field має бути відносним каталогом на роутері без '..'"
  fi
  printf '%s' "$v"
}

ensure_private_dir() {  # права обмежуємо лише на щойно створеному каталозі; існуючі не чіпаємо
  [[ -d $1 ]] && return 0
  mkdir -p -- "$1"
  chmod 700 -- "$1"
  chmod g-s -- "$1"
}

build_profile() {  # build_profile <profile> [name.rsc]
  load_profile "$1"
  RSC_CONFIG_SHA256=$(profile_config_sha256) || die "Не вдалося обчислити SHA-256 TOML профілю"
  RSC_SECRETS_SHA256=$(profile_secrets_sha256) || die "Не вдалося обчислити SHA-256 секретів профілю"
  RSC_APPLY_TOKEN=$(printf '%s:%s:%s' "$(date +%s)" "$$" "$RANDOM" | sha256sum | cut -c1-20)
  RSC_NAME=${2:-$PROFILE.rsc}
  local outdir
  if [[ -n $OUTPUT_OVERRIDE ]]; then
    outdir=$OUTPUT_OVERRIDE
    [[ $outdir == /* ]] || outdir="$PWD/$outdir"
  else
    outdir="$PROFILE_DIR/$(rel_dir_checked "$(cfg paths.output_dir output)" local 'paths.output_dir')"
  fi
  RSC_OUT="$outdir/$RSC_NAME"
  RSC_REMOTE="$(rel_dir_checked "$(cfg paths.remote_dir "")" remote 'paths.remote_dir')"
  RSC_REMOTE="${RSC_REMOTE:+${RSC_REMOTE%/}/}$RSC_NAME"
  ensure_private_dir "$outdir"
  if (( VERBOSE )); then info "Каталог локального RSC: $outdir"; fi
  RSC_TMP=$(mktemp "$outdir/.build.XXXXXX")
  gen_all "$RSC_REMOTE"
  mv -f "$RSC_TMP" "$RSC_OUT"; RSC_TMP=""
  chmod 600 "$RSC_OUT"
  info "Згенеровано: $RSC_OUT ($(wc -l < "$RSC_OUT") рядків; містить паролі — chmod 600)"
}

resolve_existing_rsc() {  # resolve_existing_rsc <profile> [name.rsc]
  load_profile "$1"
  RSC_NAME=${2:-$PROFILE.rsc}
  local outdir
  if [[ -n $OUTPUT_OVERRIDE ]]; then
    outdir=$OUTPUT_OVERRIDE
    [[ $outdir == /* ]] || outdir="$PWD/$outdir"
  else
    outdir="$PROFILE_DIR/$(rel_dir_checked "$(cfg paths.output_dir output)" local 'paths.output_dir')"
  fi
  RSC_OUT="$outdir/$RSC_NAME"
  RSC_REMOTE="$(rel_dir_checked "$(cfg paths.remote_dir "")" remote 'paths.remote_dir')"
  RSC_REMOTE="${RSC_REMOTE:+${RSC_REMOTE%/}/}$RSC_NAME"
  [[ -f $RSC_OUT && -r $RSC_OUT ]] || die "RSC не знайдено: $RSC_OUT. Спочатку виконайте --build --profile $PROFILE${NAME:+ --name $NAME}${OUTPUT_OVERRIDE:+ --output $OUTPUT_OVERRIDE}"
  [[ -s $RSC_OUT ]] || die "RSC порожній: $RSC_OUT"
}

verify_rsc_token() {
  # apply-token використовується лише для зіставлення журналу поточного RSC
  # після перезавантаження. Він не є одноразовим і не блокує повторні операції.
  local stored_token
  stored_token=$(sed -n 's/^# apply-token: \([0-9a-f]\{20\}\)$/\1/p' "$RSC_OUT" | head -n1)
  [[ -n $stored_token ]] || die "RSC не містить унікального apply-token; виконайте --build перед --upload"
  RSC_APPLY_TOKEN=$stored_token
}

cmd_verify() {
  load_profile "$PROFILE_ARG"
  local driver
  driver=$(cfg wireless.driver none)
  # Перелік команд друкується у stdout. Немає запису у profiles/*/output.
  python3 "$VERIFY_ENGINE" "$PROFILE" "$driver" || die "Не вдалося сформувати read-only перелік команд"
  info "PASS: показано лише read-only команди; файли, SSH/SCP та RouterOS не використовувалися"
}

SSH_OPTS=(); SCP_OPTS=(); TARGET=""
ssh_setup() {
  local shk
  need connection.host connection.user
  shk=$(cfg connection.strict_host_key_checking yes)
  [[ $shk =~ ^(yes|no|accept-new|ask)$ ]] || die "connection.strict_host_key_checking: yes|accept-new|no|ask"
  local port; port=$(cfg connection.port 22); is_port "$port" || die "connection.port некоректний"
  local timeout; timeout=$(cfg connection.timeout_seconds 10)
  [[ $timeout =~ ^[0-9]+$ ]] && (( 10#$timeout >= 1 && 10#$timeout <= 300 )) || die "connection.timeout_seconds має бути 1..300"
  local common=(-o "ConnectTimeout=$timeout" -o "StrictHostKeyChecking=$shk")
  if [[ $shk == no ]]; then
    warn "strict_host_key_checking=no: ризик MITM (лише для контрольованої лабораторії)"
    common+=(-o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -o LogLevel=ERROR)
  fi
  if has connection.identity_file; then
    expand_path "${CFG[connection.identity_file]}"
    if [[ -f $EXP ]]; then common+=(-i "$EXP" -o IdentitiesOnly=yes)
    else warn "SSH-ключ $EXP не знайдено — ssh запитає пароль"; fi
  fi
  SSH_OPTS=(-p "$port" "${common[@]}")
  SCP_OPTS=(-P "$port" "${common[@]}")
  TARGET="${CFG[connection.user]}@${CFG[connection.host]}"
}

do_backup() {
  local ts base dst
  ts=$(date +%Y%m%d-%H%M%S); base="$PROFILE-pre-reset-$ts"
  dst="$PROFILE_DIR/$(rel_dir_checked "$(cfg paths.backup_dir backups)" local 'paths.backup_dir')"
  ensure_private_dir "$dst"
  info "Backup → $dst/$base.{backup,rsc}"
  if is_true backup.encrypt false; then
    need backup.password_file backup.password_key
    read_pw "${CFG[backup.password_file]}" "backup" "${CFG[backup.password_key]}"
    # Пароль передається через stdin RouterOS shell, а не в argv процесу ssh.
    printf '%s\n' "/system backup save name=$base password=$(q "$PW")" | ssh -T "${SSH_OPTS[@]}" -- "$TARGET"
  else
    ssh "${SSH_OPTS[@]}" -- "$TARGET" "/system backup save name=$base dont-encrypt=yes"
  fi
  ssh "${SSH_OPTS[@]}" -- "$TARGET" "/export file=$base"
  local settle; settle=$(cfg connection.transfer_settle_seconds 2)
  [[ $settle =~ ^[0-9]+$ ]] && (( 10#$settle >= 0 && 10#$settle <= 30 )) || die "connection.transfer_settle_seconds має бути 0..30"
  sleep "$settle"
  scp -q "${SCP_OPTS[@]}" -- "$TARGET:$base.backup" "$dst/"
  scp -q "${SCP_OPTS[@]}" -- "$TARGET:$base.rsc" "$dst/"
  chmod 600 "$dst/$base.backup" "$dst/$base.rsc"
  if is_true backup.remove_remote_after_download true; then
    if ! ssh "${SSH_OPTS[@]}" -- "$TARGET" "/file remove [find where name=\"$base.backup\"]; /file remove [find where name=\"$base.rsc\"]"; then
      warn "Backup збережено локально, але тимчасові файли на роутері не вдалося видалити"
    fi
  fi
}

confirm_reset() {
  local a
  if (( YES )) || ! is_true reset.require_confirmation true; then return 0; fi
  [[ -t 0 ]] || die "Немає інтерактивного терміналу: додайте --yes для reset без підтвердження"
  warn "RESET знищить ВСЮ конфігурацію $TARGET (no-defaults=yes)."
  read -r -p "Виконати RESET? [y/N] " a
  [[ $a =~ ^([Yy]([Ee][Ss])?|[Тт][Аа][Кк])$ ]] || die "Скасовано."
}

cmd_build() { build_profile "$PROFILE_ARG" "$NAME"; BUILT=1; }

cmd_backup() {
  load_profile "$PROFILE_ARG"
  ssh_setup
  do_backup
}

cmd_upload() {
  if (( BUILD && ! BUILT )); then
    build_profile "$PROFILE_ARG" "$NAME"
    BUILT=1
  elif (( ! BUILD )); then
    resolve_existing_rsc "$PROFILE_ARG" "$NAME"
  fi
  if (( RESET )); then verify_rsc_token; fi
  local rsc_sha_before rsc_sha_after
  rsc_sha_before=$(sha256sum "$RSC_OUT" | awk '{print $1}')
  ssh_setup
  if (( RESET )); then
    is_true reset.run_after_reset true || die "--reset потребує reset.run_after_reset=true"
    confirm_reset
  fi
  if (( BACKUP )); then do_backup; fi
  if (( VERBOSE )); then info "Локальний RSC: $RSC_OUT"; info "Віддалений шлях: $RSC_REMOTE"; fi
  info "Завантаження → $TARGET:$RSC_REMOTE"
  scp -q "${SCP_OPTS[@]}" -- "$RSC_OUT" "$TARGET:$RSC_REMOTE"
  rsc_sha_after=$(sha256sum "$RSC_OUT" | awk '{print $1}')
  [[ $rsc_sha_before == "$rsc_sha_after" ]] || die "Локальний RSC змінився під час передачі; файл на роутері не застосовувався. Повторіть build/upload."
  # apply-token перевірено один раз до scp; локальний RSC під час передачі не змінюється.
  if (( RESET )); then
    info "Reset з run-after-reset=$RSC_REMOTE (без backup RouterOS: skip-backup=yes) ..."
    # Preflight: код 255 — це «всі» помилки OpenSSH (timeout, авторизація, хост),
    # не лише розрив при reboot. Перевіряємо канал до reset; якщо він неисправний,
    # reset не відправляємо взагалі.
    if ! ssh "${SSH_OPTS[@]}" -- "$TARGET" ":put 'mgr-preflight-ok'" >/dev/null 2>&1; then
      die "SSH-канал до $TARGET недоступний (preflight не пройшов); reset НЕ відправлено"
    fi
    local reset_rc=0
    printf 'y\n' | ssh "${SSH_OPTS[@]}" -- "$TARGET" \
      "/system reset-configuration no-defaults=$(yn "$(cfg reset.no_defaults true)") skip-backup=$(yn "$(cfg reset.skip_backup true)") run-after-reset=$RSC_REMOTE" || reset_rc=$?
    if (( reset_rc == 255 )); then
      # Preflight пройдено, тому це значення трактується як очікуваний розрив при reboot.
      warn "SSH повернув 255 після reset; preflight перед reset пройшов — ймовірно очікуваний розрив на перезавантаженні."
    elif (( reset_rc != 0 )); then
      die "Команда reset завершилася з кодом $reset_rc; стан роутера потрібно перевірити вручну"
    fi
    info "Reset відправлено. Результат перевірте в журналі роутера: mgr: apply done / apply failed token=$RSC_APPLY_TOKEN (host key SSH зміниться — ssh-keygen -R)."
  else
    info "Файл завантажено. Застосувати вручну: /import file-name=$RSC_REMOTE"
  fi
}

cmd_secrets() {
  local s p k a b d
  load_profile "$PROFILE_ARG"
  for s in "${SECTIONS[@]}"; do
    has "$s.password_file" || continue
    if [[ $s == backup ]] && ! is_true backup.encrypt false; then
      info "[$s] пропущено (backup.encrypt=false — пароль не потрібен)"
      continue
    fi
    if [[ $s == users.* ]] && [[ $(cfg "$s.create" false) != true && $(cfg "$s.enabled" false) != true ]]; then
      info "[$s] пропущено (create=false та enabled=false — користувач не створюється й пароль не змінюється)"
      continue
    fi
    if [[ $s == security.* ]] && ! wifi_security_in_use "$s"; then info "[$s] пропущено (Wi-Fi вимкнено — пароль не потрібен)"; continue; fi
    expand_path "${CFG[$s.password_file]}"; p=$EXP; k=$(cfg "$s.password_key")
    if [[ -n $k ]]; then
      if lookup_key "$p" "$k"; then info "[$s] $k вже є у $p"; continue; fi
    elif [[ -s $p ]]; then info "[$s] вже існує: $p"; continue; fi
    [[ -t 0 ]] || die "Для введення паролів потрібен інтерактивний термінал"
    d=$(dirname "$p")
    if [[ ! -d $d ]]; then mkdir -p "$d"; chmod 700 "$d"; fi
    read -rs -p "Пароль для [$s]${k:+ ($k)}: " a; echo
    read -rs -p "Повторіть пароль: " b; echo
    [[ -n $a && $a == "$b" ]] || die "Паролі порожні або не збігаються"
    [[ $a != *$'\n'* ]] || die "Пароль не може містити перенесення рядка"
    (
      umask 077
      if [[ -n $k ]]; then
        [[ -f $p ]] || printf '# Секрети профілю %s (KEY=VALUE, без лапок)\n' "$PROFILE" > "$p"
        printf '%s=%s\n' "$k" "$a" >> "$p"
      else
        printf '%s\n' "$a" > "$p"
      fi
    )
    chmod 600 "$p"
    (( ${#a} >= 12 )) || warn "Пароль для [$s] коротший за 12 символів; рекомендовано довший пароль"
    info "Збережено${k:+ $k} → $p"
  done
}

cmd_list() {
  local f n h
  local -a cfg_files=()
  local -A seen=()
  for f in "$PROFILES_DIR"/*/ "$PROFILES_DIR"/*.toml; do
    if [[ -d $f ]]; then
      n=${f%/}; n=${n##*/}
      cfg_files=("$f"*.toml)
      (( ${#cfg_files[@]} )) || continue
    else
      n=${f##*/}; n=${n%.toml}
      cfg_files=("$f")
    fi
    [[ -z ${seen[$n]+x} ]] || continue
    seen[$n]=1
    # list не запускає повну валідацію профілю — лише читає host із [connection].
    # FNR==1 скидає стан на межі файлів: без цього in_connection "[connection]"
    # з першого файла помилково захоплював top-level host з наступного файла.
    h=$(awk '
      FNR == 1 { in_connection=0 }
      /^\[connection\][[:space:]]*$/ { in_connection=1; next }
      /^\[/ { in_connection=0 }
      in_connection && /^[[:space:]]*host[[:space:]]*=/ {
        sub(/^[^=]*=[[:space:]]*/, ""); gsub(/\"/, ""); print; exit
      }
    ' "${cfg_files[@]}" 2>/dev/null)
    [[ -n $h ]] || h='?'
    printf '  %-20s %s\n' "$n" "$h"
  done
  (( ${#seen[@]} )) || info "Профілів не знайдено у $PROFILES_DIR"
}

# ------------------------------------------------------------
# main — прапорцевий CLI; порядок операцій визначається окремо від порядку опцій.
# ------------------------------------------------------------
PROFILE=""; PROFILE_ARG=""; NAME=""; OUTPUT_OVERRIDE=""
BUILD=0; BUILT=0; UPLOAD=0; BACKUP=0; VALIDATE=0; VERIFY=0; RESET=0; YES=0; VERBOSE=0
LIST=0; SECRETS=0

main() {
  (( $# )) || { usage >&2; die "Не вказано операцію. Див. --help"; }
  while (( $# )); do
    case $1 in
      --profile)
        [[ $# -ge 2 && -n $2 && $2 != -* ]] || die "--profile потребує назву профілю"
        [[ -z $PROFILE_ARG ]] || die "--profile можна вказати лише один раз"
        PROFILE_ARG=$2; shift 2 ;;
      --profile=*)
        [[ -z $PROFILE_ARG ]] || die "--profile можна вказати лише один раз"
        PROFILE_ARG=${1#*=}; [[ -n $PROFILE_ARG ]] || die "--profile потребує назву профілю"; shift ;;
      --name)
        [[ $# -ge 2 && -n $2 && $2 != -* ]] || die "--name потребує ім'я файлу"
        [[ -z $NAME ]] || die "--name можна вказати лише один раз"
        NAME=$2; shift 2 ;;
      --name=*)
        [[ -z $NAME ]] || die "--name можна вказати лише один раз"
        NAME=${1#*=}; [[ -n $NAME ]] || die "--name потребує ім'я файлу"; shift ;;
      --output)
        [[ $# -ge 2 && -n $2 && $2 != -* ]] || die "--output потребує каталог"
        [[ -z $OUTPUT_OVERRIDE ]] || die "--output можна вказати лише один раз"
        OUTPUT_OVERRIDE=$2; shift 2 ;;
      --output=*)
        [[ -z $OUTPUT_OVERRIDE ]] || die "--output можна вказати лише один раз"
        OUTPUT_OVERRIDE=${1#*=}; [[ -n $OUTPUT_OVERRIDE ]] || die "--output потребує каталог"; shift ;;
      --build) BUILD=1; shift ;;
      --verify) VERIFY=1; shift ;;
      --upload) UPLOAD=1; shift ;;
      --backup) BACKUP=1; shift ;;
      --validate) VALIDATE=1; shift ;;
      --list) LIST=1; shift ;;
      --secrets) SECRETS=1; shift ;;
      --verbose|-v) VERBOSE=1; shift ;;
      --reset) RESET=1; shift ;;
      --yes|-y) YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; (( $# == 0 )) || die "Позиційні аргументи не підтримуються; використовуйте --profile PROFILE" ;;
      -*) die "Невідома опція: $1" ;;
      *) die "Непідтримуваний позиційний аргумент '$1'; використовуйте --profile PROFILE" ;;
    esac
  done

  if [[ -n $NAME ]]; then
    [[ $NAME =~ ^[A-Za-z0-9._-]+\.rsc$ ]] || die "--name: дозволені [A-Za-z0-9._-], обов'язкове розширення .rsc"
    [[ $NAME != .rsc ]] || die "--name: задайте непорожню назву перед .rsc"
  fi
  if [[ -n $OUTPUT_OVERRIDE ]] && (( ! BUILD && ! UPLOAD )); then die "--output доступний лише з --build та/або --upload"; fi
  if [[ -n $NAME ]] && (( ! BUILD && ! UPLOAD )); then die "--name доступний лише з --build та/або --upload"; fi
  if (( YES && ! RESET )); then die "--yes доступний лише разом з --reset"; fi
  if (( RESET && ! UPLOAD )); then die "--reset потребує --upload"; fi

  local actions=$((BUILD + UPLOAD + BACKUP + VALIDATE + VERIFY + LIST + SECRETS))
  (( actions > 0 )) || die "Не вказано операцію. Див. --help"
  if (( LIST )); then
    (( actions == 1 )) || die "--list не можна комбінувати з іншими операціями"
    [[ -z $PROFILE_ARG && -z $NAME && -z $OUTPUT_OVERRIDE ]] || die "--list не приймає --profile/--name/--output"
    cmd_list; return
  fi
  if (( VALIDATE || SECRETS || VERIFY )); then
    (( actions == 1 )) || die "--validate, --verify та --secrets виконуються окремо від інших операцій"
    if (( VERIFY )) && [[ -n $NAME || -n $OUTPUT_OVERRIDE ]]; then
      die "--verify не створює файлів і не приймає --name або --output"
    fi
  fi
  [[ -n $PROFILE_ARG ]] || die "Вкажіть --profile PROFILE (див. --list)"
  [[ $PROFILE_ARG =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "Некоректна назва профілю: $PROFILE_ARG"

  if (( VALIDATE )); then
    load_profile "$PROFILE_ARG"
    check_secret_perms
    info "PASS: профіль '$PROFILE' валідний"
    return
  fi
  if (( SECRETS )); then cmd_secrets; return; fi
  if (( VERIFY )); then cmd_verify; return; fi

  # Послідовність незалежна від порядку прапорців у командному рядку.
  if (( BUILD )); then cmd_build; fi
  if (( BACKUP && ! UPLOAD )); then cmd_backup; fi
  if (( UPLOAD )); then cmd_upload; fi
}
main "$@"
