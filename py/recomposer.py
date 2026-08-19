"""
recomposer.py — CNN-based event recomposition engine
Part of Praat AudioTools plugin
Version: 1.2.3 (2026)


Usage:
    python recomposer.py input_events.csv output_plan.csv

Pipeline:
    1. Parse per-event trajectory sequences from CSV
    2. Resample each event to T=128 frames, build [N, T, F] feature tensor
    3. Robust normalisation across all events (including event duration)
    4. Train a NumPy CNN (multi-scale conv + self-supervised contrastive loss)
    5. Extract embeddings [N, D=32]
    6. Unit-sphere embedding geometry + data-driven K-means (k=2..4)
    7. Compute morphology_score from source-rate motion proxies + CNN activations + explicit 10% duration
    8. Build selected montage form (sorted/braid/phase/walk) → output_plan.csv

Constraints: numpy + scikit-learn only (no torch/tensorflow, no model saving)
"""

import csv
import sys
import math
import numpy as np
from sklearn.cluster import KMeans

# ─────────────────────────────────────────────────────────────────────────────
# Global constants
# ─────────────────────────────────────────────────────────────────────────────

SEED        = 42
T_FIXED     = 128          # resample every event to this many frames
F_DIM       = 8            # + duration_s as an invariant event-scale feature
D_EMB       = 32           # embedding dimension
N_CLUSTERS  = 4            # maximum k; k is selected from 2..4 when possible
EPOCHS      = 120          # contrastive training epochs
LR          = 3e-4         # Adam learning rate
TEMPERATURE = 0.5          # NT-Xent temperature
BATCH_SIZE  = 32           # contrastive batch (pairs)
POOL_SIZE   = 4            # temporal max-pool stride
DURATION_IDX = 7           # invariant feature; excluded from temporal augmentation noise/dropout

np.random.seed(SEED)

# ─────────────────────────────────────────────────────────────────────────────
# 1. CSV parsing
# ─────────────────────────────────────────────────────────────────────────────

def parse_seq(s):
    """Parse 'v1;v2;v3;...' into a finite float array. Blank -> empty."""
    s = s.strip().strip('"')
    if not s:
        return np.array([], dtype=np.float32)
    vals = []
    for token in s.split(";"):
        token = token.strip()
        if not token:
            continue
        try:
            v = float(token)
        except ValueError:
            v = 0.0
        vals.append(v if math.isfinite(v) else 0.0)
    return np.asarray(vals, dtype=np.float32)


def load_events(path):
    """
    Read input_events.csv.
    Returns list of dicts with keys:
        event_id, start_time_s, end_time_s, duration_s,
        pitch_hz, intensity_db, hnr_db, voiced,
        spectral_centroid_hz, spectral_spread_hz, zcr
    Each trajectory key holds a 1-D float32 array.
    """
    events = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ev = {
                "event_id":    int(row["event_id"]),
                "start_time_s": float(row["start_time_s"]),
                "end_time_s":   float(row["end_time_s"]),
                "duration_s":   float(row["duration_s"]),
                "pitch_hz":     parse_seq(row["pitch_seq_hz"]),
                "intensity_db": parse_seq(row["intensity_seq_db"]),
                "hnr_db":       parse_seq(row["hnr_seq_db"]),
                "voiced":       parse_seq(row["voiced_seq"]),
                "spectral_centroid": parse_seq(row.get("spectral_centroid_seq_hz", "")),
                "spectral_spread":   parse_seq(row.get("spectral_spread_seq_hz", "")),
                "zcr":               parse_seq(row.get("zcr_seq", "")),
            }
            events.append(ev)
    return events


# ─────────────────────────────────────────────────────────────────────────────
# 2. Feature tensor construction
# ─────────────────────────────────────────────────────────────────────────────

def resample_1d(arr, target):
    """Linear resample 1-D array to exactly `target` points."""
    n = len(arr)
    if n == 0:
        return np.zeros(target, dtype=np.float32)
    if n == 1:
        return np.full(target, arr[0], dtype=np.float32)
    x_old = np.linspace(0.0, 1.0, n)
    x_new = np.linspace(0.0, 1.0, target)
    return np.interp(x_new, x_old, arr).astype(np.float32)


def build_feature_tensor(events):
    """
    Returns X of shape [N, T_FIXED, F_DIM].

    Dynamic feature order:
      pitch_hz, intensity_db, hnr_db, voiced_flag,
      spectral_centroid_hz, spectral_spread_hz, zcr

    The final channel is event duration in seconds, repeated across time so the
    CNN does not confuse identical normalised shapes at radically different
    absolute durations. It is treated as invariant by augment().
    """
    N = len(events)
    X = np.zeros((N, T_FIXED, F_DIM), dtype=np.float32)
    for i, ev in enumerate(events):
        X[i, :, 0] = resample_1d(ev["pitch_hz"],          T_FIXED)
        X[i, :, 1] = resample_1d(ev["intensity_db"],      T_FIXED)
        X[i, :, 2] = resample_1d(ev["hnr_db"],            T_FIXED)
        X[i, :, 3] = resample_1d(ev["voiced"],            T_FIXED)
        X[i, :, 4] = resample_1d(ev["spectral_centroid"], T_FIXED)
        X[i, :, 5] = resample_1d(ev["spectral_spread"],   T_FIXED)
        X[i, :, 6] = resample_1d(ev["zcr"],               T_FIXED)
        dur = float(ev.get("duration_s", 0.0))
        X[i, :, DURATION_IDX] = max(0.0, dur) if math.isfinite(dur) else 0.0

    # Last-resort safety: malformed numerical input should not poison training.
    return np.nan_to_num(X, nan=0.0, posinf=0.0, neginf=0.0)


