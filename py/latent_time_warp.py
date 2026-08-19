"""
latent_time_warp.py - Temporal Elasticity / Latent Time Warping Engine v1.2

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Called by TemporalElasticity.praat - not run directly.

Usage:
    python latent_time_warp.py events.csv output_durations.csv [options]

Pipeline:
    Stage 1 - Load events.csv (start_time, duration, spectral features)
    Stage 2 - Encode events -> latent vectors (lightweight autoencoder / PCA)
    Stage 3 - Construct temporal field over latent space
    Stage 4 - Map each event to a new duration via the temporal field
    Stage 5 - Write output_durations.csv and stats.txt
              Optional cleanup is available for direct CLI use

Temporal field modes:
    gravitational - latent cluster centers stretch time (Gaussian wells)
    inversion     - dense regions compress, sparse regions stretch
    turbulence    - stochastic local fluctuations (seeded, deterministic)
    gradient      - dilation ramps along the first principal component of Z
    relativistic  - latent velocity between events drives Lorentz time dilation

No PyTorch. No TensorFlow. No sklearn. No internet.
Dependencies: numpy, soundfile (for patch reading)
"""

import sys
import os
import csv
import math

VERSION       = "1.2.1"

# Windows/Praat may launch Python with a legacy console encoding such as cp1252.
# Status text must never abort the engine merely because a character cannot be
# encoded. Messages are kept ASCII, and the streams are defensive as a fallback.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except (AttributeError, ValueError):
        pass

TEMP_PREFIX   = "temp_te_"
SCALE_MIN     = 0.3
SCALE_MAX     = 3.0


# ===========================================================================
# Utilities
# ===========================================================================

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


# ===========================================================================
# Stage 1b - Feature Extraction from audio patches
# ===========================================================================

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
    """Extract the 24-D acoustic feature vector from one event patch.

    For multichannel material the strongest real channel is analysed instead of
    an arithmetic fold-down, so anti-phase stereo cannot disappear. Spectral
    summaries are computed from active frames only (60 dB gate relative to the
    strongest frame), while RMS remains a whole-event level descriptor.
    """
    import numpy as np
    import soundfile as sf

    audio, sr = sf.read(wav_path, always_2d=True)
    audio = np.asarray(audio, dtype=np.float64)
    if audio.shape[0] == 0:
        return np.zeros(24, dtype=np.float64), int(sr), 0

    ch_rms = np.sqrt(np.mean(audio ** 2, axis=0) + 1e-20)
    analysis_channel = int(np.argmax(ch_rms))
    x = audio[:, analysis_channel]
    N = len(x)

    # Stable analysis size. Short patches are zero-padded rather than creating
    # hop=0 / empty FFT edge cases.
    if N <= 64:
        n_fft = 64
    else:
        n_fft = min(1024, 1 << int(math.ceil(math.log2(N))))
    hop = max(1, n_fft // 4)
    n_mels = 26
    n_mfcc = 13
    win = np.hanning(n_fft)
    fb = _mel_filterbank(sr, n_fft, n_mels)
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sr)

    n_frames = max(1, int(math.ceil(max(0, N - n_fft) / float(hop))) + 1)
    mfcc_frames, centroid_frames = [], []
    flatness_frames, rms_frames, zcr_frames = [], [], []

    dct_cos = np.cos(math.pi * np.arange(n_mfcc)[:, None] / n_mels *
                     (np.arange(n_mels)[None, :] + 0.5))

    for fi in range(n_frames):
        st = fi * hop
        fr_raw = np.zeros(n_fft, dtype=np.float64)
        av = max(0, min(n_fft, N - st))
        if av:
            fr_raw[:av] = x[st:st + av]
        fr = fr_raw * win
        mag = np.abs(np.fft.rfft(fr))
        pow_ = mag ** 2

        mel_e = fb.dot(pow_)
        log_mel = np.log(mel_e + 1e-10)
        mfcc_frames.append(dct_cos.dot(log_mel))

        s_sum = np.sum(mag) + 1e-12
        centroid_frames.append(np.sum(freqs * mag) / s_sum)
        log_mean = np.mean(np.log(pow_ + 1e-10))
        arith = np.mean(pow_) + 1e-10
        flatness_frames.append(math.exp(log_mean) / arith)
        rms_frames.append(math.sqrt(np.mean(fr_raw ** 2) + 1e-20))
        zcr_frames.append(np.mean(np.signbit(fr_raw[:-1]) != np.signbit(fr_raw[1:]))
                          if n_fft > 1 else 0.0)

    rms_arr = np.asarray(rms_frames, dtype=np.float64)
    gate = max(float(rms_arr.max()) * 1e-3, 1e-10)
    active = rms_arr >= gate
    if not np.any(active):
        active[:] = True

    mfcc_arr = np.asarray(mfcc_frames, dtype=np.float64)[active]
    mfcc_mean = mfcc_arr.mean(axis=0)
    if len(mfcc_arr) > 1:
        delta = np.abs(np.diff(mfcc_arr, axis=0)).mean(axis=0)[:6]
    else:
        delta = np.zeros(6)

    centroid_norm = float(np.mean(np.asarray(centroid_frames)[active])) / (sr / 2 + 1e-12)
    flatness = float(np.mean(np.asarray(flatness_frames)[active]))
    rms = float(np.sqrt(np.mean(x ** 2) + 1e-20))
    zcr = float(np.mean(np.asarray(zcr_frames)[active]))
    log_dur = math.log(max(N / float(sr), 1e-6))

    feat = np.concatenate([mfcc_mean, [centroid_norm, flatness, rms, zcr, log_dur], delta])
    return feat.astype(np.float64), int(sr), N


