#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#define D 128
#define SIMD 16
#define NUM_TESTS 5

static const int TEST_N[NUM_TESTS] = {8, 32, 64, 128, 256};

static inline uint32_t xorshift32(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    *state = x; return x;
}

static inline int8_t prng_int8(uint32_t *state) {
    return (int8_t)(xorshift32(state) & 0xFF);
}

int main(void) {
    const char *path_g_hex   = "matrix_gamma.hex";
    const char *path_g_pack  = "matrix_gamma_packed128.hex";
    const char *path_stim    = "stimulus_tokens.hex";
    const char *path_gold    = "golden_output.hex";
    const char *path_acc     = "golden_acc_psi.hex";
    const char *path_s_total = "golden_s_total.hex";

    uint32_t rng = 42;
    int8_t Gamma[D][D];
    for (int i = 0; i < D; i++) {
        for (int j = i; j < D; j++) {
            int8_t val = (i == j) ? (int8_t)((i % 64) - 32) : prng_int8(&rng);
            Gamma[i][j] = val; Gamma[j][i] = val;
        }
    }

    FILE *f_g     = fopen(path_g_hex, "w");
    FILE *f_gpack = fopen(path_g_pack, "w");
    FILE *f_stim  = fopen(path_stim, "w");
    FILE *f_gold  = fopen(path_gold, "w");
    FILE *f_acc   = fopen(path_acc, "w");
    FILE *f_stot  = fopen(path_s_total, "w");

    if (!f_g || !f_gpack || !f_stim || !f_gold || !f_acc || !f_stot) {
        fprintf(stderr, "[-] Error al crear archivos.\n");
        return 1;
    }

    // 1. Matriz plana byte a byte
    for (int i = 0; i < D; i++) {
        for (int j = 0; j < D; j++) fprintf(f_g, "%02X\n", (uint8_t)Gamma[i][j]);
    }
    fclose(f_g);

    // 2. Matriz empaquetada en bloques de 16 bytes (128 bits) para BRAM
    for (int r = 0; r < D; r++) {
        for (int blk = 0; blk < (D / SIMD); blk++) {
            for (int b = SIMD - 1; b >= 0; b--) {
                fprintf(f_gpack, "%02X", (uint8_t)Gamma[r][blk * SIMD + b]);
            }
            fprintf(f_gpack, "\n");
        }
    }
    fclose(f_gpack);

    for (int seq = 0; seq < NUM_TESTS; seq++) {
        int N = TEST_N[seq];
        int8_t *tokens = (int8_t*)malloc(N * D);
        for (int t = 0; t < N; t++) {
            for (int d = 0; d < D; d++) tokens[t * D + d] = prng_int8(&rng);
        }

        for (int t = 0; t < N; t++) {
            int tlast = (t == N - 1) ? 1 : 0;
            fprintf(f_stim, "%d ", tlast);
            for (int d = D - 1; d >= 0; d--) fprintf(f_stim, "%02X", (uint8_t)tokens[t * D + d]);
            fprintf(f_stim, "\n");
        }

        int32_t Psi[D];
        memset(Psi, 0, sizeof(Psi));
        for (int t = 0; t < N; t++) {
            for (int d = 0; d < D; d++) Psi[d] += (int32_t)tokens[t * D + d];
        }

        for (int d = 0; d < D; d++) fprintf(f_acc, "%08X\n", (uint32_t)Psi[d]);

        int64_t F_pair = 0;
        for (int i = 0; i < N; i++) {
            for (int j = i + 1; j < N; j++) {
                int64_t cross = 0;
                for (int r = 0; r < D; r++) {
                    int32_t g_c = 0;
                    for (int c = 0; c < D; c++) g_c += (int32_t)Gamma[r][c] * (int32_t)tokens[j * D + c];
                    cross += (int64_t)tokens[i * D + r] * (int64_t)g_c;
                }
                F_pair += cross;
            }
        }

        int64_t Z[D];
        for (int r = 0; r < D; r++) {
            int64_t s = 0;
            for (int c = 0; c < D; c++) s += (int64_t)Gamma[r][c] * (int64_t)Psi[c];
            Z[r] = s;
        }

        int64_t S_total = 0;
        for (int r = 0; r < D; r++) S_total += (int64_t)Psi[r] * Z[r];

        int64_t S_self = 0;
        for (int t = 0; t < N; t++) {
            for (int r = 0; r < D; r++) {
                int32_t g_tok = 0;
                for (int c = 0; c < D; c++) g_tok += (int32_t)Gamma[r][c] * (int32_t)tokens[t * D + c];
                S_self += (int64_t)tokens[t * D + r] * (int64_t)g_tok;
            }
        }

        int64_t F_desc = (S_total - S_self) / 2;
        fprintf(f_gold, "%d %d %lld %lld %lld %lld\n", seq, N, (long long)F_pair, (long long)F_desc, (long long)S_total, (long long)S_self);
        fprintf(f_stot, "%016llX\n", (unsigned long long)S_total);
        free(tokens);
    }

    fclose(f_stim); fclose(f_gold); fclose(f_acc); fclose(f_stot);
    printf("[+] Archivos actualizados (incluido matrix_gamma_packed128.hex).\n");
    return 0;
}