def robust_normalize(X):
    """
    Per-feature robust normalisation using median and IQR across all events.
    Returns normalised X_norm and (median, scale) for each feature.
    """
    N, T, F = X.shape
    Xf = X.reshape(-1, F)   # [N*T, F]
    medians = np.median(Xf, axis=0)
    q75 = np.percentile(Xf, 75, axis=0)
    q25 = np.percentile(Xf, 25, axis=0)
    scales = q75 - q25
    scales[scales < 1e-6] = 1.0   # avoid division by zero for constant features
    X_norm = (X - medians) / scales
    return X_norm.astype(np.float32), medians, scales


# ─────────────────────────────────────────────────────────────────────────────
# 3. NumPy CNN — forward pass utilities
# ─────────────────────────────────────────────────────────────────────────────

def im2col_1d(x, k, pad):
    """
    x: [T, C]  →  col: [T_padded - k + 1, k*C]   (valid conv after padding)
    """
    if pad > 0:
        x = np.pad(x, ((pad, pad), (0, 0)), mode="edge")
    T_p, C = x.shape
    T_out = T_p - k + 1
    return np.lib.stride_tricks.sliding_window_view(
        x, (k, C)).reshape(T_out, k * C)


def conv1d_same_forward(x, W, b):
    """
    Same-padded 1-D convolution.
    x: [T, C_in]
    W: [k, C_in, C_out]
    b: [C_out]
    returns out: [T, C_out], cache
    """
    k, C_in, C_out = W.shape
    pad = k // 2
    col = im2col_1d(x, k, pad)              # [T, k*C_in]
    W_flat = W.reshape(-1, C_out)           # [k*C_in, C_out]
    out = col @ W_flat + b                  # [T, C_out]
    return out, (x, col, W_flat, k, pad)


def conv1d_same_backward(dout, cache, need_dx=True):
    """Returns dx, dW, db. Skip input-gradient work when need_dx=False."""
    x, col, W_flat, k, pad = cache
    T, C_in = x.shape

    db = dout.sum(axis=0)
    dW_flat = col.T @ dout
    k_val = W_flat.shape[0] // C_in
    dW = dW_flat.reshape(k_val, C_in, dout.shape[1])
    if not need_dx:
        return None, dW, db

    dcol = dout @ W_flat.T
    dx_padded = np.zeros((T + 2 * pad, C_in), dtype=x.dtype)
    for t in range(T):
        dx_padded[t:t + k_val] += dcol[t].reshape(k_val, C_in)

    if pad > 0:
        # Forward used mode="edge": padded samples are copies of x[0]/x[-1].
        # Their gradients therefore belong to those edge samples too.
        dx = dx_padded[pad:pad + T].copy()
        dx[0]  += dx_padded[:pad].sum(axis=0)
        dx[-1] += dx_padded[pad + T:].sum(axis=0)
    else:
        dx = dx_padded

    dW = dW_flat.reshape(k_val, C_in, dout.shape[1])
    return dx, dW, db


def relu(x):
    return np.maximum(0.0, x)


def relu_backward(dout, x):
    return dout * (x > 0)


def maxpool1d_forward(x, size):
    """x: [T, C] → [T//size, C], with mask for backward."""
    T, C = x.shape
    T_out = T // size
    x_crop = x[:T_out * size].reshape(T_out, size, C)
    out = x_crop.max(axis=1)
    mask = (x_crop == out[:, None, :])          # [T_out, size, C]
    return out, (mask, size, T)


def maxpool1d_backward(dout, cache):
    mask, size, T = cache
    T_out, C = dout.shape
    d = dout[:, None, :] * mask                 # [T_out, size, C]
    # average when multiple maxima
    counts = mask.sum(axis=1, keepdims=True)
    counts = np.maximum(counts, 1)
    d = d / counts
    dx = d.reshape(T_out * size, C)
    if dx.shape[0] < T:
        dx = np.pad(dx, ((0, T - dx.shape[0]), (0, 0)))
    return dx


def global_pool_forward(x):
    """x: [T, C] → mean [C] + max [C] → concat [2C]"""
    mean_out = x.mean(axis=0)
    max_out  = x.max(axis=0)
    return np.concatenate([mean_out, max_out]), (x,)


def global_pool_backward(dout, cache):
    (x,) = cache
    T, C = x.shape
    d_mean = dout[:C]
    d_max  = dout[C:]
    dx_mean = np.broadcast_to(d_mean / T, (T, C)).copy()
    dx_max  = d_max * (x == x.max(axis=0, keepdims=True))
    counts  = (x == x.max(axis=0, keepdims=True)).sum(axis=0, keepdims=True)
    dx_max  = dx_max / np.maximum(counts, 1)
    return dx_mean + dx_max


def dense_forward(x, W, b):
    """x: [in] → out: [out]"""
    out = x @ W + b
    return out, (x, W)


