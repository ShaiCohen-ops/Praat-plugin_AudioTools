"""
latent_time_warp.py — Temporal Elasticity / Latent Time Warping Engine

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Called by TemporalElasticity.praat — not run directly.

Usage:
    python latent_time_warp.py events.csv output_durations.csv [options]

Pipeline:
    Stage 1 — Load events.csv (start_time, duration, spectral features)
    Stage 2 — Encode events → latent vectors (lightweight autoencoder / PCA)
    Stage 3 — Construct temporal field over latent space
    Stage 4 — Map each event to a new duration via the temporal field
    Stage 5 — Write output_durations.csv and stats.txt
              Delete events.csv and any temp files

Temporal field modes:
    gravitational — latent cluster centers stretch time (Gaussian wells)
    inversion     — dense regions compress, sparse regions stretch
    turbulence    — stochastic local fluctuations (seeded, deterministic)
    gradient      — dilation ramps along the first principal component of Z
    relativistic  — latent velocity between events drives Lorentz time dilation

No PyTorch. No TensorFlow. No sklearn. No internet.
Dependencies: numpy, soundfile (for patch reading)
"""

import sys
import os
import csv
import math

TEMP_PREFIX   = "temp_te_"
SCALE_MIN     = 0.3
SCALE_MAX     = 3.0
DUR_MIN_ABS   = 0.02   # absolute minimum new duration (s) — avoids micro-clicks
DUR_MAX_ABS   = 2.0    # absolute maximum new duration (s) — avoids huge smears


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

def check_deps():
    for pkg in ["numpy", "soundfile"]:
        try:
            __import__(pkg)
        except ImportError:
            print("ERROR: missing package: %s" % pkg, file=sys.stderr)
            print("pip install %s" % pkg, file=sys.stderr)
            sys.exit(1)


def load_events_csv(path):
    events = []
    with open(path, "r") as f:
        header = [h.strip() for h in f.readline().strip().split(",")]
        for line in f:
            line = line.strip()
            if not line:
                continue
            vals = line.split(",")
            if len(vals) != len(header):
                continue
            row = {}
            for h, v in zip(header, vals):
                v = v.strip()
                try:
                    row[h] = float(v)
                except ValueError:
                    row[h] = v
            events.append(row)
    return events


# ═══════════════════════════════════════════════════════════════════════════
# Stage 1b — Feature Extraction from audio patches
# ═══════════════════════════════════════════════════════════════════════════

_mel_filterbank_cache = {}

def _mel_filterbank(sr, n_fft, n_mels):
    import numpy as np
    key = (sr, n_fft, n_mels)
    if key in _mel_filterbank_cache:
        return _mel_filterbank_cache[key]
    def hz2mel(h): return 2595.0 * math.log10(1.0 + h / 700.0)
    def mel2hz(m): return 700.0 * (10.0 ** (m / 2595.0) - 1.0)
    n_bins = n_fft // 2 + 1
    mel_lo = hz2mel(20)
    mel_hi = hz2mel(sr / 2)
    pts    = np.array([mel2hz(mel_lo + i * (mel_hi - mel_lo) / (n_mels + 1))
                       for i in range(n_mels + 2)])
    bins   = np.clip(np.floor((n_fft + 1) * pts / sr).astype(int), 0, n_bins - 1)
    fb     = np.zeros((n_mels, n_bins))
    k_all  = np.arange(n_bins)
    for m in range(1, n_mels + 1):
        lo, c, hi = bins[m-1], bins[m], bins[m+1]
        if c > lo:
            mask = (k_all >= lo) & (k_all < c)
            fb[m-1, mask] = (k_all[mask] - lo) / (c - lo)
        if hi > c:
            mask = (k_all >= c) & (k_all < hi)
            fb[m-1, mask] = (hi - k_all[mask]) / (hi - c)
    _mel_filterbank_cache[key] = fb
    return fb


