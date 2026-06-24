"""
granular_navigation_engine.py — Granular Navigation Engine  v1.4

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Email: shai.cohen@biu.ac.il

Called by GranularNavigationEngine.praat — not run directly.

Changelog v1.4:
    - FIXED: training could crash on grain counts where the final batch
      held a single sample (n % batch_size == 1), because BatchNorm1d
      raises "Expected more than 1 value per channel" in training mode.
      The DataLoader now drops the final batch ONLY in that exact case,
      so all other grain counts produce bit-for-bit identical embeddings.

Usage:
    python granular_navigation_engine.py \\
        --folder      /path/to/sounds/ \\
        --path_out    path.csv \\
        --stats       stats.txt \\
        --mode        similarity \\
        --grain_ms    150 \\
        --path_length 60 \\
        --epochs      80 \\
        --seed        42

Architecture:
    A — Scan folder for audio files (wav / aif / aiff / flac)
    B — Batch-FFT feature extraction — all grains of a file
        processed at once with vectorised numpy (no per-grain loops).
        Features: 8 log-spaced spectral band energies, centroid,
        spread, flatness, rolloff, ZCR, RMS  (14 total).
    C — Normalise features (robust z-score)
    D — Train compact autoencoder → grain embeddings
    E — PCA 2-D projection for Praat scatter plot
    F — Build pairwise transition score matrix
    G — Generate navigation path
    H — Write path CSV + stats

No Praat objects. No scipy. Audio I/O via soundfile only.
Dependencies: torch, numpy, soundfile.
"""

import argparse
import csv
import math
import os
import random
import sys
import time


def check_dependencies():
    """Verify required packages are installed with clear error messages."""
    missing = []
    for pkg in ["numpy", "soundfile", "torch"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing required Python packages:", ", ".join(missing),
              file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing),
              file=sys.stderr)
        sys.exit(1)


check_dependencies()

import numpy as np
import soundfile as sf
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset


LATENT_DIM  = 16
EXTS        = {".wav", ".aif", ".aiff", ".flac"}
N_MEL_BANDS = 8       # log-spaced spectral bands
N_FEATURES  = 14      # mel×8 + centroid + spread + flatness + rolloff + zcr + rms


# ─────────────────────────────────────────────────────────────────────────────
# A — Folder scan
# ─────────────────────────────────────────────────────────────────────────────

def scan_folder(folder):
    paths = []
    for fname in sorted(os.listdir(folder)):
        if os.path.splitext(fname)[1].lower() in EXTS:
            paths.append(os.path.join(folder, fname))
    return paths


# ─────────────────────────────────────────────────────────────────────────────
# B — Batch-FFT feature extraction
# ─────────────────────────────────────────────────────────────────────────────

def _mel_band_edges(sr, fft_size, n_bands):
    """Return (n_bands+1,) array of FFT-bin edges for log-spaced bands."""
    f_min  = 80.0
    f_max  = min(8000.0, sr / 2.0 - 1.0)
    log_lo = np.log10(f_min)
    log_hi = np.log10(f_max)
    freqs  = np.log10(
        np.linspace(10 ** log_lo, 10 ** log_hi, n_bands + 1)
    )
    # Convert Hz → FFT bins
    freq_axis = np.fft.rfftfreq(fft_size, 1.0 / sr)
    edges = np.searchsorted(freq_axis, 10 ** freqs)
    edges = np.clip(edges, 1, len(freq_axis) - 1)
    return edges