def dense_backward(dout, cache):
    x, W = cache
    dW = np.outer(x, dout)
    db = dout
    dx = W @ dout
    return dx, dW, db


# ─────────────────────────────────────────────────────────────────────────────
# 4. CNN class
# ─────────────────────────────────────────────────────────────────────────────

class NumpyCNN:
    """
    Architecture (per event, input [T=128, F=8]):

      Branch A: Conv1D(k=9,  C_in=4, C_out=8, same) → ReLU
      Branch B: Conv1D(k=21, C_in=4, C_out=8, same) → ReLU
      Concat along channels → [T, 16]
      MaxPool1D(size=4)     → [32, 16]
      Conv1D(k=9, C_in=16, C_out=16, same) → ReLU  → [32, 16]
      GlobalMeanPool + GlobalMaxPool → [32]
      Dense(32 → 32)

    Embedding: [32]
    """

    def __init__(self):
        rng = np.random.RandomState(SEED)

        def he(shape):
            fan_in = shape[0] * shape[1] if len(shape) == 3 else shape[0]
            return rng.randn(*shape).astype(np.float32) * math.sqrt(2.0 / fan_in)

        # Branch A: k=9
        self.WA = he((9,  F_DIM, 8));  self.bA = np.zeros(8,  np.float32)
        # Branch B: k=21
        self.WB = he((21, F_DIM, 8));  self.bB = np.zeros(8,  np.float32)
        # Conv2
        self.W2 = he((9,  16,   16));  self.b2 = np.zeros(16, np.float32)
        # Dense
        self.Wd = he((32,       32));  self.bd = np.zeros(32, np.float32)

        # Adam state
        self._params = ["WA","bA","WB","bB","W2","b2","Wd","bd"]
        self._m = {p: np.zeros_like(getattr(self, p)) for p in self._params}
        self._v = {p: np.zeros_like(getattr(self, p)) for p in self._params}
        self._t = 0

    # ── forward (single event x: [T, F]) ────────────────────────────────────
    def forward(self, x, store=True):
        cA_pre, cA_c = conv1d_same_forward(x,  self.WA, self.bA)
        cA = relu(cA_pre)
        cB_pre, cB_c = conv1d_same_forward(x,  self.WB, self.bB)
        cB = relu(cB_pre)

        cat = np.concatenate([cA, cB], axis=1)       # [T, 16]
        pool, pool_c = maxpool1d_forward(cat, POOL_SIZE)   # [T//4, 16]

        c2_pre, c2_c = conv1d_same_forward(pool, self.W2, self.b2)
        c2 = relu(c2_pre)

        gp, gp_c = global_pool_forward(c2)           # [32]
        emb, d_c = dense_forward(gp, self.Wd, self.bd)  # [32]

        if store:
            self._cache = dict(
                x=x, cA_pre=cA_pre, cA_c=cA_c, cA=cA,
                cB_pre=cB_pre, cB_c=cB_c, cB=cB,
                cat=cat, pool=pool, pool_c=pool_c,
                c2_pre=c2_pre, c2_c=c2_c, c2=c2,
                gp=gp, gp_c=gp_c, emb=emb, d_c=d_c
            )
        return emb

    # ── backward (single event, grad w.r.t. output emb) ─────────────────────
    def backward(self, d_emb):
        c = self._cache
        grads = {}

        d_gp, grads["Wd"], grads["bd"] = dense_backward(d_emb, c["d_c"])
        d_c2 = global_pool_backward(d_gp, c["gp_c"])
        d_c2_pre = relu_backward(d_c2, c["c2_pre"])
        d_pool, grads["W2"], grads["b2"] = conv1d_same_backward(d_c2_pre, c["c2_c"])

        d_cat = maxpool1d_backward(d_pool, c["pool_c"])
        d_cA = d_cat[:, :8]
        d_cB = d_cat[:, 8:]

        d_cA_pre = relu_backward(d_cA, c["cA_pre"])
        _, grads["WA"], grads["bA"] = conv1d_same_backward(d_cA_pre, c["cA_c"], need_dx=False)

        d_cB_pre = relu_backward(d_cB, c["cB_pre"])
        _, grads["WB"], grads["bB"] = conv1d_same_backward(d_cB_pre, c["cB_c"], need_dx=False)

        return grads

    # ── Adam step ────────────────────────────────────────────────────────────
    def adam_step(self, grads, lr=LR, b1=0.9, b2=0.999, eps=1e-8):
        self._t += 1
        t = self._t
        for p in self._params:
            g = grads[p]
            self._m[p] = b1 * self._m[p] + (1 - b1) * g
            self._v[p] = b2 * self._v[p] + (1 - b2) * g * g
            m_hat = self._m[p] / (1 - b1 ** t)
            v_hat = self._v[p] / (1 - b2 ** t)
            setattr(self, p, getattr(self, p) - lr * m_hat / (np.sqrt(v_hat) + eps))

    # ── accumulate grads over a batch ────────────────────────────────────────
    def zero_grads(self):
        self._accum = {p: np.zeros_like(getattr(self, p)) for p in self._params}

    def accumulate(self, grads):
        for p in self._params:
            self._accum[p] += grads[p]

    def step(self, batch_size, lr=LR):
        g = {p: self._accum[p] / max(batch_size, 1) for p in self._params}
        self.adam_step(g, lr=lr)

    # ── embed all events (no grad) ───────────────────────────────────────────
    def embed_all(self, X):
        N = X.shape[0]
        E = np.zeros((N, D_EMB), np.float32)
        for i in range(N):
            E[i] = self.forward(X[i], store=False)
        return E

    # ── internal activations for morphology scoring ──────────────────────────
    def get_activations(self, X):
        """
        Returns pool-level activations [N, T//4, 16] used for morphology scoring.
        """
        N = X.shape[0]
        T_pool = T_FIXED // POOL_SIZE
        acts = np.zeros((N, T_pool, 16), np.float32)
        for i in range(N):
            x = X[i]
            cA_pre, _ = conv1d_same_forward(x, self.WA, self.bA)
            cA = relu(cA_pre)
            cB_pre, _ = conv1d_same_forward(x, self.WB, self.bB)
            cB = relu(cB_pre)
            cat = np.concatenate([cA, cB], axis=1)
            pool, _ = maxpool1d_forward(cat, POOL_SIZE)
            acts[i] = pool
        return acts


