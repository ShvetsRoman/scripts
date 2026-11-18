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

# Best-effort очікування, поки Docker звільнить порти 80/443
# після down попереднього тестового стеку.
wait_port_free() {
    if ! docker info >/dev/null 2>&1; then
        return 0
    fi

    local i
    # shellcheck disable=SC2034
    for i in $(seq 1 30); do
        if ! docker ps --format '{{.Ports}}' |
            grep -qE ':(80|443)->'
        then
            return 0
        fi
        sleep 1
    done

    return 0
}

echo "=== WordPress Stack Installer V${REPO_VERSION} tests ==="

echo "[1/33] Bash syntax"

while IFS= read -r -d '' file; do
    bash -n "$file"
done < <(
    find "$ROOT" -type f -name '*.sh' -print0
)

bash -n "$ROOT/config/defaults.conf"
pass "syntax"

echo "[2/33] Required files"

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

echo "[3/33] LAN default domain"

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

echo "[4/33] WP-CLI installer execution"

grep -Eq '^[[:space:]]+bash[[:space:]]*\\?$' "$ROOT/lib/wordpress.sh" ||
    fail "wp-install is not invoked through bash"

grep -Fq '/scripts/wp-install.sh' "$ROOT/lib/wordpress.sh" ||
    fail "missing wp-install path"

pass "WP-CLI installer execution"

echo "[5/33] Database readiness"

if grep -Fq 'wp db check' "$ROOT/templates/scripts/wp-install.sh"; then
    fail "wp db check found"
fi

grep -Fq 'new mysqli' "$ROOT/templates/scripts/wp-install.sh" ||
    fail "mysqli readiness missing"

pass "database readiness"

echo "[6/33] Admin email separation"

grep -Fq -- '--admin-email' "$ROOT/lib/args.sh" ||
    fail "--admin-email missing"

grep -Fq 'ADMIN_EMAIL="admin@example.com"' "$ROOT/lib/system.sh" ||
    fail "valid LAN admin email default missing"

pass "admin email separation"

echo "[7/33] Runtime permissions"

while IFS= read -r -d '' file; do
    [[ "$(stat -c '%a' "$file")" == "755" ]] ||
        fail "$file is not 0755"
done < <(
    find "$ROOT/templates/scripts" -maxdepth 1 -type f -name '*.sh' -print0
)

grep -Fq 'chown -R www-data:www-data /var/www/html' "$ROOT/lib/wordpress.sh" ||
    fail "WordPress ownership normalization missing"

pass "runtime permissions"

echo "[8/33] Backend egress"

if grep -A4 '^  backend:' "$ROOT/templates/compose.yml" | grep -Fq 'internal: true'; then
    fail "backend is still internal"
fi

pass "backend egress"

echo "[9/33] Stable network names"

grep -Fq 'name: "${COMPOSE_PROJECT_NAME}_frontend"' "$ROOT/templates/compose.yml" ||
    fail "frontend network name missing"

grep -Fq 'name: "${COMPOSE_PROJECT_NAME}_backend"' "$ROOT/templates/compose.yml" ||
    fail "backend network name missing"

pass "stable network names"

echo "[10/33] Explicit Traefik frontend network"

grep -Fq 'network: "${frontend_network}"' "$ROOT/lib/docker.sh" ||
    fail "Traefik provider network missing"

grep -Fq 'traefik.docker.network: "${frontend_network}"' "$ROOT/lib/docker.sh" ||
    fail "traefik.docker.network label missing"

pass "explicit Traefik frontend network"

echo "[11/33] LAN router aliases"

grep -Fq 'Host(\`${DOMAIN}\`) || Host(\`localhost\`) || Host(\`127.0.0.1\`)' \
    "$ROOT/lib/docker.sh" ||
    fail "LAN Host aliases missing"

pass "LAN router aliases"

echo "[12/33] Dynamic LAN WordPress URLs"

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

echo "[13/33] LAN healthcheck primary hostname"

grep -Fq -- '--resolve "${DOMAIN}:80:127.0.0.1"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "primary LAN hostname healthcheck missing"

pass "LAN primary hostname healthcheck"

