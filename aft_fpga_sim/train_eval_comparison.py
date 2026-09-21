import math
import time
import os
import sys

# 1. Comprobación de dependencias
try:
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
except ImportError:
    print("[-] ERROR: PyTorch (torch) no esta instalado en este entorno de Python.")
    print("    Para ejecutar este benchmark comparativo en Termux necesitas PyTorch,")
    print("    o bien podemos ejecutar la comparativa mediante el arnes nativo en C.")
    sys.exit(1)

# Configuración determinista
torch.manual_seed(42)
device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

D_MODEL = 128
VOCAB_SIZE = 256
SEQ_LEN = 128
BATCH_SIZE = 16
EPOCHS = 6
LR = 1e-3

# ==============================================================================
# 1. ARQUITECTURA: AFT OUROBOROS O-128 (CONTRACCIÓN LINEAL O(N))
# ==============================================================================
class OuroborosO128(nn.Module):
    def __init__(self, vocab_size=256, d_model=128):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, d_model)
        self.gamma = nn.Parameter(torch.randn(d_model, d_model) * 0.02)
        self.proj_up = nn.Linear(d_model, d_model * 2)
        self.proj_down = nn.Linear(d_model * 2, d_model)
        self.head = nn.Linear(d_model, vocab_size, bias=False)

    def forward(self, x):
        emb = self.embedding(x) # [B, N, D]
        psi_cum = torch.cumsum(emb, dim=1) # [B, N, D] (Acumulación causal O(N))
        gamma_sym = 0.5 * (self.gamma + self.gamma.T)
        z = torch.matmul(psi_cum, gamma_sym) # [B, N, D]
        inter = emb * z
        h = F.silu(self.proj_up(inter))
        out = self.proj_down(h) + emb
        return self.head(out)

# ==============================================================================
# 2. BASELINE: MICRO-TRANSFORMER CAUSAL O(N^2)
# ==============================================================================
class MicroTransformer(nn.Module):
    def __init__(self, vocab_size=256, d_model=128, nhead=4, num_layers=2):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, d_model)
        self.pos_embedding = nn.Parameter(torch.randn(1, 512, d_model) * 0.02)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=d_model * 2,
            activation='gelu', batch_first=True
        )
        self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        self.head = nn.Linear(d_model, vocab_size, bias=False)

    def forward(self, x):
        B, N = x.shape
        pos = self.pos_embedding[:, :N, :]
        h = self.embedding(x) + pos
        mask = nn.Transformer.generate_square_subsequent_mask(N).to(x.device)
        h = self.transformer(h, mask=mask, is_causal=True)
        return self.head(h)

# ==============================================================================
# 3. PIPELINE DE EVALUACIÓN
# ==============================================================================
def count_parameters(model):
    return sum(p.numel() for p in model.parameters() if p.requires_grad)

def load_data(path, seq_len):
    if not os.path.exists(path):
        print(f"[!] No se encontro {path}. Usando buffer de respaldo de 100 KB...")
        data_bytes = (b"void *memcpy(void *dest, const void *src, size_t n) { char *d = dest; while (n--) *d++ = *(char*)src++; return dest; }\n" * 800)
    else:
        with open(path, 'rb') as f:
            data_bytes = f.read()
            
    tokens = list(data_bytes)
    n = int(len(tokens) * 0.8)
    train_data = torch.tensor(tokens[:n], dtype=torch.long)
    val_data = torch.tensor(tokens[n:], dtype=torch.long)
    return train_data, val_data

def get_batches(data, seq_len, batch_size):
    num_batches = (len(data) - 1) // (seq_len * batch_size)
    for i in range(num_batches):
        idx = i * seq_len * batch_size
        chunk = data[idx : idx + (seq_len * batch_size) + 1]
        x = chunk[:-1].view(batch_size, seq_len)
        y = chunk[1:].view(batch_size, seq_len)
        yield x.to(device), y.to(device)

