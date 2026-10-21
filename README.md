<p align="center">
  <img src="docs/header.svg" alt="php-fil-c" width="900"/>
</p>

<p align="center">
  <em>memory-safe PHP, from source.</em>
</p>

<p align="center">
PHP 8.4 compiled with <a href="https://fil-c.org">Fil-C</a> -- capability-based
memory safety, no <code>unsafe</code>, runs on stock x86_64 Linux.
</p>

[![build-and-publish](https://github.com/hjanuschka/php-fil-c/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/hjanuschka/php-fil-c/actions/workflows/build-and-publish.yml)
![PHP](https://img.shields.io/badge/PHP-8.4.27-777BB4?logo=php&logoColor=white)
![Fil-C](https://img.shields.io/badge/Fil--C-0.686-2ea44f)
![platform](https://img.shields.io/badge/platform-linux%20amd64-lightgrey)
![license](https://img.shields.io/badge/license-PHP--3.0-blue)

</div>

---

Prebuilt, **patched** PHP images (CLI and FPM) plus a from-source build script,
all compiled with [Fil-C](https://fil-c.org) -- a memory-safe C compiler that
catches every out-of-bounds, use-after-free and type confusion as a panic
instead of letting it become an exploit.

> **Security status.** The published images are built from **PHP 8.4.27**, the
> first 8.4 release containing the fixes for
> [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
> and [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
> The earlier 8.4.25 build in this repo's history is **vulnerable** and is no
> longer built or published. Fil-C is defence-in-depth, **not** a substitute for
> PHP security updates -- see [Security](#security).

## Images

Hosted on GitHub Container Registry. `linux/amd64`.

```sh
# CLI
docker run --rm ghcr.io/hjanuschka/php-fil-c:cli-bookworm -v
docker run --rm -v "$PWD:/var/www/html" ghcr.io/hjanuschka/php-fil-c:cli-bookworm script.php

# FPM (port 9000, front it with nginx/Apache)
docker run -d -p 127.0.0.1:9000:9000 ghcr.io/hjanuschka/php-fil-c:fpm-bookworm
```

| Tag | SAPI | PHP |
|-----|------|-----|
| `cli-bookworm`, `8-cli-bookworm`, `8.4-cli-bookworm`, `8.4.27-cli-bookworm` | CLI | 8.4.27 |
| `fpm-bookworm`, `8-fpm-bookworm`, `8.4-fpm-bookworm`, `8.4.27-fpm-bookworm` | FPM | 8.4.27 |

Built by the [`build-and-publish`](../../actions/workflows/build-and-publish.yml)
workflow from this repo's `build.sh` + `docker/`.

### nginx + FPM example

```yaml
# docker-compose.yml
services:
  fpm:
    image: ghcr.io/hjanuschka/php-fil-c:fpm-bookworm
    volumes: [./app:/var/www/html]
  nginx:
    image: nginx:alpine
    ports: ["8080:80"]
    volumes:
      - ./app:/var/www/html:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
```

```nginx
# nginx.conf
server {
  listen 80; root /var/www/html; index index.php;
  location ~ \.php$ {
    fastcgi_pass fpm:9000;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME /var/www/html$fastcgi_script_name;
  }
}
```

## Build from source

Prerequisite: the Fil-C `/opt/fil` glibc distribution (the glibc build is
required -- fibers use `ucontext`, which Fil-C only implements in its glibc).

```sh
curl -LO https://github.com/pizlonator/fil-c/releases/download/v0.686/optfil-0.686-linux-x86_64.tar.xz
tar -xf optfil-0.686-linux-x86_64.tar.xz
cd optfil-0.686-linux-x86_64 && sudo ./setup.sh -u     # installs to /opt/fil
```

Then:

```sh
./build.sh                       # downloads, patches, compiles, installs to ./install
./install/bin/php -v
```

`build.sh` pins the PHP tarball by sha256, applies
`patches/php-8.4.27-filc.patch`, configures with `CC=/opt/fil/bin/filcc`, and
runs a smoke test (WeakMap, fibers, `Dom\HTMLDocument`, overflow arithmetic,
tracked allocator). It prints `php ok` on success.

Build your own image:

```sh
./docker/prepare.sh              # assemble docker/ context from ./install
docker build --target cli -t php-fil-c:cli docker
docker build --target fpm -t php-fil-c:fpm docker
```

## What Fil-C changes here

Fil-C is a drop-in C compiler (clang 20 based) that gives every pointer a
hidden capability and checks every access. PHP needs a small port patch (all
`#ifdef __FILC__`, a no-op for normal builds) for the places that store
pointers as integers or use tricky asm:

- **Pointer-as-integer sites** -- weakref/WeakMap keys, typed-property source
  lists, and ext/dom's bundled lexbor name IDs are retagged via pointer
  arithmetic or a weak `zexact_ptrtable`.
- **Inline asm** -- portable C paths for `zend_safe_address`, string compare
  and `fast_long_*`; `xgetbv` spelled as an instruction.
- **Fibers** -- built `--disable-fiber-asm` so fibers use `ucontext`.
- **OPcache** -- shared memory mapped `MAP_PRIVATE` (capabilities are
  per-process).
- **Allocator** -- defaults to PHP's tracked system allocator so each value
  gets its own capability and use-after-free between values is caught.

Adapted from the upstream
[`php.projeny`](https://github.com/pizlonator/fil-c/blob/deluge/projects/php.projeny)
port by Filip Pizlo.

## Known limitations

- **No JIT.** `--without-pcre-jit --disable-opcache-jit` -- Fil-C cannot
  execute generated machine code.
- **OPcache off by default.** The port currently panics when OPcache persists
  certain classes; the images ship `opcache.enable=0`. Tracked in the repo.
- **Performance.** Capability checks + GC make PHP noticeably slower than
  native. This is a safety research build, not a production replacement.
- **Extensions not built** (no Fil-C-built lib in `/opt/fil`): gd, sqlite3,
  xsl, ldap, gmp.
- **`linux/amd64` only** for now.

## Security

Fil-C turns memory-safety violations (the OOB read, the use-after-free) into a
**panic** rather than an exploitable primitive, which is exactly the class of
bug behind the recent PHP session/OOM RCEs. It does **not** fix the underlying
logic, and a stale pointer kept alive by the GC may not panic at all -- so the
images are built from **patched** PHP, and Fil-C is layered on top as
defence-in-depth.

`experiments/filc-vs-rce/` documents an attempt to reproduce the
[CVE-2026-109618/109619](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
mechanism against unpatched Fil-C PHP.

## Layout

```
build.sh                 one-shot source build + smoke test
patches/                 Fil-C port patch per PHP version
docker/                  Dockerfile (cli + fpm targets), prepare.sh, php.ini
.github/workflows/       build-and-publish (GHCR)
experiments/             Fil-C vs PHP RCE experiment + results
PLAN.md                  release/security plan
```

## License

PHP is PHP-3.0. Fil-C is LLVM/PAS licensed. This repo's scripts: MIT.
