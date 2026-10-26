# syntax=docker/dockerfile:1
#
# php-fil-c: PHP built from source with the Fil-C memory-safe C compiler.
#
# Self-contained: every layer (Fil-C libs, Apache stack, SQLite, oniguruma, and
# PHP itself) is compiled with Fil-C inside this build, so the whole process
# runs on Fil-C's libc -- no native/Fil-C mixing.
#
#   docker build --target cli   -t php-fil-c:cli   --build-arg PHP_VERSION=8.4.27 .
#   docker build --target fpm   -t php-fil-c:fpm   --build-arg PHP_VERSION=8.4.27 .
#   docker build --target apache -t php-fil-c:apache --build-arg PHP_VERSION=8.4.27 .
#
# The build context must contain patches/php-<ver>-filc.patch (see versions.json).

ARG DEBIAN_BASE=debian:bookworm-slim
ARG FILC_VERSION=0.686

# ---------------------------------------------------------------------------
# deps: Fil-C toolchain + the Apache stack + SQLite + oniguruma, all via filcc.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_BASE} AS deps
ARG FILC_VERSION
ARG DEBIAN_BASE
# Debian releases that are EOL moved to archive.debian.org; point apt there so
# the index and pool stay self-consistent (the live mirrors lag/rotate).
RUN if [ -f /etc/os-release ]; then . /etc/os-release; case "${VERSION_CODENAME}" in buster|stretch|jessie) printf 'deb http://archive.debian.org/debian %s main\ndeb http://archive.debian.org/debian-security %s/updates main\n' "$VERSION_CODENAME" "$VERSION_CODENAME" > /etc/apt/sources.list; printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/90nocheckvalid;; esac; fi
ARG APR_VER=1.7.4
ARG APU_VER=1.6.3
ARG HTTPD_VER=2.4.62
ARG SQLITE_VER=3460000
ARG ONIG_VER=6.9.9

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates xz-utils unzip build-essential libtool autoconf pkg-config \
      python3 libssl-dev zlib1g-dev libbz2-dev libcurl4-openssl-dev libicu-dev \
      libedit-dev libpcre2-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fLO "https://github.com/pizlonator/fil-c/releases/download/v${FILC_VERSION}/optfil-${FILC_VERSION}-linux-x86_64.tar.xz" \
 && tar -xf "optfil-${FILC_VERSION}-linux-x86_64.tar.xz" \
 && ( cd "optfil-${FILC_VERSION}-linux-x86_64" && ./setup.sh -u ) \
 && rm -rf optfil-* && /opt/fil/bin/filcc --version | head -1

# Fil-C compiler; system binutils for ld is NOT needed here (plain filcc works).
ENV CC=/opt/fil/bin/filcc
ENV CXX=/opt/fil/bin/fil++

