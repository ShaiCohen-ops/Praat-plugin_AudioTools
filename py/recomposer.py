"""
recomposer.py — CNN-based event recomposition engine
Part of Praat AudioTools plugin

Usage:
    python recomposer.py input_events.csv output_plan.csv

Pipeline:
    1. Parse per-event trajectory sequences from CSV
    2. Resample each event to T=128 frames, build [N, T, F] feature tensor
    3. Robust normalisation across all events
    4. Train a NumPy CNN (multi-scale conv + self-supervised contrastive loss)
    5. Extract embeddings [N, D=32]
    6. K-means clustering (k=3 or 4, auto-adjusted)
    7. Compute morphology_score per cluster from CNN activations
    8. Build montage plan sorted by morphology_score → output_plan.csv

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
F_DIM       = 7            # features: pitch_hz, intensity_db, hnr_db, voiced, spectral_centroid, spectral_spread, zcr
D_EMB       = 32           # embedding dimension
N_CLUSTERS  = 4            # default k (auto-reduced if N < k)
EPOCHS      = 120          # contrastive training epochs
LR          = 3e-4         # Adam learning rate
TEMPERATURE = 0.5          # NT-Xent temperature
BATCH_SIZE  = 32           # contrastive batch (pairs)
POOL_SIZE   = 4            # temporal max-pool stride

np.random.seed(SEED)

# ─────────────────────────────────────────────────────────────────────────────
# 1. CSV parsing
# ─────────────────────────────────────────────────────────────────────────────

def parse_seq(s):
    """Parse 'v1;v2;v3;...' into a float array. Returns empty array if blank."""
    s = s.strip().strip('"')
    if not s:
        return np.array([], dtype=np.float32)
    return np.array([float(x) for x in s.split(";") if x.strip() != ""],
                    dtype=np.float32)


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
    Feature order: pitch_hz, intensity_db, hnr_db, voiced_flag,
                   spectral_centroid_hz, spectral_spread_hz, zcr
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
    return X


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
    idx = np.arange(k)[:, None] * C + np.arange(C)[None, :]   # [k, C]
    idx = idx.reshape(-1)                                       # [k*C]
    rows = np.arange(T_out)[:, None] * C + idx[None, :]        # [T_out, k*C]
    # use stride tricks for speed
    x_flat = x.reshape(-1)
    col = np.empty((T_out, k * C), dtype=x.dtype)
    for t in range(T_out):
        col[t] = x_flat[t * C: t * C + k * C]                 # naive fallback
    # proper strided version:
    col2 = np.lib.stride_tricks.sliding_window_view(
        x, (k, C)).reshape(T_out, k * C)
    return col2


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


def conv1d_same_backward(dout, cache):
    """Returns dx, dW, db."""
    x, col, W_flat, k, pad = cache
    T, C_in = x.shape
    _, C_out = dout.shape
    k_C_in = W_flat.shape[0]
    C_in2 = C_in

    db = dout.sum(axis=0)
    dW_flat = col.T @ dout                          # [k*C_in, C_out]
    dcol = dout @ W_flat.T                          # [T, k*C_in]

    # col-to-input gradient (un-slide)
    x_padded = np.pad(x, ((pad, pad), (0, 0)), mode="edge")
    dx_padded = np.zeros_like(x_padded)
    k_val = k_C_in // C_in2
    for t in range(T):
        dx_padded[t:t + k_val] += dcol[t].reshape(k_val, C_in2)

    dx = dx_padded[pad:pad + T] if pad > 0 else dx_padded
    dW = dW_flat.reshape(k_val, C_in2, C_out)
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
    Architecture (per event, input [T=128, F=4]):

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
        _, grads["WA"], grads["bA"] = conv1d_same_backward(d_cA_pre, c["cA_c"])

        d_cB_pre = relu_backward(d_cB, c["cB_pre"])
        _, grads["WB"], grads["bB"] = conv1d_same_backward(d_cB_pre, c["cB_c"])

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
    Produces one augmented view of event x: [T, F].
    Augmentations applied stochastically:
      - Gaussian noise
      - Frame dropout (zero out random frames)
      - Time jitter (shift by ±2 frames with wrap)
      - Slight time warp (resample with sinusoidal distortion)
    """
    T, F = x.shape
    x = x.copy()

    # Noise
    x += rng.randn(T, F).astype(np.float32) * 0.05

    # Frame dropout (10% of frames)
    n_drop = max(1, int(T * 0.10))
    drop_idx = rng.choice(T, n_drop, replace=False)
    x[drop_idx] = 0.0

    # Time jitter (roll)
    shift = rng.randint(-3, 4)
    x = np.roll(x, shift, axis=0)

    # Slight time warp via interpolation
    if rng.rand() < 0.5:
        warp_amp = 0.07
        t_orig = np.linspace(0, 1, T)
        t_warp = t_orig + warp_amp * np.sin(np.pi * t_orig * rng.uniform(1, 3))
        t_warp = np.clip(t_warp, 0, 1)
        x_warp = np.zeros_like(x)
        for f in range(F):
            x_warp[:, f] = np.interp(t_warp, t_orig, x[:, f])
        x = x_warp

    return x