# ─────────────────────────────────────────────────────────────────────────────
# 5. Augmentation
# ─────────────────────────────────────────────────────────────────────────────

def augment(x, rng):
    """
    Produce a morphology-preserving augmented view of one event.

    Only dynamic channels are perturbed. The duration channel is an invariant
    event-scale descriptor and is restored unchanged after augmentation.
    Time jitter uses edge fill rather than circular wrap, so the tail of an
    event can never reappear artificially at its beginning.
    """
    T, F = x.shape
    x0 = x.copy()
    x = x.copy()
    dyn_F = min(DURATION_IDX, F)

    # Small noise on dynamic acoustic trajectories only.
    x[:, :dyn_F] += rng.randn(T, dyn_F).astype(np.float32) * 0.05

    # Frame dropout: zero in normalised space means "median", not hard silence.
    n_drop = max(1, int(T * 0.10))
    drop_idx = rng.choice(T, n_drop, replace=False)
    x[drop_idx, :dyn_F] = 0.0

    # Non-circular time jitter with edge replication.
    shift = int(rng.randint(-3, 4))
    if shift > 0:
        x[shift:, :dyn_F] = x[:-shift, :dyn_F]
        x[:shift, :dyn_F] = x[shift, :dyn_F]
    elif shift < 0:
        s = -shift
        x[:-s, :dyn_F] = x[s:, :dyn_F]
        x[-s:, :dyn_F] = x[-s-1, :dyn_F]

    # Slight time warp of dynamic channels only.
    if rng.rand() < 0.5:
        warp_amp = 0.07
        t_orig = np.linspace(0, 1, T)
        t_warp = t_orig + warp_amp * np.sin(np.pi * t_orig * rng.uniform(1, 3))
        t_warp = np.clip(t_warp, 0, 1)
        x_warp = x.copy()
        for f in range(dyn_F):
            x_warp[:, f] = np.interp(t_warp, t_orig, x[:, f])
        x = x_warp

    if F > DURATION_IDX:
        x[:, DURATION_IDX] = x0[:, DURATION_IDX]
    return x


def l2_normalize(E):
    norms = np.linalg.norm(E, axis=1, keepdims=True)
    norms = np.maximum(norms, 1e-8)
    return E / norms


def nt_xent_loss_and_grad(E_a, E_p, tau=TEMPERATURE):
    """
    Symmetric NT-Xent / InfoNCE over two augmented views.

    Both directions (A->P and P->A) are included. Embeddings are L2-normalised
    inside the loss, so every downstream geometric operation must use the same
    unit-sphere representation.
    """
    B, _ = E_a.shape
    Ea = l2_normalize(E_a)
    Ep = l2_normalize(E_p)

    def one_direction(Q, K):
        S = Q @ K.T / tau
        S_max = S.max(axis=1, keepdims=True)
        exp_S = np.exp(S - S_max)
        denom = np.maximum(exp_S.sum(axis=1, keepdims=True), 1e-10)
        log_softmax = S - S_max - np.log(denom)
        loss = -log_softmax[np.arange(B), np.arange(B)].mean()
        dS = exp_S / denom
        dS[np.arange(B), np.arange(B)] -= 1.0
        dS /= (B * tau)
        return loss, dS @ K, dS.T @ Q

    loss_ap, dEa_ap, dEp_ap = one_direction(Ea, Ep)
    loss_pa, dEp_pa, dEa_pa = one_direction(Ep, Ea)
    loss = 0.5 * (loss_ap + loss_pa)
    dEa_norm = 0.5 * (dEa_ap + dEa_pa)
    dEp_norm = 0.5 * (dEp_ap + dEp_pa)

    def l2_norm_backward(dout, E_unnorm):
        norms = np.maximum(np.linalg.norm(E_unnorm, axis=1, keepdims=True), 1e-8)
        E_n = E_unnorm / norms
        return (dout - (dout * E_n).sum(axis=1, keepdims=True) * E_n) / norms

    return loss, l2_norm_backward(dEa_norm, E_a), l2_norm_backward(dEp_norm, E_p)