# APR's generated libtool leaves global_symbol_pipe empty, which makes httpd's
# shared-module link emit `nm ... |  | sed` (an empty pipeline). A pass-through
# filter keeps the pipeline valid; Apache modules pass no -export-symbols so the
# generated list is unused.
RUN set -eux; \
    fixlt() { python3 -c 'import sys;p=sys.argv[1];s=open(p).read();s=s.replace("\nglobal_symbol_pipe=\"\"", "\nglobal_symbol_pipe=\"cat\"");open(p,"w").write(s)' "$1"; }; \
    cd /tmp; \
    curl -fL "https://github.com/libexpat/libexpat/releases/download/R_2_6_2/expat-2.6.2.tar.xz" -o e.txz; \
    tar -xf e.txz; ( cd expat-2.6.2 && ./configure --prefix=/opt/fil --enable-shared && make -j"$(nproc)" && make install ); \
    curl -fL "https://www.sqlite.org/2024/sqlite-amalgamation-${SQLITE_VER}.zip" -o sq.zip || \
      curl -fL "https://www.sqlite.org/2024/sqlite-amalgamation-${SQLITE_VER}.tar.gz" -o sq.tgz; \
    ( mkdir -p sqlite && if [ -f sq.zip ]; then cd sqlite && unzip -q ../sq.zip; else tar -xf ../sq.tgz; fi ); \
    SQLDIR=$(find /tmp/sqlite -maxdepth 1 -name 'sqlite-amalgamation-*' -type d | head -1); \
    ( cd "$SQLDIR" && \
      $CC -O2 -fPIC -shared -o /opt/fil/lib/libsqlite3.so.0 sqlite3.c -lpthread -ldl -lm && \
      ln -sf libsqlite3.so.0 /opt/fil/lib/libsqlite3.so && \
      install -Dm644 sqlite3.h /opt/fil/include/sqlite3.h && \
      install -Dm644 sqlite3ext.h /opt/fil/include/sqlite3ext.h ); \
    curl -fL "https://github.com/kkos/oniguruma/releases/download/v${ONIG_VER}/onig-${ONIG_VER}.tar.gz" -o onig.tgz; \
    tar -xf onig.tgz; ( cd "onig-${ONIG_VER}" && ./configure --prefix=/opt/fil --enable-shared && make -j"$(nproc)" && make install ); \
    curl -fL "https://archive.apache.org/dist/apr/apr-${APR_VER}.tar.bz2" -o apr.tbz; \
    tar -xf apr.tbz; ( cd "apr-${APR_VER}" && ./configure --prefix=/opt/fil --enable-shared --disable-static && make -j"$(nproc)" && make install ); \
    fixlt /opt/fil/build-1/libtool; \
    curl -fL "https://archive.apache.org/dist/apr/apr-util-${APU_VER}.tar.bz2" -o apu.tbz; \
    tar -xf apu.tbz; ( cd "apr-util-${APU_VER}" && ./configure --prefix=/opt/fil --with-apr=/opt/fil --without-sqlite3 --without-mysql --with-expat=/opt/fil --enable-shared && make -j"$(nproc)" && make install ); \
    curl -fL "https://archive.apache.org/dist/httpd/httpd-${HTTPD_VER}.tar.bz2" -o h.tbz; \
    tar -xf h.tbz; ( cd "httpd-${HTTPD_VER}" && ./configure --prefix=/opt/fil/apache --with-apr=/opt/fil --with-apr-util=/opt/fil --with-ssl=/opt/fil --enable-mpms-shared=all --with-mpm=prefork --enable-mods-shared=all --enable-so && make -j"$(nproc)" && make install ); \
    /opt/fil/apache/bin/httpd -v

