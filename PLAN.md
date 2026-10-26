# php-fil-c — Roadmap & Spec

Goal: a maintainable "safe haven" that publishes memory-safe PHP (built with
[Fil-C](https://fil-c.org)) as drop-in Docker images — CLI, FPM, Apache
(mod_php), and a WordPress image — across PHP 7.x → latest, reproducible so a
new PHP CVE is a version bump + rebuild.

---

## 0. Current state (what already works)

Everything below is built **entirely in Docker** (`docker/Dockerfile`,
multi-stage) and verified locally:

- **8.4.27** Fil-C: `cli`, `fpm`, `apache` (mod_php), and **WordPress 6.7**
  serving a live site (native MySQL over TCP; only PHP runs under Fil-C).
- Fil-C-built dependency stack in `/opt/fil`: expat, APR, APR-util, httpd
  2.4.62, SQLite, oniguruma.
- Extensions working: mysqli, pdo_mysql, pdo_sqlite, sqlite3, curl, dom,
  SimpleXML, xml, xmlreader, xmlwriter, mbstring, intl, fileinfo, openssl,
  zlib, bz2, exif, ftp, sockets, pcntl, bcmath.
- `versions.json` is the single source of truth for the matrix.

Key build tricks discovered (encoded in the Dockerfile):
- Fil-C's `ld` auto-loads the host GCC LTO plugin (needs `libc.so.6`) and
  fails; use plain `filcc` and keep optfil's `ld` off `PATH`.
- APR's generated libtool leaves `global_symbol_pipe=""`, breaking httpd's
  shared-module link (`nm … |  | sed`); set it to `cat`.
- PHP needs a hand-written `sqlite3.pc`; oniguruma/sqlite are built with Fil-C.

---

## 1. The single most important decision: adopt Filnix, don't reinvent

[mbrock/filnix](https://github.com/mbrock/filnix) is a mature Fil-C PHP port
that has **already solved most of the limitations** we currently list. Its
patch set (`patches/php-*.patch`) is the reference. Our repo's value-add is the
Docker matrix, the WordPress drop-in, the per-version branch/CI model, and
reproducible CVE rebuilds — not re-deriving the Fil-C port.

Filnix already ships (verified in its repo tree):

| Capability | Filnix patch | Our status |
| --- | --- | --- |
| Core Fil-C port 8.4 | `php-8.4-filc.patch`, `php-8.4-alloc-filc.patch`, `php-8.4-dom-filc.patch`, `php-8.4-shmop-filc.patch` | we have a single combined subset |
| **OPcache** (works, 864 tests) | `php-8.4-opcache-filc.patch`, `php-8.4-opcache-ce-cache-filc.patch` | we ship opcache OFF |
| **OPcache JIT via C** (475 tests, 4–60× on CPU) | `php-8.4-opcache-jit-c-filc.patch`, `php-8.5-opcache-jit-c-filc.patch` | not started |
| PCRE2 under Fil-C | `pcre2-10.48-filc-match.patch` | we use `--without-pcre-jit` |
| PHP 7.4 (+ CVE backports) | `php-7.4-filc.patch`, `php-7.4-alloc-filc.patch`, `php-7.4-opcache-filc.patch`, `php-7.4-cve-*.patch` | not started |
| PHP 8.5 (hybrid VM, JIT) | `php-8.5-*.patch` | not started |
| Image libs for gd/imagick (libpng, libjpeg-turbo, libwebp, libtiff, …) | Filnix package set | not started |
| PECL: apcu, redis, msgpack, xdebug, imagick, xsl, … | `patches/php-*.patch` + `ports/overlay.nix` | not started |

**Action:** vendor Filnix's PHP patches into `patches/` (with attribution and
upstream commit pins), and mirror its build flags. Track Filnix upstream so new
Fil-C fixes flow in.

Filnix's documented results we can inherit by adopting its patches:
- OPcache: 864 tests pass; shared memory mapped **privately** (capabilities
  don't cross processes) → each FPM worker has its own cache.
- JIT-through-C: prints opcache JIT IR as C, compiles with `filcc`, `dlopen`s
  it. Safety preserved (a JIT bug = Fil-C panic, not corruption). Persistent
  object cache via `PHP_JIT_C_CACHE` + ccache. Function mode 4–60× on CPU-bound
  code; tracing works but slower than interpreter; PCRE JIT still off.
- Performance: PHP is 1.5–4× slower than native; system allocator (default) is
  ~2× slower than Zend's but gives per-value bounds (this is the safety win).

---

## 2. Version strategy: one branch per minor, flexible per-version patches

The user's model: a branch per PHP minor (`7.1`, `7.2`, … `8.5`), each free to
carry whatever patch set it needs, and CI builds images per branch. This is the
right call because the Fil-C patch genuinely diverges per line (e.g. 7.4 has no
`zend_weakrefs.c` retagging identical to 8.x; 8.4+ has lexbor DOM).

### Branch model
```
main            → the tooling: docker/, versions.json, CI, docs, shared scripts
php/8.5         → patches/php-8.5.*-filc.patch, versions.json entry
php/8.4         → (default; already works)
php/8.3  php/8.2  php/8.1  php/8.0  php/7.4  php/7.3  php/7.2  php/7.1
```
Each `php/x.y` branch:
- pins its exact tarball(s) + sha256 in `versions.json`
- carries its own `patches/php-x.y.*-filc.patch` set (may be Filnix's, may be
  hand-ported, may include sury/ondrej build glue)
- CI builds `cli`/`fpm`/`apache`/`wordpress` for that version and pushes
  `:x.y.N-<sapi>`, `:x.y-<sapi>`, plus `:latest` from the newest supported.

`main` holds the shared Dockerfile + matrix logic; branches only diverge in
`patches/` and their `versions.json` entry. Rebase branches on `main` to pick up
tooling fixes.

### Where old-version patches come from
- **8.3 / 8.2**: port Filnix's 8.4 patch back (drop lexbor hunks, fix
  `zend_alloc.c`/`zend_fibers.c` context). Mostly mechanical; ~2–4 hunks/version.
- **8.1 / 8.0 / 7.4**: Filnix has 7.4; port 7.4 forward to 8.0/8.1 or 8.4 back.
  Use **sury.org / ondrej PPA** source packaging as the *base tarball* for these
  EOL lines — it carries the build-system glue and CVE backports that make old
  PHP compile on a modern toolchain. Note: sury patches are **Debian packaging**,
  not Fil-C patches; we still apply the Fil-C patch on top.
- **7.3 / 7.2 / 7.1**: no Fil-C port exists upstream (Filnix stops at 7.4).
  These need a from-scratch Fil-C port per line (no `zend_weakrefs.c` before
  7.4; OpenSSL 1.0/1.1 vs optfil's 3.x). **Mark research/best-effort**, not
  guaranteed.
- **5.x**: same as 7.1 but worse (very different internals, OpenSSL 1.0, no
  `zend_weakrefs`, no PHP 7 object model). **Out of scope** unless Filnix or
  another port adds it. Recommend documenting as unsupported.

---

## 3. Image variants (close the gap without destabilising the default)

Mirror the official `php`/`wordpress` images so we're a drop-in:

| Image | Contents | Notes |
| --- | --- | --- |
| `:cli` | Fil-C PHP CLI | safe interpreter, full extensions |
| `:fpm` | FPM + **OPcache on** (Filnix opcache patch) | default; no JIT |
| `:fpm-jit` | FPM + OPcache + **JIT-through-C** | experimental; `PHP_JIT_C_CACHE` warm |
| `:apache` | Fil-C httpd + mod_php | done |
| `:wordpress` | apache + WordPress, env-var contract | done for 8.4 |

Keep JIT in a separate `:fpm-jit` variant so the default stays stable (matches
Filnix keeping `php-jit` separate from `php`).

---

## 4. Gap-closure plan (ordered by value/effort)

| # | Gap | Fix | Effort | Source |
| --- | --- | --- | --- | --- |
| P0 | OPcache off | Adopt Filnix opcache + ce-cache patches; enable in `:fpm` | Med | Filnix |
| P0 | Extensions: gd, zip, sodium, xsl, gmp, ldap | Build dep libs with Fil-C (libpng, libjpeg-turbo, libwebp, freetype, libzip, libsodium, libxslt, gmp, openldap) into `/opt/fil` | Med | Filnix pkg set |
| P1 | No JIT | Integrate `php-8.4-opcache-jit-c-filc.patch`; new `:fpm-jit` variant; `PHP_JIT_CC=/opt/fil/bin/filcc` | High | Filnix |
| P1 | PCRE JIT off | Adopt `pcre2-10.48-filc-match.patch` (interpreter, not JIT) to at least get PCRE2 correct under Fil-C | Low | Filnix |
| P2 | JIT compile overhead | Persistent object cache (`PHP_JIT_C_CACHE`) + ccache; prefilled cache image | High | Filnix |
| P2 | FPM worker cache dup | Pre-fork warmup; document private-cache semantics | Med | — |
| P3 | amd64 only | Fil-C runtime is amd64; arm64 needs upstream Fil-C work | Very high | upstream |
| P3 | PCRE native JIT | PCRE2-to-C backend (research) | Very high | research |
| P4 | 7.1–7.3, 5.x | from-scratch Fil-C port per line | Very high | research |

**Do NOT** weaken the safety model to chase speed: keep the system allocator
default (per-value bounds) and keep JIT output going through Fil-C (no raw
executable mmap). Those are the whole point.

---

## 5. Reproducible CVE rebuild (the operational goal)

When PHP ships a patch release (e.g. 8.4.28):
1. On branch `php/8.4`: bump `versions.json` version + sha256.
2. Re-apply the Fil-C patch set to the new tarball (usually applies clean; fix
   any drifted hunks).
3. Push → CI builds all SAPIs + WordPress, runs the smoke tests, pushes tags.
4. `main`'s `:latest`/`:8` tags move via the newest branch.

CI (`.github/workflows/build-and-publish.yml`) becomes a matrix over branches
(or a `versions.json` list on `main`), building `docker --target {cli,fpm,apache,wordpress}`
per version and pushing to GHCR. Add a WordPress end-to-end job (bring up
`mysql:8` service, run `wp core install`, curl the homepage) as the acceptance
test.

---

## 6. Immediate next steps (this repo)

1. Vendor Filnix's 8.4 patch set (split: core/alloc/dom/opcache/shmop) and
   enable OPcache in `:fpm`. Verify the 864-test OPcache suite.
2. Add `gd`, `zip`, `sodium` by building their libs with Fil-C in the deps stage.
3. Add `:fpm-jit` target with the JIT-through-C patch; smoke-test with
   `opcache.jit=function` on a CPU script.
4. Port the patch to 8.3 / 8.2 (drop lexbor, fix alloc/fibers hunks); open
   `php/8.3`, `php/8.2` branches.
5. Convert CI to the per-version matrix + WordPress acceptance job.
6. Rewrite README limitations to reflect what's now solved (OPcache, JIT via C,
   extensions, 7.4) vs. genuinely open (PCRE JIT, arm64, ≤7.3, 5.x).

## Old versions (8.0, 7.4, ≤7.3): the real blocker and the path

**Finding (conclusive).** Fil-C rewrites every call into an external library to
a `pizlonated_`-prefixed symbol and requires the linked library to export those
symbols. optfil's own libs do (libxml2.so.16 exports 4023 `pizlonated_*`
symbols; its libc 3342). Debian's system libxml2/OpenSSL export plain symbols
(0 `pizlonated_*`), so a Fil-C-built PHP **cannot link against system libs** --
it fails with `undefined reference to pizlonated_xmlParserVersion` etc. This is
why optfil bundles its own libxml/OpenSSL/ICU/libc.

Consequences:
- "Build against a Debian base's dev libs" does not work: the symbols do not
  match. Confirmed by linking PHP 8.0 against system libxml/OpenSSL.
- optfil ships only current libs (libxml 2.15, OpenSSL 3.6, ICU 78). EOL PHP
  (8.0/7.x) cannot compile against those (removed `RSA_SSLV23_PADDING`, libxml
  2.15 header changes, etc.).

**The path.** In the `deps` stage, build the *old* lib versions with `filcc`
against optfil's libc so the symbols match, then build PHP against them:
1. Build libxml2 2.9.x with `filcc` into a per-series prefix (e.g. `/opt/fil-8.0`).
2. Build OpenSSL 3.0.x with `filcc` into the same prefix.
3. Build PHP 8.0/7.4 against that prefix (pkg-config there), keeping optfil ICU
   for intl (libc++ ABI) or dropping intl for the oldest lines.
4. Backport CVE-2026-109618/109619 to the EOL branch (they were never released
   there) and keep the Fil-C port patch (already drafted for 8.0).

This is per-series lib pinning, not a one-liner. Start with libxml 2.9 + OpenSSL
3.0 for 8.0; the same pattern extends to 7.4 (OpenSSL 1.1 if needed).

---

## 7. Building 7.4 / 7.3 / 7.2 / 5.x — old-Debian investigation (findings)

Idea: build the old PHP lines on an **old Debian** base so the system OpenSSL /
libxml / glibc already match what old PHP expects, instead of hand-building old
libs with `filcc` on bookworm. The Dockerfile now takes `DEBIAN_BASE` and rewrites
apt to `archive.debian.org` for `buster|stretch|jessie`.

Validated:
- **optfil Fil-C runs on old Debian.** `filcc --version` and a compile+run
  succeed on bullseye (glibc 2.31), buster (2.28), stretch (2.24) and jessie
  (2.19). Fil-C is self-contained: it ships its own libc (`libc.so.6666`),
  loader (`ld-fil1-x86_64.so`), crt objects and headers under `/opt/fil`, and
  links `-lpizlo -lyolort …`. It does not depend on the host glibc at runtime.
- **`archive.debian.org` gives consistent old packages** (buster → OpenSSL
  1.1.1n, libxml 2.9.4, ICU 63). The live `bullseye-security` mirror is currently
  serving a stale index (404 on the openssl .deb) and bullseye is not on
  archive-security, so bullseye apt needs `snapshot.debian.org` pinned to a date
  matching the base image's baked package versions.

Blocker found (why it is not a drop-in):
- Fil-C's bundled headers are a **full recent-glibc copy** (they define
  `__MATHDECL_ALIAS` etc., glibc ≥ ~2.29). PHP's build puts `/usr/include` on the
  path for the system openssl/curl/icu headers; on buster (glibc 2.28) the system
  `math.h` is pulled but its `#include <bits/…>` resolves to Fil-C's newer `bits`,
  so `__MATHDECL_ALIAS` is undefined → `mathcalls-helper-functions.h` fails to
  parse. Forcing `-I/opt/fil/include` ahead of `-I/usr/include` does **not** fix
  it: Fil-C's `math.h` is conditionally compiled against the host `__GLIBC__`
  version macros (from the system `features.h`), so it still defers to the old
  system math.h. Fil-C's headers are effectively coupled to a bookworm-era glibc.
