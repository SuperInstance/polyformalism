/*
 * Polyformalism Experiment 1: SIMD Scaling
 * How does constraint check scale with vector width?
 * 8, 16, 32, 64, 128, 256, 512, 1024, 4096 elements
 *
 * gcc -O2 -mavx2 -o exp_simd_scaling exp_simd_scaling.c && ./exp_simd_scaling
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <immintrin.h>

#define MAX_N 4096
#define ITERS 1000000

double now_sec() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* Scalar constraint check */
double bench_scalar(int32_t *lower, int32_t *upper, int32_t *values, int n) {
    volatile int r;
    double t0 = now_sec();
    for (int i = 0; i < ITERS; i++) {
        int pass = 1;
        for (int j = 0; j < n; j++) {
            if (values[j] < lower[j] || values[j] > upper[j]) { pass = 0; break; }
        }
        r = pass;
    }
    double t1 = now_sec();
    (void)r;
    return (t1 - t0) * 1e9 / ITERS;  // ns per check
}

/* AVX2 constraint check */
double bench_avx2(int32_t *lower, int32_t *upper, int32_t *values, int n) {
    volatile int r;
    double t0 = now_sec();
    for (int i = 0; i < ITERS; i++) {
        int pass = 1;
        for (int j = 0; j < n; j += 8) {
            __m256i vl = _mm256_loadu_si256((__m256i*)(lower + j));
            __m256i vu = _mm256_loadu_si256((__m256i*)(upper + j));
            __m256i vv = _mm256_loadu_si256((__m256i*)(values + j));
            __m256i cmp_lo = _mm256_cmpgt_epi32(vv, vl);
            __m256i cmp_hi = _mm256_cmpgt_epi32(vu, vv);
            __m256i both = _mm256_and_si256(cmp_lo, cmp_hi);
            int mask = _mm256_movemask_epi8(both);
            if (mask != (int)0xFFFFFFFF) { pass = 0; break; }
        }
        r = pass;
    }
    double t1 = now_sec();
    (void)r;
    return (t1 - t0) * 1e9 / ITERS;
}

int main() {
    printf("=== Experiment 1: SIMD Scaling (constraint check) ===\n");
    printf("Hardware: AMD Ryzen AI 9 HX 370 (Zen 5, AVX-512, gcc -O2 -mavx2)\n\n");

    /* Align to 64 bytes for cache line */
    __attribute__((aligned(64))) int32_t lower[MAX_N], upper[MAX_N], values[MAX_N];
    for (int i = 0; i < MAX_N; i++) {
        lower[i] = 0;
        upper[i] = 100;
        values[i] = 50;
    }

    printf("%8s %12s %12s %8s\n", "Elements", "Scalar(ns)", "AVX2(ns)", "Speedup");
    printf("%8s %12s %12s %8s\n", "--------", "----------", "--------", "-------");

    int sizes[] = {8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096};
    for (int s = 0; s < 10; s++) {
        int n = sizes[s];
        double ns_scalar = bench_scalar(lower, upper, values, n);
        double ns_avx2 = bench_avx2(lower, upper, values, n);
        printf("%8d %10.1fns %10.1fns %7.1fx\n", n, ns_scalar, ns_avx2, ns_scalar / ns_avx2);
    }

    return 0;
}
