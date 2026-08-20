"""
granular_navigation_engine.py — Granular Navigation Engine  v1.6.6

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Email: shai.cohen@biu.ac.il

Called by GranularNavigationEngine.praat — not run directly.

Changelog v1.6.6:
    - Production-stable companion release for the Praat v1.6.6 wrapper.
      Python feature extraction, training, embedding, cache, transition,
      navigation, and output behavior are unchanged from v1.6.5.
      Windows-safe redirected logging remains enabled.

Changelog v1.6.5:
    - Diagnostic wrapper companion release only. Python analysis/training/embedding/
      navigation/output behavior is unchanged from v1.6.4.

Changelog v1.6.4:
    - Wrapper-side bounded-memory reconstruction release. Python DSP/navigation
      math is unchanged. Redirected stdout/stderr are also made code-page-safe
      on Windows so diagnostic logging cannot fail on Unicode progress text.

Changelog v1.6.3:
    - Stable-I/O diagnostics release. The wrapper redirects both stdout and
      stderr to one log, and each run prints the exact Python runtime and engine
      file path. No feature, training, embedding, cache,
      transition, navigation, or output math changed.

Changelog v1.6.2:
    - Frontend compatibility release: cache path is now optional and the engine
      continues to use its automatic persistent cache when --cache_dir is omitted.
      No feature, training, embedding, or navigation math changed.

Changelog v1.6.0:
    - Added persistent two-level corpus cache without changing DSP/navigation:
      analysis cache reuses decoded/FFT features for unchanged corpus + grain size;
      embedding cache reuses the exact trained latent embedding + PCA for unchanged
      analysis + epochs + seed. Changing only navigation mode/path length now skips
      audio scanning, feature extraction, 80-epoch training, and PCA.
    - Cache invalidates automatically when any top-level corpus audio file changes
      filename, size, or modification timestamp, or when grain size/epochs/seed or
      relevant engine/dependency schema changes. Cache failure is non-fatal.
    - Stats report cache hits and per-stage timings.

Changelog v1.5.1:
    - Removed the full N x N transition matrix. Transition similarity is now
      evaluated only for the current candidate set and for the written path
      edges, preserving the same score formula/path decisions while avoiding
      quadratic memory.
    - Phase-safe stereo analysis: normal stereo still uses the channel mean,
      but if that mean collapses below 10% of the strongest channel RMS, the
      strongest channel is used for descriptors and recorded in the path CSV
      so Praat reconstructs from the same representative channel.
    - Documentation corrected: the eight legacy spectral bands are linearly
      spaced in Hz (80-8 kHz), not log-spaced. Their boundaries are intentionally
      left unchanged to preserve existing embeddings/navigation character.
    - Added stage timing + phase-safe fallback counts to stats.

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
    B — Batch-FFT feature extraction — grain spectra of a file are
        processed together with vectorised numpy.
        Features: 8 broad linear-Hz spectral band energies, centroid,
        spread, flatness, rolloff, ZCR, RMS  (14 total).
    C — Normalise features (robust z-score)
    D — Train compact autoencoder → grain embeddings
    E — PCA 2-D projection for Praat scatter plot
    F — Prepare exact transition metric with O(N) memory
    G — Generate navigation path
    H — Write path CSV + stats

No Praat objects. No scipy. Audio I/O via soundfile only.
Dependencies: torch, numpy, soundfile.
"""

import argparse
import csv
import hashlib
import importlib.metadata
import importlib.util
import json
import math
import os
import random
import sys
import time


# Redirected logging must not fail on Windows legacy code pages. The engine
# prints a few Unicode diagnostics (for example em dashes); replacement on
# encoding errors is preferable to aborting after expensive analysis/training.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except Exception:
        pass


def check_dependencies():
    """Verify packages without importing heavyweight PyTorch on cache hits."""
    missing = [pkg for pkg in ("numpy", "soundfile", "torch")
               if importlib.util.find_spec(pkg) is None]
    if missing:
        print("ERROR: Missing required Python packages:", ", ".join(missing),
              file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing),
              file=sys.stderr)
        sys.exit(1)


check_dependencies()