- Consequence: the glibc floor tracks Fil-C's bundled headers, not the compiler.
  7.x wants OpenSSL 1.1.1 (bullseye/buster); 5.x wants OpenSSL 1.0.x (stretch/
  jessie, glibc ≤ 2.24) which is far below Fil-C's header expectations.

Recommended path (instead of old-Debian base):
1. **Stay on bookworm** (glibc compatible with Fil-C headers) and **build the old
   OpenSSL with `filcc`** into `/opt/fil`, then point PHP at it via
   `--with-openssl=/opt/fil` + an `openssl.pc`. For 7.4/7.3/7.2 that is OpenSSL
   1.1.1; for 5.6 it is OpenSSL 1.0.2. This keeps Fil-C's headers happy and only
   swaps the crypto lib. The libxml-2.9-with-filcc step already added for 8.0 is
   the same pattern.
2. Verify the Fil-C port patch per series (7.4, 7.3, 7.2 and a 5.6
   prototype now build locally; TLS and memory limits still block release).
3. Apply the CVE backport (`patches/cve-backports/`) where it exists. The
   5.6 PPA fix applies with its multipart part limit backport; other 5.x
   series still need a port and security testing.

Net: old-Debian is a dead end because of Fil-C's glibc-coupled headers; the
filcc-built-old-OpenSSL-on-bookworm route is the one to pursue.

