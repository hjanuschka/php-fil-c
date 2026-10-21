# Release plan: patched PHP on Fil-C

**Status:** no images published; the old PHP 8.4.25 build is on security hold.
The first release candidate is PHP 8.4.27 + Fil-C 0.686, `linux/amd64`.
Do not publish a tag until all gates below pass.

## Security policy

PHP fixes, not Fil-C panics, are the prerequisite for releases. Two critical
issues published on 2026-10-21 affect the previous 8.4.25 build:

- [GHSA-w8hw-w9fx-j79w](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
  (CVE-2026-109618): OOM `longjmp` can skip cleanup while request state is
  partially initialized. Shutdown can then act on corrupt state.
- [GHSA-6wmf-4rv5-p3rp](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)
  (CVE-2026-109619): globals retaining request-owned state can be consumed
  by a subsequent request before they are reset. A producer and a consumer
  on the same worker can lead to use-after-free and RCE.

Fil-C makes many invalid accesses abort, but this does **not** prove either
exploit is blocked: a stale pointer may remain reachable through the collector,
logic/state bugs need not violate bounds, and PHP can execute code legitimately.
The supported PHP releases containing the complete fixes start at 8.2.35,
8.3.36, 8.4.27 and 8.5.12. Verify this list against upstream advisories on
each release; do not use version comparison as a substitute for source review.

Ondrej's [Ubuntu PHP PPA](https://launchpad.net/~ondrej/+archive/ubuntu/php/)
source packages include a backport for **both** CVEs in 7.1.33-80,
7.2.34-66, 7.3.33-35, 7.4.33-31, 8.0.30-25 and 8.1.34-9 (Debian revision,
not an upstream PHP patch version). Their source patch explicitly calls itself
"Minimal mitigation for EOL version". Treat these branches as *not yet approved*
for a patched Fil-C image: audit each backport and its missing coverage, apply
it to the exact source archive, port that source to Fil-C, and pass targeted
cross-request tests. PPA binaries are ordinary PHP compiled for Ubuntu; they
cannot be copied into a Fil-C Debian Bookworm image.

## Phase 0: repair the public build

1. Disable the vulnerable 8.4.25 download/build and warn existing users.
2. Pin the 8.4.27 source and checksum; forward-port the Fil-C patch with zero
   rejected hunks. Verify the exact source version in `src-<version>` and the
   installed binary before calling it a release. Do not allow arbitrary
   `PHP_VERSION`/checksum overrides in the publish path.
3. Run the existing smoke test, new upstream OOM/session PHPTs and broad PHP
   tests. Local trial currently builds 8.4.27 and passes selected OOM/session
   PHPTs, but **three Zend tests panic** in
   `zend_accel_pending_ce_cache_commit` with OPcache enabled. Resolve that
   Fil-C capability issue and rerun tests before enabling public builds or FPM.
4. Test both CLI and repeated requests to the same FPM worker (including OOM,
   fatal error, next request, session upload progress). A crash in a worker is
   not an acceptable security regression test outcome merely because it is not
   RCE. Document any unsupported extension or remaining failure.

## Phase 1: one local Bookworm image

- Build from pinned `debian:bookworm` + verified Fil-C `/opt/fil` release and
  patched PHP source in a multi-stage Dockerfile. Start with `linux/amd64`.
- Provide `cli` and `fpm` targets, with CA certificates, appropriate FPM
  config/port, non-root workers and explicit entrypoints. Do not include the
  build toolchain in runtime images. Preserve the Fil-C loader, runtime,
  Fil-C-built shared-library closure and required data files; use `readelf`
  plus a runtime `docker run` check rather than host `ldd` alone. Don't
  silently link in Debian's native C libraries.
- Disable JITs, document OPcache's per-process behavior and allocator costs;
  verify image functionality from a clean host using `docker run` for CLI,
  curl/openssl/intl and FPM. Measure and document image sizes.

## Phase 2: CI without publishing

- Manifest/allowlist records for each candidate: exact PHP source URL and
  SHA256, Fil-C release/digest, port/backport patch checksum and provenance,
  required security fixes, supported architecture, SAPI variants and expected
  module list. Begin with **8.4.27 only**. Version strings alone cannot
  establish a source backport.
- PR workflow derives a matrix from *reviewed* manifest entries, never PR
  labels or an untrusted input version. Compile and test with no registry
  credentials. Treat failed and skipped **mandatory** security tests as
  failures. A normal PHPUnit/PHPT fail cannot be waived by the publishing job.
- `docker run` smoke checks should verify `php -v`, `php -m`, Fibers, WeakMap,
  DOM, OPcache, memory limit, dynamic dependencies and a multi-request FPM
  session. Reproduce release candidate tests on each architecture separately.
- Pin Actions by commit SHA, give PR jobs read-only permissions, and restrict
  network/secret access for untrusted contributions.

## Phase 3: promote to GHCR and Docker Hub

- A separate trusted, approval-gated workflow publishes only a tested commit
  and manifest entry. Use Buildx for a per-platform candidate, inspect the
  pushed image by digest, then promote the same digest to GHCR and Docker Hub.
- GHCR: `ghcr.io/hjanuschka/php-fil-c` with scoped `GITHUB_TOKEN` package-write
  permission. Docker Hub: `hjanuschka/php-fil-c` with repository-scoped access
  token stored in GitHub Actions secrets (not a password). Never expose these
  credentials to PR workflows.
- Immutable tags first: `8.4.27-cli-bookworm`, `8.4.27-fpm-bookworm` (or
  `8.4.27-bookworm` for CLI). Only after successful digest checks promote
  `8.4-cli-bookworm` / `8.4-fpm-bookworm` and, once a default PHP 8 branch is
  defined, `8-bookworm` / `8-fpm-bookworm`. Never retag a vulnerable image.
- Generate SBOM/provenance attestation, record source/toolchain digests and
  image digest, publish a changelog and a rollback target. Add arm64 only
  after the aarch64 Fil-C toolchain and runtime pass identical tests.

## Phase 4: expand the matrix

Add 8.2, 8.3 and 8.5 one by one using the first patched (or newer) upstream
releases. A Fil-C port patch is version-specific; do not assume the 8.4 patch
applies safely elsewhere. Assess the six EOL/PPA versions individually and
explicitly omit any that cannot meet the security and runtime gates. CI may
build research candidates, but the publication matrix contains approved entries
only. Monitor both PHP security releases and Fil-C toolchain updates; rebuild
and repromote only after tests.

## README checklist

- Support table: exact PHP version, architecture, CLI/FPM, extensions, Fil-C
  version, security provenance and currently available image digests.
- Local setup from a clean system: Fil-C distribution, pinned PHP source,
  `./build.sh`, verification commands, how to clean/rebuild, FPM configuration.
- Copy/paste `docker run` and Compose examples for CLI/FPM, including a
  digest-pinned deployment example and how to configure nginx/FastCGI.
- Threat model and warnings: Fil-C does not replace security patches; no JIT;
  OPcache per-worker state; performance; known test failures, unsupported
  extensions and how long image tags receive updates.
- Links to advisory sources, exact PHP fix commits, PPA source patches (if an
  EOL version is ever approved), and toolchain licenses.