echo "[14/33] LAN healthcheck localhost"

grep -Fq -- '--resolve "localhost:80:127.0.0.1"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "localhost healthcheck missing"

grep -Fq '"http://localhost/"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "localhost URL missing"

pass "LAN localhost healthcheck"

echo "[15/33] LAN healthcheck loopback IP"

grep -Fq '"http://127.0.0.1/"' \
    "$ROOT/templates/scripts/healthcheck.sh" ||
    fail "127.0.0.1 healthcheck missing"

pass "LAN loopback IP healthcheck"

echo "[16/33] Restore bind mount safety"

if grep -Fq 'rm -rf -- "$PROJECT_DIR/data/wordpress"' "$ROOT/templates/scripts/restore.sh"; then
    fail "restore deletes bind mount root"
fi

pass "restore bind mount safety"

echo "[17/33] MySQL password handling"

if grep -R -- '-p"\$MYSQL' "$ROOT/templates/scripts" >/dev/null; then
    fail "password passed through -p"
fi

grep -Fq 'MYSQL_PWD' "$ROOT/templates/scripts/backup.sh" ||
    fail "backup MYSQL_PWD missing"

pass "MySQL password handling"

echo "[18/33] HSTS safety"

if grep -Rq 'stsPreload.*true\|stsIncludeSubdomains.*true' "$ROOT/lib/docker.sh"; then
    fail "aggressive HSTS enabled"
fi

pass "HSTS safety"

echo "[19/33] No unconditional root requirement"

if grep -Rq 'check_root' "$ROOT/wordpress-stack.sh" "$ROOT/lib"; then
    fail "unconditional root requirement found"
fi

pass "no unconditional root requirement"

echo "[20/33] Single VERSION source"

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

echo "[21/33] Let's Encrypt staging flag"

grep -Fq -- '--staging' "$ROOT/lib/args.sh" ||
    fail "--staging flag missing"

grep -Fq 'acme-staging-v02.api.letsencrypt.org' "$ROOT/lib/docker.sh" ||
    fail "staging CA URL missing"

grep -Fq 'ACME_STAGING' "$ROOT/config/defaults.conf" ||
    fail "ACME_STAGING default missing"

pass "Let's Encrypt staging flag"

echo "[22/33] DNS preflight"

grep -Fq 'preflight_domain_dns' "$ROOT/lib/system.sh" ||
    fail "preflight_domain_dns missing in lib/system.sh"

grep -Fq 'preflight_domain_dns' "$ROOT/wordpress-stack.sh" ||
    fail "preflight_domain_dns not called from main"

grep -Fq 'getent ahostsv4' "$ROOT/lib/system.sh" ||
    fail "DNS lookup helper missing"

pass "DNS preflight"

echo "[23/33] server_tokens off"

grep -Fq 'server_tokens off;' "$ROOT/templates/nginx/default.conf" ||
    fail "server_tokens off missing"

pass "server_tokens off"

echo "[24/33] FPM ping healthcheck"

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

echo "[25/33] Real-IP frontend subnet only"

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

echo "[26/33] Container resource limits"

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

echo "[27/33] Nginx log rotation"

grep -Fq 'logs-rotate' "$ROOT/templates/Makefile" || fail "make logs-rotate missing"

grep -Fq 'logrotate-nginx.sh' "$ROOT/templates/Makefile" ||
    fail "Makefile does not call logrotate-nginx.sh"

[[ "$(stat -c '%a' "$ROOT/templates/scripts/logrotate-nginx.sh")" == "755" ]] ||
    fail "logrotate-nginx.sh is not 0755"

pass "nginx log rotation"

echo "[28/33] Installer smoke (--no-start)"

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

echo "[29/33] Redis object cache"

grep -Fq 'ENABLE_REDIS=false' "$ROOT/config/defaults.conf" ||
    fail "ENABLE_REDIS default missing"

grep -Fq -- '--enable-redis' "$ROOT/lib/args.sh" ||
    fail "--enable-redis missing"

grep -Fq 'profiles:' "$ROOT/templates/compose.yml" ||
    fail "redis service profiles missing"