Bookworm-side fixes needed for 7.x (the modern-glibc issues old-Debian would
have dodged, now that we stay on bookworm):
- OpenSSL: build OpenSSL 1.1.1 with `filcc` into `/opt/fil`, write an
  `openssl.pc`, configure PHP with `--with-openssl=/opt/fil`. Fixes the
  `OPENSSL_API_COMPAT expresses an impossible API compatibility level` error
  (PHP 7.4 vs OpenSSL 3.x).
- `strlcpy`: glibc ≥ 2.38 ships `strlcpy`, so PHP's configure sets
  `HAVE_STRLCPY=1` but the declaration is not visible → `call to undeclared
  library function 'strlcpy'`. Force PHP's own copy with
  `ac_cv_func_strlcpy=no` on the configure line.
- `L_tmpnam`: PHP 7.4's generated Makefile adds `-I/usr/include` (and iconv
  adds `-I"/usr/include"`), which Fil-C searches *before* `/opt/fil/include`.
  The resulting system `stdio.h` mixes with Fil-C's `bits` headers. Remove both
  system include flags after configure; `-D_DEFAULT_SOURCE` alone does not
  solve this.

### Historical Bookworm 7.4 checkpoint (2026-10-24)

- Fil-C builds OpenSSL 1.1.1w shared libraries and OpenSSL 1.0.2u's
  `build_libs`. OpenSSL 1.0.2u links and runs a Fil-C digest program and
  the PHP 5.6 prototype. Its `include/openssl` is a
  symlink farm, so copying it with `cp -a` makes broken headers; use `cp -aL`.
  OpenSSL 1.1.1's linker version scripts hide Fil-C-renamed `pizlonated_*`
  symbols; removing the scripts for both libraries enables real PHP links.