# ---------------------------------------------------------------------------
# php: build PHP (cli + fpm + apache2handler) with Fil-C against the deps tree.
# ---------------------------------------------------------------------------
FROM deps AS php
ARG PHP_VERSION
# PHP_JIT=1 applies Filnix's OPcache + JIT-through-C patches: the JIT IR is
# emitted as C, compiled with filcc at run time and dlopen'ed, so generated
# code stays Fil-C-instrumented. Requires patches/php-<ver>-opcache-*.patch.
ARG PHP_JIT=0
COPY build.sh /build/build.sh
COPY versions.json /build/versions.json
COPY patches/ /build/patches/
RUN set -eux; \
    cd /build; \
    curl -fLO "https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz"; \
    php_sha=$(python3 -c 'import json,sys; print(next(v["sha256"] for v in json.load(open("/build/versions.json"))["versions"] if v["version"] == sys.argv[1]))' "$PHP_VERSION"); \
    echo "$php_sha  php-${PHP_VERSION}.tar.xz" | sha256sum -c -; \
    mkdir -p src && tar -xf "php-${PHP_VERSION}.tar.xz" -C src; \
    cd "src/php-${PHP_VERSION}"; \
    cve="/build/patches/cve-backports/php-${PHP_VERSION}-CVE-2026-109618-109619.patch"; \
    if [ -f "$cve" ]; then echo "applying CVE-2026-109618/109619 backport"; patch -p1 --silent -i "$cve"; fi; \
    patch -p1 --silent -i "/build/patches/php-${PHP_VERSION}-filc.patch"; \
    if [ "${PHP_JIT}" = 1 ]; then \
      patch -p1 --silent -i "/build/patches/php-${PHP_VERSION}-opcache-ce-cache-filc.patch"; \
      hybrid="/build/patches/php-${PHP_VERSION}-jit-hybrid-vm-filc.patch"; \
      if [ -f "$hybrid" ]; then patch -p1 --silent -i "$hybrid"; fi; \
      patch -p1 --silent -i "/build/patches/php-${PHP_VERSION}-opcache-jit-c-filc.patch"; \
      grep -q '#define ZEND_JIT_C_CC "clang"' ext/opcache/jit/zend_jit_c.c; \
      sed -i 's|#define ZEND_JIT_C_CC "clang"|#define ZEND_JIT_C_CC "/opt/fil/bin/filcc"|' ext/opcache/jit/zend_jit_c.c; \
    fi; \
    case "${PHP_VERSION}" in 5.*|7.2.*|7.3.*) sed -i -e 's/pharcmd=pharcmd$/pharcmd=/' -e 's/pharcmd_install=install-pharcmd$/pharcmd_install=/' configure ;; esac; \
    sed -i 's|PHP_INTL_CXX_FLAGS="\$INTL_COMMON_FLAGS \$PHP_INTL_STDCXX \$ICU_CXXFLAGS"|PHP_INTL_CXX_FLAGS="$INTL_COMMON_FLAGS $PHP_INTL_STDCXX $ICU_CXXFLAGS -std=c++17"|' configure; \
    case "${PHP_VERSION}" in \
      5.*|7.*|8.0.*) \
        echo "PHP ${PHP_VERSION}: building libxml 2.9 with Fil-C (optfil ships only 2.15, which EOL PHP cannot compile against)"; \
        curl -fL "https://download.gnome.org/sources/libxml2/2.9/libxml2-2.9.14.tar.xz" -o /tmp/lx.txz; \
        mkdir -p /tmp/lx && tar -xf /tmp/lx.txz -C /tmp/lx; \
        ( cd /tmp/lx/libxml2-2.9.14 && CC=/opt/fil/bin/filcc ./configure --prefix=/opt/fil --enable-shared --without-python >/dev/null && make -j"$(nproc)" >/dev/null && make install >/dev/null ); \
        ;; \
    esac; \
    case "${PHP_VERSION}" in \
      7.*) SSL_VER=1.1.1w; SSL_URL="https://www.openssl.org/source/old/1.1.1/openssl-1.1.1w.tar.gz"; SSL_SHA256=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8 ;; \
      5.*) SSL_VER=1.0.2u; SSL_URL="https://www.openssl.org/source/old/1.0.2/openssl-1.0.2u.tar.gz"; SSL_SHA256=ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16 ;; \
      *) SSL_VER="" ;; \
    esac; \
    if [ -n "$SSL_VER" ]; then \
      echo "PHP ${PHP_VERSION}: building OpenSSL ${SSL_VER} with Fil-C (EOL PHP cannot compile against bookworm OpenSSL 3.x)"; \
      curl -fL "$SSL_URL" -o /tmp/ssl.tgz; echo "$SSL_SHA256  /tmp/ssl.tgz" | sha256sum -c -; mkdir -p /tmp/ssl && tar -xf /tmp/ssl.tgz -C /tmp/ssl; \
      ( cd "/tmp/ssl/openssl-${SSL_VER}" && patch -p1 --silent -i "/build/patches/openssl-${SSL_VER}-filc-nist.patch" && CC=/opt/fil/bin/filcc ./Configure linux-x86_64 no-asm shared --prefix=/opt/fil --libdir=lib >/dev/null && sed -i -E 's/-Wl,--version-script=lib(crypto|ssl)\.map//g' Makefile && make -j"$(nproc)" build_libs >/dev/null && mkdir -p /opt/fil/lib /opt/fil/include && cp -a libssl.so* libcrypto.so* /opt/fil/lib/ && rm -rf /opt/fil/include/openssl && cp -aL include/openssl /opt/fil/include/ ); \
      printf 'prefix=/opt/fil\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: OpenSSL\nDescription: OpenSSL (Fil-C)\nVersion: %s\nLibs: -L${libdir} -lssl -lcrypto\nCflags: -I${includedir}\n' "$SSL_VER" > /opt/fil/lib/pkgconfig/openssl.pc; \
      if [ "${PHP_VERSION#7.4.}" != "${PHP_VERSION}" ]; then \
        ( cd "/tmp/onig-${ONIG_VER}" && patch -p1 --silent -i /build/patches/oniguruma-6.9.9-filc.patch && make -j"$(nproc)" >/dev/null && make install >/dev/null ); \
      fi; \
      curl -fL --retry 5 "https://curl.se/download/curl-8.11.1.tar.xz" -o /tmp/curl.tar.xz; \
      ( cd /tmp && tar -xf curl.tar.xz && cd curl-8.11.1 && \
        PKG_CONFIG_PATH=/opt/fil/lib/pkgconfig ./configure --prefix=/opt/fil --disable-static --with-openssl=/opt/fil --without-libpsl --without-nghttp2 >/dev/null && \
        sed -i 's/^global_symbol_pipe=""/global_symbol_pipe="cat"/' libtool && \
        sed -i 's/^am__append_6 = .*/am__append_6 =/' lib/Makefile && \
        make -j"$(nproc)" -C lib >/dev/null && make -C lib install >/dev/null ); \
    fi; \
    printf 'prefix=/opt/fil\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: sqlite3\nDescription: SQLite (Fil-C)\nVersion: 3.46.0\nLibs: -L${libdir} -lsqlite3\nCflags: -I${includedir}\n' > /opt/fil/lib/pkgconfig/sqlite3.pc; \
    case "${PHP_VERSION}" in \
      5.*|7.*) SSL_FLAGS="--with-openssl=/opt/fil"; EOL_FIXES="ac_cv_func_strlcpy=no"; BZ2_FLAG=""; EOL_CPPFLAGS="-I/opt/fil/include -D_DEFAULT_SOURCE" ;; \
      *) SSL_FLAGS="--with-openssl"; EOL_FIXES=""; BZ2_FLAG="--with-bz2"; EOL_CPPFLAGS="" ;; \
    esac; \
    if [ "${PHP_JIT}" = 1 ]; then OPCACHE_FLAGS=""; else OPCACHE_FLAGS="--disable-opcache-jit --disable-opcache"; fi; \
    case "${PHP_VERSION}" in \
      5.*|7.2.*|7.3.*) \
        session_flag="--enable-session"; \
        CPPFLAGS="${EOL_CPPFLAGS}" ./configure --prefix=/opt/php-filc \
          --disable-all --enable-cli --enable-fpm --with-apxs2=/opt/fil/apache/bin/apxs \
          --disable-cgi --without-pear --with-openssl=/opt/fil --with-zlib \
          --enable-json --enable-hash --enable-ctype --enable-filter \
          --enable-tokenizer --enable-phar --enable-fileinfo \
          --enable-mbstring --enable-pdo --with-mysqli=mysqlnd \
          --with-pdo-mysql=mysqlnd --enable-sockets --with-curl=/opt/fil \
          --enable-libxml --with-libxml-dir=/opt/fil --enable-dom --enable-xml \
          --enable-simplexml --with-sqlite3=/opt/fil --with-pdo-sqlite=/opt/fil \
          ${session_flag} ac_cv_what_readdir_r=POSIX; \
        ;; \
      *) \
    PKG_CONFIG_PATH=/opt/fil/lib/pkgconfig \
    PKG_CONFIG=/opt/fil/bin/pkg-config \
    CPPFLAGS="${EOL_CPPFLAGS}" CXXFLAGS="-std=c++17" LIBS="-lc++abi" \
    ./configure --prefix=/opt/php-filc \
      --enable-cli --enable-fpm --with-apxs2=/opt/fil/apache/bin/apxs \
      --disable-fiber-asm --without-pcre-jit ${OPCACHE_FLAGS} \
      --disable-cgi --disable-phpdbg \
      ${SSL_FLAGS} --with-zlib ${BZ2_FLAG} --with-curl \
      --with-sqlite3 --with-pdo-sqlite \
      --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
      --enable-mbstring --enable-intl --enable-sockets --enable-bcmath \
      --enable-exif --enable-ftp --enable-shmop --enable-sysvsem --enable-pcntl \
      --with-libedit \
      ac_cv_have_decl_UFFDIO_WRITEPROTECT_MODE_WP=no ${EOL_FIXES}; \
        ;; \
    esac; \
    case "${PHP_VERSION}" in 5.*|7.*) sed -i -e 's@ -I/usr/include @ @g' -e 's@ -I"/usr/include" @ @g' Makefile ;; esac; \
    make -j"$(nproc)"; \
    make install; \
    ls -la /opt/fil/apache/modules/libphp*.so