def extract_features_from_events(events, patch_dir):
    """Build a semantically consistent Nx24 matrix.

    Patch-derived features are preferred. If a patch is unavailable, the CSV
    fallback is placed in the SAME feature slots (centroid, flatness, RMS, ZCR,
    log-duration) instead of masquerading as the first five MFCC coefficients.
    Derived flatness/ZCR values are also copied back into each event so the
    optional duration rules operate on the analysed event rather than defaults.
    """
    import numpy as np

    feats = []
    for ev in events:
        patch_file = str(ev.get("patch_file", "") or "")
        patch_path = os.path.join(patch_dir, patch_file) if patch_file else ""
        if patch_file and os.path.isfile(patch_path):
            feat, _, _ = extract_features_from_patch(patch_path)
            ev["spectral_centroid"] = float(feat[13])
            ev["spectral_flatness"] = float(feat[14])
            ev["rms"] = float(feat[15])
            ev["zero_crossing_rate"] = float(feat[16])
            ev["_feature_source"] = "patch"
        else:
            feat = np.zeros(24, dtype=np.float64)
            feat[13] = float(ev.get("spectral_centroid", 0.0))
            feat[14] = float(ev.get("spectral_flatness", 0.0))
            feat[15] = float(ev.get("rms", 0.0))
            feat[16] = float(ev.get("zero_crossing_rate", 0.0))
            feat[17] = math.log(max(float(ev.get("duration", 0.1)), 1e-6))
            ev["_feature_source"] = "csv"
        feats.append(feat)
    return np.asarray(feats, dtype=np.float64)


# ===========================================================================
# Stage 2 - Latent Space (lightweight autoencoder, pure NumPy)
# ===========================================================================

