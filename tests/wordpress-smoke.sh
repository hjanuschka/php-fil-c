#!/bin/bash
set -euo pipefail

image="${1:?image tag required}"
expected="${2:?WordPress version required}"
workspace=$(mktemp -d -p /var/tmp filc-wordpress-XXXXXX)
network="filc-wp-$$"
db="filc-wp-db-$$"
wp="filc-wp-app-$$"
password=$(openssl rand -hex 24)
admin_password=$(openssl rand -hex 24)
success=0

cleanup() {
  if [ "$success" != 1 ]; then
    echo "WordPress smoke failed at ${stage:-startup}; HTTP ${status:-unknown}" >&2
    for page in home dashboard; do
      if [ -f "$workspace/$page.html" ]; then
        grep -Eo '<title>[^<]*|Fatal error.{0,120}|Error establishing a database connection' "$workspace/$page.html" | head -6 || :
      fi
    done
    if [ -f "$workspace/dashboard.html" ]; then
      sed -n '/id="login_error"/,+5p' "$workspace/dashboard.html" | head -6 || :
    fi
    docker cp "$wp:/opt/fil/apache/logs/error_log" "$workspace/apache-error.log" 2>/dev/null && tail -12 "$workspace/apache-error.log" || :
    docker logs "$wp" 2>&1 || :
  fi
  docker rm -f "$wp" "$db" >/dev/null 2>&1 || :
  docker network rm "$network" >/dev/null 2>&1 || :
  rm -rf "$workspace"
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker run -d --name "$db" --network "$network" \
  -e MARIADB_RANDOM_ROOT_PASSWORD=yes -e MARIADB_DATABASE=wordpress \
  -e MARIADB_USER=wordpress -e MARIADB_PASSWORD="$password" mariadb:11.4 >/dev/null

for i in $(seq 1 60); do
  if docker logs "$db" 2>&1 | grep -q 'ready for connections'; then break; fi
  sleep 2
done

docker run -d --name "$wp" --network "$network" -p 127.0.0.1::8080 \
  -e WORDPRESS_DB_HOST="$db" -e WORDPRESS_DB_USER=wordpress \
  -e WORDPRESS_DB_NAME=wordpress -e WORDPRESS_DB_PASSWORD="$password" \
  "$image" >/dev/null
port=$(docker port "$wp" 8080/tcp | sed -n 's/.*://p')

status=000
stage=install-page
for i in $(seq 1 30); do
  status=$(curl --max-time 30 -s -o "$workspace/install.html" -w '%{http_code}' \
    "http://127.0.0.1:$port/wp-admin/install.php?step=1" || :)
  if [ "$status" = 200 ]; then break; fi
  sleep 2
done
echo "install page HTTP $status"
[ "$status" = 200 ]
grep -q 'name="weblog_title"' "$workspace/install.html"
stage=version
actual=$(docker exec "$wp" /usr/local/bin/php -r 'require "/opt/fil/apache/htdocs/wp-includes/version.php"; echo $wp_version;')
echo "WordPress version $actual"
[ "$actual" = "$expected" ]
stage=install-post

status=$(curl --max-time 90 -s -o "$workspace/installed.html" -w '%{http_code}' \
  --data-urlencode 'weblog_title=Fil-C smoke test' \
  --data-urlencode 'user_name=admin' \
  --data-urlencode "admin_password=$admin_password" \
  --data-urlencode "admin_password2=$admin_password" \
  --data-urlencode 'admin_email=admin@example.com' \
  "http://127.0.0.1:$port/wp-admin/install.php?step=2")
echo "install POST HTTP $status"
[ "$status" = 200 ]
grep -q 'wp-login.php' "$workspace/installed.html"
stage=home
status=$(curl --max-time 90 -s -o "$workspace/home.html" -w '%{http_code}' "http://127.0.0.1:$port/")
echo "home page HTTP $status"
[ "$status" = 200 ]
grep -q 'Fil-C smoke test' "$workspace/home.html"
stage=login-page
status=$(curl --max-time 90 -s -c "$workspace/cookies" -b "$workspace/cookies" \
  -o "$workspace/login.html" -w '%{http_code}' "http://127.0.0.1:$port/wp-login.php")
[ "$status" = 200 ]
grep -q 'name="loginform"' "$workspace/login.html"
stage=dashboard
status=$(curl --max-time 180 -Ls -c "$workspace/cookies" -b "$workspace/cookies" \
  -o "$workspace/dashboard.html" -w '%{http_code}' \
  --data-urlencode 'log=admin' --data-urlencode "pwd=$admin_password" \
  --data-urlencode 'wp-submit=Log In' --data-urlencode 'testcookie=1' \
  --data-urlencode "redirect_to=http://127.0.0.1:$port/wp-admin/" \
  "http://127.0.0.1:$port/wp-login.php")
echo "admin dashboard HTTP $status"
[ "$status" = 200 ]
grep -q 'id="wpadminbar"' "$workspace/dashboard.html"
echo "WordPress $actual installed and served through $image"
success=1