# ---------------------------------------------------------------------------
# runtime images
# ---------------------------------------------------------------------------
FROM ${DEBIAN_BASE} AS runtime
ARG DEBIAN_BASE
RUN if [ -f /etc/os-release ]; then . /etc/os-release; case "${VERSION_CODENAME}" in buster|stretch|jessie) printf 'deb http://archive.debian.org/debian %s main\ndeb http://archive.debian.org/debian-security %s/updates main\n' "$VERSION_CODENAME" "$VERSION_CODENAME" > /etc/apt/sources.list; printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/90nocheckvalid;; esac; fi
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && getent group www-data >/dev/null || groupadd -r --gid 82 www-data \
 && getent passwd www-data >/dev/null || useradd -r -u 82 -g 82 -s /usr/sbin/nologin www-data
COPY --from=php /opt/fil/lib/ /opt/fil/lib/
# PHP's compiled-in ini path is /opt/php-filc/lib; use a scan dir so the config
# survives the per-SAPI COPYs and matches the official images' conf.d pattern.
# session.upload_progress.enabled=0 is the CVE-2026-109619 mitigation (GHSA-6wmf-4rv5-p3rp).
ENV PHP_INI_SCAN_DIR=/usr/local/etc/php/conf.d
RUN mkdir -p /usr/local/etc/php/conf.d && printf '[PHP]\nmemory_limit = 512M\nupload_max_filesize = 64M\npost_max_size = 64M\nmax_execution_time = 300\ndate.timezone = UTC\nexpose_php = Off\npcre.jit = 0\nopcache.enable = 0\nsession.upload_progress.enabled = 0\n' > /usr/local/etc/php/conf.d/filc.ini