def extract_features_batch(audio, sr, fname, grain_sec, hop_sec):
    """
    Slice audio into grains and extract features for ALL grains at once
    using a single batch FFT — no per-grain Python loops.

    Returns list of dicts (one per grain).
    """
    n_audio  = len(audio)
    g_samp   = int(round(grain_sec * sr))
    h_samp   = max(1, int(round(hop_sec * sr)))
    min_samp = max(int(0.020 * sr), 8)

    # ── Build frame matrix (n_grains × g_samp) with stride tricks ──────────
    starts = np.arange(0, n_audio - min_samp + 1, h_samp)
    grains = []
    for s in starts:
        e = min(s + g_samp, n_audio)
        chunk = audio[s:e]
        if len(chunk) < min_samp:
            break
        if len(chunk) < g_samp:
            chunk = np.pad(chunk, (0, g_samp - len(chunk)))
        grains.append((s, min(s + g_samp, n_audio), chunk))

    if not grains:
        return []

    n_grains  = len(grains)
    start_arr = np.array([g[0] for g in grains])
    end_arr   = np.array([g[1] for g in grains])
    frames    = np.stack([g[2] for g in grains]).astype(np.float32)
    # frames: (n_grains, g_samp)

    # ── Hanning window + FFT for all grains at once ──────────────────────────
    window    = np.hanning(g_samp).astype(np.float32)
    windowed  = frames * window[np.newaxis, :]           # (n_grains, g_samp)
    spectra   = np.fft.rfft(windowed, axis=1)            # (n_grains, fft_bins)
    power     = (np.abs(spectra) ** 2).astype(np.float64)
    n_bins    = power.shape[1]
    freq_axis = np.fft.rfftfreq(g_samp, 1.0 / sr)       # (fft_bins,)

    # ── Log-spaced band energies ─────────────────────────────────────────────
    band_edges = _mel_band_edges(sr, g_samp, N_MEL_BANDS)
    band_feats = np.zeros((n_grains, N_MEL_BANDS), dtype=np.float64)
    for b in range(N_MEL_BANDS):
        lo, hi = int(band_edges[b]), int(band_edges[b + 1])
        if hi > lo:
            band_feats[:, b] = np.log1p(power[:, lo:hi].sum(axis=1))

    # ── Total power per grain ─────────────────────────────────────────────────
    total_power = power.sum(axis=1) + 1e-12              # (n_grains,)

    # ── Spectral centroid ────────────────────────────────────────────────────
    centroid = (freq_axis[np.newaxis, :] * power).sum(axis=1) / total_power

    # ── Spectral spread ──────────────────────────────────────────────────────
    spread = np.sqrt(
        (((freq_axis[np.newaxis, :] - centroid[:, np.newaxis]) ** 2)
         * power).sum(axis=1) / total_power
    )

    # ── Spectral flatness ────────────────────────────────────────────────────
    log_mean = np.mean(np.log(power + 1e-12), axis=1)
    arith    = total_power / n_bins
    flatness = np.exp(log_mean) / (arith + 1e-12)

    # ── Spectral rolloff (85 %) ──────────────────────────────────────────────
    cumsum    = np.cumsum(power, axis=1)
    threshold = 0.85 * total_power[:, np.newaxis]
    rolloff   = freq_axis[np.argmax(cumsum >= threshold, axis=1)]

    # ── ZCR — vectorised ─────────────────────────────────────────────────────
    signs = np.sign(frames)                              # (n_grains, g_samp)
    zcr   = (np.abs(np.diff(signs, axis=1)) > 0).mean(axis=1)

    # ── RMS ──────────────────────────────────────────────────────────────────
    rms = np.sqrt((frames ** 2).mean(axis=1))

    # ── Assemble rows ─────────────────────────────────────────────────────────
    rows = []
    for i in range(n_grains):
        row = {"filename": fname,
               "grain_id": i + 1,
               "start_s":  "%.6f" % (start_arr[i] / sr),
               "end_s":    "%.6f" % (end_arr[i]   / sr)}
        for b in range(N_MEL_BANDS):
            row["band%d" % b] = "%.5f" % band_feats[i, b]
        row["centroid_hz"] = "%.2f" % centroid[i]
        row["spread_hz"]   = "%.2f" % spread[i]
        row["flatness"]    = "%.5f" % flatness[i]
        row["rolloff_hz"]  = "%.2f" % rolloff[i]
        row["zcr"]         = "%.6f" % zcr[i]
        row["rms"]         = "%.6f" % rms[i]
        rows.append(row)

    return rows


def scan_and_extract(folder, grain_sec, hop_sec):
    paths = scan_folder(folder)
    if not paths:
        print("ERROR: No audio files found in: %s" % folder, file=sys.stderr)
        sys.exit(1)

    print("    Found %d file(s)" % len(paths))
    all_rows = []

    for path in paths:
        fname = os.path.basename(path)
        try:
            audio, sr = sf.read(path, always_2d=False)
            audio = audio.astype(np.float32)
        except Exception as e:
            print("    SKIP %s — %s" % (fname, e))
            continue
        if audio.ndim == 2:
            audio = audio.mean(axis=1)

        rows = extract_features_batch(audio, sr, fname, grain_sec, hop_sec)
        all_rows.extend(rows)
        print("    %s  (%d grains)" % (fname, len(rows)))

    if not all_rows:
        print("ERROR: No grains extracted.", file=sys.stderr)
        sys.exit(1)

    print("    Total grains: %d" % len(all_rows))
    return all_rows


