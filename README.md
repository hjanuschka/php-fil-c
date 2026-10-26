<p align="center">
  <img src="docs/header.svg" alt="php-fil-c" width="900"/>
</p>

<p align="center">
  <em>memory-safe PHP, from source -- a safe haven while PHP has a hard time.</em>
</p>

<p align="center">
PHP built with <a href="https://fil-c.org">Fil-C</a>: capability-based memory
safety turns every out-of-bounds, use-after-free and type confusion into a
panic instead of an exploit. Drop-in <code>php</code> / <code>wordpress</code>
Docker images, rebuilt the day a PHP CVE lands.
</p>

<p align="center">
<a href="https://github.com/hjanuschka/php-fil-c/actions/workflows/build-and-publish.yml"><img src="https://github.com/hjanuschka/php-fil-c/actions/workflows/build-and-publish.yml/badge.svg" alt="build-and-publish"/></a>
<img src="https://img.shields.io/badge/PHP-8.0--8.5-777BB4?logo=php&logoColor=white" alt="PHP"/>
<img src="https://img.shields.io/badge/Fil--C-0.686-2ea44f" alt="Fil-C"/>
<img src="https://img.shields.io/badge/CVE--2026--109618%20%2B%20109619-patched-b31d1c" alt="CVE patched"/>
<img src="https://img.shields.io/badge/platform-linux%20amd64-lightgrey" alt="platform"/>
<img src="https://img.shields.io/badge/license-PHP--3.0-blue" alt="license"/>
</p>

---

## Support matrix

The **8.2 - 8.5** builds are compiled from the PHP releases that fix the two
request-handling RCEs -- **CVE-2026-109618** (OOM corruption,
[GHSA-w8hw-w9fx-j79w](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w))
and **CVE-2026-109619** (stale global state,
[GHSA-6wmf-4rv5-p3rp](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)).
Every image also ships the advisory's `session.upload_progress.enabled=0`
mitigation. The **8.0** and **8.1** builds use the tracked EOL backports in
[`patches/cve-backports/`](patches/cve-backports/); these fixes were not
released by upstream PHP for those branches.