def train_contrastive(cnn, X, epochs=EPOCHS, lr=LR, verbose=True):
    N = X.shape[0]
    rng = np.random.RandomState(SEED + 1)
    best_loss = float("inf")
    best_params = {p: getattr(cnn, p).copy() for p in cnn._params}
    initial_params = {p: getattr(cnn, p).copy() for p in cnn._params}
    diverged = False

    for epoch in range(epochs):
        idx = rng.permutation(N)
        epoch_loss = 0.0
        n_batches = 0

        for start in range(0, N, BATCH_SIZE):
            batch_idx = idx[start:start + BATCH_SIZE]
            B = len(batch_idx)
            if B < 2:
                continue

            E_a = np.zeros((B, D_EMB), np.float32)
            E_p = np.zeros((B, D_EMB), np.float32)
            caches_a, caches_p = [], []

            for j, i in enumerate(batch_idx):
                xa = augment(X[i], rng)
                xp = augment(X[i], rng)
                E_a[j] = cnn.forward(xa, store=True)
                caches_a.append(dict(cnn._cache))
                E_p[j] = cnn.forward(xp, store=True)
                caches_p.append(dict(cnn._cache))

            loss, dEa, dEp = nt_xent_loss_and_grad(E_a, E_p)
            if not np.isfinite(loss) or loss > 1e4:
                diverged = True
                break

            epoch_loss += float(loss)
            n_batches += 1

            cnn.zero_grads()
            for j in range(B):
                cnn._cache = caches_a[j]
                cnn.accumulate(cnn.backward(dEa[j]))
                cnn._cache = caches_p[j]
                cnn.accumulate(cnn.backward(dEp[j]))
            cnn.step(B * 2, lr=lr)

        if diverged:
            break

        avg = epoch_loss / max(n_batches, 1)
        if avg < best_loss:
            best_loss = avg
            best_params = {p: getattr(cnn, p).copy() for p in cnn._params}
        if verbose and (epoch % 20 == 0 or epoch == epochs - 1):
            print(f"[CNN] epoch {epoch+1:3d}/{epochs}  loss={avg:.4f}",
                  file=sys.stderr)

    if diverged:
        print("  [CNN] WARNING: training diverged — restoring initial weights.",
              file=sys.stderr)
        for p, v in initial_params.items():
            setattr(cnn, p, v)
        cnn.training_valid = False
    else:
        # Use the best observed epoch, not merely the final one.
        for p, v in best_params.items():
            setattr(cnn, p, v)
        cnn.training_valid = True
        if verbose:
            print(f"  [CNN] best loss={best_loss:.4f}; best checkpoint restored",
                  file=sys.stderr)

    return cnn



def acoustic_summary_embeddings(X):
    """
    Deterministic fallback embedding for very small corpora or failed training.

    Uses per-feature mean, standard deviation, and temporal motion from the
    already robust-normalised trajectories, plus the invariant duration channel.
    The vector is padded/truncated to D_EMB and then L2-normalised downstream.
    """
    X = np.asarray(X, dtype=np.float32)
    dyn = X[:, :, :DURATION_IDX]
    means = dyn.mean(axis=1)
    stds = dyn.std(axis=1)
    if dyn.shape[1] > 1:
        motion = np.abs(np.diff(dyn, axis=1)).mean(axis=1)
    else:
        motion = np.zeros_like(means)
    dur = X[:, :, DURATION_IDX].mean(axis=1, keepdims=True)
    feat = np.concatenate([means, stds, motion, dur], axis=1).astype(np.float32)
    out = np.zeros((len(X), D_EMB), dtype=np.float32)
    n = min(D_EMB, feat.shape[1])
    out[:, :n] = feat[:, :n]
    return out


def _scale_proxy_matrix(proxies, min_relative_span=0.02):
    """
    Column-wise min-max scaling to [0,1] without magnifying numerical trivia.

    A proxy whose corpus span is less than 2% of its characteristic magnitude
    is treated as effectively constant. This prevents tiny interpolation/CNN
    differences from being stretched into a false 0..1 contrast.
    """
    proxies = np.asarray(proxies, dtype=np.float64)
    scaled = np.zeros_like(proxies)
    if proxies.size == 0:
        return scaled
    for j in range(proxies.shape[1]):
        col = proxies[:, j]
        lo, hi = float(np.min(col)), float(np.max(col))
        span = hi - lo
        characteristic = max(abs(float(np.median(col))), abs(lo), abs(hi), 1e-8)
        if span > max(1e-10, min_relative_span * characteristic):
            scaled[:, j] = (col - lo) / span
    return scaled


def _event_native_frames(event):
    """Best available native analysis-frame count before T_FIXED resampling."""
    lengths = []
    for key in ("intensity_db", "pitch_hz", "hnr_db", "voiced",
                "spectral_centroid", "spectral_spread", "zcr"):
        arr = event.get(key)
        if arr is not None and len(arr) > 0:
            lengths.append(len(arr))
    return max(lengths) if lengths else 2


