FROM debian:bookworm-slim

# Fil-C runtime (loader + capability/GC runtime + Fil-C-built libs the PHP links against)
COPY optfil-lib/ /opt/fil/lib/

# PHP built with Fil-C (unpatched 8.4.25 for this experiment)
COPY php-install/ /usr/local/

# opcache extension lives under the standard extension_dir layout
ENV PHP_EXTENSION_DIR=/usr/local/lib/php/extensions

# No LD_LIBRARY_PATH: the php binary's PT_INTERP is
# /opt/fil/lib/ld-fil1-x86_64.so, which finds its own libs. Exporting
# LD_LIBRARY_PATH would leak Fil-C libs into system tools and break them.

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -r -u 65534 -s /usr/sbin/nologin www-data 2>/dev/null || true

WORKDIR /app
COPY exploit/ /app/exploit/

CMD ["/usr/local/bin/php", "-v"]
