#!/bin/bash
# Assemble the Docker build context from a Fil-C PHP install tree.
#   FILC_PHP_PREFIX=/path/to/php-install ./docker/prepare.sh
# Defaults to the ./install produced by ../build.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CTX="$ROOT/docker"
PHP="${FILC_PHP_PREFIX:-$ROOT/install}"
EXTDIR="$(ls -d "$PHP"/lib/php/extensions/*/ 2>/dev/null | head -1)"
EXT="$(basename "$EXTDIR")"
[ -x "$PHP/bin/php" ] || { echo "no php at $PHP/bin/php" >&2; exit 1; }

rm -rf "$CTX/optfil-lib" "$CTX/php-cli" "$CTX/php-fpm"
mkdir -p "$CTX/optfil-lib" \
         "$CTX/php-cli/bin" "$CTX/php-cli/lib/php/extensions/$EXT" \
         "$CTX/php-fpm/bin" "$CTX/php-fpm/sbin" "$CTX/php-fpm/etc/php-fpm.d" \
         "$CTX/php-fpm/lib/php/extensions/$EXT"

# Fil-C runtime closure: the loader plus every shared object the PHP binaries
# need (transitively). Copy by soname from /opt/fil/lib.
mapfile -t LIBS < <(
  for b in "$PHP/bin/php" "$PHP/sbin/php-fpm" "$EXTDIR"*.so; do
    [ -e "$b" ] && readelf -d "$b" 2>/dev/null | grep NEEDED | sed -E 's/.*\[(.*)\]/\1/'
  done | sort -u
)
for l in "${LIBS[@]}"; do cp -L "/opt/fil/lib/$l" "$CTX/optfil-lib/" 2>/dev/null || true; done
# transitive deps of those libs (curl->nghttp2/zstd, icu->data, ...)
for l in "$CTX"/optfil-lib/*; do
  for n in $(readelf -d "$l" 2>/dev/null | grep NEEDED | sed -E 's/.*\[(.*)\]/\1/'); do
    cp -L "/opt/fil/lib/$n" "$CTX/optfil-lib/" 2>/dev/null || true
  done
done
cp -L /opt/fil/lib/ld-fil1-x86_64.so "$CTX/optfil-lib/"

cp "$PHP/bin/php" "$CTX/php-cli/bin/"; strip "$CTX/php-cli/bin/php" 2>/dev/null || true
cp "$PHP/bin/php" "$CTX/php-fpm/bin/"; strip "$CTX/php-fpm/bin/php" 2>/dev/null || true
cp "$PHP/sbin/php-fpm" "$CTX/php-fpm/sbin/"; strip "$CTX/php-fpm/sbin/php-fpm" 2>/dev/null || true
cp -r "$EXTDIR"* "$CTX/php-cli/lib/php/extensions/$EXT/" 2>/dev/null || true
cp -r "$EXTDIR"* "$CTX/php-fpm/lib/php/extensions/$EXT/" 2>/dev/null || true

# FPM config, rewritten for the container layout
cp "$PHP/etc/php-fpm.conf" "$CTX/php-fpm/etc/php-fpm.conf" 2>/dev/null || cp "$PHP/etc/php-fpm.conf.default" "$CTX/php-fpm/etc/php-fpm.conf"
cp "$PHP/etc/php-fpm.d/"*.default "$CTX/php-fpm/etc/php-fpm.d/www.conf" 2>/dev/null || cp "$PHP/etc/php-fpm.d/"*.conf "$CTX/php-fpm/etc/php-fpm.d/www.conf"
sed -i "s|^include=.*|include=/usr/local/etc/php-fpm.d/*.conf|" "$CTX/php-fpm/etc/php-fpm.conf"
sed -i "/^\[global\]/a error_log = /proc/self/fd/2\npid = /usr/local/var/run/php-fpm.pid" "$CTX/php-fpm/etc/php-fpm.conf"
sed -i -E 's|^;?listen = .*|listen = 9000|; s|^;?clear_env = .*|clear_env = no|; s|^;?catch_workers_output = .*|catch_workers_output = yes|; s|^user = .*|user = www-data|; s|^group = .*|group = www-data|' "$CTX/php-fpm/etc/php-fpm.d/www.conf"

echo "context ready: $CTX (ext dir: $EXT, $(ls "$CTX/optfil-lib" | wc -l) runtime libs)"