import numpy as np


LATENT_DIM  = 16
EXTS        = {".wav", ".aif", ".aiff", ".flac"}
N_MEL_BANDS = 8       # legacy 80-8k spectral bands (linear-Hz edges)
N_FEATURES  = 14      # bands×8 + centroid + spread + flatness + rolloff + zcr + rms

CACHE_SCHEMA_ANALYSIS = "gne_analysis_v1"
CACHE_SCHEMA_EMBEDDING = "gne_embedding_v1"




# ─────────────────────────────────────────────────────────────────────────────
# Persistent cache — analysis and embedding are independent of navigation mode
# ─────────────────────────────────────────────────────────────────────────────

def _file_stamp(path):
    st = os.stat(path)
    return [os.path.basename(path), int(st.st_size),
            int(getattr(st, "st_mtime_ns", int(st.st_mtime * 1e9)))]


def _stable_hash(payload):
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"),
                     ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _resolve_cache_dir(cache_dir):
    if not cache_dir:
        cache_dir = os.path.join(os.path.expanduser("~"),
                                 ".praat_audiotools", "gne_cache")
    try:
        cache_dir = os.path.abspath(cache_dir)
        os.makedirs(cache_dir, exist_ok=True)
        return cache_dir
    except OSError as e:
        print("    Cache disabled — cannot create cache directory: %s" % e)
        return ""


def _package_version(name):
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return ""


def _analysis_cache_key(folder, paths, grain_sec, hop_sec):
    payload = {
        "schema": CACHE_SCHEMA_ANALYSIS,
        "folder": os.path.normcase(os.path.abspath(folder)),
        "files": [_file_stamp(path) for path in paths],
        "grain_sec": round(float(grain_sec), 9),
        "hop_sec": round(float(hop_sec), 9),
        "n_features": N_FEATURES,
        "bands": N_MEL_BANDS,
        # Decoding/FFT implementation changes can alter feature values. Keep
        # dependency versions in the key rather than silently reusing stale data.
        "numpy": np.__version__,
        "soundfile": _package_version("soundfile"),
    }
    return _stable_hash(payload)


def _embedding_cache_key(analysis_key, epochs, seed):
    payload = {
        "schema": CACHE_SCHEMA_EMBEDDING,
        "analysis": analysis_key,
        "epochs": int(epochs),
        "seed": int(seed),
        "latent_dim": LATENT_DIM,
        "torch": _package_version("torch"),
        "numpy": np.__version__,
    }
    return _stable_hash(payload)


def _atomic_savez(path, **arrays):
    tmp = path + ".tmp-%d" % os.getpid()
    try:
        with open(tmp, "wb") as f:
            np.savez(f, **arrays)
        os.replace(tmp, path)
    finally:
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except OSError:
            pass


def _load_analysis_cache(path):
    try:
        with np.load(path, allow_pickle=False) as z:
            rows = json.loads(str(z["rows_json"].item()))
            X_norm = np.asarray(z["X_norm"], dtype=np.float32)
            fallback = int(z["phase_safe_fallback_files"].item())
        if not isinstance(rows, list) or X_norm.ndim != 2 or len(rows) != len(X_norm):
            raise ValueError("cache shape mismatch")
        return rows, X_norm, fallback
    except Exception as e:
        print("    Ignoring unreadable analysis cache: %s" % e)
        return None


def _save_analysis_cache(path, rows, X_norm, phase_safe_fallback_files):
    try:
        rows_json = json.dumps(rows, separators=(",", ":"), ensure_ascii=False)
        _atomic_savez(path,
                      rows_json=np.asarray(rows_json),
                      X_norm=np.asarray(X_norm, dtype=np.float32),
                      phase_safe_fallback_files=np.asarray(int(phase_safe_fallback_files), dtype=np.int32))
    except Exception as e:
        print("    WARNING: could not write analysis cache: %s" % e)