def compute_event_morphology_scores(cnn, X, X_raw, events, use_cnn=True):
    """
    Continuous per-event morphology score used by the compositional forms.

    Temporal-motion proxies are measured on the fixed-length resampled tensor,
    then converted to source-time rates using the event's native frame count:

        rate_scale = (T_FIXED - 1) / (n_native - 1)

    This removes the hidden dependence on how strongly an event had to be
    stretched/compressed to reach T_FIXED frames. Event duration is retained as
    an EXPLICIT seventh proxy, with a fixed 10% weight rather than leaking into
    the motion proxies. The six acoustic/CNN proxies share the remaining 90%.
    """
    N = len(X)
    proxies = np.zeros((N, 7), dtype=np.float64)
    acts = cnn.get_activations(X) if use_cnn and N else None

    for i in range(N):
        xi = X[i]
        n_native = max(2, int(_event_native_frames(events[i])))
        rate_scale = (max(2, xi.shape[0]) - 1) / float(n_native - 1)

        if xi.shape[0] > 1:
            proxies[i, 0] = float(np.mean(np.abs(np.diff(xi[:, 0])))) * rate_scale  # pitch rate
            proxies[i, 1] = float(np.mean(np.abs(np.diff(xi[:, 1])))) * rate_scale  # intensity rate
            proxies[i, 2] = float(np.mean(np.abs(np.diff(xi[:, 2])))) * rate_scale  # HNR rate
            cm = float(np.mean(np.abs(np.diff(xi[:, 4])))) * rate_scale
            sm = float(np.mean(np.abs(np.diff(xi[:, 5])))) * rate_scale
            proxies[i, 3] = 0.5 * (cm + sm)                                       # spectral-motion rate
            # Voicing is a state transition density; apply the same source-rate
            # correction so a fixed number of transitions is not duration-biased.
            proxies[i, 4] = float(np.mean(np.abs(np.diff(X_raw[i, :, 3])))) * rate_scale

        if acts is not None:
            mean_act = acts[i].mean(axis=0)
            p = np.abs(mean_act)
            if p.sum() > 1e-12:
                p /= p.sum()
                proxies[i, 5] = -float(np.sum(p * np.log(p + 1e-10))) / math.log(len(p))

        # Explicit duration proxy. Log compression keeps a single long event from
        # dominating before robust across-event scaling.
        proxies[i, 6] = math.log1p(max(0.0, float(events[i].get("duration_s", 0.0))))

    scaled = _scale_proxy_matrix(proxies)
    if N:
        weights = np.array([0.15, 0.15, 0.15, 0.15, 0.15, 0.15, 0.10],
                           dtype=np.float64)
        scores = scaled @ weights
    else:
        scores = np.zeros(0, dtype=np.float64)

    # The weighted sum is already in [0,1]. Do NOT min-max it again: doing so
    # would erase the explicit proxy weights (e.g. make a 10% duration term span
    # the full 0..1 range when duration is the only varying proxy).
    return scores.astype(np.float64), proxies


def compute_morphology_scores(cnn, X, labels, k, X_raw, events, use_cnn=True):
    """Cluster morphology = mean of the corrected per-event scores."""
    event_scores, event_proxies = compute_event_morphology_scores(
        cnn, X, X_raw, events, use_cnn=use_cnn)
    scores = np.zeros(k, dtype=np.float64)
    proxies = np.zeros((k, event_proxies.shape[1]), dtype=np.float64)
    for cid in range(k):
        idx = np.where(labels == cid)[0]
        if len(idx):
            scores[cid] = float(np.mean(event_scores[idx]))
            proxies[cid] = np.mean(event_proxies[idx], axis=0)

    # Event scores are already calibrated to [0,1]; cluster means therefore are
    # too. Preserve their actual span instead of forcing every corpus to 0..1.
    return scores, proxies


def _cluster_distances(E_unit, labels, k):
    """Euclidean distance to each event's centroid on the unit sphere."""
    centers = np.zeros((k, E_unit.shape[1]), dtype=np.float64)
    for cid in range(k):
        pts = E_unit[labels == cid]
        if len(pts):
            c = pts.mean(axis=0)
            n = np.linalg.norm(c)
            centers[cid] = c / max(n, 1e-12)
    d = np.zeros(len(E_unit), dtype=np.float64)
    for i in range(len(E_unit)):
        d[i] = np.linalg.norm(E_unit[i] - centers[int(labels[i])])
    return d


def _make_row(new_index, i, events, labels, morphology_scores, cluster_dist):
    ev = events[i]
    cid = int(labels[i])
    return {
        "new_index":                new_index,
        "orig_event_id":            ev["event_id"],
        "orig_start_time_s":        ev["start_time_s"],
        "orig_end_time_s":          ev["end_time_s"],
        "cluster_id":               cid,
        "cluster_morphology_score": float(morphology_scores[cid]),
        "cluster_distance":         float(cluster_dist[i]),
    }


def _cluster_buckets(N, labels, events, k):
    """Returns dict cid → [event indices] sorted chronologically."""
    buckets = {cid: [] for cid in range(k)}
    for i in range(N):
        buckets[int(labels[i])].append(i)
    for cid in buckets:
        buckets[cid].sort(key=lambda i: events[i]["event_id"])
    return buckets


def _temporal_braid_order(N):
    """0, N-1, 1, N-2, ...; deterministic fallback for degenerate spaces."""
    out = []
    lo, hi = 0, N - 1
    while lo <= hi:
        out.append(lo)
        if hi != lo:
            out.append(hi)
        lo += 1
        hi -= 1
    return out


