#include <stdio.h>
#include <stdlib.h>
#include <openssl/bn.h>

typedef int (*mod_fn)(BIGNUM *, const BIGNUM *, const BIGNUM *, BN_CTX *);
typedef const BIGNUM *(*prime_fn)(void);

int main(void)
{
    const int bits[] = {192, 224, 256, 384, 521};
    const mod_fn mods[] = {BN_nist_mod_192, BN_nist_mod_224, BN_nist_mod_256,
                           BN_nist_mod_384, BN_nist_mod_521};
    const prime_fn primes[] = {BN_get0_nist_prime_192, BN_get0_nist_prime_224,
                               BN_get0_nist_prime_256, BN_get0_nist_prime_384,
                               BN_get0_nist_prime_521};
    BN_CTX *ctx = BN_CTX_new();
    BIGNUM *a = BN_new(), *actual = BN_new(), *expected = BN_new();
    if (!ctx || !a || !actual || !expected)
        return 2;

    for (int curve = 0; curve < 5; curve++) {
        const BIGNUM *prime = primes[curve]();
        for (int i = 0; i < 2000; i++) {
            switch (i % 8) {
            case 0: BN_zero(a); break;
            case 1: if (!BN_copy(a, prime) || !BN_sub_word(a, 1)) return 2; break;
            case 2: if (!BN_copy(a, prime)) return 2; break;
            case 3: if (!BN_copy(a, prime) || !BN_add_word(a, 1)) return 2; break;
            case 4: if (!BN_copy(a, prime) || !BN_lshift1(a, a)) return 2; break;
            case 5: if (!BN_rand(a, bits[curve], 0, 0)) return 2; break;
            case 6: if (!BN_rand(a, bits[curve] * 2 - 1, 0, 0)) return 2; break;
            default: if (!BN_rand(a, bits[curve] * 2 + 8, 0, 0)) return 2; break;
            }
            if (!BN_nnmod(expected, a, prime, ctx) ||
                !mods[curve](actual, a, prime, ctx) ||
                BN_cmp(expected, actual) != 0) {
                fprintf(stderr, "%d-bit mismatch for case %d\n", bits[curve], i);
                return 1;
            }
            if (!BN_copy(actual, a) || !mods[curve](actual, actual, prime, ctx) ||
                BN_cmp(expected, actual) != 0) {
                fprintf(stderr, "%d-bit in-place mismatch for case %d\n", bits[curve], i);
                return 1;
            }
        }
        printf("%d-bit NIST modulus checked\n", bits[curve]);
    }
    BN_free(a); BN_free(actual); BN_free(expected); BN_CTX_free(ctx);
    return 0;
}