# ─────────────────────────────────────────────────────────────────────────────
# 6. NT-Xent contrastive loss (NumPy)
# ─────────────────────────────────────────────────────────────────────────────

def l2_normalize(E):
    norms = np.linalg.norm(E, axis=1, keepdims=True)
    norms = np.maximum(norms, 1e-8)
    return E / norms


def nt_xent_loss_and_grad(E_a, E_p, tau=TEMPERATURE):
    """
    E_a: [B, D] anchors (view 1)
    E_p: [B, D] positives (view 2)
    Returns scalar loss, dE_a, dE_p (grad w.r.t. non-normalised embeddings)
    """
    B, D = E_a.shape
    # L2 normalise
    Ea = l2_normalize(E_a)
    Ep = l2_normalize(E_p)

    # Similarity matrix [B, B] (anchor vs all positives)
    S = Ea @ Ep.T / tau           # [B, B]

    # Numerical stability
    S_max = S.max(axis=1, keepdims=True)
    exp_S = np.exp(S - S_max)

    denom = exp_S.sum(axis=1, keepdims=True)          # [B, 1]
    log_softmax = S - S_max - np.log(np.maximum(denom, 1e-10))

    # Positive pairs on the diagonal
    pos_loss = -log_softmax[np.arange(B), np.arange(B)]
    loss = pos_loss.mean()

    # Gradient w.r.t. S (before normalisation)
    softmax = exp_S / np.maximum(denom, 1e-10)        # [B, B]
    dS = softmax.copy()
    dS[np.arange(B), np.arange(B)] -= 1.0
    dS /= (B * tau)

    # Grad w.r.t. Ea, Ep (pre-normalisation, via chain rule through l2 norm)
    dEa_norm = dS @ Ep           # [B, D]
    dEp_norm = dS.T @ Ea         # [B, D]

    def l2_norm_backward(dout, E_unnorm):
        norms = np.linalg.norm(E_unnorm, axis=1, keepdims=True)
        norms = np.maximum(norms, 1e-8)
        E_n = E_unnorm / norms
        return (dout - (dout * E_n).sum(axis=1, keepdims=True) * E_n) / norms

    dEa = l2_norm_backward(dEa_norm, E_a)
    dEp = l2_norm_backward(dEp_norm, E_p)

    return loss, dEa, dEp


# ─────────────────────────────────────────────────────────────────────────────
# 7. Contrastive training loop
# ─────────────────────────────────────────────────────────────────────────────

