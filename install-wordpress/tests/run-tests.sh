#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail

ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
    pwd -P
)"
readonly ROOT

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

echo "=== WordPress Stack Installer V2.0.8 tests ==="

echo "[1/19] Bash syntax"

while IFS= read -r -d '' file; do
    bash -n "$file"
done < <(
    find "$ROOT" -type f -name '*.sh' -print0
)

bash -n "$ROOT/config/defaults.conf"
pass "syntax"

echo "[2/19] Required files"

required=(
    "wordpress-stack.sh"
    "config/defaults.conf"
    "lib/args.sh"
    "lib/system.sh"
    "lib/project.sh"
    "lib/docker.sh"
    "lib/wordpress.sh"
    "lib/summary.sh"
    "templates/compose.yml"
    "templates/Makefile"
    "templates/scripts/wp-install.sh"
    "templates/scripts/backup.sh"
    "templates/scripts/restore.sh"
    "templates/scripts/healthcheck.sh"
)

for file in "${required[@]}"; do
    [[ -f "$ROOT/$file" ]] || fail "missing $file"
done

pass "required files"

echo "[3/19] LAN default domain"

grep -Fq 'DOMAIN="${DOMAIN:-wp.home.arpa}"' "$ROOT/lib/args.sh" ||
    fail "wp.home.arpa LAN default missing"

if grep -Rqs 'wp.local' \
    "$ROOT/config" \
    "$ROOT/lib" \
    "$ROOT/templates/scripts" \
    "$ROOT/templates/compose.yml"; then
    fail "old wp.local remains in runtime/configuration"
fi

pass "LAN default domain"

echo "[4/19] WP-CLI installer execution"

grep -Eq '^[[:space:]]+bash[[:space:]]*\\?$' "$ROOT/lib/wordpress.sh" ||
    fail "wp-install is not invoked through bash"

grep -Fq '/scripts/wp-install.sh' "$ROOT/lib/wordpress.sh" ||
    fail "missing wp-install path"

pass "WP-CLI installer execution"

echo "[5/19] Database readiness"

if grep -Fq 'wp db check' "$ROOT/templates/scripts/wp-install.sh"; then
    fail "wp db check found"
fi

grep -Fq 'new mysqli' "$ROOT/templates/scripts/wp-install.sh" ||
    fail "mysqli readiness missing"

pass "database readiness"

echo "[6/19] Admin email separation"

grep -Fq -- '--admin-email' "$ROOT/lib/args.sh" ||
    fail "--admin-email missing"

grep -Fq 'ADMIN_EMAIL="admin@example.com"' "$ROOT/lib/system.sh" ||
    fail "valid LAN admin email default missing"

pass "admin email separation"

echo "[7/19] Runtime permissions"

while IFS= read -r -d '' file; do
    [[ "$(stat -c '%a' "$file")" == "755" ]] ||
        fail "$file is not 0755"
done < <(
    find "$ROOT/templates/scripts" -maxdepth 1 -type f -name '*.sh' -print0
)

grep -Fq 'chown -R www-data:www-data /var/www/html' "$ROOT/lib/wordpress.sh" ||
    fail "WordPress ownership normalization missing"

pass "runtime permissions"

echo "[8/19] Backend egress"

if grep -A4 '^  backend:' "$ROOT/templates/compose.yml" | grep -Fq 'internal: true'; then
    fail "backend is still internal"
fi

pass "backend egress"

echo "[9/19] Stable network names"

grep -Fq 'name: "${COMPOSE_PROJECT_NAME}_frontend"' "$ROOT/templates/compose.yml" ||
    fail "frontend network name missing"

grep -Fq 'name: "${COMPOSE_PROJECT_NAME}_backend"' "$ROOT/templates/compose.yml" ||
    fail "backend network name missing"

pass "stable network names"

echo "[10/19] Explicit Traefik frontend network"

grep -Fq 'network: "${frontend_network}"' "$ROOT/lib/docker.sh" ||
    fail "Traefik provider network missing"