def _temporal_phase_order(N):
    """Two explicit temporal phases: even-indexed events, then odd-indexed."""
    return list(range(0, N, 2)) + list(range(1, N, 2))


def _center_out_order(N):
    """Chronological center, then alternately spread left/right."""
    if N <= 0:
        return []
    c = (N - 1) // 2
    out = [c]
    step = 1
    while len(out) < N:
        r = c + step
        l = c - step
        if r < N:
            out.append(r)
        if l >= 0 and len(out) < N:
            out.append(l)
        step += 1
    return out


def build_plan(events, labels, morphology_scores, embeddings, form="sorted",
               event_morphology=None):
    """
    Build four genuinely different compositional traversals.

    The v1.2 cluster-only design collapsed all forms to chronological order when
    K-means returned k=1.  v1.2.2 uses continuous per-event morphology for the
    form layer, while preserving clusters as descriptive annotations.

    sorted — continuous morphology low -> high.
    braid  — braid low/high morphology extremes.
    phase  — stable half first in time, richer half second in reverse time.
    walk   — nearest-neighbour walk on unit embeddings; if embedding geometry is
             degenerate, an explicit center-out temporal fallback is used.
    """
    N = len(events)
    k = len(morphology_scores)
    E = l2_normalize(np.asarray(embeddings, dtype=np.float64))
    cluster_dist = _cluster_distances(E, labels, k)

    if event_morphology is None or len(event_morphology) != N:
        event_morphology = np.zeros(N, dtype=np.float64)
    M = np.asarray(event_morphology, dtype=np.float64)
    morph_span = float(np.ptp(M)) if N else 0.0
    morph_degenerate = morph_span < 1e-10

    # Rank by event morphology, not only cluster identity.
    ranked = sorted(range(N), key=lambda i: (float(M[i]), events[i]["event_id"]))

    sorted_order = ranked if not morph_degenerate else list(range(N))

    if not morph_degenerate:
        # Weave the two acoustic extremes toward the middle.
        braid_order = []
        lo, hi = 0, N - 1
        while lo <= hi:
            braid_order.append(ranked[lo])
            if hi != lo:
                braid_order.append(ranked[hi])
            lo += 1
            hi -= 1

        half = max(1, N // 2)
        stable = set(ranked[:half])
        rich = set(ranked[half:])
        # Preserve source-time continuity inside the stable phase, then make the
        # richer phase move backward through source time for a clearly different
        # dramaturgical gesture.
        phase_order = sorted(stable, key=lambda i: events[i]["event_id"])
        phase_order += sorted(rich, key=lambda i: events[i]["event_id"], reverse=True)
    else:
        braid_order = _temporal_braid_order(N)
        phase_order = _temporal_phase_order(N)
        print("  [form] WARNING: event morphology is degenerate; "
              "braid/phase use explicit temporal fallbacks.", file=sys.stderr)

    # Learned nearest-neighbour walk. Detect a geometry with no usable pairwise
    # contrast rather than silently returning 1->2->3... for every form.
    if N <= 1:
        walk_order = list(range(N))
        emb_degenerate = True
    else:
        D = np.linalg.norm(E[:, None, :] - E[None, :, :], axis=2)
        emb_span = float(np.max(D))
        emb_degenerate = emb_span < 1e-8
        if not emb_degenerate:
            current = int(np.argmin(D.mean(axis=1)))
            remaining = set(range(N))
            remaining.remove(current)
            walk_order = [current]
            while remaining:
                rem_list = sorted(remaining)
                dists = D[current, rem_list]
                nearest = rem_list[int(np.argmin(dists))]
                remaining.remove(nearest)
                walk_order.append(nearest)
                current = nearest
        else:
            walk_order = _center_out_order(N)
            print("  [form] WARNING: embedding geometry is degenerate; "
                  "walk uses center-out temporal fallback.", file=sys.stderr)

    # If the learned NN happens to be identical to the neutral sorted traversal,
    # make the degeneracy visible and use a deterministic spread traversal. This
    # is a compositional tool: four menu choices must not silently emit the same
    # montage plan.
    if N >= 3 and walk_order == sorted_order:
        walk_order = _center_out_order(N)
        print("  [form] NOTE: nearest-neighbour walk matched sorted order; "
              "using center-out fallback to preserve form distinction.", file=sys.stderr)

    orders = {
        "sorted": sorted_order,
        "braid": braid_order,
        "phase": phase_order,
        "walk": walk_order,
    }
    if form not in orders:
        raise ValueError(f"Unknown form: {form!r}. Choose: sorted braid phase walk")
    order = orders[form]

    rows = []
    for i in order:
        rows.append(_make_row(len(rows), i, events, labels,
                              morphology_scores, cluster_dist))

    id_seq = [str(r["orig_event_id"]) for r in rows]
    cid_seq = [f"C{r['cluster_id']}" for r in rows]
    signature = ",".join(id_seq)
    print(f"  [{form}] traversal: {' -> '.join(id_seq)}", file=sys.stderr)
    print(f"  [{form}] clusters:  {' -> '.join(cid_seq)}", file=sys.stderr)
    print(f"  [{form}] order_signature: {signature}", file=sys.stderr)
    print(f"  [{form}] morphology_span={morph_span:.6g}  "
          f"embedding_degenerate={emb_degenerate}", file=sys.stderr)
    return rows

def write_plan(rows, path):
    fields = ["new_index", "orig_event_id", "orig_start_time_s", "orig_end_time_s",
              "cluster_id", "cluster_morphology_score", "cluster_distance"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: f"{v:.6f}" if isinstance(v, float) else v
                        for k, v in r.items()})



