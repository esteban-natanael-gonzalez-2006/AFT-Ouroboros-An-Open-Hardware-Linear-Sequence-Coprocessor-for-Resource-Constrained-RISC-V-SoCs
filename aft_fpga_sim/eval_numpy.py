import os, math, time
import numpy as np

# Cargar corpus
p = os.path.expanduser("~/aft_fpga_sim/corpus_curado_100kb.txt")
if not os.path.exists(p):
    p = os.path.expanduser("~/aft-ouroboros/03_data/curated/corpus_curado_100kb.txt")

with open(p, "rb") as f:
    data = np.frombuffer(f.read(), dtype=np.uint8)

n_tr = int(len(data) * 0.8)
tr_data, val_data = data[:n_tr], data[n_tr:]
D, V, SEQ, LR = 64, 256, 64, 0.01

print(f"[+] Dataset: {len(data):,} bytes ({len(tr_data):,} train | {len(val_data):,} val)")

# Ouroboros O-64 / O-128
np.random.seed(42)
W_emb = np.random.randn(V, D).astype(np.float32) * 0.1
Gamma = np.random.randn(D, D).astype(np.float32) * 0.05
Gamma = 0.5 * (Gamma + Gamma.T)
W_head = np.random.randn(V, D).astype(np.float32) * 0.1

t0 = time.time()
for ep in range(1, 4):
    for i in range(0, len(tr_data) - SEQ, SEQ):
        x = tr_data[i:i+SEQ]
        y = tr_data[i+1:i+SEQ+1]
        emb = W_emb[x]
        psi = np.cumsum(emb, axis=0)
        h = emb * (psi @ Gamma)
        logits = h @ W_head.T
        logits -= np.max(logits, axis=-1, keepdims=True)
        probs = np.exp(logits) / np.sum(np.exp(logits), axis=-1, keepdims=True)
        
        grad = probs.copy()
        grad[np.arange(SEQ), y] -= 1.0
        W_head -= (LR / SEQ) * (grad.T @ h)

    val_loss = 0; steps = 0
    for i in range(0, len(val_data) - SEQ, SEQ):
        x = val_data[i:i+SEQ]
        y = val_data[i+1:i+SEQ+1]
        emb = W_emb[x]
        psi = np.cumsum(emb, axis=0)
        h = emb * (psi @ Gamma)
        logits = h @ W_head.T
        logits -= np.max(logits, axis=-1, keepdims=True)
        probs = np.exp(logits) / np.sum(np.exp(logits), axis=-1, keepdims=True)
        val_loss += -np.mean(np.log(probs[np.arange(SEQ), y] + 1e-12))
        steps += 1

    avg_v = val_loss / max(steps, 1)
    print(f"  Epoca {ep}/3 | Val Loss: {avg_v:.4f} nats | PPL: {math.exp(avg_v):.2f}")

print(f"[+] Verificacion completada en {time.time() - t0:.2f}s")