- PHP 7.4.33 CLI/FPM/Apache build in Docker with the CVE backport, Fil-C
  patch, libxml 2.9.14, OpenSSL 1.1.1w, Oniguruma 6.9.9 and curl 8.11.1.
  Oniguruma's integer hash entries lost pointer capabilities during mbstring
  startup; `patches/oniguruma-6.9.9-filc.patch` gives the hash table
  pointer-typed entries. Build curl against OpenSSL 1.1.1: optfil's curl
  links OpenSSL 3 and mixing both OpenSSL ABIs panics in TLS.
- CLI runs PHP, mbstring, HTTP curl, random_bytes and openssl_digest;
  Apache serves `/index.php`; FPM starts. `session.upload_progress.enabled=0`.
  The bailout and multipart-limit backports apply; with a temporary limit of
  one part, a two-field multipart POST exposes only the first field.
  PHP 7.4's Apache module is named `libphp7.so`, not `libphp.so`.
- **Do not publish 7.4 yet:** HTTPS curl panics in `BN_nist_mod_384` inside
  OpenSSL 1.1.1. The constant-time pointer-mask selection loses Fil-C's
  capability. A naive branch-based replacement may introduce crypto timing
  side channels, so the correct solution still needs design and TLS tests.
  The Fil-C tracked system allocator enforces `memory_limit` and reports
  per-request memory usage and peaks in CLI, FPM and Apache tests. An OOM
  exits the worker through Zend's safe fatal-error path; TLS and broader
  security regression testing remain. bz2 is omitted because system libbz2
  cannot satisfy Fil-C's symbol rewriting.
  Other PHP 5.x CVE backports remain pending.