def choose_kmeans(E_unit, max_k=N_CLUSTERS):
    """
    Select k from 2..max_k by silhouette score when the corpus supports it.
    Returns contiguous labels and actual k. Degenerate corpora become k=1.
    """
    from sklearn.metrics import silhouette_score

    E = np.asarray(E_unit, dtype=np.float64)
    N = len(E)
    if N < 2:
        return np.zeros(N, dtype=int), 1

    distinct = len(np.unique(np.round(E, decimals=6), axis=0))
    if distinct < 2:
        return np.zeros(N, dtype=int), 1

    k_max = min(max_k, N - 1, distinct)
    if k_max < 2:
        return np.zeros(N, dtype=int), 1

    best_score = -np.inf
    best_k = None
    best_labels = None
    for k in range(2, k_max + 1):
        km = KMeans(n_clusters=k, random_state=SEED, n_init=10)
        labels = km.fit_predict(E)
        if len(np.unique(labels)) < 2:
            continue
        try:
            sil = float(silhouette_score(E, labels, metric="euclidean"))
        except Exception:
            sil = -1.0
        if sil > best_score + 1e-12 or (abs(sil - best_score) <= 1e-12 and (best_k is None or k < best_k)):
            best_score = sil
            best_k = k
            best_labels = labels.copy()

    if best_labels is None:
        return np.zeros(N, dtype=int), 1

    lut = {}
    compact = np.zeros_like(best_labels, dtype=int)
    next_id = 0
    for i, lab in enumerate(best_labels):
        lab = int(lab)
        if lab not in lut:
            lut[lab] = next_id
            next_id += 1
        compact[i] = lut[lab]
    return compact, next_id


def main():
    import argparse
    ap = argparse.ArgumentParser(description="CNN event recomposition engine v1.2.2")
    ap.add_argument("input_csv",  help="input_events.csv from Praat")
    ap.add_argument("output_csv", help="output_plan.csv to write")
    ap.add_argument("--form", default="sorted",
                    choices=["sorted", "braid", "phase", "walk"],
                    help=("Compositional form: sorted=cluster blocks by morphology "
                          "score, braid=interleaved, phase=stable->rich, "
                          "walk=nearest-neighbour unit-embedding traversal"))
    args = ap.parse_args()

    print(f"[recomposer] v1.2.2 | Form: {args.form}", file=sys.stderr)
    print(f"[recomposer] Loading events from: {args.input_csv}", file=sys.stderr)
    try:
        events = load_events(args.input_csv)
    except Exception as e:
        print(f"[recomposer] ERROR reading events: {e}", file=sys.stderr)
        sys.exit(1)

    N = len(events)
    print(f"[recomposer] {N} events loaded", file=sys.stderr)
    if N == 0:
        print("[recomposer] ERROR: no events in input CSV", file=sys.stderr)
        sys.exit(1)

    X_raw = build_feature_tensor(events)
    X_norm, _med, _sc = robust_normalize(X_raw)

    cnn = NumpyCNN()
    use_cnn = False
    if N >= 4:
        print("[recomposer] Training CNN (symmetric contrastive, NumPy)...",
              file=sys.stderr)
        train_contrastive(cnn, X_norm, epochs=EPOCHS, lr=LR, verbose=True)
        use_cnn = bool(getattr(cnn, "training_valid", True))

    if use_cnn:
        embeddings = cnn.embed_all(X_norm)
        print("[recomposer] Using trained CNN embeddings.", file=sys.stderr)
    else:
        print("[recomposer] Using deterministic acoustic-summary embeddings "
              "(small corpus or invalid training).", file=sys.stderr)
        embeddings = acoustic_summary_embeddings(X_norm)

    E_unit = l2_normalize(embeddings)
    labels, k = choose_kmeans(E_unit)
    print(f"[recomposer] Data-driven K-means k={k}", file=sys.stderr)

    event_morph_scores, _event_morph_proxies = compute_event_morphology_scores(
        cnn, X_norm, X_raw, events, use_cnn=use_cnn)
    morph_scores, morph_proxies = compute_morphology_scores(
        cnn, X_norm, labels, k, X_raw, events, use_cnn=use_cnn)
    print(f"[recomposer] Event morphology span: "
          f"{float(np.ptp(event_morph_scores)):.6g}", file=sys.stderr)
    for cid in range(k):
        n_ev = int((labels == cid).sum())
        print(f"  cluster {cid}: {n_ev} events  score={morph_scores[cid]:.4f}",
              file=sys.stderr)

    rows = build_plan(events, labels, morph_scores, embeddings, form=args.form,
                      event_morphology=event_morph_scores)
    write_plan(rows, args.output_csv)
    print(f"[recomposer] Written {len(rows)} rows -> {args.output_csv}",
          file=sys.stderr)
    print("[recomposer] Done.", file=sys.stderr)


if __name__ == "__main__":
    main()
