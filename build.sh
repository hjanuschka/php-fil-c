#!/bin/bash
#
# Build PHP from source with the Fil-C memory-safe C/C++ compiler.
#
# Prerequisite: the Fil-C /opt/fil glibc distribution (see README.md).
#
#   ./build.sh              # build + install + smoke test -> ./install
#   PREFIX=/opt/php ./build.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
FILC_ROOT="${FILC_ROOT:-/opt/fil}"
PHP_VERSION="8.4.27"
# sha256 of the php.net tarball this build is verified against.
PHP_SHA256="dcf93923b0e38e0d5252b25b796520b5a47761a08b3488b6d0b5d1115764d3f0"
PREFIX="${PREFIX:-$ROOT/install}"
JOBS="${JOBS:-$(nproc)}"

FILCC="$FILC_ROOT/bin/filcc"
FILCPP="$FILC_ROOT/bin/fil++"
TARBALL="$ROOT/download/php-$PHP_VERSION.tar.xz"
SRC="$ROOT/src-$PHP_VERSION"

[ -x "$FILCC" ] || { echo "error: $FILCC not found - install the Fil-C /opt/fil distribution first (see README.md)" >&2; exit 1; }

mkdir -p "$ROOT/download"
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading php-$PHP_VERSION.tar.xz"
    curl -fL -o "$TARBALL" "https://www.php.net/distributions/php-$PHP_VERSION.tar.xz"
fi
(cd "$ROOT/download" && echo "$PHP_SHA256  $(basename "$TARBALL")" | sha256sum -c)

if [ ! -d "$SRC" ]; then
    echo "==> Extracting"
    tar -xf "$TARBALL" -C "$ROOT"
    mv "$ROOT/php-$PHP_VERSION" "$SRC"
fi

echo "==> Applying Fil-C patch"
if grep -q __FILC__ "$SRC/Zend/zend_weakrefs.c"; then
    echo "    (already applied)"
else
    (cd "$SRC" && patch -p1 --silent -i "$ROOT/patches/php-$PHP_VERSION-filc.patch")
fi

echo "==> Configuring"
cd "$SRC"
if [ ! -f Makefile ]; then
    PATH="$FILC_ROOT/bin:$PATH" \
    PKG_CONFIG="$FILC_ROOT/bin/pkg-config" \
    PKG_CONFIG_PATH="$FILC_ROOT/lib/pkgconfig" \
    CC="$FILCC -g -O2" CXX="$FILCPP -g -O2" \
    ./configure \
        --prefix="$PREFIX" \
        --disable-fiber-asm \
        --without-pcre-jit \
        --disable-opcache-jit \
        --with-external-pcre \
        --enable-fpm \
        --with-openssl --with-zlib --with-bz2 --with-curl \
        --without-sqlite3 --without-pdo-sqlite \
        --with-libedit \
        --enable-intl \
        --enable-mbstring --disable-mbregex \
        --enable-bcmath --enable-calendar --enable-exif \
        --enable-pcntl --enable-sockets \
        ac_cv_have_decl_UFFDIO_WRITEPROTECT_MODE_WP=no
fi

echo "==> Building (-j$JOBS)"
make -j"$JOBS"

echo "==> Installing to $PREFIX"
make install

# Smoke test exercises exactly the code the Fil-C patch touches. OPcache is
# left OFF: the port currently panics when OPcache persists certain classes
# (see README "Known limitations").
echo "==> Smoke test"
"$PREFIX/bin/php" -n -d zend.assertions=1 -r '
$m = new WeakMap; $o = new stdClass; $m[$o] = 1;
foreach ($m as $k => $v) assert($k === $o && $v === 1);
unset($o, $k); assert(count($m) === 0);
function f($n) { return array_map("f", [$n + 1]); }
$fiber = new Fiber(function () {
    try { f(0); } catch (Error $e) { Fiber::suspend($e->getMessage()); }
});
assert(str_starts_with($fiber->start(), "Maximum call stack size"));
$d = Dom\HTMLDocument::createFromString("<custom-el data-x=y>hi</custom-el>", LIBXML_NOERROR);
assert($d->querySelector("custom-el")->getAttribute("data-x") === "y");
$i = PHP_INT_MAX; $i++; assert(is_float($i));
assert(memory_get_usage(true) % (2 << 20) !== 0);
echo "php ok\n";'

"$PREFIX/bin/php" -v