def train_contrastive(cnn, X, epochs=EPOCHS, lr=LR, verbose=True):
    N = X.shape[0]
    rng = np.random.RandomState(SEED + 1)
    best_loss = float("inf")
    diverged  = False

    for epoch in range(epochs):
        # shuffle indices
        idx = rng.permutation(N)
        epoch_loss = 0.0
        n_batches  = 0

        for start in range(0, N, BATCH_SIZE):
            batch_idx = idx[start:start + BATCH_SIZE]
            B = len(batch_idx)
            if B < 2:
                continue

            # Two augmented views per event
            E_a = np.zeros((B, D_EMB), np.float32)
            E_p = np.zeros((B, D_EMB), np.float32)
            caches_a = []
            caches_p = []

            for j, i in enumerate(batch_idx):
                xa = augment(X[i], rng)
                xp = augment(X[i], rng)
                E_a[j] = cnn.forward(xa, store=True)
                caches_a.append(dict(cnn._cache))
                E_p[j] = cnn.forward(xp, store=True)
                caches_p.append(dict(cnn._cache))

            loss, dEa, dEp = nt_xent_loss_and_grad(E_a, E_p)

            # Check for NaN / explosion
            if not np.isfinite(loss) or loss > 1e4:
                diverged = True
                break

            epoch_loss += loss
            n_batches  += 1

            # Backprop through both views
            cnn.zero_grads()
            for j in range(B):
                cnn._cache = caches_a[j]
                grads_a = cnn.backward(dEa[j])
                cnn.accumulate(grads_a)

                cnn._cache = caches_p[j]
                grads_p = cnn.backward(dEp[j])
                cnn.accumulate(grads_p)

            cnn.step(B * 2, lr=lr)

        if diverged:
            break

        avg = epoch_loss / max(n_batches, 1)
        if avg < best_loss:
            best_loss = avg
        if verbose and (epoch % 20 == 0 or epoch == epochs - 1):
            print(f"[CNN] epoch {epoch+1:3d}/{epochs}  loss={avg:.4f}",
                  file=sys.stderr)

    if diverged:
        print("  [CNN] WARNING: training diverged — using random weights.",
              file=sys.stderr)

    return cnn


# ─────────────────────────────────────────────────────────────────────────────
# 8. Morphology scoring from CNN activations
# ─────────────────────────────────────────────────────────────────────────────

def compute_morphology_scores(cnn, X, labels, k, X_raw):
    """
    For each cluster, derive a scalar morphology_score.

    Proxies (from CNN pool activations + raw features):
      - voiced_mean:    fraction of voiced frames (raw)
      - hnr_variance:   temporal variance of HNR trajectory (raw)
      - intensity_slope: mean absolute slope of intensity trajectory (raw)
      - activation_entropy: entropy of mean pool-layer activations (CNN internal)

    Score = weighted sum of proxies, normalised to [0, 1].
    Low score ≈ stable/homogeneous; high score ≈ complex/morphologically rich.
    """
    acts = cnn.get_activations(X)    # [N, T_pool, 16]

    scores = np.zeros(k)
    for cid in range(k):
        mask = labels == cid
        if not mask.any():
            continue
        ev_idx = np.where(mask)[0]

        # ── raw feature proxies ────────────────────────────────────────
        voiced_means = []
        hnr_vars     = []
        int_slopes   = []
        for i in ev_idx:
            v = X_raw[i, :, 3]
            voiced_means.append(v.mean())
            h = X_raw[i, :, 2]
            hnr_vars.append(h.var())
            inten = X_raw[i, :, 1]
            slope = np.abs(np.diff(inten)).mean()
            int_slopes.append(slope)

        voiced_mean  = np.mean(voiced_means)
        hnr_var      = np.mean(hnr_vars)
        int_slope    = np.mean(int_slopes)

        # ── CNN activation entropy ─────────────────────────────────────
        cluster_acts = acts[mask]              # [n_c, T_pool, 16]
        mean_act     = cluster_acts.mean(axis=(0, 1))   # [16]
        p = np.abs(mean_act)
        p = p / (p.sum() + 1e-8)
        entropy = -np.sum(p * np.log(p + 1e-10))

        # ── Combined score (higher = richer morphology) ────────────────
        raw_score = (0.25 * voiced_mean +
                     0.25 * np.tanh(hnr_var) +
                     0.25 * np.tanh(int_slope) +
                     0.25 * entropy / math.log(16 + 1))
        scores[cid] = raw_score

    # Normalise to [0, 1]
    s_min, s_max = scores.min(), scores.max()
    if s_max - s_min < 1e-8:
        scores = np.linspace(0.0, 1.0, k)
    else:
        scores = (scores - s_min) / (s_max - s_min)
    return scores


