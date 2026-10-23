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
COPY build.sh /build/build.sh
COPY versions.json /build/versions.json
COPY patches/ /build/patches/
RUN set -eux; \
    cd /build; \
    curl -fLO "https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz"; \
    mkdir -p src && tar -xf "php-${PHP_VERSION}.tar.xz" -C src; \
    cd "src/php-${PHP_VERSION}"; \
    patch -p1 --silent -i "/build/patches/php-${PHP_VERSION}-filc.patch"; \
    printf 'prefix=/opt/fil\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: sqlite3\nDescription: SQLite (Fil-C)\nVersion: 3.46.0\nLibs: -L${libdir} -lsqlite3\nCflags: -I${includedir}\n' > /opt/fil/lib/pkgconfig/sqlite3.pc; \
    PKG_CONFIG_PATH=/opt/fil/lib/pkgconfig \
    PKG_CONFIG=/opt/fil/bin/pkg-config \
    ./configure --prefix=/opt/php-filc \
      --enable-cli --enable-fpm --with-apxs2=/opt/fil/apache/bin/apxs \
      --disable-fiber-asm --without-pcre-jit --disable-opcache-jit --disable-opcache \
      --with-openssl --with-zlib --with-bz2 --with-curl \
      --with-sqlite3 --with-pdo-sqlite \
      --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
      --enable-mbstring --enable-intl --enable-sockets --enable-bcmath \
      --enable-exif --enable-ftp --enable-shmop --enable-sysvsem --enable-pcntl \
      --with-libedit \
      ac_cv_have_decl_UFFDIO_WRITEPROTECT_MODE_WP=no; \
    make -j"$(nproc)"; \
    make install; \
    ls -la /opt/fil/apache/modules/libphp.so

# ---------------------------------------------------------------------------
# runtime images
# ---------------------------------------------------------------------------
FROM ${DEBIAN_BASE} AS runtime
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && getent group www-data >/dev/null || groupadd -r --gid 82 www-data \
 && getent passwd www-data >/dev/null || useradd -r -u 82 -g 82 -s /usr/sbin/nologin www-data
COPY --from=php /opt/fil/lib/ /opt/fil/lib/
RUN printf '[PHP]\nmemory_limit = 512M\nupload_max_filesize = 64M\npost_max_size = 64M\nmax_execution_time = 300\ndate.timezone = UTC\nexpose_php = Off\n' > /usr/local/lib/php.ini

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
    mkdir -p php-fpm.d; \
    [ -f php-fpm.d/www.conf ] || cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
    sed -i 's|^include=.*|include=/usr/local/etc/php-fpm.d/*.conf|' php-fpm.conf; \
    sed -i '/^\[global\]/a error_log = /proc/self/fd/2\npid = /usr/local/var/run/php-fpm.pid' php-fpm.conf; \
    sed -i -E 's|^;?listen = .*|listen = 9000|; s|^;?clear_env = .*|clear_env = no|; s|^;?catch_workers_output = .*|catch_workers_output = yes|; s|^user = .*|user = www-data|; s|^group = .*|group = www-data|' php-fpm.d/www.conf; \
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
    printf '\nLoadModule php_module modules/libphp.so\nAddType application/x-httpd-php .php\n<FilesMatch \.php$>\n  SetHandler application/x-httpd-php\n</FilesMatch>\nDirectoryIndex index.php\n' >> "$conf"; \
    printf '<?php echo "php-fil-c ok: ", PHP_VERSION, " on ", php_sapi_name(), "\\n";' \
      > /opt/fil/apache/htdocs/index.php
EXPOSE 8080
WORKDIR /var/www/html
CMD ["/opt/fil/apache/bin/httpd", "-DFOREGROUND"]

# ---------------------------------------------------------------------------
# wordpress: drop-in for the official `wordpress` image. Same env contract
# (WORDPRESS_DB_HOST/USER/PASSWORD/NAME, WORDPRESS_* ), Fil-C PHP + Apache.
# ---------------------------------------------------------------------------
FROM apache AS wordpress
ARG WORDPRESS_VERSION=6.7.1
ENV WORDPRESS_VERSION=${WORDPRESS_VERSION} \
    WORDPRESS_DB_HOST=db \
    WORDPRESS_DB_USER=wordpress \
    WORDPRESS_DB_PASSWORD=wordpress \
    WORDPRESS_DB_NAME=wordpress \
    WORDPRESS_CONFIG_EXTRA=""
RUN apt-get update && apt-get install -y --no-install-recommends less mariadb-client curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz" -o /tmp/wp.tar.gz \
 && rm -rf /opt/fil/apache/htdocs/* \
 && tar -xzf /tmp/wp.tar.gz -C /opt/fil/apache/htdocs --strip-components=1 \
 && rm /tmp/wp.tar.gz \
 && curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
 && chmod +x /usr/local/bin/wp
COPY docker/wordpress/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENV WORDPRESS_PATH=/opt/fil/apache/htdocs
WORKDIR /opt/fil/apache/htdocs
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/opt/fil/apache/bin/httpd", "-DFOREGROUND"]