### Historical Bookworm 7.2 checkpoint (2026-10-25)

- PHP 7.2.34's Fil-C port and the EOL CVE backport plus `ZSTR_MAX_LEN`
  and `max_multipart_body_parts` prerequisites compile from the repository
  Dockerfile. Local CLI, FPM and Apache start; CLI runs typed arguments,
  mbstring, DOM, SQLite, MySQL drivers, session and HTTP curl. PHP 7.2's
  singleton GPC array needs at least two buckets for Fil-C-aligned entries;
  the one-bucket EOL backport traps when handling multipart POSTs.
- **Do not publish 7.2:** HTTPS curl traps in OpenSSL 1.1.1w's
  `BN_nist_mod_384`, and `memory_limit=1M` allows an 8 MiB string while
  `memory_get_usage()` stays at zero.

### Historical Bookworm 7.3 checkpoint (2026-10-25)

- PHP 7.3.33 builds with Fil-C on bookworm using OpenSSL 1.1.1w and the
  tracked `patches/php-7.3.33-filc.patch`. CLI, FPM and Apache start locally;
  CLI runs typed class arguments, mbstring, DOM, SQLite, and HTTP curl.
- Its bundled Oniguruma must store hash-table pointers as pointers rather
  than integers. The CVE-2026-109618/109619 backport from deb.sury.org
  applies with its `ZSTR_MAX_LEN` and multipart-limit prerequisites.
- **Do not publish 7.3:** HTTPS curl traps in OpenSSL's `BN_nist_mod_384`,
  and the system-allocator workaround bypasses PHP's `memory_limit` and
  `memory_get_usage()`. `memory_limit=1M` allows an 8 MiB string. The backport
  needs regression tests with a working memory limit before claiming security.

### Historical Bookworm 5.6 checkpoint (2026-10-25)

- PHP 5.6.40 builds with Fil-C on bookworm using OpenSSL 1.0.2u and the
  initial `patches/php-5.6.40-filc.patch`. Local CLI, FPM and Apache images
  build from `docker/Dockerfile`; CLI runs arrays, sorting and `openssl_digest`,
  FPM starts, and Apache serves `/index.php` through `libphp5.so`.