# ─────────────────────────────────────────────────────────────────────────────
# 9. Build montage plan
# ─────────────────────────────────────────────────────────────────────────────

def _make_row(new_index, i, events, labels, morphology_scores, embeddings):
    ev = events[i]
    cid = int(labels[i])
    return {
        "new_index":                new_index,
        "orig_event_id":            ev["event_id"],
        "orig_start_time_s":        ev["start_time_s"],
        "orig_end_time_s":          ev["end_time_s"],
        "cluster_id":               cid,
        "cluster_morphology_score": float(morphology_scores[cid]),
        "event_embedding_norm":     float(np.linalg.norm(embeddings[i])),
    }


def _cluster_buckets(N, labels, events, k):
    """Returns dict cid → [event indices] sorted chronologically."""
    buckets = {cid: [] for cid in range(k)}
    for i in range(N):
        buckets[int(labels[i])].append(i)
    for cid in buckets:
        buckets[cid].sort(key=lambda i: events[i]["event_id"])
    return buckets


def build_plan(events, labels, morphology_scores, embeddings, form="sorted"):
    """
    Build montage plan according to `form`:

    sorted  — clusters ordered by morphology_score asc; chronological within cluster.
    braid   — interleave clusters: A0 B0 C0 A1 B1 C1 … (round-robin by score rank).
    phase   — first half of montage uses only the two lowest-score clusters
              (stable material), second half introduces the rest in score order.
    walk    — nearest-neighbour traversal in embedding space (greedy);
              start from event with lowest embedding norm.
    """
    N = len(events)
    k = len(morphology_scores)
    cluster_order = list(np.argsort(morphology_scores))   # asc score
    buckets = _cluster_buckets(N, labels, events, k)

    rows = []
    ni = 0  # new_index counter

    # ── sorted ────────────────────────────────────────────────────────────────
    if form == "sorted":
        for cid in cluster_order:
            for i in buckets[cid]:
                rows.append(_make_row(ni, i, events, labels, morphology_scores, embeddings))
                ni += 1

    # ── braid ─────────────────────────────────────────────────────────────────
    elif form == "braid":
        # Round-robin over clusters in score order; exhaust shortest first.
        active = [list(buckets[cid]) for cid in cluster_order]
        while any(active):
            for lane in active:
                if lane:
                    i = lane.pop(0)
                    rows.append(_make_row(ni, i, events, labels, morphology_scores, embeddings))
                    ni += 1

    # ── phase ─────────────────────────────────────────────────────────────────
    elif form == "phase":
        # First half: stable clusters (lowest score half), second half: rest.
        half = max(1, k // 2)
        stable_ids  = cluster_order[:half]
        complex_ids = cluster_order[half:]

        stable_events = []
        for cid in stable_ids:
            stable_events.extend(buckets[cid])
        stable_events.sort(key=lambda i: events[i]["event_id"])

        complex_events = []
        for cid in complex_ids:
            complex_events.extend(buckets[cid])
        complex_events.sort(key=lambda i: events[i]["event_id"])

        for i in stable_events + complex_events:
            rows.append(_make_row(ni, i, events, labels, morphology_scores, embeddings))
            ni += 1

    # ── walk ──────────────────────────────────────────────────────────────────
    elif form == "walk":
        # Greedy nearest-neighbour in embedding space.
        E = embeddings.copy()
        norms = np.linalg.norm(E, axis=1)
        remaining = set(range(N))
        # Start from event with lowest embedding norm (most "central")
        current = int(np.argmin(norms))
        remaining.remove(current)
        order = [current]
        while remaining:
            rem_list = list(remaining)
            dists = np.linalg.norm(E[rem_list] - E[current], axis=1)
            nearest = rem_list[int(np.argmin(dists))]
            remaining.remove(nearest)
            order.append(nearest)
            current = nearest
        for i in order:
            rows.append(_make_row(ni, i, events, labels, morphology_scores, embeddings))
            ni += 1

    else:
        raise ValueError(f"Unknown form: {form!r}. Choose: sorted braid phase walk")

    # ── traversal log (all forms) ──────────────────────────────────────────
    id_seq  = [str(r["orig_event_id"]) for r in rows]
    cid_seq = [f"C{r['cluster_id']}" for r in rows]
    traversal_str = " -> ".join(id_seq)
    clusters_str  = " -> ".join(cid_seq)
    print(f"  [{form}] traversal: {traversal_str}", file=sys.stderr)
    print(f"  [{form}] clusters:  {clusters_str}", file=sys.stderr)

    return rows


def write_plan(rows, path):
    fields = ["new_index", "orig_event_id", "orig_start_time_s", "orig_end_time_s",
              "cluster_id", "cluster_morphology_score", "event_embedding_norm"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: f"{v:.6f}" if isinstance(v, float) else v
                        for k, v in r.items()})


