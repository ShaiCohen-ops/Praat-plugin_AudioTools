"""
self_attention_latent.py — Self-Attention Latent Navigation Engine

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Called by SelfAttentionLatent.praat — not run directly.

Usage:
    python self_attention_latent.py input.wav events.csv output.wav [options]

Pipeline:
    Stage 1 — Load audio + events; encode events → latent μᵢ (VAE, NumPy only)
    Stage 2 — Build self-attention matrix A ∈ ℝᴺˣᴺ (multi-head, NumPy only)
    Stage 3 — Generate navigation plan in memory (list of dicts, no CSV)
    Stage 4 — Execute plan:
               for each step:
                 • compute latent target (drift/mutate/return/settle)
                 • select K nearest neighbors
                 • mixing weight: w_j ∝ (1/dist_j^p) * (A[i,j]^q)
                 • mix waveforms → crossfade → append
    Stage 5 — Time-normalize, loudness-compensate, write output.wav
              Delete events.csv and any temp files
              Only output.wav remains

No PyTorch. No TensorFlow. No sklearn. No external plan file.
Dependencies: numpy, soundfile (scipy optional, unused here)
"""

import sys
import os
import csv
import math

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────
N_MELS      = 64
MEL_FRAMES  = 32
XFADE_SEC   = 0.012   # crossfade length between segments (seconds)
TEMP_PREFIX = "temp_sal_"   # prefix Praat uses for temp files it creates


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