grep -Fq 'REDIS_PASSWORD' "$ROOT/templates/compose.yml" ||
    fail "REDIS_PASSWORD missing in compose.yml"

grep -Fq 'redis-cache' "$ROOT/templates/scripts/wp-install.sh" ||
    fail "redis-cache plugin install missing"

grep -Fq 'COMPOSE_PROFILES' "$ROOT/lib/project.sh" ||
    fail "COMPOSE_PROFILES missing in .env generation"

pass "redis object cache"

echo "[30/33] Production hardening"

grep -Fq 'ENABLE_CRON=false' "$ROOT/config/defaults.conf" ||
    fail "ENABLE_CRON default missing"

grep -Fq -- '--enable-cron' "$ROOT/lib/args.sh" ||
    fail "--enable-cron missing"

grep -Fq 'schedule_cron_tasks' "$ROOT/wordpress-stack.sh" ||
    fail "schedule_cron_tasks not called in main"

grep -Fq 'wordpress-stack.conf' "$ROOT/lib/security.sh" ||
    fail "cron.d file missing in security.sh"

grep -Fq '[wordpress]' "$ROOT/lib/security.sh" ||
    fail "fail2ban wordpress jail missing"

grep -Fq 'filter.d/wordpress-stack.conf' "$ROOT/lib/security.sh" ||
    fail "fail2ban wp-login filter missing"

grep -Fq 'POST /wp-login' "$ROOT/lib/security.sh" ||
    fail "failregex wp-login missing"

! grep -Eq "printf '  Password: %s" "$ROOT/lib/summary.sh" ||
    fail "admin password still printed to stdout"

pass "production hardening"

echo "[31/33] Backup/restore roundtrip"

if docker info >/dev/null 2>&1; then
    if (
        set -Eeuo pipefail

        rt_dir="$(
            mktemp -d "${TMPDIR:-/tmp}/wp-roundtrip.XXXXXX"
        )"
        rt_tmp="${TMPDIR:-/tmp}"
        # shellcheck disable=SC2329
        cleanup() {
            (
                cd "$rt_dir" &&
                    docker compose \
                        -f compose.yml \
                        -f compose.override.yml \
                        down -v \
                        >/dev/null 2>&1
            ) || true
            docker run --rm -v "$rt_tmp:/t" alpine \
                rm -rf "/t/$(basename "$rt_dir")" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT

        "$ROOT/wordpress-stack.sh" \
            --mode lan \
            --dir "$rt_dir" \
            >"$rt_tmp/wp-roundtrip-install.log" 2>&1

        cd "$rt_dir"

        make up >"$rt_tmp/wp-roundtrip-up.log" 2>&1

        # Чекаємо, доки wp-install.sh завершить інсталяцію WordPress.
        ready=0
        for _ in $(seq 1 90); do
            if docker compose \
                -f compose.yml \
                -f compose.override.yml \
                exec -T wpcli \
                wp core is-installed >/dev/null 2>&1
            then
                ready=1
                break
            fi
            sleep 2
        done
        [[ "$ready" == 1 ]] || exit 1

        wp() {
            docker compose \
                -f compose.yml \
                -f compose.override.yml \
                exec -T wpcli wp "$@"
        }

        wp post create \
            --post_title=roundtrip-keep >/dev/null

        bash scripts/backup.sh >"$rt_tmp/wp-roundtrip-backup.log" 2>&1

        rt_backup="$(
            find backups -mindepth 1 -maxdepth 1 -type d |
                sort |
                tail -n 1
        )"
        [[ -f "$rt_backup/database.sql.gz" ]] || exit 1
        [[ -f "$rt_backup/wordpress.tar.gz" ]] || exit 1
        [[ -f "$rt_backup/backup.info" ]] || exit 1

        gzip -t "$rt_backup/database.sql.gz" || exit 1
        tar -tzf "$rt_backup/wordpress.tar.gz" >/dev/null || exit 1

        # Пошкодження ПІСЛЯ бекапу: post і файл, яких у бекапі немає.
        wp post create \
            --post_title=roundtrip-delete >/dev/null

        docker compose \
            -f compose.yml \
            -f compose.override.yml \
            exec -T -u 0 wordpress \
            sh -c 'printf "restore-test\n" > /var/www/html/wp-content/restore-test.txt'

        printf 'y\n' | bash scripts/restore.sh "$(
            basename "$rt_backup"
        )" >"$rt_tmp/wp-roundtrip-restore.log" 2>&1 || exit 1

        titles="$(
            wp post list --field=post_title --posts_per_page=100
        )"
        printf '%s' "$titles" | grep -q 'roundtrip-keep' || exit 1
        if printf '%s' "$titles" | grep -q 'roundtrip-delete'; then
            exit 1
        fi
        docker compose \
            -f compose.yml \
            -f compose.override.yml \
            exec -T -u 0 wordpress \
            sh -c 'test ! -f /var/www/html/wp-content/restore-test.txt'
    ); then
        pass "backup/restore roundtrip"
    else
        fail "backup/restore roundtrip"
    fi