class _AE:
    """
    Minimal symmetric autoencoder: input -> hidden -> latent -> hidden -> output.
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
    if N == 0:
        raise ValueError("no events available for latent analysis")
    mu_n = features.mean(0)
    sg_raw = features.std(0)
    # Near-constant dimensions must not be inflated by division through an
    # epsilon-sized standard deviation. Leave them near zero after centering.
    sg_n = np.where(sg_raw > 1e-6, sg_raw, 1.0)
    X = (features - mu_n) / sg_n

    if N == 1:
        return np.zeros((1, 1), dtype=np.float64), [0.0], {
            "method": "identity", "norm_mu": mu_n.tolist(), "norm_sg": sg_n.tolist()}

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


# ===========================================================================
# Stage 3 - Temporal Field Construction
# ===========================================================================

def _find_cluster_centers(Z, n_clusters, seed):
    """Seeded k-means++ with a safe degenerate-corpus fallback."""
    import numpy as np
    rng = np.random.RandomState(seed)
    N, D = Z.shape
    n_clusters = max(1, min(int(n_clusters), N))
    idx = [int(rng.randint(0, N))]
    for _ in range(n_clusters - 1):
        d2 = np.min(np.sum((Z[:, None, :] - Z[idx, :][None, :, :]) ** 2, axis=2), axis=1)
        total = float(d2.sum())
        if total < 1e-12:
            break
        idx.append(int(rng.choice(N, p=d2 / total)))
    centers = Z[idx].copy()
    for _ in range(50):
        d2 = np.sum((Z[:, None, :] - centers[None, :, :]) ** 2, axis=2)
        labels = np.argmin(d2, axis=1)
        new_c = centers.copy()
        for ci in range(len(centers)):
            mask = labels == ci
            if mask.any():
                new_c[ci] = Z[mask].mean(0)
        if np.allclose(centers, new_c, atol=1e-6):
            break
        centers = new_c
    return centers, labels


def build_temporal_field(Z, mode, seed,
                         amplitude=0.8, sigma=1.0, n_clusters=3,
                         gradient_axis=0, turbulence_strength=0.3):
    """Return one temporal scale per latent event.

    amplitude=0 is an exact identity baseline in every mode.
    """
    import numpy as np
    Z = np.asarray(Z, dtype=np.float64)
    N, D = Z.shape
    if N <= 1 or amplitude <= 0.0:
        return np.ones(N, dtype=np.float64)
    rng = np.random.RandomState(seed)

    if mode == "gravitational":
        centers, _ = _find_cluster_centers(Z, n_clusters, seed)
        scales = np.ones(N)
        for center in centers:
            d2 = np.sum((Z - center) ** 2, axis=1)
            scales += amplitude * np.exp(-d2 / (2 * sigma ** 2 + 1e-12))

    elif mode == "inversion":
        # Local spacing is the mean distance to k nearest neighbours. Small
        # spacing = dense region. Therefore spacing/median gives the documented
        # dense->compress, sparse->stretch behaviour.
        k = min(3, N - 1)
        dists = np.sqrt(np.sum((Z[:, None, :] - Z[None, :, :]) ** 2, axis=2))
        part = np.partition(dists, kth=k, axis=1)
        spacing = part[:, 1:k + 1].mean(axis=1) + 1e-8
        med = float(np.median(spacing)) + 1e-12
        scales = (spacing / med) ** amplitude

    elif mode == "turbulence":
        # Anchor the random field IN the observed latent cloud. The old N(0,1)
        # centres could miss an arbitrarily scaled/rotated AE space entirely.
        n_noise = max(4, N // 2)
        centers = Z[rng.randint(0, N, size=n_noise)]
        strength = amplitude * (float(turbulence_strength) / 0.3)
        amps = rng.uniform(-strength, strength, size=n_noise)
        sig_t = max(1e-6, sigma * 0.5)
        scales = np.ones(N)
        for center, a in zip(centers, amps):
            d2 = np.sum((Z - center) ** 2, axis=1)
            scales += a * np.exp(-d2 / (2 * sig_t ** 2 + 1e-12))

    elif mode == "gradient":
        Zc = Z - Z.mean(axis=0)
        if np.linalg.norm(Zc) < 1e-12:
            scales = np.ones(N)
        else:
            _, _, Vt = np.linalg.svd(Zc, full_matrices=False)
            proj = Zc.dot(Vt[0])
            mn, mx = float(proj.min()), float(proj.max())
            if mx - mn < 1e-12:
                scales = np.ones(N)
            else:
                t = (proj - mn) / (mx - mn)
                lo, hi = 1.0 / (1.0 + amplitude), 1.0 + amplitude
                scales = lo + t * (hi - lo)

    elif mode == "relativistic":
        deltas = np.diff(Z, axis=0)
        vels = np.sqrt(np.sum(deltas ** 2, axis=1))
        velocities = np.concatenate([[vels[0]], vels]) if len(vels) else np.zeros(N)
        vmax = float(np.max(velocities))
        if vmax < 1e-12:
            scales = np.ones(N)
        else:
            # Keep every event sub-luminal instead of setting c below the top
            # 5% of velocities and then clipping them to an arbitrary beta.
            c = max(float(np.percentile(velocities, 95)), vmax / 0.98) + 1e-12
            beta = np.clip(velocities / c, 0.0, 0.98)
            lorentz = 1.0 / np.sqrt(1.0 - beta ** 2)
            median_l = float(np.median(lorentz))
            scales = 1.0 + amplitude * (lorentz / (median_l + 1e-12) - 1.0)
    else:
        scales = np.ones(N)

    return np.clip(scales, SCALE_MIN, SCALE_MAX).astype(np.float64)


# ===========================================================================
# Stage 4 - Duration Mapping
# ===========================================================================

def apply_duration_rules(events, scales, extra_rules="none",
                         short_threshold=0.1, long_threshold=0.5):
    """
    Compute new_duration = original_duration * time_scale.

    extra_rules:
        none       - pure temporal field
        short_stretch  - short events get extra stretch bonus
        long_compress  - long events get extra compression
        harmonic_compress  - (uses spectral_flatness: low = more harmonic -> compress)
        noisy_dilate      - (uses spectral_flatness: high = noisy -> dilate)

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
            flat = float(np.clip(float(ev.get("spectral_flatness", 0.5)), 0.0, 1.0))
            # low flatness = tonal -> compress
            s *= 1.0 - 0.4 * (1.0 - flat)

        elif extra_rules == "noisy_dilate":
            flat = float(np.clip(float(ev.get("spectral_flatness", 0.5)), 0.0, 1.0))
            # high flatness = noisy -> dilate
            s *= 1.0 + 0.6 * flat

        # Proportional clamp only. This guarantees scale=1 is identity even
        # for long events; the old absolute 2 s cap shortened untouched events.
        new_dur = float(np.clip(orig * s, orig * SCALE_MIN, orig * SCALE_MAX))
        new_durations.append(new_dur)

    return new_durations


