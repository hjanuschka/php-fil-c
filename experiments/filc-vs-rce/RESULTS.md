# Fil-C vs the PHP OOM / stale-state RCEs (CVE-2026-109618, CVE-2026-109619)

Goal: show that the two critical PHP advisories (fixed in 8.4.27) are
*exploitable* on native unpatched PHP but only a *panic* on Fil-C unpatched.

## What we could reproduce

| Trigger (unpatched 8.4.25)            | native | Fil-C |
|---------------------------------------|--------|-------|
| OOM via deeply nested POST vars       | clean PHP fatal | clean PHP fatal |
| OOM via one huge POST value           | clean PHP fatal | clean PHP fatal |
| OOM via multipart header blow-up      | request completes | request completes |
| `rfc1867_no_user_code.phpt` (advisory regression) | FAIL (logical: session destroyed) | FAIL (identical logical diff) |

The advisory regression test fails on **both** native and Fil-C unpatched,
identically, as a *logical* stale-state difference -- not a crash. So the bug
is present on both, and neither build crashes on the publicly-described
triggers.

## Why we could not produce the gold-standard proof

The confirmed RCE in the advisories relies on (a) mod_php calling request
shutdown after a failed startup, and (b) deliberate heap grooming to turn the
stale pointer into a controlled write. Neither the mod_php SAPI nor the exact
grooming is in our build or the public advisory text, so the memory-corruption
step never fires on the available triggers -- on native *or* Fil-C.

Fil-C's protection model (per-value capabilities + GC) is designed to turn the
freed-memory dereference into a panic, but we could not reach that dereference
with public information. Proving "native crashes, Fil-C panics" needs the
actual exploit or an equivalent grooming chain.

## Reproduce

```sh
# Fil-C images (see ../.. for the build): unpatched vs patched
docker build -t php-filc-unpatched:exp -f experiments/filc-vs-rce/Dockerfile .
docker run --rm --network none php-filc-unpatched:exp sh /app/exploit/run.sh
# native unpatched: build php-8.4.25 with the system compiler, same configure flags
```