def extract_features_from_patch(wav_path, sr_hint=44100):
    """
    Extract a fixed-length feature vector from one event audio patch.
    Returns (feature_vector, sr, duration_samples).

    Features (24-dim):
        • 13 MFCCs (mean over frames)
        •  1 spectral centroid (normalised)
        •  1 spectral flatness
        •  1 RMS energy
        •  1 zero-crossing rate
        •  1 log duration (samples)
        •  6 delta-MFCCs (first 6, mean absolute)
    """
    import numpy as np
    import soundfile as sf

    audio, sr = sf.read(wav_path, always_2d=False)
    audio = np.asarray(audio, dtype=np.float64)
    if audio.ndim == 2:
        audio = audio.mean(axis=1)
    N = len(audio)

    n_fft  = min(1024, N)
    hop    = n_fft // 4
    n_mels = 26
    n_mfcc = 13
    win    = np.hanning(n_fft)
    fb     = _mel_filterbank(sr, n_fft, n_mels)

    # STFT frames
    n_frames = max(1, (N - n_fft) // hop + 1)
    mfcc_frames = []
    centroid_frames = []
    flatness_frames = []
    rms_frames = []
    zcr_frames = []

    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sr)

    for fi in range(n_frames):
        st = fi * hop
        fr = np.zeros(n_fft)
        av = min(n_fft, N - st)
        fr[:av] = audio[st:st + av]
        fr *= win

        mag  = np.abs(np.fft.rfft(fr))
        pow_ = mag ** 2

        # Mel energies and MFCCs
        mel_e = fb.dot(pow_)
        log_mel = np.log(mel_e + 1e-10)
        # DCT-II for MFCCs
        mfcc = np.zeros(n_mfcc)
        for k in range(n_mfcc):
            mfcc[k] = np.sum(log_mel * np.cos(math.pi * k / n_mels *
                             (np.arange(n_mels) + 0.5)))
        mfcc_frames.append(mfcc)

        # Spectral centroid
        s_sum = np.sum(mag) + 1e-12
        centroid_frames.append(np.sum(freqs * mag) / s_sum)

        # Spectral flatness
        log_mean = np.mean(np.log(pow_ + 1e-10))
        arith    = np.mean(pow_) + 1e-10
        flatness_frames.append(math.exp(log_mean) / arith)

        # RMS
        rms_frames.append(math.sqrt(np.mean(fr ** 2) + 1e-10))

        # ZCR
        zcr = np.sum(np.abs(np.diff(np.sign(fr)))) / (2 * n_fft)
        zcr_frames.append(zcr)

    mfcc_arr = np.array(mfcc_frames)           # (n_frames, 13)
    mfcc_mean = mfcc_arr.mean(axis=0)          # (13,)

    # Delta-MFCCs (first 6)
    if len(mfcc_frames) > 1:
        delta = np.abs(np.diff(mfcc_arr, axis=0)).mean(axis=0)[:6]
    else:
        delta = np.zeros(6)

    centroid_norm = np.mean(centroid_frames) / (sr / 2 + 1e-12)
    flatness      = float(np.mean(flatness_frames))
    rms           = float(np.mean(rms_frames))
    zcr           = float(np.mean(zcr_frames))
    log_dur       = math.log(max(N, 1))

    feat = np.concatenate([
        mfcc_mean,          # 13
        [centroid_norm],    #  1
        [flatness],         #  1
        [rms],              #  1
        [zcr],              #  1
        [log_dur],          #  1
        delta,              #  6
    ])                      # total: 24
    return feat.astype(np.float64), sr, N


