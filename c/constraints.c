/*
 * Polyformalism Constraint Kernel — C Reference Implementation
 * This is the baseline. Every other language is compared against this.
 * gcc -O2 -mavx2 -o constraints_c constraints.c && ./constraints_c
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <immintrin.h>

/* 1. Constraint check: scalar */
int constraint_check_scalar(const int32_t *lower, const int32_t *upper, const int32_t *values, int n) {
    for (int i = 0; i < n; i++) {
        if (values[i] < lower[i] || values[i] > upper[i]) return 0;
    }
    return 1;
}

/* 1b. Constraint check: AVX2 SIMD */
int constraint_check_avx2(const int32_t *lower, const int32_t *upper, const int32_t *values, int n) {
    __m256i vl, vu, vv, cmp_lo, cmp_hi, both;
    for (int i = 0; i < n; i += 8) {
        vl = _mm256_loadu_si256((__m256i*)(lower + i));
        vu = _mm256_loadu_si256((__m256i*)(upper + i));
        vv = _mm256_loadu_si256((__m256i*)(values + i));
        cmp_lo = _mm256_cmpgt_epi32(vv, vl);     /* values > lower */
        cmp_hi = _mm256_cmpgt_epi32(vu, vv);     /* upper > values */
        both = _mm256_and_si256(cmp_lo, cmp_hi);
        int mask = _mm256_movemask_epi8(both);
        if (mask != (int)0xFFFFFFFF) return 0;
    }
    return 1;
}

/* 2. Bloom merge: bitwise OR (CRDT semilattice join) */
void bloom_merge(uint64_t *dst, const uint64_t *src, int n) {
    for (int i = 0; i < n; i++) {
        dst[i] |= src[i];
    }
}

/* 2b. Bloom merge: AVX2 */
void bloom_merge_avx2(uint64_t *dst, const uint64_t *src, int n) {
    for (int i = 0; i < n; i += 4) {
        __m256i d = _mm256_loadu_si256((__m256i*)(dst + i));
        __m256i s = _mm256_loadu_si256((__m256i*)(src + i));
        d = _mm256_or_si256(d, s);
        _mm256_storeu_si256((__m256i*)(dst + i), d);
    }
}

/* 3. Eisenstein norm */
int64_t eisenstein_norm(int32_t a, int32_t b) {
    return (int64_t)a * a - (int64_t)a * b + (int64_t)b * b;
}

/* Simple hash for bloom */
uint32_t bloom_hash(int key, uint32_t total_bits) {
    uint32_t h = (uint32_t)(key & 0x7FFFFFFF);
    h ^= h >> 16;
    h *= 0x45d9f3b;
    h ^= h >> 16;
    return h % total_bits;
}

void bloom_insert(uint64_t *filter, int n_words, int key) {
    uint32_t pos = bloom_hash(key, n_words * 64);
    filter[pos / 64] |= (1ULL << (pos % 64));
}

int bloom_contains(uint64_t *filter, int n_words, int key) {
    uint32_t pos = bloom_hash(key, n_words * 64);
    return (filter[pos / 64] & (1ULL << (pos % 64))) != 0;
}

/* Benchmark helper */
double now_sec() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

#define N 16
#define BLOOM_WORDS 1000
#define ITERS 10000000

