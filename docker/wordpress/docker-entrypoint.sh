#!/bin/bash
# Generate wp-config.php from WORDPRESS_* env vars and, on first boot, install
# the site once the database is reachable. Mirrors the official image's contract
# closely enough to be a drop-in for typical single-site setups.
set -euo pipefail

: "${WORDPRESS_PATH:=/opt/fil/apache/htdocs}"
: "${WORDPRESS_DB_HOST:=db}"
: "${WORDPRESS_DB_USER:=wordpress}"
: "${WORDPRESS_DB_PASSWORD:=wordpress}"
: "${WORDPRESS_DB_NAME:=wordpress}"

cd "$WORDPRESS_PATH"

if [ ! -f wp-config.php ]; then
  echo "Generating wp-config.php"
  # Salts: random per install.
  gen_key() { tr -dc 'a-zA-Z0-9!@#$%^&*()-_' </dev/urandom | head -c 64; }
  cat > wp-config.php <<EOF
<?php
define( 'DB_NAME', '$WORDPRESS_DB_NAME' );
define( 'DB_USER', '$WORDPRESS_DB_USER' );
define( 'DB_PASSWORD', '$WORDPRESS_DB_PASSWORD' );
define( 'DB_HOST', '$WORDPRESS_DB_HOST' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );
define( 'AUTH_KEY',         '$(gen_key)' );
define( 'SECURE_AUTH_KEY',  '$(gen_key)' );
define( 'LOGGED_IN_KEY',    '$(gen_key)' );
define( 'NONCE_KEY',        '$(gen_key)' );
define( 'AUTH_SALT',        '$(gen_key)' );
define( 'SECURE_AUTH_SALT', '$(gen_key)' );
define( 'LOGGED_IN_SALT',   '$(gen_key)' );
define( 'NONCE_SALT',       '$(gen_key)' );
\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );
define( 'FS_METHOD', 'direct' );
$WORDPRESS_CONFIG_EXTRA
if ( ! defined( 'ABSPATH' ) ) define( 'ABSPATH', __DIR__ . '/' );
require_once ABSPATH . 'wp-settings.php';
EOF
  chown -R www-data:www-data "$WORDPRESS_PATH" || true
fi

# Background: wait for the DB, then install the site if it isn't already.
(
  if [ "${1#-}" != "$1" ] || [ "${1:0:1}" = "-" ]; then :; fi
  host="${WORDPRESS_DB_HOST%%:*}"; port="${WORDPRESS_DB_HOST##*:}"; [ "$port" = "$host" ] && port=3306
  for i in $(seq 1 60); do
    if mysqladmin ping -h "$host" -P "$port" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" --silent >/dev/null 2>&1; then
      if ! wp core is-installed --allow-root --path="$WORDPRESS_PATH" 2>/dev/null; then
        echo "Installing WordPress..."
        wp core install --allow-root --path="$WORDPRESS_PATH" \
          --url="http://localhost:8080" --title="Fil-C WordPress" \
          --admin_user=admin --admin_password=password --admin_email=admin@example.com \
          && wp theme install twentytwentyfour --allow-root --path="$WORDPRESS_PATH" --activate 2>/dev/null || true
      fi
      break
    fi
    sleep 2
  done
) &

exec "$@"
