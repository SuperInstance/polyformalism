/*
 * Experiment 3: Bloom CRDT Merge Bandwidth
 * At what filter size does memory bandwidth become the bottleneck?
 * Also: measure false positive rate vs filter fill.
 *
 * gcc -O2 -mavx2 -o exp_bloom exp_bloom.c -lm && ./exp_bloom
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>
#include <immintrin.h>

double now_sec() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

uint32_t hash32(uint32_t key) {
    key ^= key >> 16;
    key *= 0x45d9f3b;
    key ^= key >> 16;
    key *= 0x45d9f3b;
    key ^= key >> 16;
    return key;
}

void bloom_insert(uint64_t *filter, int n_words, uint32_t key) {
    uint32_t pos = hash32(key) % (n_words * 64);
    filter[pos / 64] |= (1ULL << (pos % 64));
}

int bloom_contains(uint64_t *filter, int n_words, uint32_t key) {
    uint32_t pos = hash32(key) % (n_words * 64);
    return (filter[pos / 64] & (1ULL << (pos % 64))) != 0;
}

void bloom_merge_scalar(uint64_t *dst, uint64_t *src, int n_words) {
    for (int i = 0; i < n_words; i++) dst[i] |= src[i];
}

void bloom_merge_avx2(uint64_t *dst, uint64_t *src, int n_words) {
    for (int i = 0; i + 4 <= n_words; i += 4) {
        __m256i d = _mm256_loadu_si256((__m256i*)(dst + i));
        __m256i s = _mm256_loadu_si256((__m256i*)(src + i));
        _mm256_storeu_si256((__m256i*)(dst + i), _mm256_or_si256(d, s));
    }
}

int main() {
    printf("=== Experiment 3: Bloom CRDT Merge Bandwidth ===\n\n");

    /* --- Part A: Merge bandwidth vs filter size --- */
    printf("--- Part A: Merge Bandwidth vs Filter Size ---\n");
    printf("%12s %12s %12s %10s\n", "Size(KB)", "Scalar GB/s", "AVX2 GB/s", "Speedup");
    printf("%12s %12s %12s %10s\n", "--------", "-----------", "---------", "-------");

    int sizes_kb[] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048};
    int reps = 1000;

    for (int s = 0; s < 12; s++) {
        int kb = sizes_kb[s];
        int n_words = kb * 1024 / 8;  // KB to uint64 count
        uint64_t *dst = aligned_alloc(64, n_words * 8);
        uint64_t *src = aligned_alloc(64, n_words * 8);
        memset(dst, 0, n_words * 8);
        memset(src, 0xFF, n_words * 8);

        /* Scalar */
        double t0 = now_sec();
        for (int r = 0; r < reps; r++) {
            bloom_merge_scalar(dst, src, n_words);
        }
        double t1 = now_sec();
        double gb_scalar = (double)reps * n_words * 8 / ((t1 - t0) * 1e9);

        memset(dst, 0, n_words * 8);

        /* AVX2 */
        t0 = now_sec();
        for (int r = 0; r < reps; r++) {
            bloom_merge_avx2(dst, src, n_words);
        }
        t1 = now_sec();
        double gb_avx2 = (double)reps * n_words * 8 / ((t1 - t0) * 1e9);

        printf("%10dKB %10.1f   %10.1f   %8.1fx\n", kb, gb_scalar, gb_avx2, gb_avx2/gb_scalar);

        free(dst);
        free(src);
    }

    /* --- Part B: False Positive Rate vs Fill --- */
    printf("\n--- Part B: False Positive Rate vs Fill ---\n");
    int n_words = 10000;  // 80KB filter
    uint64_t *filter = calloc(n_words, 8);
    int total_bits = n_words * 64;

    printf("%10s %10s %12s %12s\n", "Inserted", "Bits Set", "Fill%", "FP Rate");
    printf("%10s %10s %12s %12s\n", "--------", "--------", "-----", "-------");

    /* Insert keys and measure FP rate at checkpoints */
    int max_keys = 50000;
    int checkpoints[] = {100, 500, 1000, 2000, 5000, 10000, 20000, 50000};
    int cp_idx = 0;

    for (int k = 1; k <= max_keys; k++) {
        bloom_insert(filter, n_words, k);

        if (cp_idx < 8 && k == checkpoints[cp_idx]) {
            /* Count set bits */
            int bits_set = 0;
            for (int i = 0; i < n_words; i++) {
                bits_set += __builtin_popcountll(filter[i]);
            }
            double fill = 100.0 * bits_set / total_bits;

            /* Measure FP rate: check 10000 keys NOT inserted (100000-109999) */
            int fp = 0, tn = 0;
            for (int test = 100000; test < 110000; test++) {
                if (bloom_contains(filter, n_words, test)) fp++;
                else tn++;
            }
            double fp_rate = 100.0 * fp / 10000;
            double theoretical = 100.0 * pow(1.0 - exp(-(double)k * 3 / total_bits), 3);

            printf("%10d %10d %10.2f%%   %8.2f%% (theory: %.2f%%)\n",
                   k, bits_set, fill, fp_rate, theoretical);
            cp_idx++;
        }
    }

    /* --- Part C: CRDT Idempotency Verification --- */
    printf("\n--- Part C: CRDT Idempotency ---\n");
    int small_n = 1000;
    uint64_t *a = calloc(small_n, 8);
    uint64_t *b = calloc(small_n, 8);
    uint64_t *c = calloc(small_n, 8);

    for (int i = 0; i < 500; i++) { bloom_insert(a, small_n, i); }
    for (int i = 300; i < 800; i++) { bloom_insert(b, small_n, i); }

    /* Merge a |= b */
    bloom_merge_scalar(a, b, small_n);
    memcpy(c, a, small_n * 8);

    /* Merge again (idempotent: should be no change) */
    bloom_merge_scalar(a, b, small_n);

    int identical = 1;
    for (int i = 0; i < small_n; i++) {
        if (a[i] != c[i]) { identical = 0; break; }
    }
    printf("Idempotent (a|b|b == a|b): %s\n", identical ? "YES" : "NO");

    /* Commutative (a|b == b|a) */
    uint64_t *d = calloc(small_n, 8);
    uint64_t *e = calloc(small_n, 8);
    for (int i = 0; i < 500; i++) bloom_insert(d, small_n, i);
    for (int i = 300; i < 800; i++) bloom_insert(e, small_n, i);

    uint64_t *ab = calloc(small_n, 8);
    uint64_t *ba = calloc(small_n, 8);
    memcpy(ab, d, small_n * 8);
    memcpy(ba, e, small_n * 8);
    bloom_merge_scalar(ab, e, small_n);
    bloom_merge_scalar(ba, d, small_n);

    identical = 1;
    for (int i = 0; i < small_n; i++) {
        if (ab[i] != ba[i]) { identical = 0; break; }
    }
    printf("Commutative (a|b == b|a):  %s\n", identical ? "YES" : "NO");

    /* Associative ((a|b)|c == a|(b|c)) */
    uint64_t *f = calloc(small_n, 8);
    for (int i = 600; i < 1000; i++) bloom_insert(f, small_n, i);

    uint64_t *left = calloc(small_n, 8);
    uint64_t *right = calloc(small_n, 8);
    uint64_t *tmp = calloc(small_n, 8);

    /* (a|b)|c */
    memcpy(left, d, small_n * 8);
    bloom_merge_scalar(left, e, small_n);
    bloom_merge_scalar(left, f, small_n);

    /* a|(b|c) */
    memcpy(tmp, e, small_n * 8);
    bloom_merge_scalar(tmp, f, small_n);
    memcpy(right, d, small_n * 8);
    bloom_merge_scalar(right, tmp, small_n);

    identical = 1;
    for (int i = 0; i < small_n; i++) {
        if (left[i] != right[i]) { identical = 0; break; }
    }
    printf("Associative ((a|b)|c == a|(b|c)): %s\n", identical ? "YES" : "NO");

    printf("\nBloom CRDT is a valid semilattice: idempotent + commutative + associative.\n");

    free(a); free(b); free(c); free(d); free(e); free(f);
    free(ab); free(ba); free(left); free(right); free(tmp);
    free(filter);
    return 0;
}