grep -Fq 'traefik.docker.network: "${frontend_network}"' "$ROOT/lib/docker.sh" ||
    fail "traefik.docker.network label missing"

pass "explicit Traefik frontend network"

echo "[11/19] LAN router aliases"

grep -Fq 'Host(\`${DOMAIN}\`) || Host(\`localhost\`) || Host(\`127.0.0.1\`)' \
    "$ROOT/lib/docker.sh" ||
    fail "LAN Host aliases missing"

pass "LAN router aliases"

echo "[12/19] Dynamic LAN WordPress URLs"

grep -Fq "define('WP_HOME', 'http://' . \$\$_wp_raw_host);" \
    "$ROOT/templates/compose.yml" ||
    fail "dynamic WP_HOME missing"

grep -Fq "define('WP_SITEURL', 'http://' . \$\$_wp_raw_host);" \
    "$ROOT/templates/compose.yml" ||
    fail "dynamic WP_SITEURL missing"

grep -Fq "'localhost'," "$ROOT/templates/compose.yml" ||
    fail "localhost WordPress whitelist missing"

grep -Fq "'127.0.0.1'" "$ROOT/templates/compose.yml" ||
    fail "127.0.0.1 WordPress whitelist missing"

pass "dynamic LAN WordPress URLs"

echo "[13/19] LAN healthcheck primary hostname"

grep -Fq -- '--resolve "${DOMAIN}:80:127.0.0.1"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "primary LAN hostname healthcheck missing"

pass "LAN primary hostname healthcheck"

echo "[14/19] LAN healthcheck localhost"

grep -Fq -- '--resolve "localhost:80:127.0.0.1"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "localhost healthcheck missing"

grep -Fq '"http://localhost/"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "localhost URL missing"

pass "LAN localhost healthcheck"

echo "[15/19] LAN healthcheck loopback IP"

grep -Fq '"http://127.0.0.1/"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "127.0.0.1 healthcheck missing"

pass "LAN loopback IP healthcheck"

echo "[16/19] Restore bind mount safety"

if grep -Fq 'rm -rf -- "$PROJECT_DIR/data/wordpress"' "$ROOT/templates/scripts/restore.sh"; then
    fail "restore deletes bind mount root"
fi

pass "restore bind mount safety"

echo "[17/19] MySQL password handling"

if grep -R -- '-p"\$MYSQL' "$ROOT/templates/scripts" >/dev/null; then
    fail "password passed through -p"
fi

grep -Fq 'MYSQL_PWD' "$ROOT/templates/scripts/backup.sh" ||
    fail "backup MYSQL_PWD missing"

pass "MySQL password handling"

echo "[18/19] HSTS safety"

if grep -Rq 'stsPreload.*true\|stsIncludeSubdomains.*true' "$ROOT/lib/docker.sh"; then
    fail "aggressive HSTS enabled"
fi

pass "HSTS safety"

echo "[19/19] No unconditional root requirement"

if grep -Rq 'check_root' "$ROOT/wordpress-stack.sh" "$ROOT/lib"; then
    fail "unconditional root requirement found"
fi

pass "no unconditional root requirement"

echo
echo "== ShellCheck =="

if command -v shellcheck >/dev/null 2>&1; then
    (
        cd "$ROOT" || exit 1

        # Основний application аналізуємо разом з усіма sourced modules.
        shellcheck \
            -x \
            -P "$ROOT" \
            wordpress-stack.sh
    )

    # Самостійні runtime scripts аналізуємо окремо.
    shellcheck \
        "$ROOT/templates/scripts/backup.sh" \
        "$ROOT/templates/scripts/restore.sh" \
        "$ROOT/templates/scripts/healthcheck.sh" \
        "$ROOT/templates/scripts/wp-install.sh"

    # Test runner є самостійним скриптом.
    shellcheck \
        "$ROOT/tests/run-tests.sh"

    echo "PASS: shellcheck"
else
    echo "SKIP: shellcheck not installed"
fi

echo
echo "Усі доступні тести пройдено."
