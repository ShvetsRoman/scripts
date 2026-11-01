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

REPO_VERSION="$(
    sed -n 's/^readonly VERSION="//p' "$ROOT/config/defaults.conf" |
    sed -E 's/"$//'
)"
readonly REPO_VERSION

[[ -n "$REPO_VERSION" ]] || fail "VERSION not found in config/defaults.conf"

echo "=== WordPress Stack Installer V${REPO_VERSION} tests ==="

echo "[1/28] Bash syntax"

while IFS= read -r -d '' file; do
    bash -n "$file"
done < <(
    find "$ROOT" -type f -name '*.sh' -print0
)

bash -n "$ROOT/config/defaults.conf"
pass "syntax"

echo "[2/28] Required files"

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
    "templates/php/fpm-ping.conf"
    "templates/scripts/wp-install.sh"
    "templates/scripts/backup.sh"
    "templates/scripts/restore.sh"
    "templates/scripts/healthcheck.sh"
    "templates/scripts/logrotate-nginx.sh"
)

for file in "${required[@]}"; do
    [[ -f "$ROOT/$file" ]] || fail "missing $file"
done

pass "required files"

echo "[3/28] LAN default domain"

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

echo "[4/28] WP-CLI installer execution"

grep -Eq '^[[:space:]]+bash[[:space:]]*\\?$' "$ROOT/lib/wordpress.sh" ||
    fail "wp-install is not invoked through bash"

grep -Fq '/scripts/wp-install.sh' "$ROOT/lib/wordpress.sh" ||
    fail "missing wp-install path"

pass "WP-CLI installer execution"

echo "[5/28] Database readiness"

if grep -Fq 'wp db check' "$ROOT/templates/scripts/wp-install.sh"; then
    fail "wp db check found"
fi

grep -Fq 'new mysqli' "$ROOT/templates/scripts/wp-install.sh" ||
    fail "mysqli readiness missing"

pass "database readiness"

echo "[6/28] Admin email separation"

grep -Fq -- '--admin-email' "$ROOT/lib/args.sh" ||
    fail "--admin-email missing"

grep -Fq 'ADMIN_EMAIL="admin@example.com"' "$ROOT/lib/system.sh" ||
    fail "valid LAN admin email default missing"

pass "admin email separation"

echo "[7/28] Runtime permissions"

while IFS= read -r -d '' file; do
    [[ "$(stat -c '%a' "$file")" == "755" ]] ||
        fail "$file is not 0755"
done < <(
    find "$ROOT/templates/scripts" -maxdepth 1 -type f -name '*.sh' -print0
)

grep -Fq 'chown -R www-data:www-data /var/www/html' "$ROOT/lib/wordpress.sh" ||
    fail "WordPress ownership normalization missing"

pass "runtime permissions"

echo "[8/28] Backend egress"

if grep -A4 '^  backend:' "$ROOT/templates/compose.yml" | grep -Fq 'internal: true'; then
    fail "backend is still internal"
fi

pass "backend egress"

echo "[9/28] Stable network names"

grep -Fq 'name: "${COMPOSE_PROJECT_NAME}_frontend"' "$ROOT/templates/compose.yml" ||
    fail "frontend network name missing"

grep -Fq 'name: "${COMPOSE_PROJECT_NAME}_backend"' "$ROOT/templates/compose.yml" ||
    fail "backend network name missing"

pass "stable network names"

echo "[10/28] Explicit Traefik frontend network"

grep -Fq 'network: "${frontend_network}"' "$ROOT/lib/docker.sh" ||
    fail "Traefik provider network missing"

grep -Fq 'traefik.docker.network: "${frontend_network}"' "$ROOT/lib/docker.sh" ||
    fail "traefik.docker.network label missing"

pass "explicit Traefik frontend network"

echo "[11/28] LAN router aliases"

grep -Fq 'Host(\`${DOMAIN}\`) || Host(\`localhost\`) || Host(\`127.0.0.1\`)' \
    "$ROOT/lib/docker.sh" ||
    fail "LAN Host aliases missing"

pass "LAN router aliases"

echo "[12/28] Dynamic LAN WordPress URLs"

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

echo "[13/28] LAN healthcheck primary hostname"

grep -Fq -- '--resolve "${DOMAIN}:80:127.0.0.1"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "primary LAN hostname healthcheck missing"