def _load_embedding_cache(path, n_rows):
    try:
        with np.load(path, allow_pickle=False) as z:
            emb = np.asarray(z["emb"], dtype=np.float32)
            emb_2d = np.asarray(z["emb_2d"], dtype=np.float32)
        if emb.ndim != 2 or emb.shape[0] != n_rows:
            raise ValueError("embedding row count mismatch")
        if emb_2d.shape != (n_rows, 2):
            raise ValueError("PCA shape mismatch")
        return emb, emb_2d
    except Exception as e:
        print("    Ignoring unreadable embedding cache: %s" % e)
        return None


def _save_embedding_cache(path, emb, emb_2d):
    try:
        _atomic_savez(path,
                      emb=np.asarray(emb, dtype=np.float32),
                      emb_2d=np.asarray(emb_2d, dtype=np.float32))
    except Exception as e:
        print("    WARNING: could not write embedding cache: %s" % e)


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
    """Return legacy (n_bands+1,) FFT-bin edges, linearly spaced in Hz.

    The original implementation was documented as log-spaced, but algebraically
    it produces linear-Hz edges. Keep those boundaries for backward-compatible
    musical behaviour; only the documentation is corrected.
    """
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


def extract_features_batch(audio, sr, fname, grain_sec, hop_sec, analysis_channel=0):
    """
    Slice audio into grains and extract spectral features with one batch FFT.
    Small Python loops remain only for metadata/row assembly.

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
               "analysis_channel": int(analysis_channel),
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


def scan_and_extract(folder, grain_sec, hop_sec, paths=None):
    import soundfile as sf
    paths = scan_folder(folder) if paths is None else list(paths)
    if not paths:
        print("ERROR: No audio files found in: %s" % folder, file=sys.stderr)
        sys.exit(1)

    print("    Found %d file(s)" % len(paths))
    all_rows = []
    phase_safe_fallback_files = 0

    for path in paths:
        fname = os.path.basename(path)
        try:
            audio2d, sr = sf.read(path, always_2d=True)
            audio2d = audio2d.astype(np.float32)
        except Exception as e:
            print("    SKIP %s — %s" % (fname, e))
            continue

        analysis_channel = 0  # 0 means the ordinary channel mean
        if audio2d.shape[1] == 1:
            audio = audio2d[:, 0]
        else:
            mean_audio = audio2d.mean(axis=1)
            mean_rms = float(np.sqrt(np.mean(mean_audio.astype(np.float64) ** 2)))
            ch_rms = np.sqrt(np.mean(audio2d.astype(np.float64) ** 2, axis=0))
            strongest = int(np.argmax(ch_rms))
            strongest_rms = float(ch_rms[strongest])
            if strongest_rms > 1e-9 and mean_rms < 0.10 * strongest_rms:
                audio = audio2d[:, strongest]
                analysis_channel = strongest + 1  # Praat channels are 1-based
                phase_safe_fallback_files += 1
                print("    %s  [phase-safe analysis: channel %d]" %
                      (fname, analysis_channel))
            else:
                audio = mean_audio

        rows = extract_features_batch(audio, sr, fname, grain_sec, hop_sec,
                                      analysis_channel=analysis_channel)
        all_rows.extend(rows)
        print("    %s  (%d grains)" % (fname, len(rows)))

    if not all_rows:
        print("ERROR: No grains extracted.", file=sys.stderr)
        sys.exit(1)

    print("    Total grains: %d" % len(all_rows))
    return all_rows, phase_safe_fallback_files


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

def train_autoencoder(X_norm, latent_dim, n_epochs, batch_size, seed):
    # PyTorch is intentionally imported only on an embedding-cache miss. This
    # removes its substantial process-start cost from the common navigation-only
    # rerun while leaving the training graph and RNG sequence unchanged.
    import torch
    import torch.nn as nn
    from torch.utils.data import DataLoader, TensorDataset

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

    if seed > 0:
        torch.manual_seed(seed)
        np.random.seed(seed)
        random.seed(seed)

    n, n_feat  = X_norm.shape
    batch_size = max(2, min(batch_size, n))

    Xt     = torch.tensor(X_norm)
    # drop_last ONLY when the final batch would be a single sample: a
    # size-1 batch crashes BatchNorm1d in training mode.
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

def _legacy_transition_row(emb, sq_norm, current):
    """Return the exact legacy transition-score row using O(N) memory.

    NumPy/BLAS can round a 1xN matrix-vector product slightly differently from
    the old full N x N GEMM. A tiny 2xN GEMM selects the same GEMM code path and
    reproduces the old row bit-for-bit in regression tests, without retaining
    the quadratic matrix.
    """
    n = len(emb)
    current = int(current)
    if n == 1:
        return np.zeros(1, dtype=np.float32)
    helper = 1 if current == 0 else 0
    dots = (emb[[current, helper]] @ emb.T)[0]
    d2 = np.maximum(sq_norm + sq_norm[current] - 2.0 * dots, 0.0)
    scores = (1.0 / (1.0 + np.sqrt(d2))).astype(np.float32)
    scores[current] = 0.0
    return scores


def _transition_scores_from_current(emb, sq_norm, current, candidates):
    return _legacy_transition_row(emb, sq_norm, current)[np.asarray(candidates, dtype=int)]


def _transition_score_pair(emb, sq_norm, a, b):
    a = int(a); b = int(b)
    if a == b:
        return 0.0
    return float(_legacy_transition_row(emb, sq_norm, a)[b])


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


def generate_path(emb, X_norm, mode, n_path, seed, sq_norm=None):
    n      = len(emb)
    n_path = min(n_path, n)
    if seed > 0:
        np.random.seed(seed)
        random.seed(seed)

    if sq_norm is None:
        sq_norm = (emb ** 2).sum(axis=1)

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
            tscore   = _transition_scores_from_current(emb, sq_norm, current, candidates)
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

def write_path_csv(path_out, rows, grains, path_indices, emb, sq_norm, emb_2d):
    with open(path_out, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["step", "filename", "analysis_channel", "start_s", "end_s",
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
                r.get("analysis_channel", 0),
                r["start_s"],
                r["end_s"],
                next_gi + 1,
                "%.6f" % _transition_score_pair(emb, sq_norm, gi, next_gi),
                "%.6f" % float(emb_2d[gi, 0]),
                "%.6f" % float(emb_2d[gi, 1]),
            ])


def write_stats(stats_path, grains, path_indices, mode, epochs, latent_dim, seed,
                phase_safe_fallback_files=0, timings=None, cache_info=None):
    sources = len(set(g.filename for g in grains))
    with open(stats_path, "w", encoding="utf-8") as f:
        f.write("total_grains=%d\n"  % len(grains))
        f.write("n_sources=%d\n"     % sources)
        f.write("mode=%s\n"          % mode)
        f.write("path_length=%d\n"   % len(path_indices))
        f.write("epochs=%d\n"        % epochs)
        f.write("latent_dim=%d\n"    % latent_dim)
        f.write("seed=%d\n"          % seed)
        f.write("phase_safe_fallback_files=%d\n" % int(phase_safe_fallback_files))
        if cache_info:
            f.write("analysis_cache_hit=%d\n" % int(bool(cache_info.get("analysis_hit"))))
            f.write("embedding_cache_hit=%d\n" % int(bool(cache_info.get("embedding_hit"))))
            f.write("cache_dir=%s\n" % cache_info.get("cache_dir", ""))
        if timings:
            for key in ("cache_key_s", "extract_s", "train_s", "pca_s", "navigate_s", "total_s"):
                if key in timings:
                    f.write("timing_%s=%.4f\n" % (key, float(timings[key])))


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    t_total = time.time()
    print("Python runtime: %s" % sys.version.replace("\n", " "), flush=True)
    print("Engine file: %s" % os.path.abspath(__file__), flush=True)
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
    parser.add_argument("--cache_dir",   default="",
        help="persistent analysis/embedding cache directory")
    args = parser.parse_args()

    args.grain_ms    = max(25.0, min(500.0, args.grain_ms))
    args.path_length = max(4,    min(1000,  args.path_length))
    args.epochs      = max(10,   min(500,   args.epochs))
    grain_sec  = args.grain_ms / 1000.0
    hop_sec    = grain_sec * 0.50
    batch_size = 32

    timings = {}
    cache_info = {"analysis_hit": False, "embedding_hit": False, "cache_dir": ""}

    print("[Py 1/6] Corpus signature + feature analysis...")
    t0 = time.time()
    paths = scan_folder(args.folder)
    if not paths:
        print("ERROR: No audio files found in: %s" % args.folder, file=sys.stderr)
        sys.exit(1)
    cache_dir = _resolve_cache_dir(args.cache_dir)
    cache_info["cache_dir"] = cache_dir
    analysis_key = _analysis_cache_key(args.folder, paths, grain_sec, hop_sec)
    analysis_cache = (os.path.join(cache_dir, "analysis_%s.npz" % analysis_key)
                      if cache_dir else "")
    timings["cache_key_s"] = time.time() - t0

    cached_analysis = (_load_analysis_cache(analysis_cache)
                       if analysis_cache and os.path.isfile(analysis_cache) else None)
    if cached_analysis is not None:
        rows, X_norm, phase_safe_fallback_files = cached_analysis
        cache_info["analysis_hit"] = True
        timings["extract_s"] = 0.0
        print("    Analysis cache HIT — skipped audio decode + FFT (%d grains)" % len(rows))
    else:
        t0 = time.time()
        rows, phase_safe_fallback_files = scan_and_extract(
            args.folder, grain_sec, hop_sec, paths=paths)
        X_raw = build_feature_matrix(rows)
        X_norm = robust_z(X_raw)
        timings["extract_s"] = time.time() - t0
        if analysis_cache:
            _save_analysis_cache(analysis_cache, rows, X_norm,
                                 phase_safe_fallback_files)

    grains = [Grain(r) for r in rows]
    print("    Grains: %d | Features: %d" % (len(grains), X_norm.shape[1]))

    print("[Py 2/6] Normalisation ready%s" %
          (" (cache)" if cache_info["analysis_hit"] else ""))

    embedding_key = _embedding_cache_key(analysis_key, args.epochs, args.seed)
    embedding_cache = (os.path.join(cache_dir, "embedding_%s.npz" % embedding_key)
                       if cache_dir else "")
    cached_embedding = (_load_embedding_cache(embedding_cache, len(grains))
                        if embedding_cache and os.path.isfile(embedding_cache) else None)

    if cached_embedding is not None:
        print("[Py 3/6] Embedding cache HIT — skipped autoencoder training")
        emb, emb_2d = cached_embedding
        cache_info["embedding_hit"] = True
        timings["train_s"] = 0.0
        timings["pca_s"] = 0.0
        print("[Py 4/6] PCA ready (cache)")
    else:
        print("[Py 3/6] Training autoencoder...")
        t0 = time.time()
        emb = train_autoencoder(X_norm, LATENT_DIM, args.epochs, batch_size, args.seed)
        timings["train_s"] = time.time() - t0

        print("[Py 4/6] PCA projection...")
        t0 = time.time()
        emb_2d = pca_2d(emb) if emb.shape[1] >= 2 \
                 else np.zeros((len(grains), 2), dtype=np.float32)
        timings["pca_s"] = time.time() - t0
        if embedding_cache:
            _save_embedding_cache(embedding_cache, emb, emb_2d)

    print("[Py 5/6] Preparing transition metric (O(N) memory)...")
    sq_norm = (emb ** 2).sum(axis=1)

    for g, pos in zip(grains, emb_2d):
        g.emb_x = float(pos[0])
        g.emb_y = float(pos[1])

    print("[Py 6/6] Navigating (%s)..." % args.mode)
    t0 = time.time()
    path = generate_path(emb, X_norm, args.mode,
                         args.path_length, args.seed, sq_norm=sq_norm)
    timings["navigate_s"] = time.time() - t0
    print("    Path: %d grains" % len(path))

    write_path_csv(args.path_out, rows, grains, path, emb, sq_norm, emb_2d)
    timings["total_s"] = time.time() - t_total
    write_stats(args.stats, grains, path, args.mode,
                args.epochs, LATENT_DIM, args.seed,
                phase_safe_fallback_files=phase_safe_fallback_files,
                timings=timings, cache_info=cache_info)
    print("OK: %s" % args.path_out)


if __name__ == "__main__":
    main()
