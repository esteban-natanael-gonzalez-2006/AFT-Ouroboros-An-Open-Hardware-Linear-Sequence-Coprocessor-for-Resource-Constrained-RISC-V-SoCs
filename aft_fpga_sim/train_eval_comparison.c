#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <string.h>
#include <time.h>

#define V 256
#define D 128
#define S 128
#define LR 0.005f

static inline double get_t(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}
static inline float rnd(uint32_t *s) {
    *s ^= *s << 13; *s ^= *s >> 17; *s ^= *s << 5;
    return ((float)*s * (2.0f / 4294967296.0f)) - 1.0f;
}

// 1. AFT Ouroboros O-128 (Lineal O(N))
typedef struct { float emb[V][D], gamma[D][D], head[V][D]; } OuroModel;

void init_ouro(OuroModel *m, uint32_t *r) {
    float sc = 1.0f / sqrtf((float)D);
    for (int v = 0; v < V; v++) for (int d = 0; d < D; d++) m->emb[v][d] = rnd(r) * sc;
    for (int i = 0; i < D; i++) for (int j = i; j < D; j++) {
        float g = rnd(r) * 0.05f; m->gamma[i][j] = g; m->gamma[j][i] = g;
    }
    for (int v = 0; v < V; v++) for (int d = 0; d < D; d++) m->head[v][d] = rnd(r) * sc;
}

float eval_ouro(OuroModel *m, const uint8_t *toks, int len, bool train) {
    float loss = 0.0f, psi[D] = {0};
    for (int t = 0; t < len - 1; t++) {
        uint8_t in = toks[t], tgt = toks[t+1];
        for (int d = 0; d < D; d++) psi[d] += m->emb[in][d];
        
        float z[D] = {0};
        for (int r = 0; r < D; r++)
            for (int c = 0; c < D; c++) z[r] += m->gamma[r][c] * psi[c];

        float out[D];
        for (int d = 0; d < D; d++) out[d] = m->emb[in][d] + (m->emb[in][d] * z[d] * 0.1f);

        float logits[V], max_l = -1e9f;
        for (int v = 0; v < V; v++) {
            float sum = 0;
            for (int d = 0; d < D; d++) sum += m->head[v][d] * out[d];
            logits[v] = sum;
            if (sum > max_l) max_l = sum;
        }

        float sum_e = 0;
        for (int v = 0; v < V; v++) { logits[v] = expf(logits[v] - max_l); sum_e += logits[v]; }
        float p = (logits[tgt] / sum_e);
        if (p < 1e-12f) p = 1e-12f;
        loss += -logf(p);

        if (train) {
            for (int v = 0; v < V; v++) {
                float g = (logits[v] / sum_e) - (v == tgt ? 1.0f : 0.0f);
                for (int d = 0; d < D; d++) {
                    m->head[v][d] -= LR * g * out[d];
                    m->emb[in][d] -= LR * g * m->head[v][d] * 0.1f;
                }
            }
        }
    }
    return loss / (len - 1);
}

// 2. Micro-Transformer Causal (Cuadrático O(N^2))
typedef struct { float emb[V][D], pos[S][D], w_q[D][D], w_k[D][D], w_v[D][D], head[V][D]; } TransModel;

void init_trans(TransModel *m, uint32_t *r) {
    float sc = 1.0f / sqrtf((float)D);
    for (int v = 0; v < V; v++) for (int d = 0; d < D; d++) m->emb[v][d] = rnd(r) * sc;
    for (int t = 0; t < S; t++) for (int d = 0; d < D; d++) m->pos[t][d] = rnd(r) * 0.02f;
    for (int i = 0; i < D; i++) for (int j = 0; j < D; j++) {
        m->w_q[i][j] = rnd(r) * sc; m->w_k[i][j] = rnd(r) * sc; m->w_v[i][j] = rnd(r) * sc;
    }
    for (int v = 0; v < V; v++) for (int d = 0; d < D; d++) m->head[v][d] = rnd(r) * sc;
}

float eval_trans(TransModel *m, const uint8_t *toks, int len, bool train) {
    float loss = 0.0f, x[S][D], Q[S][D], K[S][D], V_mat[S][D], attn[S][D];
    for (int t = 0; t < len; t++)
        for (int d = 0; d < D; d++) x[t][d] = m->emb[toks[t]][d] + m->pos[t][d];

    for (int t = 0; t < len; t++) {
        for (int d = 0; d < D; d++) {
            float sq = 0, sk = 0, sv = 0;
            for (int k = 0; k < D; k++) {
                sq += m->w_q[d][k] * x[t][k]; sk += m->w_k[d][k] * x[t][k]; sv += m->w_v[d][k] * x[t][k];
            }
            Q[t][d] = sq; K[t][d] = sk; V_mat[t][d] = sv;
        }
    }

    float sc = 1.0f / sqrtf((float)D);
    for (int t = 0; t < len; t++) {
        float scores[S], max_s = -1e9f;
        for (int j = 0; j <= t; j++) {
            float dot = 0;
            for (int d = 0; d < D; d++) dot += Q[t][d] * K[j][d];
            scores[j] = dot * sc;
            if (scores[j] > max_s) max_s = scores[j];
        }
        float sum_e = 0;
        for (int j = 0; j <= t; j++) { scores[j] = expf(scores[j] - max_s); sum_e += scores[j]; }
        for (int d = 0; d < D; d++) {
            float sum_v = 0;
            for (int j = 0; j <= t; j++) sum_v += (scores[j] / sum_e) * V_mat[j][d];
            attn[t][d] = sum_v;
        }
    }

    for (int t = 0; t < len - 1; t++) {
        uint8_t tgt = toks[t+1];
        float logits[V], max_l = -1e9f;
        for (int v = 0; v < V; v++) {
            float sum### 1. Diagnóstico del Error