def extract_features_from_events(events, patch_dir):
    """
    Load each event's audio patch and extract features.
    Falls back to CSV-embedded features if patch files are missing.
    Returns (feature_matrix NxD, feature_names).
    """
    import numpy as np

    feats = []
    for ev in events:
        patch_file = ev.get("patch_file", "")
        patch_path = os.path.join(patch_dir, patch_file) if patch_file else ""

        if patch_file and os.path.isfile(patch_path):
            feat, _, _ = extract_features_from_patch(patch_path)
            feats.append(feat)
        else:
            # Fallback: build a minimal feature vector from CSV columns
            # (start_time, duration, rms, spectral_centroid, zcr if present)
            row = []
            for col in ["duration", "rms", "spectral_centroid",
                        "zero_crossing_rate", "spectral_flatness"]:
                row.append(float(ev.get(col, 0.0)))
            # Pad to 24 dims with zeros
            row = row + [0.0] * (24 - len(row))
            feats.append(np.array(row[:24], dtype=np.float64))

    return np.array(feats, dtype=np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Latent Space (lightweight autoencoder, pure NumPy)
# ═══════════════════════════════════════════════════════════════════════════

class _AE:
    """
    Minimal symmetric autoencoder: input → hidden → latent → hidden → output.
    Adam optimiser. No PyTorch/sklearn.
    """
    def __init__(self, in_dim, h_dim, z_dim, seed):
        import numpy as np
        rng = np.random.RandomState(seed)
        s   = lambda a, b: rng.randn(a, b) * math.sqrt(2.0 / (a + b))
        # Encoder
        self.We1 = s(in_dim, h_dim); self.be1 = np.zeros(h_dim)
        self.We2 = s(h_dim, z_dim);  self.be2 = np.zeros(z_dim)
        # Decoder
        self.Wd1 = s(z_dim, h_dim);  self.bd1 = np.zeros(h_dim)
        self.Wd2 = s(h_dim, in_dim); self.bd2 = np.zeros(in_dim)
        self.params = [self.We1, self.be1, self.We2, self.be2,
                       self.Wd1, self.bd1, self.Wd2, self.bd2]
        self.m = [np.zeros_like(p) for p in self.params]
        self.v = [np.zeros_like(p) for p in self.params]
        self.t  = 0
        self.rng = rng
        self.in_dim = in_dim

    def _relu(self, x):
        import numpy as np; return np.maximum(0.0, x)

    def encode(self, X):
        self._h1 = self._relu(X.dot(self.We1) + self.be1)
        return self._h1.dot(self.We2) + self.be2   # linear bottleneck

    def decode(self, Z):
        h = self._relu(Z.dot(self.Wd1) + self.bd1)
        return h.dot(self.Wd2) + self.bd2

    def step(self, X, lr, noise=0.1):
        import numpy as np
        B  = X.shape[0]
        Xn = X + noise * self.rng.randn(*X.shape)
        Z  = self.encode(Xn)
        R  = self.decode(Z)
        diff = R - X
        loss = float(np.mean(diff ** 2))

        # Backward
        dR   = 2.0 * diff / (B * self.in_dim)
        dWd2 = (self._relu(Z.dot(self.Wd1) + self.bd1)).T.dot(dR)
        dbd2 = np.sum(dR, 0)
        dh   = dR.dot(self.Wd2.T) * (Z.dot(self.Wd1) + self.bd1 > 0)
        dWd1 = Z.T.dot(dh); dbd1 = np.sum(dh, 0)
        dZ   = dh.dot(self.Wd1.T)

        dWe2 = self._h1.T.dot(dZ); dbe2 = np.sum(dZ, 0)
        dh1  = dZ.dot(self.We2.T) * (Xn.dot(self.We1) + self.be1 > 0)
        dWe1 = Xn.T.dot(dh1); dbe1 = np.sum(dh1, 0)

        grads = [dWe1, dbe1, dWe2, dbe2, dWd1, dbd1, dWd2, dbd2]
        self.t += 1
        b1, b2, eps = 0.9, 0.999, 1e-8
        for i, (p, g) in enumerate(zip(self.params, grads)):
            self.m[i] = b1*self.m[i] + (1-b1)*g
            self.v[i] = b2*self.v[i] + (1-b2)*g**2
            mh = self.m[i] / (1 - b1**self.t)
            vh = self.v[i] / (1 - b2**self.t)
            p -= lr * mh / (np.sqrt(vh) + eps)
        return loss


def _pca(X, n_components):
    """PCA via SVD. Returns (scores, explained_variance_ratio)."""
    import numpy as np
    mu = X.mean(0)
    Xc = X - mu
    U, S, Vt = np.linalg.svd(Xc, full_matrices=False)
    scores = Xc.dot(Vt[:n_components].T)
    total  = float((S ** 2).sum()) + 1e-12
    var_r  = (S[:n_components] ** 2) / total
    return scores, var_r, mu, Vt[:n_components]


def learn_latent(features, z_dim, n_iter, seed, method="ae"):
    """
    Learn latent representations.
    method: 'ae' (autoencoder) or 'pca'
    Returns (Z: NxD, losses or variance_explained, metadata_dict)
    """
    import numpy as np

    N, D = features.shape
    mu_n = features.mean(0)
    sg_n = features.std(0) + 1e-8
    X    = (features - mu_n) / sg_n

    if method == "pca" or N < 6:
        z_dim = min(z_dim, N - 1, D)
        Z, var_r, pca_mu, pca_Vt = _pca(X, z_dim)
        meta = {"method": "pca", "var_explained": var_r.tolist(),
                "pca_mu": pca_mu.tolist(), "pca_Vt": pca_Vt.tolist(),
                "norm_mu": mu_n.tolist(), "norm_sg": sg_n.tolist()}
        losses = list(1.0 - var_r.cumsum())
        return Z.astype(np.float64), losses, meta

    # Autoencoder
    h_dim = max(z_dim * 2, min(128, int(math.sqrt(D * z_dim))))
    ae    = _AE(D, h_dim, z_dim, seed)
    lr0   = 0.003
    losses = []
    for i in range(n_iter):
        lr   = lr0 * (1.0 - 0.5 * i / n_iter)
        loss = ae.step(X, lr, noise=0.15)
        losses.append(loss)
    Z = ae.encode(X)
    meta = {"method": "ae", "norm_mu": mu_n.tolist(), "norm_sg": sg_n.tolist()}
    return Z.astype(np.float64), losses, meta


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Temporal Field Construction
# ═══════════════════════════════════════════════════════════════════════════

def _find_cluster_centers(Z, n_clusters, seed):
    """
    Simple k-means (pure NumPy, seeded).
    Returns (centers: n_clusters×D, labels: N,)
    """
    import numpy as np
    rng  = np.random.RandomState(seed)
    N, D = Z.shape
    n_clusters = min(n_clusters, N)

    # K-means++ init
    idx = [int(rng.randint(0, N))]
    for _ in range(n_clusters - 1):
        d2 = np.min(np.sum((Z[:, None, :] - Z[idx, :][None, :, :]) ** 2, axis=2),
                    axis=1)
        probs = d2 / (d2.sum() + 1e-12)
        idx.append(int(rng.choice(N, p=probs)))

    centers = Z[idx].copy()

    for _ in range(50):
        # Assign
        d2  = np.sum((Z[:, None, :] - centers[None, :, :]) ** 2, axis=2)
        labels = np.argmin(d2, axis=1)
        # Update
        new_c = np.zeros_like(centers)
        for ci in range(n_clusters):
            mask = labels == ci
            if mask.any():
                new_c[ci] = Z[mask].mean(0)
            else:
                new_c[ci] = centers[ci]
        if np.allclose(centers, new_c, atol=1e-6):
            break
        centers = new_c

    return centers, labels


def build_temporal_field(Z, mode, seed,
                         amplitude=0.8,
                         sigma=1.0,
                         n_clusters=3,
                         gradient_axis=0,
                         turbulence_strength=0.3):
    """
    Compute a time_scale value for each event in Z.

    mode:
        gravitational — Gaussian wells at cluster centers stretch time
                        scale = 1 + A * exp(-d²/σ²)
        inversion     — dense regions compress, sparse regions stretch
                        scale = 1 / (density + ε), normalised
        turbulence    — seeded deterministic noise field in latent space
        gradient      — linear ramp along the principal axis of Z

    Returns (scales: (N,) float64) clamped to [SCALE_MIN, SCALE_MAX].
    """
    import numpy as np

    N, D = Z.shape
    rng  = np.random.RandomState(seed)

    if mode == "gravitational":
        centers, _ = _find_cluster_centers(Z, n_clusters, seed)
        scales = np.ones(N)
        for ci in range(len(centers)):
            dists = np.sqrt(np.sum((Z - centers[ci]) ** 2, axis=1))
            scales += amplitude * np.exp(-(dists ** 2) / (2 * sigma ** 2 + 1e-12))

    elif mode == "inversion":
        # Local density = mean distance to k nearest neighbours (k=3)
        k = min(3, N - 1)
        dists_all = np.sqrt(np.sum((Z[:, None, :] - Z[None, :, :]) ** 2, axis=2))
        # Mean distance to k nearest neighbours — vectorised via np.partition
        # col 0 is self (dist=0), cols 1..k are the k nearest neighbours
        partitioned = np.partition(dists_all, kth=k + 1, axis=1)
        density = partitioned[:, 1:k + 1].mean(axis=1) + 1e-8
        # Dense → compress (scale < 1), sparse → stretch (scale > 1)
        # Scale = median_density / density (so median gets scale=1)
        median_d = np.median(density)
        scales   = (median_d / density) ** amplitude

    elif mode == "turbulence":
        # Deterministic RBF noise: seed random centres, random amplitudes
        n_noise = max(4, N // 2)
        centers = rng.randn(n_noise, D)
        amps    = (rng.rand(n_noise) * 2 - 1) * turbulence_strength
        sig_t   = sigma * 0.5
        scales  = np.ones(N)
        for ci in range(n_noise):
            dists = np.sqrt(np.sum((Z - centers[ci]) ** 2, axis=1))
            scales += amps[ci] * np.exp(-(dists ** 2) / (2 * sig_t ** 2 + 1e-12))

    elif mode == "gradient":
        # Project Z onto the first principal component of Z (dominant latent direction).
        # This automatically aligns the time ramp with the axis of greatest
        # acoustic variation — regardless of latent dimensionality or rotation.
        Zc   = Z - Z.mean(axis=0)
        _, _, Vt = np.linalg.svd(Zc, full_matrices=False)
        pc1  = Vt[0]                        # first right singular vector (D,)
        proj = Zc.dot(pc1)                  # projection onto dominant axis (N,)
        mn, mx = proj.min(), proj.max()
        t      = (proj - mn) / (mx - mn + 1e-12)    # 0 → 1
        # Scale ramps from 1/(1+A) to (1+A)
        lo     = 1.0 / (1.0 + amplitude)
        hi     = 1.0 + amplitude
        scales = lo + t * (hi - lo)

    elif mode == "relativistic":
        # Latent velocity between consecutive events drives time dilation.
        # High latent velocity (rapid identity change) → time slows down.
        # Based on special relativity: scale = 1 / sqrt(1 - (v/c)^2)
        # where c is set to the 95th-percentile velocity (so most events
        # stay sub-luminal and the formula remains real-valued).

        # Compute per-event velocity: ||z(i) - z(i-1)||
        deltas = np.diff(Z, axis=0)                           # (N-1, D)
        vels   = np.sqrt(np.sum(deltas ** 2, axis=1))         # (N-1,)
        velocities = np.concatenate([[vels[0] if N > 1 else 0.0], vels])

        # Set c to 95th-percentile velocity so scale stays finite
        c = np.percentile(velocities, 95) + 1e-8

        # Lorentz factor
        beta   = np.clip(velocities / c, 0.0, 0.999)
        lorentz = 1.0 / np.sqrt(1.0 - beta ** 2)

        # Normalise so median event gets scale = 1, then apply amplitude
        median_l = np.median(lorentz)
        scales   = 1.0 + amplitude * (lorentz / (median_l + 1e-8) - 1.0)

    else:
        scales = np.ones(N)

    # Clamp
    scales = np.clip(scales, SCALE_MIN, SCALE_MAX)
    return scales.astype(np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Duration Mapping
# ═══════════════════════════════════════════════════════════════════════════

def apply_duration_rules(events, scales, extra_rules="none",
                         short_threshold=0.1, long_threshold=0.5):
    """
    Compute new_duration = original_duration * time_scale.

    extra_rules:
        none       — pure temporal field
        short_stretch  — short events get extra stretch bonus
        long_compress  — long events get extra compression
        harmonic_compress  — (uses spectral_flatness: low = more harmonic → compress)
        noisy_dilate      — (uses spectral_flatness: high = noisy → dilate)

    Returns list of new_duration floats.
    """
    import numpy as np

    new_durations = []
    for ev, scale in zip(events, scales):
        orig = float(ev.get("duration", 0.1))
        s    = float(scale)

        if extra_rules == "short_stretch" and orig < short_threshold:
            s *= 1.0 + (short_threshold - orig) / (short_threshold + 1e-8)

        elif extra_rules == "long_compress" and orig > long_threshold:
            excess = (orig - long_threshold) / (long_threshold + 1e-8)
            s *= max(0.5, 1.0 - 0.3 * excess)

        elif extra_rules == "harmonic_compress":
            flat = float(ev.get("spectral_flatness", 0.5))
            # low flatness = tonal → compress
            s *= 1.0 - 0.4 * (1.0 - flat)

        elif extra_rules == "noisy_dilate":
            flat = float(ev.get("spectral_flatness", 0.5))
            # high flatness = noisy → dilate
            s *= 1.0 + 0.6 * flat

        # Proportional clamp (relative to original duration)
        new_dur = float(np.clip(orig * s, orig * SCALE_MIN, orig * SCALE_MAX))
        # Absolute clamp (avoids micro-clicks and runaway smears)
        new_dur = float(np.clip(new_dur, DUR_MIN_ABS, DUR_MAX_ABS))
        new_durations.append(new_dur)

    return new_durations


# ═══════════════════════════════════════════════════════════════════════════
# Metrics
# ═══════════════════════════════════════════════════════════════════════════

def compute_metrics(events, scales, Z, new_durations):
    """
    Optional reflection metrics:
        - event density (events per second, before/after)
        - spectral centroid drift (std of centroid across events)
        - entropy of scale distribution
        - latent dispersion (mean pairwise distance)
    """
    import numpy as np

    orig_total = sum(float(e.get("duration", 0)) for e in events)
    new_total  = sum(new_durations)

    # Event density
    n = len(events)
    orig_density = n / (orig_total + 1e-9)
    new_density  = n / (new_total  + 1e-9)

    # Spectral centroid drift
    centroids = [float(e.get("spectral_centroid", 0)) for e in events]
    centroid_std = float(np.std(centroids)) if len(centroids) > 1 else 0.0

    # Scale entropy
    scale_bins = np.histogram(scales, bins=10, range=(SCALE_MIN, SCALE_MAX))[0]
    scale_probs = scale_bins / (scale_bins.sum() + 1e-12)
    scale_entropy = float(-np.sum(scale_probs * np.log(scale_probs + 1e-12)))

    # Latent dispersion
    if len(Z) > 1:
        diffs = Z[:, None, :] - Z[None, :, :]
        dists = np.sqrt(np.sum(diffs ** 2, axis=2))
        latent_dispersion = float(np.mean(dists))
    else:
        latent_dispersion = 0.0

    return {
        "orig_total_dur":    round(orig_total,  4),
        "new_total_dur":     round(new_total,   4),
        "compression_ratio": round(new_total / (orig_total + 1e-9), 4),
        "orig_density":      round(orig_density, 4),
        "new_density":       round(new_density,  4),
        "centroid_std":      round(centroid_std, 4),
        "scale_entropy":     round(scale_entropy, 4),
        "scale_mean":        round(float(np.mean(scales)), 4),
        "scale_std":         round(float(np.std(scales)),  4),
        "latent_dispersion": round(latent_dispersion, 4),
    }


# ═══════════════════════════════════════════════════════════════════════════
# Output writers
# ═══════════════════════════════════════════════════════════════════════════

def write_durations_csv(path, events, scales, new_durations, Z):
    """
    Write output_durations.csv — read back by Praat for reconstruction.
    Columns: event_index, start_time, original_duration, time_scale, new_duration,
             latent_z0, latent_z1 (first 2 dims for Praat visualization)
    """
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["event_index", "start_time", "original_duration",
                         "time_scale", "new_duration",
                         "latent_z0", "latent_z1"])
        for i, (ev, sc, nd) in enumerate(zip(events, scales, new_durations)):
            z0 = float(Z[i, 0]) if Z.shape[1] > 0 else 0.0
            z1 = float(Z[i, 1]) if Z.shape[1] > 1 else 0.0
            writer.writerow([
                i,
                round(float(ev.get("start_time", 0.0)), 6),
                round(float(ev.get("duration", 0.0)), 6),
                round(float(sc), 6),
                round(float(nd), 6),
                round(z0, 6),
                round(z1, 6),
            ])


def write_stats(path, events, scales, new_durations, Z,
                losses, meta, metrics, mode, extra_rules,
                z_dim, n_iter, warnings):
    with open(path, "w") as f:
        f.write("n_events=%d\n"          % len(events))
        f.write("z_dim=%d\n"             % z_dim)
        f.write("latent_method=%s\n"     % meta.get("method", "?"))
        f.write("n_iter=%d\n"            % n_iter)
        f.write("field_mode=%s\n"        % mode)
        f.write("extra_rules=%s\n"       % extra_rules)
        f.write("vae_loss_initial=%.6f\n"% (losses[0]  if losses else 0))
        f.write("vae_loss_final=%.6f\n"  % (losses[-1] if losses else 0))
        for k, v in sorted(metrics.items()):
            f.write("%s=%s\n" % (k, v))
        f.write("scale_min=%.4f\n"       % float(min(scales)))
        f.write("scale_max=%.4f\n"       % float(max(scales)))
        for w in warnings:
            f.write("warning=%s\n"       % w)


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    import argparse
    import numpy as np

    parser = argparse.ArgumentParser(
        description="Temporal Elasticity — Latent Time Warping Engine")

    # I/O
    parser.add_argument("events_csv",
        help="Input: event table from Praat (start_time, duration, ...)")
    parser.add_argument("durations_csv",
        help="Output: warped durations table read by Praat")
    parser.add_argument("stats_txt",
        help="Output: human-readable stats")

    # Patch directory (where event .wav patches live, if exported by Praat)
    parser.add_argument("--patch_dir", default="",
        help="Directory containing event audio patches (optional)")

    # Latent space
    parser.add_argument("--z_dim",   type=int,   default=4,
        help="Latent dimensionality (2–8, default 4)")
    parser.add_argument("--n_iter",  type=int,   default=120,
        help="Autoencoder training iterations (default 120)")
    parser.add_argument("--latent_method",
        choices=["ae", "pca"], default="ae",
        help="Latent learning method: ae (autoencoder) or pca (default: ae)")
    parser.add_argument("--seed",    type=int,   default=42)

    # Temporal field
    parser.add_argument("--mode",
        choices=["gravitational", "inversion", "turbulence", "gradient", "relativistic"],
        default="gravitational",
        help="Temporal field mode (default: gravitational)")
    parser.add_argument("--amplitude",  type=float, default=0.8,
        help="Field amplitude — controls max stretch/compression (default 0.8)")
    parser.add_argument("--sigma",      type=float, default=1.0,
        help="Gaussian well width for gravitational/turbulence modes (default 1.0)")
    parser.add_argument("--n_clusters", type=int,   default=3,
        help="Number of latent clusters for gravitational mode (default 3)")
    parser.add_argument("--gradient_axis", type=int, default=0,
        help="Latent axis for gradient mode (default 0)")
    parser.add_argument("--turbulence_strength", type=float, default=0.3,
        help="Turbulence noise amplitude (default 0.3)")

    # Duration rules
    parser.add_argument("--extra_rules",
        choices=["none", "short_stretch", "long_compress",
                 "harmonic_compress", "noisy_dilate"],
        default="none",
        help="Additional duration mapping rule (default: none)")
    parser.add_argument("--short_threshold", type=float, default=0.1)
    parser.add_argument("--long_threshold",  type=float, default=0.5)

    # Cleanup
    parser.add_argument("--cleanup", action="store_true",
        help="Delete Praat-created temp files after run")

    args = parser.parse_args()
    check_deps()

    import numpy as np

    np.random.seed(args.seed)
    warnings_list = []

    # Clamp
    args.z_dim      = max(2, min(8,   args.z_dim))
    args.n_iter     = max(20, min(400, args.n_iter))
    args.amplitude  = max(0.1, min(3.0, args.amplitude))
    args.sigma      = max(0.1, min(5.0, args.sigma))
    args.n_clusters = max(1,  min(8,   args.n_clusters))

    # ── Stage 1: Load ──────────────────────────────────────────────────────
    print("  [TE 1/5] Loading events...")
    events = load_events_csv(args.events_csv)
    print("    Events: %d" % len(events))

    if len(events) < 2:
        warnings_list.append("too_few_events_%d" % len(events))

    patch_dir = args.patch_dir if args.patch_dir else os.path.dirname(args.events_csv)

    print("  [TE 1/5] Extracting features from patches...")
    features = extract_features_from_events(events, patch_dir)
    print("    Feature matrix: %s" % str(features.shape))

    # ── Stage 2: Learn latent space ────────────────────────────────────────
    print("  [TE 2/5] Learning latent space (%s, z=%d, %d iters)..." %
          (args.latent_method, args.z_dim, args.n_iter))
    Z, losses, meta = learn_latent(features, args.z_dim, args.n_iter,
                                   args.seed, method=args.latent_method)
    if losses:
        print("    Loss: %.6f → %.6f" % (losses[0], losses[-1]))
    print("    Z: %s  range [%.3f, %.3f]" % (str(Z.shape), Z.min(), Z.max()))

    if losses and len(losses) > 1 and losses[-1] / (losses[0] + 1e-12) > 0.92:
        warnings_list.append("latent_model_did_not_converge_well")

    # ── Stage 3: Build temporal field ──────────────────────────────────────
    print("  [TE 3/5] Building temporal field (mode=%s)..." % args.mode)
    scales = build_temporal_field(
        Z, mode=args.mode, seed=args.seed,
        amplitude=args.amplitude,
        sigma=args.sigma,
        n_clusters=args.n_clusters,
        gradient_axis=args.gradient_axis,
        turbulence_strength=args.turbulence_strength,
    )
    print("    Scale range: [%.3f, %.3f]  mean=%.3f  std=%.3f" % (
        scales.min(), scales.max(), scales.mean(), scales.std()))

    # ── Stage 4: Apply duration rules ─────────────────────────────────────
    print("  [TE 4/5] Applying duration mapping (rules=%s)..." % args.extra_rules)
    new_durations = apply_duration_rules(
        events, scales, extra_rules=args.extra_rules,
        short_threshold=args.short_threshold,
        long_threshold=args.long_threshold,
    )
    orig_total = sum(float(e.get("duration", 0)) for e in events)
    new_total  = sum(new_durations)
    print("    Total duration: %.3fs → %.3fs (ratio %.3f)" % (
        orig_total, new_total, new_total / (orig_total + 1e-9)))

    # Metrics
    metrics = compute_metrics(events, scales, Z, new_durations)

    # ── Stage 5: Write outputs ─────────────────────────────────────────────
    print("  [TE 5/5] Writing outputs...")
    write_durations_csv(args.durations_csv, events, scales, new_durations, Z)
    write_stats(args.stats_txt, events, scales, new_durations, Z,
                losses, meta, metrics,
                args.mode, args.extra_rules, args.z_dim, args.n_iter,
                warnings_list)

    # Cleanup: only Praat-created temp files (have TEMP_PREFIX)
    if args.cleanup:
        for path in [args.events_csv]:
            if os.path.basename(path).startswith(TEMP_PREFIX) and os.path.exists(path):
                os.remove(path)
                print("    Deleted: %s" % path)
        # Delete any exported patches
        if args.patch_dir and os.path.isdir(args.patch_dir):
            for fn in os.listdir(args.patch_dir):
                if fn.startswith(TEMP_PREFIX) and fn.endswith(".wav"):
                    fp = os.path.join(args.patch_dir, fn)
                    if os.path.exists(fp):
                        os.remove(fp)
                        print("    Deleted patch: %s" % fn)

    print("OK: %s" % args.durations_csv)


if __name__ == "__main__":
    main()
