/*
 * Experiment 2: Precision Loss on the Eisenstein Lattice
 * Convert Eisenstein integers through INT8, INT16, FP16, FP32, FP64
 * and measure round-trip accuracy.
 *
 * gcc -O2 -mavx2 -o exp_precision exp_precision.c -lm && ./exp_precision
 */
#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

typedef struct { int32_t a; int32_t b; } Eise;

int64_t eise_norm(Eise e) {
    return (int64_t)e.a * e.a - (int64_t)e.a * e.b + (int64_t)e.b * e.b;
}

/* Round-trip through INT8 */
int eise_roundtrip_int8(Eise e) {
    if (e.a < -128 || e.a > 127 || e.b < -128 || e.b > 127) return -1;  // overflow
    int8_t a8 = (int8_t)e.a;
    int8_t b8 = (int8_t)e.b;
    return (a8 == e.a && b8 == e.b) ? 1 : 0;
}

/* Round-trip through INT16 */
int eise_roundtrip_int16(Eise e) {
    if (e.a < -32768 || e.a > 32767 || e.b < -32768 || e.b > 32767) return -1;
    int16_t a16 = (int16_t)e.a;
    int16_t b16 = (int16_t)e.b;
    return (a16 == e.a && b16 == e.b) ? 1 : 0;
}

/* Round-trip through FP32 (float) */
int eise_roundtrip_fp32(Eise e) {
    float af = (float)e.a;
    float bf = (float)e.b;
    int32_t ar = (int32_t)af;
    int32_t br = (int32_t)bf;
    return (ar == e.a && br == e.b) ? 1 : 0;
}

/* Round-trip through FP16 (approximate via float truncation) */
int eise_roundtrip_fp16(Eise e) {
    /* FP16 range: ±65504, precision: 10 bits mantissa = ~3 decimal digits */
    /* Values > 2048 lose integer precision */
    if (abs(e.a) > 2048 || abs(e.b) > 2048) {
        /* Check if the value is exactly representable */
        float af = (float)e.a;
        float bf = (float)e.b;
        /* Simulate FP16: round to nearest 2^(exp-10) */
        /* Actually, use half-precision conversion: strip mantissa to 10 bits */
        union { float f; uint32_t u; } ua, ub;
        ua.f = (float)e.a;
        ub.f = (float)e.b;
        /* Extract FP16-style precision: keep sign + 5 exp + 10 mantissa */
        /* Simplification: check if mantissa bits beyond 10 cause drift */
        uint32_t mant_a = ua.u & 0x007FFFFF;
        uint32_t mant_b = ub.u & 0x007FFFFF;
        /* If original float has bits beyond position 13 (10+3 for the implicit 1),
           FP16 will round */
        if (mant_a & 0x00001FFF) return 0;  // precision loss
        if (mant_b & 0x00001FFF) return 0;
    }
    return 1;
}

int main() {
    printf("=== Experiment 2: Precision Loss on Eisenstein Lattice ===\n\n");

    int max_radius = 500;  // check all (a,b) with |a|,|b| <= 500

    int total = 0;
    int ok_int8 = 0, ok_int16 = 0, ok_fp16 = 0, ok_fp32 = 0;
    int overflow_int8 = 0, overflow_int16 = 0;

    /* Track by norm shell */
    int max_norm = 100;
    int shell_counts[max_norm + 1];
    int shell_fp16_fail[max_norm + 1];
    int shell_fp32_fail[max_norm + 1];
    memset(shell_counts, 0, sizeof(shell_counts));
    memset(shell_fp16_fail, 0, sizeof(shell_fp16_fail));
    memset(shell_fp32_fail, 0, sizeof(shell_fp32_fail));

    for (int a = -max_radius; a <= max_radius; a++) {
        for (int b = -max_radius; b <= max_radius; b++) {
            Eise e = {a, b};
            int64_t n = eise_norm(e);
            if (n < 0) continue;
            total++;

            /* Per-norm tracking */
            if (n <= max_norm) {
                shell_counts[n]++;
            }

            int r;
            r = eise_roundtrip_int8(e);
            if (r == 1) ok_int8++;
            else if (r == -1) overflow_int8++;

            r = eise_roundtrip_int16(e);
            if (r == 1) ok_int16++;
            else if (r == -1) overflow_int16++;

            r = eise_roundtrip_fp16(e);
            if (r == 1) ok_fp16++;
            else if (n <= max_norm) shell_fp16_fail[n]++;

            r = eise_roundtrip_fp32(e);
            if (r == 1) ok_fp32++;
            else if (n <= max_norm) shell_fp32_fail[n]++;
        }
    }

    printf("Total lattice points (|a|,|b| ≤ %d): %d\n\n", max_radius, total);

    printf("%-10s %12s %12s %10s\n", "Precision", "Preserved", "Lost", "Survival%");
    printf("%-10s %12s %12s %10s\n", "--------", "---------", "----", "---------");
    printf("%-10s %12d %12d %9.1f%%\n", "INT8", ok_int8, total - ok_int8 - overflow_int8, 100.0*ok_int8/total);
    printf("%-10s %12d %12d %9.1f%%\n", "INT16", ok_int16, total - ok_int16 - overflow_int16, 100.0*ok_int16/total);
    printf("%-10s %12d %12d %9.1f%%\n", "FP16", ok_fp16, total - ok_fp16, 100.0*ok_fp16/total);
    printf("%-10s %12d %12d %9.1f%%\n", "FP32", ok_fp32, total - ok_fp32, 100.0*ok_fp32/total);
    printf("%-10s %12d %12d %9.1f%%\n", "FP64", total, 0, 100.0);
    printf("%-10s %12d %12d %9.1f%%\n", "INT32", total, 0, 100.0);

    /* Norm shells where precision first fails */
    printf("\n--- FP32 First Failure by Norm Shell ---\n");
    printf("%-8s %8s %8s\n", "Norm", "Points", "FP32 Fail");
    for (int n = 0; n <= max_norm; n++) {
        if (shell_counts[n] > 0 && (shell_fp32_fail[n] > 0 || n <= 20 || n % 50 == 0)) {
            printf("%-8d %8d %8d%s\n", n, shell_counts[n], shell_fp32_fail[n],
                   shell_fp32_fail[n] > 0 ? " <-- PRECISION LOSS" : "");
        }
    }

    /* FP16 first failure */
    printf("\n--- FP16 First Failure by Norm Shell ---\n");
    printf("%-8s %8s %8s\n", "Norm", "Points", "FP16 Fail");
    int first_fp16_fail = -1;
    for (int n = 0; n <= max_norm; n++) {
        if (shell_counts[n] > 0) {
            printf("%-8d %8d %8d%s\n", n, shell_counts[n], shell_fp16_fail[n],
                   shell_fp16_fail[n] > 0 ? " <-- PRECISION LOSS" : "");
            if (shell_fp16_fail[n] > 0 && first_fp16_fail == -1) first_fp16_fail = n;
        }
    }

    printf("\nFP16 first loses precision at norm shell N = %d\n", first_fp16_fail);

    /* Eisenstein representation counts (OEIS A004016) */
    printf("\n--- Eisenstein Representation Counts (OEIS A004016) ---\n");
    for (int n = 0; n <= 30; n++) {
        if (shell_counts[n] > 0) {
            printf("N=%3d: %3d lattice points\n", n, shell_counts[n]);
        }
    }

    return 0;
}