# ─────────────────────────────────────────────────────────────────────────────
# 10. Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    import argparse
    ap = argparse.ArgumentParser(description="CNN event recomposition engine")
    ap.add_argument("input_csv",  help="input_events.csv from Praat")
    ap.add_argument("output_csv", help="output_plan.csv to write")
    ap.add_argument("--form", default="sorted",
                    choices=["sorted", "braid", "phase", "walk"],
                    help=(
                        "Compositional form: "
                        "sorted=cluster blocks by morphology score (default), "
                        "braid=interleaved round-robin, "
                        "phase=stable-first/complex-second, "
                        "walk=nearest-neighbour embedding traversal"
                    ))
    args = ap.parse_args()
    in_path  = args.input_csv
    out_path = args.output_csv
    form     = args.form
    print(f"[recomposer] Form: {form}", file=sys.stderr)

    print(f"[recomposer] Loading events from: {in_path}", file=sys.stderr)
    events = load_events(in_path)
    N = len(events)
    print(f"[recomposer] {N} events loaded", file=sys.stderr)

    if N == 0:
        print("[recomposer] ERROR: no events in input CSV", file=sys.stderr)
        sys.exit(1)

    # ── Feature tensor ────────────────────────────────────────────────────────
    X_raw  = build_feature_tensor(events)                # [N, T, F] unnormalised
    X_norm, _med, _sc = robust_normalize(X_raw)          # [N, T, F] normalised

    # ── CNN ───────────────────────────────────────────────────────────────────
    cnn = NumpyCNN()

    if N >= 4:
        print("[recomposer] Training CNN (contrastive, NumPy)...", file=sys.stderr)
        train_contrastive(cnn, X_norm, epochs=EPOCHS, lr=LR, verbose=True)
    else:
        print("[recomposer] Too few events for contrastive training "
              "— using random initialisation.", file=sys.stderr)

    print("[recomposer] Extracting embeddings...", file=sys.stderr)
    embeddings = cnn.embed_all(X_norm)                   # [N, D]

    # ── K-means ───────────────────────────────────────────────────────────────
    k = min(N_CLUSTERS, N)
    if k < 2:
        k = 1
    print(f"[recomposer] K-means k={k}...", file=sys.stderr)
    km = KMeans(n_clusters=k, random_state=SEED, n_init=10)
    labels = km.fit_predict(embeddings)

    # ── Morphology scoring ────────────────────────────────────────────────────
    print("[recomposer] Computing morphology scores...", file=sys.stderr)
    morph_scores = compute_morphology_scores(cnn, X_norm, labels, k, X_raw)
    for cid in range(k):
        n_ev = (labels == cid).sum()
        print(f"  cluster {cid}: {n_ev} events  score={morph_scores[cid]:.4f}",
              file=sys.stderr)

    # ── Build and write plan ──────────────────────────────────────────────────
    rows = build_plan(events, labels, morph_scores, embeddings, form=form)
    write_plan(rows, out_path)
    print(f"[recomposer] Written {len(rows)} rows -> {out_path}", file=sys.stderr)
    print("[recomposer] Done.", file=sys.stderr)


if __name__ == "__main__":
    main()