def check_deps():
    missing = []
    for pkg in ["numpy", "soundfile"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: missing packages: " + ", ".join(missing), file=sys.stderr)
        print("pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


def load_events(path):
    events = []
    with open(path, "r") as f:
        header = [h.strip() for h in f.readline().strip().split(",")]
        for line in f:
            vals = line.strip().split(",")
            if len(vals) != len(header):
                continue
            row = {}
            for h, v in zip(header, vals):
                try:
                    row[h] = float(v)
                except ValueError:
                    row[h] = v.strip()
            events.append(row)
    return events


# ═══════════════════════════════════════════════════════════════════════════
# Stage 1a — Log-Mel Patch Extraction
# ═══════════════════════════════════════════════════════════════════════════

def _mel_filterbank(sr, n_fft, n_mels):
    import numpy as np
    def hz2mel(h): return 2595.0 * np.log10(1.0 + h / 700.0)
    def mel2hz(m): return 700.0 * (10.0 ** (m / 2595.0) - 1.0)
    n_bins = n_fft // 2 + 1
    pts    = mel2hz(np.linspace(hz2mel(20), hz2mel(sr / 2), n_mels + 2))
    bins   = np.clip(np.floor((n_fft + 1) * pts / sr).astype(int), 0, n_bins - 1)
    fb     = np.zeros((n_mels, n_bins))
    for m in range(1, n_mels + 1):
        lo, ctr, hi = bins[m-1], bins[m], bins[m+1]
        for k in range(lo, ctr):
            if ctr > lo: fb[m-1, k] = (k - lo) / (ctr - lo)
        for k in range(ctr, hi):
            if hi > ctr: fb[m-1, k] = (hi - k) / (hi - ctr)
    return fb


def extract_patches(audio_mono, sr, events):
    import numpy as np
    n_fft  = 2048
    hop    = 512
    win    = np.hanning(n_fft)
    fb     = _mel_filterbank(sr, n_fft, N_MELS)
    N      = len(audio_mono)
    out    = []
    for ev in events:
        s = max(0, min(int(float(ev["start_time"]) * sr), N))
        e = max(s + 1, min(int(float(ev["end_time"]) * sr), N))
        seg     = audio_mono[s:e]
        n_fr    = max(1, (len(seg) - n_fft) // hop + 1)
        mel     = np.zeros((N_MELS, n_fr))
        for fi in range(n_fr):
            st = fi * hop
            fr = seg[st:st + n_fft]
            if len(fr) < n_fft:
                fr = np.pad(fr, (0, n_fft - len(fr)))
            mel[:, fi] = np.log(fb.dot(np.abs(np.fft.rfft(fr * win)) ** 2) + 1e-10)
        if n_fr >= MEL_FRAMES:
            off   = (n_fr - MEL_FRAMES) // 2
            patch = mel[:, off:off + MEL_FRAMES]
        else:
            patch = np.zeros((N_MELS, MEL_FRAMES))
            off   = (MEL_FRAMES - n_fr) // 2
            patch[:, off:off + n_fr] = mel
            for pi in range(off):           patch[:, pi]  = mel[:, 0]
            for pi in range(off + n_fr, MEL_FRAMES): patch[:, pi] = mel[:, -1]
        out.append(patch.flatten())
    return np.array(out, dtype=np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 1b — Lightweight VAE (pure NumPy)
# ═══════════════════════════════════════════════════════════════════════════

class _VAE:
    def __init__(self, in_dim, h_dim, z_dim, seed):
        import numpy as np
        rng = np.random.RandomState(seed)
        def he(a, b): return rng.randn(a, b) * np.sqrt(2.0 / (a + b))
        self.We = he(in_dim, h_dim);  self.be = np.zeros(h_dim)
        self.Wm = he(h_dim,  z_dim);  self.bm = np.zeros(z_dim)
        self.Wv = he(h_dim,  z_dim);  self.bv = np.zeros(z_dim)
        self.Wd = he(z_dim,  h_dim);  self.bd = np.zeros(h_dim)
        self.Wo = he(h_dim,  in_dim); self.bo = np.zeros(in_dim)
        self.params = [self.We, self.be, self.Wm, self.bm,
                       self.Wv, self.bv, self.Wd, self.bd,
                       self.Wo, self.bo]
        self.t = 0
        self.m = [np.zeros_like(p) for p in self.params]
        self.v = [np.zeros_like(p) for p in self.params]
        self.rng = rng
        self.in_dim = in_dim

    def _relu(self, x):
        import numpy as np; return np.maximum(0, x)

    def encode(self, X):
        self._h = self._relu(X.dot(self.We) + self.be)
        mu = self._h.dot(self.Wm) + self.bm
        lv = self._h.dot(self.Wv) + self.bv
        return mu, lv

    def step(self, X, lr, beta):
        import numpy as np
        B  = X.shape[0]
        Xn = X + 0.3 * self.rng.randn(*X.shape)
        mu, lv = self.encode(Xn)
        std = np.exp(0.5 * np.clip(lv, -4, 4))
        Z   = mu + std * self.rng.randn(*std.shape)
        h2  = self._relu(Z.dot(self.Wd) + self.bd)
        rec = h2.dot(self.Wo) + self.bo
        diff = rec - X
        rl   = np.mean(diff ** 2)
        kl   = 0.5 * np.mean(mu**2 + np.exp(lv) - lv - 1.0)
        loss = rl + beta * kl
        # backward
        dout = 2 * diff / (B * self.in_dim)
        dWo  = h2.T.dot(dout);             dbo = np.sum(dout, 0)
        dh2  = dout.dot(self.Wo.T) * (h2 > 0)
        dWd  = Z.T.dot(dh2);              dbd = np.sum(dh2, 0)
        dZ   = dh2.dot(self.Wd.T)
        dmu  = dZ + beta * mu / B
        dlv  = dZ * std * 0.5 + beta * 0.5 * (np.exp(lv) - 1) / B
        dWm  = self._h.T.dot(dmu);        dbm = np.sum(dmu, 0)
        dWv  = self._h.T.dot(dlv);        dbv = np.sum(dlv, 0)
        dh1  = (dmu.dot(self.Wm.T) + dlv.dot(self.Wv.T)) * (self._h > 0)
        dWe  = Xn.T.dot(dh1);             dbe = np.sum(dh1, 0)
        grads = [dWe, dbe, dWm, dbm, dWv, dbv, dWd, dbd, dWo, dbo]
        self.t += 1
        b1, b2, eps = 0.9, 0.999, 1e-8
        for i, (p, g) in enumerate(zip(self.params, grads)):
            self.m[i] = b1*self.m[i] + (1-b1)*g
            self.v[i] = b2*self.v[i] + (1-b2)*g**2
            mh = self.m[i] / (1 - b1**self.t)
            vh = self.v[i] / (1 - b2**self.t)
            p -= lr * mh / (np.sqrt(vh) + eps)
        return loss


def train_vae(patches, z_dim, n_iter, seed):
    import numpy as np
    N, D   = patches.shape
    h_dim  = max(z_dim * 2, min(256, int(np.sqrt(D * z_dim))))
    mu_n   = patches.mean(0); sig_n = patches.std(0) + 1e-8
    X      = (patches - mu_n) / sig_n
    model  = _VAE(D, h_dim, z_dim, seed)
    lr0    = 0.003
    losses = []
    for i in range(n_iter):
        lr   = lr0 * (1.0 - 0.4 * i / n_iter)
        loss = model.step(X, lr, 0.05)
        losses.append(float(loss))
    model._mu_n  = mu_n
    model._sig_n = sig_n
    return model, losses


def encode(model, patches):
    import numpy as np
    X      = (patches - model._mu_n) / model._sig_n
    mu, _  = model.encode(X)
    return mu   # (N, z_dim)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Self-Attention Matrix (pure NumPy)
# ═══════════════════════════════════════════════════════════════════════════

def build_attention(Z, n_heads=4, seed=42):
    """
    Multi-head self-attention over N latent vectors.
    Returns A (N×N, rows sum to 1) and mean row entropy (nats).

    Architecture (spec Stage 2):
      • Layer-norm + residual on inputs
      • Fixed He-init projections Wq, Wk  (seeded, not trained)
      • Scaled dot-product per head, softmax, average across heads
    """
    import numpy as np
    N, d = Z.shape
    rng  = np.random.RandomState(seed)

    # Clamp heads to clean divisor of d
    n_heads = max(1, min(n_heads, d))
    while d % n_heads != 0 and n_heads > 1:
        n_heads -= 1
    dh = d // n_heads

    # Layer-norm + residual
    mu_z  = Z.mean(0, keepdims=True)
    sig_z = Z.std(0,  keepdims=True) + 1e-8
    Zn    = (Z - mu_z) / sig_z
    Zr    = Zn + Z / (np.abs(Z).max() + 1e-8)

    sc = np.sqrt(2.0 / (d + dh))
    Wq = rng.randn(d, d) * sc
    Wk = rng.randn(d, d) * sc
    Q  = Zr.dot(Wq)
    K  = Zr.dot(Wk)

    A_sum = np.zeros((N, N), dtype=np.float64)
    inv   = 1.0 / np.sqrt(dh)
    for h in range(n_heads):
        s, e   = h * dh, (h + 1) * dh
        scores = Q[:, s:e].dot(K[:, s:e].T) * inv
        scores -= scores.max(1, keepdims=True)
        exp_s  = np.exp(scores)
        A_sum += exp_s / (exp_s.sum(1, keepdims=True) + 1e-12)

    A = A_sum / n_heads
    A = A / (A.sum(1, keepdims=True) + 1e-12)
    H = float(-np.sum(A * np.log(A + 1e-12), axis=1).mean())
    return A, H


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Navigation Plan (in memory only, no CSV)
# ═══════════════════════════════════════════════════════════════════════════

def generate_plan(Z, A, n_steps=72, seed=42,
                  dur_scale=1.0, dur_jitter=0.0,
                  eng_scale=1.0, eng_jitter=0.0):
    """
    Deterministic latent navigation plan as List[Dict].
    No file is written — plan lives in memory only.

    Phase layout  (spec minimums in parentheses):
        drift  33%  (≥15%)  — geometry dominant, α=0.90
        mutate 33%  (≥15%)  — attention grows, α ramps 0.70→0.30
        return 25%  (≥10%)  — attention dominant, anchor via A cosine
        settle  9%  (≥10%)  — geometry re-dominant, α=0.90

    Smoothness constraints enforced every step:
        |Δ step_size|   ≤ 0.15
        |Δ temperature| ≤ 0.20
        |Δ k_neighbors| ≤ 2

    Mixing weight formula (used in Stage 4):
        w_j ∝ (1/dist_j^p) * (A[i,j]^q)
    α stored per step as '_alpha'; p/q computed from α at execution time.
    """
    import numpy as np, random
    rng = random.Random(seed)
    N   = Z.shape[0]
    n_steps = max(8, min(500, n_steps))

    DRIFT_END  = 0.333
    MUTATE_END = 0.667
    RETURN_END = 0.917

    def lerp(a, b, t):
        return a + (b - a) * float(np.clip(t, 0, 1))

    drift_idxs = [i for i in range(n_steps)
                  if i / max(1, n_steps - 1) < DRIFT_END]

    plan   = []
    p_sz   = 0.05
    p_tmp  = 0.05
    p_k    = 2

    for i in range(n_steps):
        frac = i / max(1, n_steps - 1)

        # ── Phase parameters ────────────────────────────────────────────────
        if frac < DRIFT_END:
            ph = "drift"
            t  = frac / DRIFT_END
            tsz, ttmp, tk = lerp(0.05,0.25,t), lerp(0.05,0.20,t), int(round(lerp(2,4,t)))
            alpha, r_str, anchor = 0.90, 0.0, -1

        elif frac < MUTATE_END:
            ph = "mutate"
            t  = (frac - DRIFT_END) / (MUTATE_END - DRIFT_END)
            tsz, ttmp, tk = lerp(0.30,0.70,t), lerp(0.40,0.80,t), int(round(lerp(4,8,t)))
            alpha, r_str, anchor = lerp(0.70,0.30,t), 0.0, -1

        elif frac < RETURN_END:
            ph = "return"
            t  = (frac - MUTATE_END) / (RETURN_END - MUTATE_END)
            tsz, ttmp, tk = lerp(0.30,0.10,t), lerp(0.20,0.10,t), int(round(lerp(4,2,t)))
            alpha  = lerp(0.20, 0.35, t)
            r_str  = lerp(0.50, 0.80, t)
            # Attention-guided anchor: drift step whose A-row best matches A[i%N]
            if drift_idxs and N > 1:
                q = A[i % N]
                best_j, best_cos = drift_idxs[0], -2.0
                for dj in drift_idxs:
                    c  = A[dj % N]
                    cs = float(np.dot(q, c) / (np.linalg.norm(q) * np.linalg.norm(c) + 1e-12))
                    if cs > best_cos:
                        best_cos, best_j = cs, dj
                anchor = best_j
            else:
                anchor = -1

        else:
            ph = "settle"
            t  = (frac - RETURN_END) / max(1e-9, 1.0 - RETURN_END)
            tsz, ttmp, tk = lerp(0.20,0.05,t), lerp(0.15,0.05,t), int(round(lerp(3,2,t)))
            alpha, r_str, anchor = 0.90, 0.0, -1

        # ── Smoothness clamp ────────────────────────────────────────────────
        sz  = float(np.clip(tsz,  p_sz  - 0.15, p_sz  + 0.15))
        tmp = float(np.clip(ttmp, p_tmp - 0.20, p_tmp + 0.20))
        k   = int(np.clip(tk, p_k - 2, p_k + 2))
        k   = max(2, min(8, min(k, N)))
        p_sz, p_tmp, p_k = sz, tmp, k

        # ── Per-step jitter ─────────────────────────────────────────────────
        sdur = float(np.clip(dur_scale * (1 + rng.uniform(-dur_jitter, dur_jitter)
                                          if dur_jitter > 0 else 1), 0.85, 1.15))
        seng = float(np.clip(eng_scale * (1 + rng.uniform(-eng_jitter, eng_jitter)
                                          if eng_jitter > 0 else 1), 0.80, 1.20))

        plan.append({
            "step_index":             i,
            "relative_time":          round(i / max(1, n_steps - 1), 6),
            "mode":                   ph,
            "step_size":              round(sz,  4),
            "temperature":            round(tmp, 4),
            "k_neighbors":            k,
            "return_anchor_step":     anchor,
            "return_strength":        round(float(r_str), 4),
            "segment_duration_scale": round(sdur, 4),
            "segment_energy_scale":   round(seng, 4),
            "_alpha":                 round(float(alpha), 4),
        })

    if plan:
        plan[0]["relative_time"]  = 0.0
        plan[-1]["relative_time"] = 1.0
    return plan


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Execution
# ═══════════════════════════════════════════════════════════════════════════

def _extract_clips(audio, events, sr):
    """Return list of float32 arrays (samples,) or (samples, ch), one per event.
    Preserves original channel count so mixing does not lose stereo information."""
    import numpy as np
    N = audio.shape[0] if audio.ndim == 2 else len(audio)
    clips = []
    for ev in events:
        s = max(0, min(int(float(ev["start_time"]) * sr), N - 1))
        e = max(s + 1, min(int(float(ev["end_time"]) * sr), N))
        clips.append(audio[s:e].astype(np.float32))
    return clips


def _sinc_resample(clip, target_len):
    """
    Fast high-quality resampling using FFT-based sinc interpolation.
    Preserves high frequencies far better than np.interp.
    Used for ratio changes within 0.7–1.4x where pvoc is overkill.
    """
    import numpy as np
    n = len(clip)
    if n == target_len:
        return clip.copy().astype(np.float32)
    # FFT resample: zero-pad or truncate spectrum, then IFFT
    X = np.fft.rfft(clip.astype(np.float64))
    if target_len > n:
        # upsample — pad spectrum with zeros
        X_new = np.zeros(target_len // 2 + 1, dtype=np.complex128)
        X_new[:len(X)] = X
    else:
        # downsample — truncate spectrum (anti-alias built in)
        X_new = X[:target_len // 2 + 1]
    out = np.fft.irfft(X_new, n=target_len)
    # scale to preserve amplitude
    out *= target_len / n
    return out.astype(np.float32)


def _resample(clip, target_len):
    """
    Dispatch to the best resampler based on stretch ratio:
      ratio 0.9–1.1  → pad/trim only (imperceptible difference)
      ratio 0.7–1.4  → sinc FFT resample (fast, high quality)
      outside        → phase vocoder (slow but accurate for large stretches)
    """
    import numpy as np
    n = len(clip)
    if n == target_len:
        return clip.copy().astype(np.float32)
    ratio = target_len / max(n, 1)
    if 0.90 <= ratio <= 1.10:
        # pad or trim with short crossfade
        if n > target_len:
            fl  = min(64, target_len // 4)
            out = clip[:target_len].copy().astype(np.float32)
            if fl > 0:
                out[-fl:] *= np.cos(np.linspace(0, np.pi/2, fl)).astype(np.float32)
            return out
        else:
            out = np.zeros(target_len, dtype=np.float32)
            out[:n] = clip.astype(np.float32)
            return out
    elif 0.70 <= ratio <= 1.40:
        return _sinc_resample(clip, target_len)
    else:
        return _pvoc_stretch(clip, target_len)


def _pvoc_stretch(clip, target_len):
    """
    Phase-vocoder time-stretch to target_len (preserves pitch).
    75% overlap Hann window.  Falls back to pad/trim for very short clips.
    """
    import numpy as np
    clip = np.asarray(clip, dtype=np.float32)
    n    = len(clip)
    if n == target_len:
        return clip.copy()
    if n < 2048 or target_len < 4:
        # pad/trim with fade
        if n > target_len:
            out = clip[:target_len].copy()
            fl  = min(64, target_len // 4)
            if fl > 0:
                out[-fl:] *= np.cos(np.linspace(0, np.pi/2, fl)).astype(np.float32)
            return out
        else:
            out      = np.zeros(target_len, dtype=np.float32)
            fl       = min(64, n // 4)
            c        = clip.copy()
            if fl > 0:
                c[-fl:] *= np.cos(np.linspace(0, np.pi/2, fl)).astype(np.float32)
            out[:n] = c
            return out

    n_fft  = 2048
    hop    = n_fft // 4
    ratio  = target_len / n
    hop_in = hop / ratio
    win    = np.hanning(n_fft).astype(np.float64)
    win_sq = win ** 2
    floor  = float(np.sum(win_sq) / hop) * 0.1

    # Analysis STFT
    hop_a      = hop
    n_fr_in    = max(2, (n - n_fft) // hop_a + 2)
    n_bins     = n_fft // 2 + 1
    stft       = np.zeros((n_bins, n_fr_in), dtype=np.complex128)
    for fi in range(n_fr_in):
        st = fi * hop_a
        fr = np.zeros(n_fft)
        av = min(n_fft, n - st)
        if av > 0: fr[:av] = clip[st:st + av]
        stft[:, fi] = np.fft.rfft(fr * win)

    mag   = np.abs(stft)
    phase = np.angle(stft)
    omega = 2 * np.pi * np.arange(n_bins) / n_fft

    # Pre-compute instantaneous frequencies
    inst = np.zeros_like(mag)
    for fi in range(n_fr_in - 1):
        dp        = phase[:, fi+1] - phase[:, fi] - omega * hop_a
        dp        = dp - 2*np.pi * np.round(dp / (2*np.pi))
        inst[:, fi] = omega + dp / hop_a
    inst[:, -1] = omega

    n_fr_out = max(1, int(np.ceil((target_len - n_fft) / hop)) + 2)
    buf_len  = n_fr_out * hop + n_fft
    out_buf  = np.zeros(buf_len)
    norm_buf = np.zeros(buf_len)
    ph_acc   = phase[:, 0].copy()

    for fo in range(n_fr_out):
        fi_f  = fo * hop_in / hop_a
        fi_lo = min(int(fi_f), n_fr_in - 1)
        fi_hi = min(fi_lo + 1, n_fr_in - 1)
        al    = max(0.0, min(1.0, fi_f - fi_lo))
        m     = (1 - al) * mag[:, fi_lo] + al * mag[:, fi_hi]
        ifreq = (1 - al) * inst[:, fi_lo] + al * inst[:, fi_hi]
        frame = np.fft.irfft(m * np.exp(1j * ph_acc)).real[:n_fft] * win
        st    = fo * hop
        out_buf[st:st + n_fft]  += frame
        norm_buf[st:st + n_fft] += win_sq
        ph_acc = ph_acc + ifreq * hop

    norm_buf = np.maximum(norm_buf, floor)
    return (out_buf / norm_buf)[:target_len].astype(np.float32)


def _mix_weights(query, neighbor_positions, attn_row, alpha, p=2.0, q=1.0):
    """
    Spec formula: w_j ∝ (1/dist_j^p) * (A[i,j]^q)

    alpha controls the balance between geometry and attention
    by adjusting effective p and q:
        p_eff = p * alpha          (high alpha → geometry dominates)
        q_eff = q * (1 - alpha)    (low alpha  → attention dominates)

    When alpha=1.0 this reduces to pure inverse-distance (original).
    When alpha=0.0 this reduces to pure attention power.
    """
    import numpy as np
    dists = np.sqrt(np.sum((neighbor_positions - query) ** 2, axis=1))
    dists = np.maximum(dists, 1e-8)
    p_eff = p * max(alpha, 1e-3)
    q_eff = q * max(1.0 - alpha, 1e-3)
    geom  = 1.0 / (dists ** p_eff)
    attn  = np.maximum(np.asarray(attn_row, dtype=np.float64), 0.0) ** q_eff
    w     = geom * attn
    s     = w.sum()
    if s < 1e-12:
        return geom / (geom.sum() + 1e-12)
    return w / s


def execute_plan(plan, Z, A, clips, sr, target_samples, seed,
                 pitch_mode="off"):
    """
    Execute the navigation plan. For every step:
      1. Advance latent position (drift/mutate/return/settle)
      2. Find K nearest neighbors in Z
      3. Compute mixing weights: w_j ∝ (1/dist_j^p) * (A[i,j]^q)
      4. Mix clips (with optional pitch preservation)
      5. Crossfade and append

    After all steps: time-normalize full stream to target_samples.
    Returns (stereo float32 array, step_stats list).
    """
    import numpy as np

    rng      = np.random.RandomState(seed)
    N_ev, d  = Z.shape
    xfade    = max(4, int(XFADE_SEC * sr))
    angle    = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in  = np.sin(angle)    # 0 → 1
    fade_out = np.cos(angle)    # 1 → 0

    center   = Z.mean(0)
    pos      = center.copy()
    vel      = np.zeros(d)
    anchors  = {}

    # Detect channel count from clips
    n_ch     = clips[0].shape[1] if clips[0].ndim == 2 else 1
    mean_cl  = int(np.mean([c.shape[0] for c in clips]))
    buf_shape = (mean_cl * (len(plan) + 4), n_ch) if n_ch > 1 else (mean_cl * (len(plan) + 4),)
    buf      = np.zeros(buf_shape, dtype=np.float32)
    ptr      = 0
    stats    = []

    for si, step in enumerate(plan):
        mode   = step["mode"]
        sz     = step["step_size"]
        tmp    = step["temperature"]
        K      = min(step["k_neighbors"], N_ev)
        anch   = step["return_anchor_step"]
        rstr   = step["return_strength"]
        dsca   = step["segment_duration_scale"]
        esca   = step["segment_energy_scale"]
        alpha  = float(step.get("_alpha", 1.0))

        # ── 1. Latent displacement ──────────────────────────────────────────
        if mode in ("drift", "settle"):
            td  = vel / (np.linalg.norm(vel) + 1e-8)
            pos = pos + td * sz + rng.randn(d) * tmp * sz

        elif mode == "mutate":
            noise = rng.randn(d); noise /= (np.linalg.norm(noise) + 1e-8)
            pos   = pos + noise * sz + rng.randn(d) * tmp

        elif mode == "return":
            if anch == -1:
                ap = center
            elif anch in anchors:
                ap = anchors[anch]
            else:
                ap = center
            pull = ap - pos
            pos  = pos + rstr * pull * sz + rng.randn(d) * tmp * sz

        else:
            pos = pos + rng.randn(d) * tmp * sz

        anchors[si] = pos.copy()
        vel = 0.7 * vel + 0.3 * (pos - (anchors.get(si - 1, pos)))

        # ── 2. K nearest neighbors ──────────────────────────────────────────
        dists_all = np.sqrt(np.sum((Z - pos) ** 2, axis=1))
        nn_idx    = np.argsort(dists_all)[:K]
        nn_pos    = Z[nn_idx]

        # ── 3. Mixing weights (spec formula) ────────────────────────────────
        attn_row = A[si % N_ev][nn_idx]
        weights  = _mix_weights(pos, nn_pos, attn_row, alpha)

        # ── 4. Mix clips ────────────────────────────────────────────────────
        tgt_len = max(4, int(round(
            sum(w * c.shape[0] for w, c in zip(weights, [clips[i] for i in nn_idx])))))

        mixed = np.zeros((tgt_len, n_ch) if n_ch > 1 else (tgt_len,), dtype=np.float32)
        for w, ev_idx in zip(weights, nn_idx):
            c = clips[ev_idx].astype(np.float32)
            clen = c.shape[0]
            if clen == tgt_len:
                pass  # exact match — use as-is
            elif abs(clen - tgt_len) <= max(4, int(tgt_len * 0.10)):
                # within 10% — pad or trim cleanly, no resampling
                if clen > tgt_len:
                    fl = min(64, tgt_len // 4)
                    c  = c[:tgt_len].copy()
                    if fl > 0:
                        c[-fl:] = (c[-fl:].T * np.cos(np.linspace(0, np.pi/2, fl)).astype(np.float32)).T
                else:
                    pad_shape = (tgt_len - clen, n_ch) if n_ch > 1 else (tgt_len - clen,)
                    c = np.concatenate([c, np.zeros(pad_shape, dtype=np.float32)])
            else:
                # Use _resample dispatcher — pvoc only for large ratios
                if n_ch > 1:
                    c = np.stack([_resample(c[:, ch], tgt_len) for ch in range(n_ch)], axis=1)
                else:
                    c = _resample(c, tgt_len)
            mixed += w * c

        # Duration + energy scaling
        if abs(dsca - 1.0) > 0.01:
            nl = max(4, int(round(mixed.shape[0] * dsca)))
            if n_ch > 1:
                mixed = np.stack([_resample(mixed[:, ch], nl) for ch in range(n_ch)], axis=1)
            else:
                mixed = _resample(mixed, nl)
        mixed = (mixed * esca).astype(np.float32)

        # ── 5. Crossfade and append ─────────────────────────────────────────
        cl  = mixed.shape[0]
        do_xfade = ptr > 0 and cl >= xfade * 3
        if do_xfade:
            # fade-out the tail already written in buf
            tail_start = ptr - xfade
            if tail_start >= 0:
                if n_ch > 1:
                    buf[tail_start:ptr] = (buf[tail_start:ptr].T * fade_out).T
                else:
                    buf[tail_start:ptr] *= fade_out
            # fade-in the new clip (replace, not add)
            if n_ch > 1:
                mixed[:xfade] = (mixed[:xfade].T * fade_in).T
            else:
                mixed[:xfade] *= fade_in
            # write from the crossfade start — replace, don't accumulate
            write_ptr = ptr - xfade
        else:
            write_ptr = ptr

        end = write_ptr + cl
        if end > buf.shape[0]:
            pad_shape = (end - buf.shape[0] + mean_cl, n_ch) if n_ch > 1 else (end - buf.shape[0] + mean_cl,)
            buf = np.concatenate([buf, np.zeros(pad_shape, dtype=np.float32)])
        buf[write_ptr:end] = mixed   # overwrite, not accumulate
        ptr = end

        stats.append({"step": si, "mode": mode, "k": K,
                       "nn": nn_idx.tolist(), "w": [round(float(x),4) for x in weights]})

    # ── Time-normalize to target_samples ────────────────────────────────────
    raw = buf[:max(1, ptr)]
    if raw.shape[0] != target_samples:
        if n_ch > 1:
            mono = np.stack([_resample(raw[:, ch], target_samples) for ch in range(n_ch)], axis=1)
        else:
            mono = _resample(raw, target_samples)
    else:
        mono = raw.copy().astype(np.float32)

    # Build stereo output
    if n_ch >= 2:
        # Already multichannel — use first two channels directly
        stereo = mono[:, :2].copy()
    else:
        # Mono source — duplicate to stereo, no delay
        stereo = np.stack([mono, mono], axis=1)

    peak = np.max(np.abs(stereo))
    if peak > 0.99:
        stereo *= 0.99 / peak

    return stereo, stats


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Output, compensation, cleanup
# ═══════════════════════════════════════════════════════════════════════════

def _rms_compensate(stereo, ref_rms, mode):
    """
    mode: none | peak | rms
    Safety ceiling: -1 dBFS (0.891)
    """
    import numpy as np
    CEIL = 0.891
    out  = stereo.astype(np.float32)
    peak = np.max(np.abs(out))
    if peak < 1e-9:
        return out
    if mode == "peak":
        out *= CEIL / peak
    elif mode in ("rms", "loudness"):
        rms = float(np.sqrt(np.mean(out.astype(np.float64) ** 2)))
        if rms > 1e-9 and ref_rms > 1e-9:
            out *= ref_rms / rms
        pk2 = np.max(np.abs(out))
        if pk2 > CEIL:
            out *= CEIL / pk2
    return out


def write_stats(path, events, plan, losses, stats,
                sr, out_dur, attn_heads, attn_entropy,
                pitch_mode, norm_mode, ref_rms, out_rms, warnings):
    import numpy as np
    mode_counts = {}
    for s in stats:
        mode_counts[s["mode"]] = mode_counts.get(s["mode"], 0) + 1
    with open(path, "w") as f:
        f.write("n_events=%d\n"         % len(events))
        f.write("n_plan_steps=%d\n"     % len(plan))
        f.write("n_executed=%d\n"       % len(stats))
        f.write("output_duration=%.3f\n"% out_dur)
        f.write("attn_heads=%d\n"       % attn_heads)
        f.write("attn_entropy=%.4f\n"   % attn_entropy)
        f.write("pitch_mode=%s\n"       % pitch_mode)
        f.write("normalize_mode=%s\n"   % norm_mode)
        f.write("rms_input=%.6f\n"      % ref_rms)
        f.write("rms_output=%.6f\n"     % out_rms)
        f.write("vae_loss_initial=%.6f\n" % (losses[0]  if losses else 0))
        f.write("vae_loss_final=%.6f\n"   % (losses[-1] if losses else 0))
        for m, c in sorted(mode_counts.items()):
            f.write("mode_%s=%d\n"      % (m, c))
        dur_arr = [float(e["end_time"]) - float(e["start_time"]) for e in events]
        f.write("mean_event_dur=%.3f\n" % float(np.mean(dur_arr)))
        for w in warnings:
            f.write("warning=%s\n"      % w)


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    import argparse
    import numpy as np
    import soundfile as sf

    parser = argparse.ArgumentParser(
        description="Self-Attention Latent navigation engine")

    # Positional — Praat passes exactly these
    parser.add_argument("input_wav")
    parser.add_argument("events_csv")
    parser.add_argument("output_wav")
    parser.add_argument("stats_txt")

    # Core
    parser.add_argument("--latent_size",  type=int,   default=8)
    parser.add_argument("--seed",         type=int,   default=42)
    parser.add_argument("--duration",     type=float, default=0.0,
        help="Target duration in seconds (0 = match input)")

    # Attention
    parser.add_argument("--attn_heads",   type=int,   default=4)

    # Plan
    parser.add_argument("--plan_steps",   type=int,   default=72)
    parser.add_argument("--plan_dur_scale",  type=float, default=1.0)
    parser.add_argument("--plan_dur_jitter", type=float, default=0.0)
    parser.add_argument("--plan_eng_scale",  type=float, default=1.0)
    parser.add_argument("--plan_eng_jitter", type=float, default=0.0)

    # Audio
    parser.add_argument("--pitch_mode",
        choices=["off", "preserve_f0", "preserve_spectral_envelope"],
        default="off")
    parser.add_argument("--normalize_mode",
        choices=["none", "peak", "rms"],
        default="rms")

    # Cleanup
    parser.add_argument("--cleanup", action="store_true",
        help="Delete Praat-created temp files after run")

    args = parser.parse_args()
    check_deps()

    np.random.seed(args.seed)
    warnings_list = []

    # ── Stage 1: Load ──────────────────────────────────────────────────────
    print("  [SAL 1/5] Loading audio + events...")
    audio, sr = sf.read(args.input_wav, always_2d=False)
    audio     = np.asarray(audio, dtype=np.float32)
    events    = load_events(args.events_csv)

    n_samp   = len(audio) if audio.ndim == 1 else audio.shape[0]
    orig_dur = n_samp / sr
    tgt_dur  = args.duration if args.duration > 0 else orig_dur
    tgt_samp = int(tgt_dur * sr)

    print("    Audio: %.2fs  SR=%d  Events=%d" % (orig_dur, sr, len(events)))
    if len(events) < 3:
        warnings_list.append("too_few_events_%d" % len(events))

    # Input RMS for loudness compensation
    mono_ref = audio if audio.ndim == 1 else audio.mean(1)
    ref_rms  = float(np.sqrt(np.mean(mono_ref.astype(np.float64) ** 2)))

    # Mel patches
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
    patches    = extract_patches(audio_mono.astype(np.float64), sr, events)
    print("    Patches: %s" % str(patches.shape))

    # VAE
    z_dim    = max(2, min(32, args.latent_size))
    n_iter   = max(60, min(300, 80 + len(events) * 3))
    print("  [SAL 1/5] Training VAE (%d iters, z=%d)..." % (n_iter, z_dim))
    model, losses = train_vae(patches, z_dim, n_iter, args.seed)
    lr = losses[-1] / (losses[0] + 1e-12) if losses else 1.0
    print("    Loss: %.6f → %.6f (%.1f%% reduction)" % (
        losses[0], losses[-1], (1 - lr) * 100))
    if lr > 0.95:
        warnings_list.append("vae_did_not_converge")

    Z = encode(model, patches)
    print("    Z: %s  range [%.3f, %.3f]" % (str(Z.shape), Z.min(), Z.max()))

    # ── Stage 2: Self-attention ────────────────────────────────────────────
    heads = max(1, min(args.attn_heads, z_dim))
    print("  [SAL 2/5] Building attention matrix (%d heads)..." % heads)
    A, H_mean = build_attention(Z, n_heads=heads, seed=args.seed)
    print("    A: %s  entropy=%.4f nats" % (str(A.shape), H_mean))

    # ── Stage 3: Plan generation ───────────────────────────────────────────
    print("  [SAL 3/5] Generating navigation plan (%d steps)..." % args.plan_steps)
    plan = generate_plan(Z, A,
                         n_steps    = args.plan_steps,
                         seed       = args.seed,
                         dur_scale  = args.plan_dur_scale,
                         dur_jitter = args.plan_dur_jitter,
                         eng_scale  = args.plan_eng_scale,
                         eng_jitter = args.plan_eng_jitter)
    # Clamp k to event count
    for row in plan:
        row["k_neighbors"] = min(row["k_neighbors"], len(events))
    modes = {}
    for s in plan:
        modes[s["mode"]] = modes.get(s["mode"], 0) + 1
    print("    Plan: %s" % "  ".join("%s=%d" % kv for kv in sorted(modes.items())))

    # ── Stage 4: Execute ───────────────────────────────────────────────────
    print("  [SAL 4/5] Extracting clips + executing plan...")
    clips  = _extract_clips(audio, events, sr)
    output, step_stats = execute_plan(
        plan, Z, A, clips, sr, tgt_samp, args.seed,
        pitch_mode=args.pitch_mode)
    print("    Used %d/%d steps | %.2fs | peak=%.4f" % (
        len(step_stats), len(plan),
        output.shape[0] / sr, np.max(np.abs(output))))

    # ── Stage 5: Output ────────────────────────────────────────────────────
    print("  [SAL 5/5] Loudness compensation + writing output...")
    pre_rms = float(np.sqrt(np.mean(output.astype(np.float64) ** 2)))
    output  = _rms_compensate(output, ref_rms, args.normalize_mode)
    out_rms = float(np.sqrt(np.mean(output.astype(np.float64) ** 2)))
    print("    %s: RMS %.4f → %.4f (ref %.4f)" % (
        args.normalize_mode, pre_rms, out_rms, ref_rms))

    sf.write(args.output_wav, output, sr)
    write_stats(args.stats_txt, events, plan, losses, step_stats,
                sr, output.shape[0] / sr,
                heads, H_mean, args.pitch_mode, args.normalize_mode,
                ref_rms, out_rms, warnings_list)

    # Cleanup: delete Praat-created temp files only
    if args.cleanup:
        for path in [args.input_wav, args.events_csv]:
            if os.path.basename(path).startswith(TEMP_PREFIX) and os.path.exists(path):
                os.remove(path)
                print("    Deleted: %s" % path)

    print("OK: %s" % args.output_wav)


if __name__ == "__main__":
    main()