# ─────────────────────────────────────────────────────────────────────────────
# Data model
# ─────────────────────────────────────────────────────────────────────────────

class Grain:
    __slots__ = (
        "filename", "grain_id", "start_s", "end_s",
        "cluster", "emb_x", "emb_y",
    )

    def __init__(self, row):
        def sf_(k, d=0.0):
            try:
                v = float(row.get(k, d))
                return v if math.isfinite(v) else d
            except (ValueError, TypeError):
                return d

        self.filename  = row.get("filename", "")
        self.grain_id  = int(sf_("grain_id"))
        self.start_s   = max(0.0, sf_("start_s"))
        self.end_s     = max(0.0, sf_("end_s"))
        self.cluster   = 0
        self.emb_x     = 0.0
        self.emb_y     = 0.0


def build_feature_matrix(rows):
    """
    Build [N, N_FEATURES] matrix directly from row dicts
    (band0..band7, centroid_hz, spread_hz, flatness, rolloff_hz, zcr, rms).
    """
    keys = (
        ["band%d" % b for b in range(N_MEL_BANDS)]
        + ["centroid_hz", "spread_hz", "flatness", "rolloff_hz", "zcr", "rms"]
    )

    def sf_(v, d=0.0):
        try:
            x = float(v)
            return x if math.isfinite(x) else d
        except (ValueError, TypeError):
            return d

    matrix = np.array(
        [[sf_(row.get(k, 0.0)) for k in keys] for row in rows],
        dtype=np.float32
    )
    return matrix


# ─────────────────────────────────────────────────────────────────────────────
# C — Normalisation
# ─────────────────────────────────────────────────────────────────────────────

def robust_z(X):
    """Median / IQR normalisation — robust to outlier grains."""
    med = np.median(X, axis=0)
    q25 = np.percentile(X, 25, axis=0)
    q75 = np.percentile(X, 75, axis=0)
    iqr = np.maximum(q75 - q25, 1e-6)
    return ((X - med) / iqr).astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# D — Autoencoder
# ─────────────────────────────────────────────────────────────────────────────

class GrainAutoencoder(nn.Module):
    def __init__(self, input_dim, latent_dim):
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Linear(input_dim, 64),
            nn.BatchNorm1d(64),
            nn.LeakyReLU(0.1),
            nn.Linear(64, 32),
            nn.LeakyReLU(0.1),
            nn.Linear(32, latent_dim),
        )
        self.decoder = nn.Sequential(
            nn.Linear(latent_dim, 32),
            nn.LeakyReLU(0.1),
            nn.Linear(32, 64),
            nn.LeakyReLU(0.1),
            nn.Linear(64, input_dim),
        )

    def forward(self, x):
        z = self.encoder(x)
        return self.decoder(z), z

    def encode(self, x):
        return self.encoder(x)