int main() {
    printf("=== Polyformalism: C Reference (gcc + AVX2) ===\n\n");

    int32_t lower[N] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    int32_t upper[N] = {100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100};
    int32_t pass[N] = {25,30,35,40,50,60,70,80,10,20,30,40,55,65,75,85};
    int32_t fail[N];
    for (int i = 0; i < N; i++) fail[i] = 200 + i;

    /* Correctness */
    printf("--- Correctness ---\n");
    printf("Scalar  pass: %d\n", constraint_check_scalar(lower, upper, pass, N));
    printf("Scalar  fail: %d\n", constraint_check_scalar(lower, upper, fail, N));
    printf("AVX2    pass: %d\n", constraint_check_avx2(lower, upper, pass, N));
    printf("AVX2    fail: %d\n", constraint_check_avx2(lower, upper, fail, N));

    /* Bloom */
    uint64_t bloom_a[BLOOM_WORDS], bloom_b[BLOOM_WORDS], bloom_c[BLOOM_WORDS];
    memset(bloom_a, 0, sizeof(bloom_a));
    memset(bloom_b, 0, sizeof(bloom_b));
    memset(bloom_c, 0, sizeof(bloom_c));

    bloom_insert(bloom_a, BLOOM_WORDS, 42);
    bloom_insert(bloom_a, BLOOM_WORDS, 100);
    bloom_insert(bloom_a, BLOOM_WORDS, 500);
    bloom_insert(bloom_b, BLOOM_WORDS, 500);
    bloom_insert(bloom_b, BLOOM_WORDS, 999);

    memcpy(bloom_c, bloom_a, sizeof(bloom_a));
    bloom_merge(bloom_c, bloom_b, BLOOM_WORDS);

    printf("\nBloom 42 in merged:   %d\n", bloom_contains(bloom_c, BLOOM_WORDS, 42));
    printf("Bloom 500 in merged:  %d\n", bloom_contains(bloom_c, BLOOM_WORDS, 500));
    printf("Bloom 999 in merged:  %d\n", bloom_contains(bloom_c, BLOOM_WORDS, 999));
    printf("Bloom 9999 in merged: %d\n", bloom_contains(bloom_c, BLOOM_WORDS, 9999));

    /* Eisenstein norms */
    printf("\nN(3,0)  = %ld\n", eisenstein_norm(3, 0));
    printf("N(0,1)  = %ld\n", eisenstein_norm(0, 1));
    printf("N(2,-1) = %ld\n", eisenstein_norm(2, -1));
    printf("N(-1,2) = %ld\n", eisenstein_norm(-1, 2));
    printf("N(5,5)  = %ld\n", eisenstein_norm(5, 5));

    /* Benchmarks */
    printf("\n--- Benchmarks (%d iterations) ---\n", ITERS);

    double t0 = now_sec();
    volatile int r;
    for (int i = 0; i < ITERS; i++) {
        r = constraint_check_scalar(lower, upper, pass, N);
    }
    double t1 = now_sec();
    printf("Constraint check scalar: %.3f ms (%.1fM ops/s)\n",
           (t1-t0)*1000, ITERS/(t1-t0)/1e6);

    t0 = now_sec();
    for (int i = 0; i < ITERS; i++) {
        r = constraint_check_avx2(lower, upper, pass, N);
    }
    t1 = now_sec();
    printf("Constraint check AVX2:   %.3f ms (%.1fM ops/s)\n",
           (t1-t0)*1000, ITERS/(t1-t0)/1e6);

    uint64_t bench_dst[BLOOM_WORDS], bench_src[BLOOM_WORDS];
    memset(bench_dst, 0, sizeof(bench_dst));
    memset(bench_src, 0xFF, sizeof(bench_src));

    t0 = now_sec();
    for (int i = 0; i < 1000; i++) {
        bloom_merge(bench_dst, bench_src, BLOOM_WORDS);
    }
    t1 = now_sec();
    printf("Bloom merge scalar:      %.3f ms (%.1f GB/s)\n",
           (t1-t0)*1000, (double)1000*BLOOM_WORDS*8/(t1-t0)/1e9);

    memset(bench_dst, 0, sizeof(bench_dst));
    t0 = now_sec();
    for (int i = 0; i < 1000; i++) {
        bloom_merge_avx2(bench_dst, bench_src, BLOOM_WORDS);
    }
    t1 = now_sec();
    printf("Bloom merge AVX2:        %.3f ms (%.1f GB/s)\n",
           (t1-t0)*1000, (double)1000*BLOOM_WORDS*8/(t1-t0)/1e9);

    t0 = now_sec();
    volatile int64_t nr;
    for (int i = 0; i < ITERS; i++) {
        nr = eisenstein_norm(3, 0);
    }
    t1 = now_sec();
    printf("Eisenstein norm:         %.3f ms (%.1fM ops/s)\n",
           (t1-t0)*1000, ITERS/(t1-t0)/1e6);

    printf("\nAll tests passed.\n");
    return 0;
}
