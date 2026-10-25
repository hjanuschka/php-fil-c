#!/bin/bash
set -euo pipefail

: "${WORDPRESS_PATH:=/opt/fil/apache/htdocs}"
: "${WORDPRESS_DB_HOST:=db}"
: "${WORDPRESS_DB_USER:=wordpress}"
: "${WORDPRESS_DB_PASSWORD:?Set WORDPRESS_DB_PASSWORD}"
: "${WORDPRESS_DB_NAME:=wordpress}"
: "${WORDPRESS_CONFIG_EXTRA:=}"
export WORDPRESS_DB_HOST WORDPRESS_DB_USER WORDPRESS_DB_PASSWORD WORDPRESS_DB_NAME

cd "$WORDPRESS_PATH"

if [ ! -f wp-config.php ]; then
  echo "Generating wp-config.php"
  gen_key() { dd if=/dev/urandom bs=32 count=1 status=none | od -An -tx1 | tr -d ' \n'; }
  cat > wp-config.php <<EOF
<?php
define( 'DB_NAME', getenv('WORDPRESS_DB_NAME') );
define( 'DB_USER', getenv('WORDPRESS_DB_USER') );
define( 'DB_PASSWORD', getenv('WORDPRESS_DB_PASSWORD') );
define( 'DB_HOST', getenv('WORDPRESS_DB_HOST') );
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

exec "$@"