pass "LAN primary hostname healthcheck"

echo "[14/28] LAN healthcheck localhost"

grep -Fq -- '--resolve "localhost:80:127.0.0.1"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "localhost healthcheck missing"

grep -Fq '"http://localhost/"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "localhost URL missing"

pass "LAN localhost healthcheck"

echo "[15/28] LAN healthcheck loopback IP"

grep -Fq '"http://127.0.0.1/"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "127.0.0.1 healthcheck missing"

pass "LAN loopback IP healthcheck"

echo "[16/28] Restore bind mount safety"

if grep -Fq 'rm -rf -- "$PROJECT_DIR/data/wordpress"' "$ROOT/templates/scripts/restore.sh"; then
    fail "restore deletes bind mount root"
fi

pass "restore bind mount safety"

echo "[17/28] MySQL password handling"

if grep -R -- '-p"\$MYSQL' "$ROOT/templates/scripts" >/dev/null; then
    fail "password passed through -p"
fi

grep -Fq 'MYSQL_PWD' "$ROOT/templates/scripts/backup.sh" ||
    fail "backup MYSQL_PWD missing"

pass "MySQL password handling"

echo "[18/28] HSTS safety"

if grep -Rq 'stsPreload.*true\|stsIncludeSubdomains.*true' "$ROOT/lib/docker.sh"; then
    fail "aggressive HSTS enabled"
fi

pass "HSTS safety"

echo "[19/28] No unconditional root requirement"

if grep -Rq 'check_root' "$ROOT/wordpress-stack.sh" "$ROOT/lib"; then
    fail "unconditional root requirement found"
fi

pass "no unconditional root requirement"

echo "[20/28] Single VERSION source"

grep -Fq 'readonly VERSION=' "$ROOT/config/defaults.conf" ||
    fail "VERSION missing in config/defaults.conf"

if grep -Eq '^readonly VERSION' "$ROOT/wordpress-stack.sh"; then
    fail "worderpress-stack.sh duplicate VERSION definition"
fi

grep -Fq 'V%s' "$ROOT/lib/summary.sh" ||
    fail "summary.sh hardcodes version instead of \$VERSION"

while IFS= read -r readme; do
    head -n 1 "$readme" | grep -Fq "V${REPO_VERSION}" ||
        fail "$readme title does not match V${REPO_VERSION}"
done < <(
    printf '%s\n' "$ROOT/README.md" "$ROOT/templates/README.md"
)

pass "single VERSION source"

echo "[21/28] Let's Encrypt staging flag"

grep -Fq -- '--staging' "$ROOT/lib/args.sh" ||
    fail "--staging flag missing"

grep -Fq 'acme-staging-v02.api.letsencrypt.org' "$ROOT/lib/docker.sh" ||
    fail "staging CA URL missing"

grep -Fq 'ACME_STAGING' "$ROOT/config/defaults.conf" ||
    fail "ACME_STAGING default missing"

pass "Let's Encrypt staging flag"

echo "[22/28] DNS preflight"

grep -Fq 'preflight_domain_dns' "$ROOT/lib/system.sh" ||
    fail "preflight_domain_dns missing in lib/system.sh"

grep -Fq 'preflight_domain_dns' "$ROOT/wordpress-stack.sh" ||
    fail "preflight_domain_dns not called from main"

grep -Fq 'getent ahostsv4' "$ROOT/lib/system.sh" ||
    fail "DNS lookup helper missing"

pass "DNS preflight"

echo "[23/28] server_tokens off"

grep -Fq 'server_tokens off;' "$ROOT/templates/nginx/default.conf" ||
    fail "server_tokens off missing"

pass "server_tokens off"

echo "[24/28] FPM ping healthcheck"

grep -Fq 'ping.path = /fpm-ping' "$ROOT/templates/php/fpm-ping.conf" ||
    fail "FPM ping.path missing"

grep -Fq 'zz-fpm-ping.conf' "$ROOT/templates/compose.yml" ||
    fail "FPM pool override not mounted"

grep -Fq -- 'location = /fpm-ping' "$ROOT/templates/nginx/default.conf" ||
    fail "nginx /fpm-ping location missing"

grep -Fq '127.0.0.1/fpm-ping' "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "fpm-ping healthcheck missing in healthcheck.sh"