def train_and_eval(model, train_data, val_data, name):
    print(f"\n================================================================================")
    print(f"  ENTRENANDO: {name} | Parametros: {count_parameters(model):,}")
    print(f"================================================================================")
    optimizer = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=0.01)
    criterion = nn.CrossEntropyLoss()
    
    start_time = time.time()
    tokens_processed = 0
    
    for epoch in range(1, EPOCHS + 1):
        model.train()
        total_loss = 0.0
        n_b = 0
        for x, y in get_batches(train_data, SEQ_LEN, BATCH_SIZE):
            optimizer.zero_grad()
            logits = model(x)
            loss = criterion(logits.view(-1, VOCAB_SIZE), y.view(-1))
            loss.backward()
            optimizer.step()
            total_loss += loss.item()
            n_b += 1
            tokens_processed += x.numel()
        
        # Validación
        model.eval()
        val_loss = 0.0
        v_b = 0
        with torch.no_grad():
            for vx, vy in get_batches(val_data, SEQ_LEN, BATCH_SIZE):
                v_logits = model(vx)
                v_loss = criterion(v_logits.view(-1, VOCAB_SIZE), vy.view(-1))
                val_loss += v_loss.item()
                v_b += 1
        
        avg_train = total_loss / max(n_b, 1)
        avg_val = val_loss / max(v_b, 1)
        ppl = math.exp(avg_val) if avg_val < 15 else float('inf')
        
        print(f"  Epoca {epoch:02d}/{EPOCHS:02d} | Train Loss: {avg_train:.4f} | Val Loss: {avg_val:.4f} | PPL: {ppl:.2f}")
            
    elapsed = time.time() - start_time
    thpt = tokens_processed / max(elapsed, 1e-6)
    print(f"  Throughput: {thpt:,.0f} tokens/s | Tiempo total: {elapsed:.2f}s")
    return avg_val, ppl, thpt

def main():
    data_path = os.path.expanduser("~/aft_fpga_sim/corpus_curado_100kb.txt")
    if not os.path.exists(data_path):
        data_path = os.path.expanduser("~/aft-ouroboros/03_data/curated/corpus_curado_100kb.txt")
        
    train_data, val_data = load_data(data_path, SEQ_LEN)
    print(f"[+] Corpus cargado: {len(train_data):,} bytes train | {len(val_data):,} bytes val")
    
    # 1. Ouroboros O-128
    model_o = OuroborosO128(VOCAB_SIZE, D_MODEL).to(device)
    loss_o, ppl_o, thpt_o = train_and_eval(model_o, train_data, val_data, "AFT Ouroboros O-128 (O(N) Lineal)")
    
    # 2. Transformer Causal Baseline
    model_t = MicroTransformer(VOCAB_SIZE, D_MODEL).to(device)
    loss_t, ppl_t, thpt_t = train_and_eval(model_t, train_data, val_data, "Micro-Transformer (O(N^2) Cuadratico)")
    
    # 3. Cuadro Comparativo
    print("\n================================================================================")
    print("  CUADRO COMPARATIVO DE CAPACIDAD REPRESENTACIONAL (PRESUPUESTO ~1 MiB)")
    print("================================================================================")
    print(f"{'Metrica':<26} | {'Ouroboros O-128':<20} | {'Transformer Causal':<20}")
    print("-" * 72)
    print(f"{'Parametros':<26} | {count_parameters(model_o):<20} | {count_parameters(model_t):<20}")
    print(f"{'Complejidad Contexto':<26} | {'O(N) Lineal':<20} | {'O(N^2) Cuadratica':<20}")
    print(f"{'Validation Loss (nats)':<26} | {loss_o:<20.4f} | {loss_t:<20.4f}")
    print(f"{'Perplejidad (PPL)':<26} | {ppl_o:<20.2f} | {ppl_t:<20.2f}")
    print(f"{'Throughput (tokens/s)':<26} | {thpt_o:<20,.0f} | {thpt_t:<20,.0f}")
    print("================================================================================")

if __name__ == '__main__':
    main()