FROM runtime AS cli
COPY --from=php /opt/php-filc/bin/php /usr/local/bin/php
WORKDIR /var/www/html
ENTRYPOINT ["/usr/local/bin/php"]
CMD ["-v"]

FROM runtime AS fpm
COPY --from=php /opt/php-filc/bin/php /usr/local/bin/php
COPY --from=php /opt/php-filc/sbin/php-fpm /usr/local/sbin/php-fpm
COPY --from=php /opt/php-filc/etc/ /usr/local/etc/
RUN set -eux; \
    mkdir -p /usr/local/var/run /var/www/html; \
    cd /usr/local/etc; \
    [ -f php-fpm.conf ] || cp php-fpm.conf.default php-fpm.conf; \
    if [ -f php-fpm.d/www.conf.default ]; then \
      [ -f php-fpm.d/www.conf ] || cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
      sed -i 's|^include=.*|include=/usr/local/etc/php-fpm.d/*.conf|' php-fpm.conf; \
      pool=php-fpm.d/www.conf; \
    else \
      pool=php-fpm.conf; \
    fi; \
    sed -i '/^\[global\]/a error_log = /proc/self/fd/2\npid = /usr/local/var/run/php-fpm.pid' php-fpm.conf; \
    sed -i -E 's|^;?listen = .*|listen = 9000|; s|^;?clear_env = .*|clear_env = no|; s|^;?catch_workers_output = .*|catch_workers_output = yes|; s|^user = .*|user = www-data|; s|^group = .*|group = www-data|' "$pool"; \
    chown -R www-data:www-data /var/www/html /usr/local/var/run
EXPOSE 9000
WORKDIR /var/www/html
CMD ["/usr/local/sbin/php-fpm", "-F", "-O", "-y", "/usr/local/etc/php-fpm.conf"]

