# syntax=docker/dockerfile:1
#
# php-fil-c: PHP built from source with the Fil-C memory-safe C compiler.
#
# Two targets:
#   docker build --target cli -t php-fil-c:cli .
#   docker build --target fpm -t php-fil-c:fpm .
#
# The build context is produced by ./docker/prepare.sh (Fil-C runtime libs +
# the Fil-C-built PHP binaries). See README.md.

FROM debian:bookworm-slim AS base
COPY optfil-lib/ /opt/fil/lib/
# ca-certificates/tzdata only; no native PHP libs (Fil-C brings its own).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && getent group www-data >/dev/null || groupadd -r --gid 82 www-data \
 && getent passwd www-data >/dev/null || useradd -r -u 82 -g 82 -s /usr/sbin/nologin www-data
COPY conf/php.ini /usr/local/lib/php.ini

FROM base AS cli
COPY php-cli/bin/php /usr/local/bin/php
COPY php-cli/lib/php/extensions/ /usr/local/lib/php/extensions/
WORKDIR /var/www/html
ENTRYPOINT ["/usr/local/bin/php"]
CMD ["-v"]

FROM base AS fpm
COPY php-fpm/bin/php     /usr/local/bin/php
COPY php-fpm/sbin/php-fpm /usr/local/sbin/php-fpm
COPY php-fpm/etc/        /usr/local/etc/
COPY php-fpm/lib/php/extensions/ /usr/local/lib/php/extensions/
RUN mkdir -p /usr/local/var/run /var/www/html && chown -R www-data:www-data /var/www/html /usr/local/var/run
EXPOSE 9000
WORKDIR /var/www/html
CMD ["/usr/local/sbin/php-fpm", "-F", "-O", "-y", "/usr/local/etc/php-fpm.conf"]
