# php-fil-c

> **Security hold:** The 8.4.25 build described below is affected by
> [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
> and [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
> Do not use it for untrusted input or deploy it. No Docker images have been
> published. A port to patched PHP 8.4.27 is in progress; the build is disabled
> until its OPcache regressions are resolved. Rebuild existing installs once a
> validated release is available.

PHP 8.4 built from source with [Fil-C](https://fil-c.org/), the memory-safe
C/C++ compiler (capability-based memory safety, GC-backed, runs on stock
x86_64/ARM64 Linux).

This repo contains a standalone build script and the patch needed to compile
PHP with Fil-C, adapted from the upstream
[`php.projeny`](https://github.com/pizlonator/fil-c/blob/deluge/projects/php.projeny)
port by Filip Pizlo.

## Status

- PHP 8.4.25, CLI + FPM + OPcache (no JIT), built with Fil-C 0.686
- `Zend/tests`: 4863/4865 pass (1 perf-sensitive timeout, see Caveats)
- `ext/openssl`, `ext/json`, `ext/filter`: 407/407 pass (3 expected fails)
- Verified working: WeakMap, fibers (ucontext), `Dom\HTMLDocument` (lexbor),
  opcache, openssl, curl, intl, mbstring, bz2, readline, pcntl, sockets

## Prerequisites

1. Linux x86_64 (or use the aarch64 Fil-C build).
2. The Fil-C `/opt/fil` glibc distribution. The glibc-based distro is required
   (not the classic musl one) because the port runs fibers on `ucontext`,
   which Fil-C only implements in its glibc:

   ```sh
   curl -LO https://github.com/pizlonator/fil-c/releases/download/v0.686/optfil-0.686-linux-x86_64.tar.xz
   tar -xf optfil-0.686-linux-x86_64.tar.xz
   cd optfil-0.686-linux-x86_64 && sudo ./setup.sh -u   # installs to /opt/fil
   ```

   `/opt/fil` also provides everything the PHP build links against
   (openssl, zlib, bzip2, curl, libxml2, icu, libedit, pcre2), all compiled
   with Fil-C.

## Build

```sh
./build.sh                       # -> ./install (default PREFIX)
PREFIX=/opt/php-fil-c ./build.sh # or pick a prefix
```

`build.sh` downloads `php-8.4.25.tar.xz`, verifies the sha256, applies
`patches/php-8.4.25-filc.patch`, configures with `CC=/opt/fil/bin/filcc`,
builds, installs, and runs a smoke test exercising exactly the code the patch
touches (WeakMap keys, fiber stack limits, lexbor name IDs, overflow
arithmetic, opcache, the tracked allocator). It prints `php ok` on success.

## Use

```sh
./install/bin/php -v
./install/bin/php script.php
./install/sbin/php-fpm            # copy etc/php-fpm.conf.default if missing
```

The binary is dynamically linked against the Fil-C runtime and libc
(`/opt/fil/lib/ld-fil1-x86_64.so` is the interpreter), so keep `/opt/fil`
around.

Memory-safety violations in PHP's own C code (or extensions) abort as a Fil-C
panic instead of being exploitable UB, e.g.:

```
filc safety error: cannot read pointer with null object.
filc panic: thwarted a futile attempt to violate memory safety.
```

## What the patch does

All changes are guarded by `#ifdef __FILC__`, so the patch is a no-op for
normal builds. In short (details in the patch header):

- **Pointer-as-integer sites.** Fil-C drops a pointer's capability when it is
  cast to an integer. The patch retags the places that store pointers as
  integers: weakref/WeakMap keys and typed-property source lists (tagged via
  pointer arithmetic or a weak `zexact_ptrtable`), and ext/dom's bundled
  lexbor name IDs.
- **Inline asm.** Uses portable C paths for `zend_safe_address`, string
  compare, and `fast_long_*` (Fil-C crashes on the `asm goto` variants), and
  spells `xgetbv` as an instruction.
- **Fibers.** Built `--disable-fiber-asm` so fibers use `ucontext`; the fiber
  stack limit is measured from the fiber's first frame.
- **OPcache.** The shared memory segment is mapped `MAP_PRIVATE` because
  capabilities are per-process; `opcache_reset()`/`opcache_invalidate()`
  become per-process.
- **Allocator.** Defaults to PHP's *tracked system allocator* (like PHP's
  ASan CI config) instead of Zend's 2 MiB-chunk allocator, so every PHP value
  gets its own capability and use-after-free between values is caught.
  `USE_ZEND_ALLOC=1` restores Zend's allocator (weaker safety),
  `USE_TRACKED_ALLOC=0` untracked malloc.

## Caveats

- **No JIT.** `--without-pcre-jit --disable-opcache-jit`: Fil-C cannot execute
  generated machine code.
- **Performance.** Capability checks + GC make PHP noticeably slower than
  native. `Zend/tests/concat_003.phpt` (a perf-sensitive string-concat test)
  times out; set `SKIP_PERF_SENSITIVE=1` when running the suite.
- **OPcache semantics.** With FPM, cached scripts are inherited at fork;
  `opcache_reset()` only affects the calling worker.
- **phpdbg** is not usable (userfaultfd unsupported); configure is told so.
- Extensions not built here (no Fil-C-built libs in `/opt/fil`): gd, sqlite3,
  xsl, ldap, gmp. Everything else in the configure line works.

## Layout

```
build.sh                        one-shot build + smoke test
patches/php-8.4.25-filc.patch   the Fil-C port patch (from upstream php.projeny)
download/, src/, install/       created by build.sh (gitignored)
```

## License

PHP is PHP-3.0 (see `src/LICENSE`). The Fil-C distribution is LLVM/PAS
licensed. This repo's scripts: MIT.