FROM runtime AS apache
COPY --from=php /opt/fil/apache/ /opt/fil/apache/
COPY --from=php /opt/php-filc/ /opt/php-filc/
RUN ln -sf /opt/php-filc/bin/php /usr/local/bin/php
# Adapt the httpd.conf that `make install` produced: listen on 8080, run as
# www-data, load mod_php, and serve .php from the default htdocs.
RUN set -eux; \
    conf=/opt/fil/apache/conf/httpd.conf; \
    sed -i -E 's|^Listen .*|Listen 8080|; s|^User .*|User www-data|; s|^Group .*|Group www-data|' "$conf"; \
    module=$(basename "$(find /opt/fil/apache/modules -maxdepth 1 -name 'libphp*.so' -print -quit)"); \
    case "$module" in libphp7.so) name=php7_module ;; libphp5.so) name=php5_module ;; libphp.so) name=php_module ;; *) exit 1 ;; esac; \
    sed -i '/^LoadModule php[0-9]*_module /d' "$conf"; \
    printf '\nLoadModule %s modules/%s\nAddType application/x-httpd-php .php\n<FilesMatch \.php$>\n  SetHandler application/x-httpd-php\n</FilesMatch>\nDirectoryIndex index.php\n' "$name" "$module" >> "$conf"; \
    printf '<?php echo "php-fil-c ok: ", PHP_VERSION, " on ", php_sapi_name(), "\\n";' \
      > /opt/fil/apache/htdocs/index.php
EXPOSE 8080
WORKDIR /var/www/html
CMD ["/opt/fil/apache/bin/httpd", "-DFOREGROUND"]

# ---------------------------------------------------------------------------
# jit variants: OPcache enabled (Fil-C persist fixes) + JIT-through-C. The
# image ships the Fil-C toolchain because the JIT compiles C per hot function
# at run time. Build with --build-arg PHP_JIT=1. Experimental.
# ---------------------------------------------------------------------------
FROM cli AS cli-jit
COPY --from=php /opt/fil/ /opt/fil/
COPY --from=php /opt/php-filc/lib/ /opt/php-filc/lib/
RUN set -eux; rm -rf /opt/fil/apache; \
    { so=$(find /opt/php-filc/lib/php/extensions -name opcache.so -print -quit 2>/dev/null || :); \
      if [ -n "$so" ]; then printf '[PHP]\nzend_extension = %s\n' "$so"; else printf '[PHP]\n'; fi; \
      printf 'opcache.enable = 1\nopcache.enable_cli = 0\nopcache.jit = 1235\nopcache.jit_buffer_size = 64M\n'; } \
      > /usr/local/etc/php/conf.d/zz-jit.ini; \
    /usr/local/bin/php -r 'exit(extension_loaded("Zend OPcache") && ini_get("opcache.enable") ? 0 : 1);'

FROM fpm AS fpm-jit
COPY --from=php /opt/fil/ /opt/fil/
COPY --from=php /opt/php-filc/lib/ /opt/php-filc/lib/
RUN set -eux; rm -rf /opt/fil/apache; \
    { so=$(find /opt/php-filc/lib/php/extensions -name opcache.so -print -quit 2>/dev/null || :); \
      if [ -n "$so" ]; then printf '[PHP]\nzend_extension = %s\n' "$so"; else printf '[PHP]\n'; fi; \
      printf 'opcache.enable = 1\nopcache.enable_cli = 0\nopcache.jit = 1235\nopcache.jit_buffer_size = 64M\n'; } \
      > /usr/local/etc/php/conf.d/zz-jit.ini; \
    /usr/local/bin/php -r 'exit(extension_loaded("Zend OPcache") && ini_get("opcache.enable") ? 0 : 1);'

# ---------------------------------------------------------------------------
# wordpress
# ---------------------------------------------------------------------------
FROM apache AS wordpress
ARG WORDPRESS_VERSION=7.1.3
ARG WORDPRESS_SHA256=d2a09acb6a15e3b9c471d72557753c266d6f41a79ed19bfe04cbfe49e283b2a5
ENV WORDPRESS_VERSION=${WORDPRESS_VERSION} \
    WORDPRESS_DB_HOST=db \
    WORDPRESS_DB_USER=wordpress \
    WORDPRESS_DB_NAME=wordpress \
    WORDPRESS_CONFIG_EXTRA=""
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz" -o /tmp/wp.tar.gz \
 && echo "${WORDPRESS_SHA256}  /tmp/wp.tar.gz" | sha256sum -c - \
 && rm -rf /opt/fil/apache/htdocs/* \
 && tar -xzf /tmp/wp.tar.gz -C /opt/fil/apache/htdocs --strip-components=1 \
 && rm /tmp/wp.tar.gz
COPY docker/wordpress/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENV WORDPRESS_PATH=/opt/fil/apache/htdocs
WORKDIR /opt/fil/apache/htdocs
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/opt/fil/apache/bin/httpd", "-DFOREGROUND"]
