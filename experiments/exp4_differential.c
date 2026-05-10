/*
 * Experiment 4: Cross-Language Differential Testing
 * Generate random test vectors, compute with C (ground truth), then verify
 * that Python/numpy and FLUX VM produce identical results.
 *
 * gcc -O2 -o exp_differential exp_differential.c && ./exp_differential > /tmp/diff_vectors.txt
 * Then: python3 experiments/exp4_verify_python.py /tmp/diff_vectors.txt
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

int64_t eisenstein_norm(int32_t a, int32_t b) {
    return (int64_t)a * a - (int64_t)a * b + (int64_t)b * b;
}

uint32_t hash32(uint32_t key) {
    key ^= key >> 16;
    key *= 0x45d9f3b;
    key ^= key >> 16;
    return key;
}

int main() {
    srand(42);  // deterministic seed

    printf("# Polyformalism Differential Test Vectors\n");
    printf("# Format: TYPE arg1 arg2 ... expected_result\n");
    printf("# 1000 random test cases per function\n\n");

    /* Constraint check vectors */
    printf("[CONSTRAINT_CHECK]\n");
    for (int t = 0; t < 1000; t++) {
        int32_t lower[16], upper[16], values[16];
        for (int i = 0; i < 16; i++) {
            lower[i] = rand() % 200 - 100;
            upper[i] = lower[i] + rand() % 200;
            values[i] = rand() % 400 - 200;
        }
        int pass = 1;
        for (int i = 0; i < 16; i++) {
            if (values[i] < lower[i] || values[i] > upper[i]) { pass = 0; break; }
        }
        printf("CC");
        for (int i = 0; i < 16; i++) printf(" %d", lower[i]);
        for (int i = 0; i < 16; i++) printf(" %d", upper[i]);
        for (int i = 0; i < 16; i++) printf(" %d", values[i]);
        printf(" %d\n", pass);
    }

    /* Eisenstein norm vectors */
    printf("\n[EISENSTEIN_NORM]\n");
    for (int t = 0; t < 1000; t++) {
        int32_t a = (rand() % 2000) - 1000;
        int32_t b = (rand() % 2000) - 1000;
        int64_t n = eisenstein_norm(a, b);
        printf("EN %d %d %ld\n", a, b, n);
    }

    /* Bloom merge vectors */
    printf("\n[BLOOM_MERGE]\n");
    for (int t = 0; t < 100; t++) {
        uint64_t dst[10], src[10], expected[10];
        for (int i = 0; i < 10; i++) {
            dst[i] = ((uint64_t)rand() << 32) | rand();
            src[i] = ((uint64_t)rand() << 32) | rand();
            expected[i] = dst[i] | src[i];
        }
        printf("BM");
        for (int i = 0; i < 10; i++) printf(" %lu", dst[i]);
        for (int i = 0; i < 10; i++) printf(" %lu", src[i]);
        for (int i = 0; i < 10; i++) printf(" %lu", expected[i]);
        printf("\n");
    }

    return 0;
}