else
    echo "SKIP: docker daemon unavailable"
fi

wait_port_free

echo "[32/33] Central proxy stack (--init-proxy)"

[[ -f "$ROOT/templates/proxy/compose.yml" ]] ||
    fail "proxy compose template missing"

if docker info >/dev/null 2>&1; then
    proxy_dir="$(
        mktemp -d "${TMPDIR:-/tmp}/wp-proxy.XXXXXX"
    )"

    proxy_cleanup() {
        (
            cd "$proxy_dir" 2>/dev/null || exit 0
            docker compose -f compose.yml down -v >/dev/null 2>&1 || true
            docker network rm wp_proxy >/dev/null 2>&1 || true
        ) || true
        rm -rf -- "$proxy_dir"
    }
    trap proxy_cleanup EXIT

    if "$ROOT/wordpress-stack.sh" \
        --init-proxy \
        --email proxy-test@example.com \
        --staging \
        --dir "$proxy_dir" \
        >/dev/null 2>&1
    then
        grep -Fq 'PROXY_SUBNET=' "$proxy_dir/.env" &&
            grep -Fq 'wp_proxy' "$proxy_dir/traefik/traefik.yml" &&
            docker network inspect wp_proxy >/dev/null 2>&1 &&
            pass "central proxy stack"
    else
        fail "central proxy stack"
    fi

    # Звільняємо порти 80/443 перед наступним тестом.
    proxy_cleanup
    trap - EXIT
    wait_port_free
else
    echo "SKIP: docker daemon unavailable"
fi

echo "[33/33] Site without Traefik (--no-traefik, lan)"

if docker info >/dev/null 2>&1; then
    notraf_dir="$(
        mktemp -d "${TMPDIR:-/tmp}/wp-notraf.XXXXXX"
    )"

    notraf_cleanup() {
        (
            cd "$notraf_dir" 2>/dev/null || exit 0
            docker compose -f compose.yml -f compose.override.yml down -v >/dev/null 2>&1 || true
        ) || true
        # data/ належить контейнерам (www-data/mysql) — чистимо через контейнер.
        docker run --rm -v "${TMPDIR:-/tmp}:/t:rw" alpine \
            rm -rf -- "/t/$(basename -- "$notraf_dir")" >/dev/null 2>&1 || true
    }
    trap notraf_cleanup EXIT

    if "$ROOT/wordpress-stack.sh" \
        --mode lan \
        --no-traefik \
        --dir "$notraf_dir" \
        >/dev/null 2>&1
    then
        if grep -Fq 'COMPOSE_PROFILES=' "$notraf_dir/.env" &&
            ! grep -E 'COMPOSE_PROFILES=.*proxy' "$notraf_dir/.env" &&
            grep -Fq '80:80' "$notraf_dir/compose.override.yml" &&
            docker compose -f "$notraf_dir/compose.yml" -f "$notraf_dir/compose.override.yml" config --quiet
        then
            pass "site without traefik (lan)"
        else
            fail "site without traefik (lan)"
        fi
    else
        fail "site without traefik (lan)"
    fi

    notraf_cleanup
    trap - EXIT
    wait_port_free
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