# ===========================================================================
# Metrics
# ===========================================================================

def compute_metrics(events, scales, Z, new_durations, field_scales=None):
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
        mask = ~np.eye(len(Z), dtype=bool)
        latent_dispersion = float(np.mean(dists[mask])) if np.any(mask) else 0.0
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
        "field_scale_mean": round(float(np.mean(field_scales if field_scales is not None else scales)), 4),
        "effective_scale_mean": round(float(np.mean(scales)), 4),
    }


# ===========================================================================
# Output writers
# ===========================================================================

def write_durations_csv(path, events, field_scales, effective_scales, new_durations, Z):
    """Write both raw field scale and the FINAL effective duration scale."""
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["event_index", "start_time", "original_duration",
                         "field_scale", "time_scale", "new_duration",
                         "latent_z0", "latent_z1"])
        for i, (ev, fs, es, nd) in enumerate(zip(events, field_scales, effective_scales, new_durations)):
            z0 = float(Z[i, 0]) if Z.shape[1] > 0 else 0.0
            z1 = float(Z[i, 1]) if Z.shape[1] > 1 else 0.0
            writer.writerow([i, round(float(ev.get("start_time", 0.0)), 6),
                              round(float(ev.get("duration", 0.0)), 6),
                              round(float(fs), 6), round(float(es), 6), round(float(nd), 6),
                              round(z0, 6), round(z1, 6)])


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
        f.write("latent_loss_initial=%.6f\n" % (losses[0] if losses else 0))
        f.write("latent_loss_final=%.6f\n" % (losses[-1] if losses else 0))
        # Legacy aliases for older Praat wrappers.
        f.write("vae_loss_initial=%.6f\n" % (losses[0] if losses else 0))
        f.write("vae_loss_final=%.6f\n" % (losses[-1] if losses else 0))
        for k, v in sorted(metrics.items()):
            f.write("%s=%s\n" % (k, v))
        f.write("scale_min=%.4f\n"       % float(min(scales)))
        f.write("scale_max=%.4f\n"       % float(max(scales)))
        for w in warnings:
            f.write("warning=%s\n"       % w)