grep -Fq '127.0.0.1/fpm-ping' "$ROOT/templates/compose.yml" ||
    fail "fpm-ping healthcheck missing in compose.yml"

pass "FPM ping healthcheck"

echo "[25/28] Real-IP frontend subnet only"

grep -Fq 'include /etc/nginx/conf.d/real-ip.conf' "$ROOT/templates/nginx/default.conf" ||
    fail "real-ip.conf include missing"

if grep -Eq '^ *set_real_ip_from (10\.|172\.16\.|192\.168\.)' "$ROOT/templates/nginx/default.conf"; then
    fail "blanket private X-Forwarded-For trust still present"
fi

grep -Fq 'set_real_ip_from ${FRONTEND_SUBNET}' "$ROOT/lib/docker.sh" ||
    fail "real-ip.conf frontend subnet missing"

grep -Fq 'subnet: "${FRONTEND_SUBNET}"' "$ROOT/templates/compose.yml" ||
    fail "frontend IPAM subnet missing"

grep -Fq 'FRONTEND_SUBNET=' "$ROOT/lib/project.sh" ||
    fail "FRONTEND_SUBNET missing in .env writer"

pass "real-IP frontend subnet only"

echo "[26/28] Container resource limits"

limit_grep() {
    local key="$1"
    grep -Fq "$key" "$ROOT/templates/compose.yml" || fail "missing $key"
}

limit_grep 'mem_limit: "${TRAEFIK_MEM_LIMIT}"'
limit_grep 'mem_limit: "${NGINX_MEM_LIMIT}"'
limit_grep 'mem_limit: "${WORDPRESS_MEM_LIMIT}"'
limit_grep 'mem_limit: "${DB_MEM_LIMIT}"'
limit_grep 'mem_limit: "${WPCLI_MEM_LIMIT}"'
limit_grep 'pids_limit: "${PIDS_LIMIT}"'
limit_grep 'pids_limit: "${DB_PIDS_LIMIT}"'

pass "container resource limits"

echo "[27/28] Nginx log rotation"

grep -Fq 'logs-rotate' "$ROOT/templates/Makefile" || fail "make logs-rotate missing"

grep -Fq 'logrotate-nginx.sh' "$ROOT/templates/Makefile" ||
    fail "Makefile does not call logrotate-nginx.sh"

[[ "$(stat -c '%a' "$ROOT/templates/scripts/logrotate-nginx.sh")" == "755" ]] ||
    fail "logrotate-nginx.sh is not 0755"

pass "nginx log rotation"

echo "[28/28] Installer smoke (--no-start)"

if docker info >/dev/null 2>&1; then
    smoke_dir="$(
        mktemp -d "${TMPDIR:-/tmp}/wp-smoke.XXXXXX"
    )"

    if "$ROOT/wordpress-stack.sh" \
        --mode lan \
        --no-start \
        --dir "$smoke_dir" \
        >/dev/null 2>&1
    then
        for file in \
            compose.yml \
            compose.override.yml \
            .env \
            traefik/traefik.yml \
            nginx/default.conf \
            nginx/real-ip.conf \
            php/custom.ini \
            php/fpm-ping.conf \
            Makefile
        do
            [[ -f "$smoke_dir/$file" ]] || fail "smoke: missing $file"
        done

        grep -Fq 'FRONTEND_SUBNET=' "$smoke_dir/.env" ||
            fail "smoke: FRONTEND_SUBNET missing in .env"

        grep -Fq 'mem_limit' "$smoke_dir/compose.yml" ||
            fail "smoke: mem_limit missing in compose.yml"

        rm -rf -- "$smoke_dir"
        pass "installer smoke"
    else
        rm -rf -- "$smoke_dir"
        fail "installer smoke exited nonzero"
    fi
else
    echo "SKIP: docker daemon unavailable"
fi

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
        "$ROOT/templates/scripts/wp-install.sh" \
        "$ROOT/templates/scripts/logrotate-nginx.sh"

    # Test runner є самостійним скриптом.
    shellcheck \
        "$ROOT/tests/run-tests.sh"

    echo "PASS: shellcheck"
else
    echo "SKIP: shellcheck not installed"
fi

echo
echo "Усі доступні тести пройдено."