def train_autoencoder(X_norm, latent_dim, n_epochs, batch_size, seed):
    if seed > 0:
        torch.manual_seed(seed)
        np.random.seed(seed)
        random.seed(seed)

    n, n_feat  = X_norm.shape
    batch_size = max(2, min(batch_size, n))

    Xt     = torch.tensor(X_norm)
    # drop_last ONLY when the final batch would be a single sample: a
    # size-1 batch crashes BatchNorm1d in training mode ("Expected more
    # than 1 value per channel"). For every other grain count the loader
    # is unchanged, so existing embeddings/paths stay bit-for-bit identical.
    drop_last = (n % batch_size == 1)
    loader = DataLoader(TensorDataset(Xt),
                        batch_size=batch_size, shuffle=True,
                        drop_last=drop_last)

    model     = GrainAutoencoder(n_feat, latent_dim)
    opt       = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-5)
    sched     = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=n_epochs)
    criterion = nn.MSELoss()

    t0 = time.time()
    for epoch in range(1, n_epochs + 1):
        model.train()
        ep_loss = 0.0
        for (batch,) in loader:
            opt.zero_grad()
            recon, _ = model(batch)
            loss = criterion(recon, batch)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            ep_loss += loss.item() * len(batch)
        sched.step()
        if epoch % max(1, n_epochs // 4) == 0:
            print("    epoch %d/%d  loss=%.5f  t=%.1fs" %
                  (epoch, n_epochs, ep_loss / n, time.time() - t0))

    model.eval()
    with torch.no_grad():
        emb = model.encode(Xt).numpy()
    print("    Training done in %.1fs" % (time.time() - t0))
    return emb


# ─────────────────────────────────────────────────────────────────────────────
# E — PCA 2-D projection (no sklearn)
# ─────────────────────────────────────────────────────────────────────────────

def pca_2d(emb):
    X   = emb - emb.mean(axis=0)
    cov = (X.T @ X) / max(len(X) - 1, 1)
    vecs = []
    for _ in range(2):
        v = np.random.randn(cov.shape[0]).astype(np.float64)
        for __ in range(300):
            v = cov @ v
            nrm = np.linalg.norm(v)
            if nrm < 1e-12:
                break
            v /= nrm
        vecs.append(v.copy())
        cov -= np.outer(v, v) * float(v @ cov @ v)
    return np.column_stack([X @ vecs[0], X @ vecs[1]]).astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# F — Transition scores
# ─────────────────────────────────────────────────────────────────────────────

def build_transition_scores(emb):
    sq = (emb ** 2).sum(axis=1, keepdims=True)
    D  = np.sqrt(np.maximum(sq + sq.T - 2.0 * (emb @ emb.T), 0.0))
    S  = 1.0 / (1.0 + D)
    np.fill_diagonal(S, 0.0)
    return S.astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# G — Navigation
# ─────────────────────────────────────────────────────────────────────────────

# Feature column indices matching build_feature_matrix order:
#   0-7  = band0..band7
#   8    = centroid_hz
#   9    = spread_hz
#   10   = flatness
#   11   = rolloff_hz
#   12   = zcr
#   13   = rms
DIRECTION_AXES = {
    "brighter": (8,  +1),   # centroid ↑
    "darker":   (8,  -1),   # centroid ↓
    "noisier":  (12, +1),   # zcr ↑
    "harmonic": (10, -1),   # flatness ↓ = more harmonic
    "denser":   (13, +1),   # rms ↑
    "sparser":  (13, -1),   # rms ↓
}


def direction_vector(emb, X_norm, mode):
    col_idx, sign = DIRECTION_AXES[mode]
    target = X_norm[:, col_idx] * sign
    E   = emb.astype(np.float64)
    t   = target.astype(np.float64)
    EtE = E.T @ E + 1e-6 * np.eye(E.shape[1])
    w   = np.linalg.solve(EtE, E.T @ t)
    nrm = np.linalg.norm(w)
    return (w / nrm).astype(np.float32) if nrm > 1e-12 else None


def generate_path(emb, X_norm, scores, mode, n_path, seed):
    n      = len(emb)
    n_path = min(n_path, n)
    if seed > 0:
        np.random.seed(seed)
        random.seed(seed)

    dir_vec = None
    if mode in DIRECTION_AXES:
        dir_vec = direction_vector(emb, X_norm, mode)

    if mode == "contrast":
        start = random.randint(0, n - 1)
    else:
        center = emb.mean(axis=0)
        start  = int(np.argmin(np.linalg.norm(emb - center, axis=1)))

    path    = [start]
    visited = {start}
    history = min(10, max(1, n // 4))

    for _ in range(n_path - 1):
        current    = path[-1]
        candidates = np.array([i for i in range(n) if i not in visited])
        if len(candidates) == 0:
            break

        if mode == "similarity":
            d    = np.linalg.norm(emb[candidates] - emb[current], axis=1)
            best = candidates[np.argmin(d)]

        elif mode == "smooth":
            d    = np.linalg.norm(X_norm[candidates] - X_norm[current], axis=1)
            best = candidates[np.argmin(d)]

        elif mode == "contrast":
            ref  = emb[path[-history:]].mean(axis=0)
            d    = np.linalg.norm(emb[candidates] - ref, axis=1)
            best = candidates[np.argmax(d)]

        elif dir_vec is not None:
            proj     = emb[candidates] @ dir_vec
            tscore   = scores[current, candidates]
            p_min, p_max = proj.min(), proj.max()
            proj_n   = (proj - p_min) / (p_max - p_min + 1e-10)
            combined = 0.60 * proj_n + 0.40 * tscore
            best = candidates[np.argmax(combined)]

        else:
            d    = np.linalg.norm(emb[candidates] - emb[current], axis=1)
            best = candidates[np.argmin(d)]

        path.append(int(best))
        visited.add(int(best))

    return path


# ─────────────────────────────────────────────────────────────────────────────
# H — Writers
# ─────────────────────────────────────────────────────────────────────────────

def write_path_csv(path_out, rows, grains, path_indices, scores, emb_2d):
    with open(path_out, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["step", "filename", "start_s", "end_s",
                         "next_grain", "transition_score",
                         "emb_x", "emb_y"])
        n = len(path_indices)
        for step, gi in enumerate(path_indices):
            g       = grains[gi]
            r       = rows[gi]
            next_gi = path_indices[step + 1] if step + 1 < n else gi
            writer.writerow([
                step + 1,
                g.filename,
                r["start_s"],
                r["end_s"],
                next_gi + 1,
                "%.6f" % float(scores[gi, next_gi]),
                "%.6f" % float(emb_2d[gi, 0]),
                "%.6f" % float(emb_2d[gi, 1]),
            ])


def write_stats(stats_path, grains, path_indices, mode, epochs, latent_dim, seed):
    sources = len(set(g.filename for g in grains))
    with open(stats_path, "w", encoding="utf-8") as f:
        f.write("total_grains=%d\n"  % len(grains))
        f.write("n_sources=%d\n"     % sources)
        f.write("mode=%s\n"          % mode)
        f.write("path_length=%d\n"   % len(path_indices))
        f.write("epochs=%d\n"        % epochs)
        f.write("latent_dim=%d\n"    % latent_dim)
        f.write("seed=%d\n"          % seed)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Granular Navigation Engine — batch-FFT features + PyTorch path planner")
    parser.add_argument("--folder",      required=True)
    parser.add_argument("--path_out",    required=True)
    parser.add_argument("--stats",       required=True)
    parser.add_argument("--mode",        default="similarity",
        choices=["similarity", "smooth", "contrast",
                 "brighter", "darker", "noisier",
                 "harmonic", "denser", "sparser"])
    parser.add_argument("--grain_ms",    type=float, default=150.0)
    parser.add_argument("--path_length", type=int,   default=60)
    parser.add_argument("--epochs",      type=int,   default=80)
    parser.add_argument("--seed",        type=int,   default=42)
    args = parser.parse_args()

    args.grain_ms    = max(25.0, min(500.0, args.grain_ms))
    args.path_length = max(4,    min(1000,  args.path_length))
    args.epochs      = max(10,   min(500,   args.epochs))
    grain_sec  = args.grain_ms / 1000.0
    hop_sec    = grain_sec * 0.50
    batch_size = 32

    print("[Py 1/6] Scanning folder + batch-FFT feature extraction...")
    rows   = scan_and_extract(args.folder, grain_sec, hop_sec)
    grains = [Grain(r) for r in rows]
    X_raw  = build_feature_matrix(rows)
    print("    Grains: %d | Features: %d" % (len(grains), X_raw.shape[1]))

    print("[Py 2/6] Normalising features...")
    X_norm = robust_z(X_raw)

    print("[Py 3/6] Training autoencoder...")
    emb = train_autoencoder(X_norm, LATENT_DIM, args.epochs, batch_size, args.seed)

    print("[Py 4/6] PCA projection...")
    emb_2d = pca_2d(emb) if emb.shape[1] >= 2 \
             else np.zeros((len(grains), 2), dtype=np.float32)

    print("[Py 5/6] Scoring transitions...")
    scores = build_transition_scores(emb)

    for g, pos in zip(grains, emb_2d):
        g.emb_x = float(pos[0])
        g.emb_y = float(pos[1])

    print("[Py 6/6] Navigating (%s)..." % args.mode)
    path = generate_path(emb, X_norm, scores, args.mode,
                         args.path_length, args.seed)
    print("    Path: %d grains" % len(path))

    write_path_csv(args.path_out, rows, grains, path, scores, emb_2d)
    write_stats(args.stats, grains, path, args.mode,
                args.epochs, LATENT_DIM, args.seed)
    print("OK: %s" % args.path_out)


if __name__ == "__main__":
    main()