- This is a **selectively enabled `--disable-all` build**, not functional
  WordPress: mbstring, zlib, sockets, mysqlnd/mysqli, PDO MySQL, XML/DOM,
  SimpleXML, SQLite, and HTTP curl work. Session is disabled, and the default
  WordPress 6.7 requires a newer PHP. HTTPS curl panics inside OpenSSL 1.0.2u
  `BN_nist_mod_256`, the same pointer-mask issue as 7.4's OpenSSL 1.1.1.
  The system-allocator workaround also bypasses `memory_limit` (8 MiB string
  allowed with `memory_limit=1M`) and returns zero for `memory_get_usage()`.
- PHP 5.6's `php-fpm.conf.default` contains its `[www]` pool, unlike newer
  releases' `php-fpm.d/www.conf.default`; the runtime stage handles both layouts.
- Fil-C PHP 5.6 requires POSIX `readdir_r` detection (configure's run probe
  incorrectly chooses the old signature), the `fopencookie` offset-pointer
  signature, a portable overflow check, capability-preserving GC color
  tagging and qsort swaps. The initial port uses the system allocator by
  default: Zend's chunk allocator weakens Fil-C's bounds, and memory usage
  accounting needs follow-up.
- The deb.sury.org PHP 5.6 CVE-2026-109618/109619 backport builds with
  the `max_multipart_body_parts` limit backport (CVE-2023-0662). The Fil-C
  overflow path uses its bailout-safe fatal error helper. An isolated
  `--enable-session` CLI build runs `session_start()` with upload progress
  disabled, but session stays off in the repository image pending regressions.
- **Do not publish 5.6:** TLS traps in the Fil-C-built legacy OpenSSL,
  `memory_limit` is ineffective and session is disabled. The backport still
  needs security regression tests; older WordPress compatibility is unverified.

### Current experimental legacy checkpoint (supersedes historical blockers)

- PHP 7.4/7.3/7.2 and 5.6 have local CLI/FPM/Apache/WordPress builds.
  WordPress 7.1.3/6.9.10/6.9.10/6.2.14 respectively installs through
  the browser and serves a page over MariaDB 11.4. Authenticated admin
  login passes on all four. PHP 7.2's mysqlnd cannot use MySQL 8.4's
  default authentication method.
- PHP CVE/multipart backports apply to pristine tarballs; `session`
  is enabled in 5.6 with upload progress off. Tracked allocations enforce
  `memory_limit` and report nonzero usage through repeated CLI/FPM/Apache
  requests. The final 5.6/7.2/7.3 builds reject lowering a limit below
  current usage and allow it after freeing memory, also verified on
  the final 7.4 build.
- Capability-preserving NIST ports of OpenSSL 1.0.2u/1.1.1w pass modular
  arithmetic comparisons and HTTPS curl. These releases are EOL and the
  timing/security properties of the changes remain unreviewed. This is
  a blocker for stable publication on all four legacy lines, irrespective
  of functional success. They remain pending; opt-in experimental tags
  must not be mistaken for production images.
- Disable PCRE JIT in runtime images: Fil-C's executable-memory
  restriction otherwise causes intermittent PHP warnings before WordPress
  login cookies, breaking authentication. The WordPress entrypoint no
  longer auto-installs a fixed admin account or writes a default DB
  password. CI must test images before pushing;
  unversioned tags are reserved for the designated default PHP version.

### JIT-through-C checkpoint (PHP 8.4.27)

- Vendored Filnix's `php-8.4-opcache-ce-cache-filc.patch` and
  `php-8.4-opcache-jit-c-filc.patch` as `patches/php-8.4.27-opcache-*`;
  both apply after our combined Fil-C patch (which already contained the
  private-SHM OPcache mapping hunks). `ZEND_JIT_C_CC` points at
  `/opt/fil/bin/filcc`.
- `PHP_JIT=1` build arg plus `cli-jit`/`fpm-jit` targets produce images
  with OPcache enabled and `opcache.jit=1235`; the runtime carries the
  Fil-C toolchain (~3 GB) because the JIT compiles each hot function's C
  at request time.
- Local verification: OPcache loads, FPM serves with opcache=1 jit=1235,
  and `Zend/bench.php` with `opcache.jit=function` runs mandel 47x and
  simple 29x faster than the interpreter; strcat (allocator-bound) is
  unchanged. `zend_jit_c: unsupported IR_EXITCALL in JIT$$trace_exit` is
  the known tracing-exit limitation; function/1235 modes are unaffected.
- The jit variants intentionally enable OPcache, which the stable-tag
  security smoke rejects; they stay out of the CI publish matrix until
  the OPcache-on posture gets its own gate. PHP 8.5 would additionally
  need Filnix's hybrid-VM patch to keep the CALL VM.