| PHP | Release | CVE fixes | Fil-C patch | CLI | FPM | Apache (mod_php) | WordPress | Tags |
|-----|---------|:---------:|-------------|:---:|:---:|:----------------:|:---------:|------|
| **8.5.12** | 2026-10 | ✅ 109618 · 109619 | [`php-8.5.12-filc.patch`](patches/php-8.5.12-filc.patch) | ✅ | ✅ | ✅ | ✅ | stable |
| **8.4.27** | 2026-10 | ✅ 109618 · 109619 | [`php-8.4.27-filc.patch`](patches/php-8.4.27-filc.patch) | ✅ | ✅ | ✅ | ✅ | stable (default) |
| **8.3.36** | 2026-10 | ✅ 109618 · 109619 | [`php-8.3.36-filc.patch`](patches/php-8.3.36-filc.patch) | ✅ | ✅ | ✅ | ✅ | stable |
| **8.2.35** | 2026-10 | ✅ 109618 · 109619 | [`php-8.2.35-filc.patch`](patches/php-8.2.35-filc.patch) | ✅ | ✅ | ✅ | ✅ | stable |
| **8.1.32** | EOL | ✅ backported 109618 · 109619 | [`php-8.1.32-filc.patch`](patches/php-8.1.32-filc.patch) | ✅ | ✅ | ✅ | ✅ | stable |
| **8.0.30** | EOL | ✅ backported 109618 · 109619 | [`php-8.0.30-filc.patch`](patches/php-8.0.30-filc.patch) | ✅ | ✅ | ✅ | ✅ | stable |
| **7.4.33** | EOL | ✅ backported 109618 · 109619 | [`php-7.4.33-filc.patch`](patches/php-7.4.33-filc.patch) | ✅ | ✅ | ✅ | ✅ | [experimental](#opt-in-experimental-legacy-tags) |
| **7.3.33** | EOL | ✅ backported 109618 · 109619 | [`php-7.3.33-filc.patch`](patches/php-7.3.33-filc.patch) | ✅ | ✅ | ✅ | ✅ | [experimental](#opt-in-experimental-legacy-tags) |
| **7.2.34** | EOL | ✅ backported 109618 · 109619 | [`php-7.2.34-filc.patch`](patches/php-7.2.34-filc.patch) | ✅ | ✅ | ✅ | ✅ | [experimental](#opt-in-experimental-legacy-tags) |
| **5.6.40** | EOL | ✅ backported 109618 · 109619 | [`php-5.6.40-filc.patch`](patches/php-5.6.40-filc.patch) | ✅ | ✅ | ✅ | ✅ | [experimental](#opt-in-experimental-legacy-tags) |
| older 5.x | EOL | backport pending | none | ⏳ | ⏳ | ⏳ | ⏳ | none |

Legend: ✅ published and CI-smoke-tested (WordPress install + admin login,
HTTPS, hardening checks) · ⏳ no port. `stable` tags are the supported
matrix; `experimental` tags run EOL PHP + EOL OpenSSL and are **not for
production** -- see the per-version notes below.
`versions.json` is the machine-readable source of truth for this table.

**Why these versions?** 8.2.35, 8.3.36, 8.4.27 and 8.5.12 are exactly the
releases PHP shipped the two RCE fixes in. Older lines (8.1, 8.0, 7.4,
7.3, 7.2, 5.6) are EOL and did not get the fixes upstream, so supporting
those lines means backporting the CVE patches *and* the Fil-C port, plus
building libxml/OpenSSL versions that old PHP can compile against inside
the image -- see [PLAN.md](PLAN.md).

**7.4 is published as experimental.** CLI/FPM/Apache and WordPress 7.1.3
pass CI, including installation and admin login over MariaDB. The Fil-C
OpenSSL 1.1.1w port avoids capability-losing pointer masks in NIST reductions;
HTTPS curl and NIST modulus correctness tests pass. Its constant-time
properties are not independently reviewed, and OpenSSL 1.1.1w is EOL.
The EOL PHP CVE/multipart backports apply; the tracked Fil-C allocator
enforces `memory_limit` and reports usage across repeated requests.
The build omits bz2 until a Fil-C-built libbz2 is available.

**7.3 and 7.2 are published as experimental.** CLI/FPM/Apache images and
WordPress 6.9.10 installation and admin login pass CI with MariaDB. Fil-C
OpenSSL 1.1.1w passes HTTPS curl smoke tests; tracked allocations enforce
`memory_limit` and report nonzero usage. EOL PHP CVE/multipart backports
apply, but the legacy OpenSSL port and security regression testing require
review. Do not expose these experimental images to untrusted requests.

**5.6 is published as experimental.** A selected-extension `--disable-all`
image runs WordPress 6.2.14 with MariaDB in CI, including installation,
serving a page and authenticated admin dashboard. Session is enabled
with upload progress disabled, and tracked Fil-C allocations enforce
`memory_limit`. The PHP CVE/multipart backports apply and patched OpenSSL
1.0.2u passes HTTPS smoke tests. OpenSSL 1.0.2u is long EOL; the NIST
timing behavior and unbackported security issues need review. Do not
process untrusted requests with it.
PCRE JIT is disabled in runtime images because Fil-C cannot allocate
executable JIT memory; otherwise WordPress login can emit warnings before
setting authentication cookies.

### Opt-in experimental legacy tags

PHP 7.4.33, 7.3.33, 7.2.34 and 5.6.40 are published under tags ending in
`-bookworm-experimental`, for example
`ghcr.io/hjanuschka/php-fil-c:7.2.34-wordpress-bookworm-experimental`.
Each pairs with the newest WordPress its PHP supports: 7.1.3 on PHP 7.4,
6.9.10 on 7.3/7.2, and 6.2.14 on 5.6. Rebuild and republish them by
running `build-and-publish` manually with `experimental: true`; every
image must pass the same CI smoke gates (WordPress install + admin login,
HTTPS, hardening checks) before it is pushed. They never receive stable
version, series or default tags, and remain `pending` in `versions.json`.
These images contain end-of-life OpenSSL with unreviewed cryptographic
timing properties; **do not use them for production or untrusted
traffic**. Earlier PHP 5.x versions have no Fil-C port or matrix entry.

## Images

`ghcr.io/hjanuschka/php-fil-c`, `linux/amd64`. Tags are
`<php>-<sapi>-bookworm` (plus `<minor>-<sapi>-bookworm` and a bare
`<sapi>-bookworm` for the default).

```sh
# CLI
docker run --rm ghcr.io/hjanuschka/php-fil-c:8.4-cli-bookworm -v
# FPM (port 9000)
docker run -d -p 127.0.0.1:9000:9000 ghcr.io/hjanuschka/php-fil-c:8.4-fpm-bookworm
# Apache + mod_php (port 8080) -- Apache itself is built with Fil-C
docker run -d -p 127.0.0.1:8080:8080 ghcr.io/hjanuschka/php-fil-c:8.4-apache-bookworm
# WordPress (needs MariaDB; env contract matches the official image)
docker run -d -p 127.0.0.1:8080:8080 \
  -e WORDPRESS_DB_HOST=db -e WORDPRESS_DB_USER=wp \
  -e WORDPRESS_DB_PASSWORD="$WP_DB_PASSWORD" -e WORDPRESS_DB_NAME=wp \
  ghcr.io/hjanuschka/php-fil-c:8.4-wordpress-bookworm
```

The Apache image runs the **whole process on Fil-C**: APR, APR-util, httpd and
mod_php are all compiled with `filcc`, so there is no native/Fil-C libc mixing.
The WordPress image uses the official `WORDPRESS_DB_*` environment contract.
It requires `WORDPRESS_DB_PASSWORD`, generates `wp-config.php` with random
salts, then leaves site installation to the administrator. It never creates
a default admin account; WP-CLI is not bundled. Keep the installer private
until the administrator finishes setup, since anyone who can reach it first
could choose the admin credentials.

### WordPress + MariaDB

```yaml
# docker-compose.yml
services:
  db:
    image: mariadb:11.4
    environment:
      MARIADB_DATABASE: wordpress
      MARIADB_USER: wp
      MARIADB_PASSWORD: ${WP_DB_PASSWORD:?Set WP_DB_PASSWORD}
      MARIADB_ROOT_PASSWORD: ${WP_ROOT_PASSWORD:?Set WP_ROOT_PASSWORD}
  wordpress:
    image: ghcr.io/hjanuschka/php-fil-c:8.4-wordpress-bookworm
    ports: ["127.0.0.1:8080:8080"]
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wp
      WORDPRESS_DB_PASSWORD: ${WP_DB_PASSWORD:?Set WP_DB_PASSWORD}
      WORDPRESS_DB_NAME: wordpress
    depends_on: [db]
```

Open `http://localhost:8080` to complete the WordPress installer and choose
a unique admin password. Do not expose an uninstalled site to the public.

Only PHP runs under Fil-C; MariaDB runs in its own container over TCP.
PHP 7.2's mysqlnd cannot authenticate with MySQL 8.4's default
`caching_sha2_password`, so the older images use MariaDB here.

## Build from source

Everything builds inside Docker (no host toolchain needed):

```sh
docker build -f docker/Dockerfile --target cli     --build-arg PHP_VERSION=8.4.27 -t php-filc:cli .
docker build -f docker/Dockerfile --target fpm     --build-arg PHP_VERSION=8.4.27 -t php-filc:fpm .
docker build -f docker/Dockerfile --target apache  --build-arg PHP_VERSION=8.4.27 -t php-filc:apache .
docker build -f docker/Dockerfile --target wordpress --build-arg PHP_VERSION=8.4.27 -t php-filc:wordpress .
```

The `deps` stage compiles expat, APR, APR-util, httpd, SQLite and oniguruma
with Fil-C; the `php` stage compiles PHP (cli + fpm + apache2handler) against
them. To add a version: drop `patches/php-<ver>-filc.patch`, add a
`versions.json` entry, build.

`build.sh` is a standalone host build (needs `/opt/fil`) if you prefer not to
use Docker.

## What Fil-C changes here

Fil-C is a drop-in C compiler (clang-based) that gives every pointer a hidden
capability and checks every access. PHP needs a small port patch (all
`#ifdef __FILC__`, a no-op for normal builds) for the places that store
pointers as integers or use tricky asm:

- **Pointer-as-integer sites** -- weakref/WeakMap keys and typed-property
  source lists are retagged via pointer arithmetic or a weak `zexact_ptrtable`.
- **Inline asm** -- portable C paths for `zend_safe_address`, string compare
  and `fast_long_*`.
- **Fibers** -- built `--disable-fiber-asm` so fibers use `ucontext`.
- **Allocator** -- defaults to PHP's tracked system allocator so each value
  gets its own capability and use-after-free between values is caught.

Adapted from the upstream
[`php.projeny`](https://github.com/pizlonator/fil-c/blob/deluge/projects/php.projeny)
port by Filip Pizlo, and informed by
[Filnix](https://github.com/mbrock/filnix).

## Known limitations

- **No JIT.** `--without-pcre-jit --disable-opcache-jit` -- Fil-C cannot
  execute generated machine code. A JIT-through-C path exists upstream
  ([PLAN.md](PLAN.md) P1).
- **OPcache off.** The port panics when OPcache persists certain classes
  (`zend_accel_pending_ce_cache_commit` writes through a null object).
  Builds pass `--disable-opcache`, and since PHP 8.5 compiles OPcache
  unconditionally, images also ship `opcache.enable=0`.
- **Performance.** Capability checks + GC make PHP ~1.5-4x slower than native.
  This is a safety research build, not a production drop-in for throughput.
- **Extensions not yet built** (no Fil-C lib in `/opt/fil`): gd, zip, sodium,
  xsl, ldap, gmp. mysqli/pdo_mysql (mysqlnd), pdo_sqlite/sqlite3, curl, dom,
  xml, mbstring, intl, openssl are built.
- **`linux/amd64` only** for now.

## Security

Fil-C turns memory-safety violations (the OOB read, the use-after-free) into a
**panic** rather than an exploitable primitive -- exactly the bug class behind
the recent PHP session/OOM RCEs. It does **not** fix the underlying logic, and
a stale pointer kept alive by the GC may not panic at all. Published images
use **patched** PHP with Fil-C layered on top as defence-in-depth. Experimental
legacy tags include EOL PHP and OpenSSL and are not CVE-complete or production-safe.

Every image with the session extension sets `session.upload_progress.enabled = 0`,
the mitigation recommended in GHSA-6wmf-4rv5-p3rp for CVE-2026-109619.

## Layout

```
versions.json            build matrix: version -> tarball sha256 + patch + status
patches/                 Fil-C port patch per PHP version
docker/Dockerfile        multi-stage build: deps -> php -> cli/fpm/apache/wordpress
docker/wordpress/        WordPress entrypoint (env -> wp-config)
build.sh                 standalone host build + smoke test
.github/workflows/       build-and-publish (GHCR matrix)
PLAN.md                  roadmap: adopt Filnix patches, JIT, per-version branches
```

## License

PHP is PHP-3.0. Fil-C is LLVM/PAS licensed. This repo's scripts: MIT.