# ===========================================================================
# Main
# ===========================================================================

def main():
    import argparse
    import numpy as np

    parser = argparse.ArgumentParser(
        description="Temporal Elasticity - Latent Time Warping Engine")

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
        help="Latent dimensionality (2-16, default 4)")
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
        help="Field amplitude (0 = identity; default 0.8)")
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
    args.z_dim      = max(2, min(16,  args.z_dim))
    args.n_iter     = max(20, min(400, args.n_iter))
    args.amplitude  = max(0.0, min(3.0, args.amplitude))
    args.sigma      = max(0.1, min(5.0, args.sigma))
    args.n_clusters = max(1,  min(8,   args.n_clusters))

    # -- Stage 1: Load ------------------------------------------------------
    print("  [TE 1/5] Loading events...")
    events = load_events_csv(args.events_csv)
    print("    Events: %d" % len(events))

    if len(events) == 0:
        print("FATAL: no events in events.csv", file=sys.stderr)
        sys.exit(1)
    if len(events) < 2:
        warnings_list.append("too_few_events_%d" % len(events))

    patch_dir = args.patch_dir if args.patch_dir else os.path.dirname(args.events_csv)

    print("  [TE 1/5] Extracting features from patches...")
    features = extract_features_from_events(events, patch_dir)
    print("    Feature matrix: %s" % str(features.shape))
    n_patch = sum(1 for e in events if e.get("_feature_source") == "patch")
    print("    Feature sources: patches=%d  csv_fallback=%d" % (n_patch, len(events)-n_patch))

    # -- Stage 2: Learn latent space ----------------------------------------
    print("  [TE 2/5] Learning latent space (%s, z=%d, %d iters)..." %
          (args.latent_method, args.z_dim, args.n_iter))
    Z, losses, meta = learn_latent(features, args.z_dim, args.n_iter,
                                   args.seed, method=args.latent_method)
    if losses:
        print("    Loss: %.6f -> %.6f" % (losses[0], losses[-1]))
    print("    Z: %s  range [%.3f, %.3f]" % (str(Z.shape), Z.min(), Z.max()))

    if meta.get("method") == "ae" and losses and len(losses) > 1 and losses[-1] / (losses[0] + 1e-12) > 0.92:
        warnings_list.append("latent_model_did_not_converge_well")

    # -- Stage 3: Build temporal field --------------------------------------
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

    # -- Stage 4: Apply duration rules -------------------------------------
    print("  [TE 4/5] Applying duration mapping (rules=%s)..." % args.extra_rules)
    new_durations = apply_duration_rules(
        events, scales, extra_rules=args.extra_rules,
        short_threshold=args.short_threshold,
        long_threshold=args.long_threshold,
    )
    orig_total = sum(float(e.get("duration", 0)) for e in events)
    new_total  = sum(new_durations)
    print("    Total duration: %.3fs -> %.3fs (ratio %.3f)" % (
        orig_total, new_total, new_total / (orig_total + 1e-9)))

    # Metrics
    effective_scales = np.array([nd / max(float(ev.get("duration", 0.1)), 1e-12)
                                 for ev, nd in zip(events, new_durations)], dtype=np.float64)
    metrics = compute_metrics(events, effective_scales, Z, new_durations, field_scales=scales)
    metrics["patch_features_used"] = n_patch
    metrics["csv_fallback_features"] = len(events) - n_patch

    # -- Stage 5: Write outputs ---------------------------------------------
    print("  [TE 5/5] Writing outputs...")
    write_durations_csv(args.durations_csv, events, scales, effective_scales, new_durations, Z)
    write_stats(args.stats_txt, events, effective_scales, new_durations, Z,
                losses, meta, metrics,
                args.mode, args.extra_rules, Z.shape[1], args.n_iter,
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
