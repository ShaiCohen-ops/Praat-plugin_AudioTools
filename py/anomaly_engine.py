"""
anomaly_engine.py — Acoustic Anomaly Extraction & Resynthesis Engine

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 0.1 (2026)
License: MIT

Usage (called by Praat, not directly):
    python anomaly_engine.py --audio_in temp_input.wav
                             --csv_in   temp_features.csv
                             --audio_out temp_outliers_output.wav
                             --algorithm IsolationForest
                             --threshold 0.05
                             --mode chronological
                             [--stats_out temp_anomaly_stats.txt]
                             [--deltas] [--smooth_frames 3]
                             [--fade_ms 7] [--min_seg_ms 40]
                             [--merge_gap_ms 30] [--max_seg_ms 2000]
                             [--join xfade] [--xfade_law equal_power]
                             [--granular_overlap 0.5] [--granular_jitter 0.0]
                             [--peak_dbfs -1.0] [--seed 42] [--cleanup]

Architecture:
    Stage 1 — Load audio (soundfile) + Praat feature table (pandas)
    Stage 2 — Clean / normalize features, optionally append delta features
    Stage 3 — Score every frame:  A(t) in [0, 1]
                IsolationForest  — sklearn ensemble, path-length score
                Mahalanobis      — shrinkage covariance, chi2 CDF -> [0,1]
                Autoencoder      — PyTorch if present, else numpy MLP fallback
    Stage 4 — Threshold -> binary mask -> contiguous [t_start, t_end] segments
    Stage 5 — Slice audio, apply Tukey taper (anti-click) to every slice
    Stage 6 — Re-assemble per --mode (chronological | sorted | granular)
    Stage 7 — Peak-normalize to --peak_dbfs, write WAV
    Stage 8 — Write stats.txt for the Praat front-end, optional temp cleanup

THRESHOLD SEMANTICS
    --threshold is a FRACTION OF FRAMES, not a score value. 0.05 means
    "flag the top 5% most anomalous frames". The cut point is
    quantile(score, 1 - threshold). This is deliberate: raw anomaly
    scores are not comparable across algorithms or across files, so an
    absolute score cut would behave differently for every input.

JOIN GEOMETRY
    Slices are OVERLAPPED by the taper length, not butt-joined. A
    faded-out tail placed adjacent to (rather than on top of) a faded-in
    head dips to silence at every junction. With --join xfade the tapers
    overlap; with --xfade_law equal_power the overlapping tapers are
    sqrt-Hann so uncorrelated material holds constant power through the
    seam (plain Hann tapers sum to constant AMPLITUDE, which costs about
    1.4 dB of power on uncorrelated slices).

EXIT CODES
    0 = success (output written).  1 = failure (message on stderr).
"""

import sys
import os
import math

try:
    import numpy as np
except ImportError:                                     # pragma: no cover
    np = None


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
PEAK_TARGET_DBFS   = -1.0       # spec: normalize peak to -1 dBFS
DEFAULT_FADE_MS    = 7.0        # spec: 5-10 ms Tukey taper
MAX_STATS_POINTS   = 400        # cap on score points written for Praat drawing
MAX_STATS_SEGMENTS = 200        # cap on segment rows written for Praat drawing
EPS                = 1e-12

# Only files whose basename starts with this prefix may be deleted by
# --cleanup. Praat owns the temp files; Python never removes user files.
PRAAT_TEMP_PREFIX  = "temp_"

# Praat writes this token into CSV cells for undefined analysis results.
PRAAT_UNDEFINED    = ["--undefined--", "--undefined", "undefined", "?"]

# Columns that are never features.
NON_FEATURE_COLS = {
    "time", "t", "frame", "index", "label", "name",
    "start_time", "end_time", "duration",
}


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

def check_dependencies(algorithm):
    """Fail early and legibly if a required package is absent."""
    missing = []
    for pkg in ["numpy", "pandas", "soundfile", "scipy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)

    if algorithm == "IsolationForest":
        try:
            __import__("sklearn")
        except ImportError:
            missing.append("scikit-learn")

    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


def _is_praat_temp(path):
    """True only for files created by Praat for this run."""
    return os.path.basename(path).startswith(PRAAT_TEMP_PREFIX)


def db_to_lin(db):
    return 10.0 ** (db / 20.0)


def _rms(x):
    x = np.asarray(x, dtype=np.float64)
    if x.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(x ** 2)))


# ═══════════════════════════════════════════════════════════════════════════
# Stage 1 — Ingestion
# ═══════════════════════════════════════════════════════════════════════════

def load_audio(path):
    """Return (audio [n, ch] float64, sr). Always 2-D so the slicing and
    windowing code has exactly one shape to reason about."""
    import soundfile as sf

    audio, sr = sf.read(path, always_2d=True)
    audio = np.asarray(audio, dtype=np.float64)
    if audio.shape[0] == 0:
        raise ValueError("Input audio '%s' contains no samples." % path)

    try:
        subtype = sf.info(path).subtype
    except Exception:
        subtype = None

    return audio, int(sr), subtype


def load_feature_table(path):
    """Load the Praat feature CSV.

    Accepts two schemas:
      (a) frame table  — a 'time' column plus one column per feature
      (b) event table  — 'start_time' / 'end_time' plus feature columns
                         (midpoint is used as the frame time)

    Returns (times, frame_dur, X_raw, names, n_dropped_rows).
    """
    import pandas as pd

    df = pd.read_csv(path, na_values=PRAAT_UNDEFINED, keep_default_na=True)
    df.columns = [str(c).strip() for c in df.columns]

    n_rows_in = len(df)
    if n_rows_in == 0:
        raise ValueError("Feature table '%s' has no rows." % path)

    # ── Time axis ────────────────────────────────────────────────────────
    frame_dur = None
    if "time" in df.columns:
        times = pd.to_numeric(df["time"], errors="coerce").to_numpy(dtype=np.float64)
    elif "start_time" in df.columns and "end_time" in df.columns:
        t0 = pd.to_numeric(df["start_time"], errors="coerce").to_numpy(dtype=np.float64)
        t1 = pd.to_numeric(df["end_time"], errors="coerce").to_numpy(dtype=np.float64)
        times = 0.5 * (t0 + t1)
        frame_dur = np.maximum(t1 - t0, 0.0)
    else:
        raise ValueError(
            "Feature table needs a 'time' column (frame table) or "
            "'start_time'+'end_time' columns (event table). Found: %s"
            % ", ".join(df.columns))

    # ── Feature columns ──────────────────────────────────────────────────
    names = []
    cols = []
    for c in df.columns:
        if c.lower() in NON_FEATURE_COLS:
            continue
        series = pd.to_numeric(df[c], errors="coerce")
        if series.notna().sum() == 0:
            continue                      # entirely undefined -> not a feature
        names.append(c)
        cols.append(series.to_numpy(dtype=np.float64))

    if not names:
        raise ValueError("Feature table '%s' contains no usable numeric "
                         "feature columns." % path)

    X = np.column_stack(cols)

    # ── Drop rows with no valid time; keep NaN features for now ─────────
    keep = np.isfinite(times)
    times, X = times[keep], X[keep]
    if frame_dur is not None:
        frame_dur = frame_dur[keep]

    order = np.argsort(times, kind="stable")
    times, X = times[order], X[order]
    if frame_dur is not None:
        frame_dur = frame_dur[order]

    if len(times) < 2:
        raise ValueError("Feature table needs at least 2 valid frames "
                         "(found %d)." % len(times))

    return times, frame_dur, X, names, n_rows_in - len(times)


def infer_time_step(times):
    """Median inter-frame interval. Robust to a few missing frames."""
    if len(times) < 2:
        return 0.01
    d = np.diff(times)
    d = d[d > 0]
    if d.size == 0:
        return 0.01
    return float(np.median(d))


# ═══════════════════════════════════════════════════════════════════════════
# Stage 2 — Feature conditioning
# ═══════════════════════════════════════════════════════════════════════════

def condition_features(X, names, use_deltas=False):
    """Fill undefined values, drop dead columns, z-score, optionally append
    first differences.

    Praat leaves gaps: pitch is undefined in unvoiced frames, formants
    fail on noise. Interpolating across those gaps is the honest choice —
    dropping the frames would break the time axis, and filling with 0 Hz
    would make every unvoiced frame the single biggest outlier in the file.
    """
    X = np.array(X, dtype=np.float64, copy=True)
    n_frames, n_cols = X.shape
    n_filled = int(np.count_nonzero(~np.isfinite(X)))

    # ── Column-wise linear interpolation over undefined frames ──────────
    idx = np.arange(n_frames, dtype=np.float64)
    keep_mask = np.ones(n_cols, dtype=bool)
    for j in range(n_cols):
        col = X[:, j]
        good = np.isfinite(col)
        if good.sum() == 0:
            keep_mask[j] = False
            continue
        if good.sum() < n_frames:
            col[~good] = np.interp(idx[~good], idx[good], col[good])
            X[:, j] = col

    X = X[:, keep_mask]
    names = [n for n, k in zip(names, keep_mask) if k]

    # ── Drop constant columns (zero variance carries no information and
    #    would divide by ~0 in the z-score) ───────────────────────────────
    sd = X.std(axis=0)
    live = sd > 1e-9
    n_const = int(np.count_nonzero(~live))
    if not np.any(live):
        raise ValueError("All feature columns are constant — nothing to "
                         "score. Check the Praat analysis settings.")
    X = X[:, live]
    names = [n for n, k in zip(names, live) if k]

    # ── z-score ──────────────────────────────────────────────────────────
    Xz = (X - X.mean(axis=0)) / (X.std(axis=0) + EPS)

    # ── Optional delta features: catches TRANSITIONS, not just extremes.
    #    A steady loud note is not unusual; a sudden jump to it is. ───────
    if use_deltas and Xz.shape[0] > 2:
        d = np.vstack([np.zeros((1, Xz.shape[1])), np.diff(Xz, axis=0)])
        d = (d - d.mean(axis=0)) / (d.std(axis=0) + EPS)
        Xz = np.hstack([Xz, d])
        names = names + ["d_" + n for n in names]

    return Xz, names, n_filled, n_const


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Anomaly scoring
# ═══════════════════════════════════════════════════════════════════════════

def _unit_scale(raw):
    """Min-max map to [0, 1]; flat input becomes all-zeros."""
    lo, hi = float(np.min(raw)), float(np.max(raw))
    if hi - lo < EPS:
        return np.zeros_like(raw)
    return (raw - lo) / (hi - lo)


def score_isolation_forest(X, seed):
    """Higher = more anomalous. sklearn's score_samples is negated so that
    short average path length (isolated point) becomes a high score."""
    from sklearn.ensemble import IsolationForest

    n = X.shape[0]
    clf = IsolationForest(
        n_estimators=200,
        max_samples=min(256, n),
        contamination="auto",
        random_state=int(seed),
        bootstrap=False,
    )
    clf.fit(X)
    raw = -clf.score_samples(X)
    return _unit_scale(raw), raw, "isolation path length (negated)", {}


def score_mahalanobis(X):
    """Squared Mahalanobis distance under a shrinkage-regularized
    covariance, mapped to [0, 1] by the chi-squared CDF.

    The chi2 map is principled rather than cosmetic: under a Gaussian
    model d^2 ~ chi2(df = n_features), so A(t) reads as "probability that
    a normal frame would be at most this far out".
    """
    from scipy.stats import chi2

    n, d = X.shape
    mu = X.mean(axis=0)
    Xc = X - mu

    cov = np.cov(Xc, rowvar=False)
    cov = np.atleast_2d(cov)

    # Ledoit-Wolf style shrinkage toward a scaled identity. With few frames
    # or collinear features the empirical covariance is singular and the
    # inverse explodes; shrinkage keeps it conditioned.
    trace_mean = float(np.trace(cov) / max(d, 1))
    shrink = 0.10 if n > 5 * d else 0.35
    cov = (1.0 - shrink) * cov + shrink * trace_mean * np.eye(d)
    cov += 1e-9 * np.eye(d)

    try:
        inv = np.linalg.inv(cov)
    except np.linalg.LinAlgError:
        inv = np.linalg.pinv(cov)

    raw = np.einsum("ij,jk,ik->i", Xc, inv, Xc)
    raw = np.maximum(raw, 0.0)

    # chi2.cdf(d^2, df) is the principled map, but it saturates: past a few
    # degrees of freedom every real outlier reads 1.0000, which flattens the
    # drawn curve and makes --mode sorted a pile of ties. Log-compress the
    # raw distance for A(t) instead (monotone, so the quantile cut and the
    # ordering are unchanged) and report the chi2 tail probability of the
    # cut point separately.
    scores = _unit_scale(np.log1p(raw))
    tail = 1.0 - chi2.cdf(raw, df=d)
    return scores, raw, "squared Mahalanobis distance (log-compressed)", {"chi2_tail": tail}


class NumpyAutoencoder:
    """Small tanh MLP autoencoder trained with Adam. Pure numpy.

    Present so the Autoencoder option works on a stock scientific Python
    install. If PyTorch is importable the torch path is used instead —
    same architecture, same objective.
    """

    def __init__(self, d_in, d_hidden, d_latent, seed):
        rng = np.random.default_rng(seed)

        def init(a, b):
            return rng.normal(0.0, math.sqrt(2.0 / (a + b)), size=(a, b))

        self.W1, self.b1 = init(d_in, d_hidden),     np.zeros(d_hidden)
        self.W2, self.b2 = init(d_hidden, d_latent), np.zeros(d_latent)
        self.W3, self.b3 = init(d_latent, d_hidden), np.zeros(d_hidden)
        self.W4, self.b4 = init(d_hidden, d_in),     np.zeros(d_in)
        self._params = ["W1", "b1", "W2", "b2", "W3", "b3", "W4", "b4"]
        self._m = {k: np.zeros_like(getattr(self, k)) for k in self._params}
        self._v = {k: np.zeros_like(getattr(self, k)) for k in self._params}
        self._t = 0

    def forward(self, X):
        h1 = np.tanh(X @ self.W1 + self.b1)
        z = h1 @ self.W2 + self.b2
        h2 = np.tanh(z @ self.W3 + self.b3)
        out = h2 @ self.W4 + self.b4
        return h1, z, h2, out

    def train(self, X, epochs=400, lr=0.01):
        n = X.shape[0]
        losses = []
        for _ in range(epochs):
            h1, z, h2, out = self.forward(X)
            err = out - X
            loss = float(np.mean(err ** 2))
            losses.append(loss)

            g_out = (2.0 / n) * err
            gW4, gb4 = h2.T @ g_out, g_out.sum(axis=0)
            g_h2 = (g_out @ self.W4.T) * (1.0 - h2 ** 2)
            gW3, gb3 = z.T @ g_h2, g_h2.sum(axis=0)
            g_z = g_h2 @ self.W3.T
            gW2, gb2 = h1.T @ g_z, g_z.sum(axis=0)
            g_h1 = (g_z @ self.W2.T) * (1.0 - h1 ** 2)
            gW1, gb1 = X.T @ g_h1, g_h1.sum(axis=0)

            self._adam({"W1": gW1, "b1": gb1, "W2": gW2, "b2": gb2,
                        "W3": gW3, "b3": gb3, "W4": gW4, "b4": gb4}, lr)
        return losses

    def _adam(self, grads, lr, b1=0.9, b2=0.999, eps=1e-8):
        self._t += 1
        for k, g in grads.items():
            self._m[k] = b1 * self._m[k] + (1 - b1) * g
            self._v[k] = b2 * self._v[k] + (1 - b2) * (g ** 2)
            mh = self._m[k] / (1 - b1 ** self._t)
            vh = self._v[k] / (1 - b2 ** self._t)
            setattr(self, k, getattr(self, k) - lr * mh / (np.sqrt(vh) + eps))


def score_autoencoder(X, seed):
    """Per-frame reconstruction error. Frames the model cannot rebuild are
    the ones it never learned — the outliers."""
    n, d = X.shape
    d_hidden = max(4, min(32, d * 2))
    d_latent = max(2, min(8, max(2, d // 2)))

    backend = "numpy"
    try:
        import torch
        import torch.nn as nn

        torch.manual_seed(int(seed))
        model = nn.Sequential(
            nn.Linear(d, d_hidden), nn.Tanh(),
            nn.Linear(d_hidden, d_latent), nn.Tanh(),
            nn.Linear(d_latent, d_hidden), nn.Tanh(),
            nn.Linear(d_hidden, d),
        )
        opt = torch.optim.Adam(model.parameters(), lr=0.01)
        Xt = torch.tensor(X, dtype=torch.float32)
        for _ in range(400):
            opt.zero_grad()
            loss = ((model(Xt) - Xt) ** 2).mean()
            loss.backward()
            opt.step()
        with torch.no_grad():
            recon = model(Xt).numpy().astype(np.float64)
        backend = "torch"
    except ImportError:
        ae = NumpyAutoencoder(d, d_hidden, d_latent, seed)
        ae.train(X, epochs=400, lr=0.01)
        recon = ae.forward(X)[3]

    # Reconstruction MSE is heavy-tailed: one extreme frame otherwise
    # compresses every other frame toward 0. Log-compress before scaling
    # (monotone, so the quantile cut and the ordering are unchanged).
    raw = np.mean((recon - X) ** 2, axis=1)
    return _unit_scale(np.log1p(raw)), raw, "reconstruction MSE (%s)" % backend, {}


def compute_scores(X, algorithm, seed):
    if algorithm == "IsolationForest":
        return score_isolation_forest(X, seed)
    if algorithm == "Mahalanobis":
        return score_mahalanobis(X)
    if algorithm == "Autoencoder":
        return score_autoencoder(X, seed)
    raise ValueError("Unknown algorithm: %s" % algorithm)


def smooth_scores(scores, n_frames_window):
    """Median filter. Single-frame score spikes produce segments shorter
    than the fade, which then become pure window and no signal."""
    if n_frames_window is None or n_frames_window < 3:
        return scores
    from scipy.signal import medfilt
    k = int(n_frames_window)
    if k % 2 == 0:
        k += 1
    k = min(k, len(scores) - (1 - len(scores) % 2))
    if k < 3:
        return scores
    return medfilt(scores, kernel_size=k)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Mask -> segments
# ═══════════════════════════════════════════════════════════════════════════

def segments_from_mask(times, scores, mask, dt, frame_dur,
                       min_seg_s, merge_gap_s, max_seg_s,
                       audio_dur, pad_s=0.0):
    """Group contiguous flagged frames into [t_start, t_end] segments.

    Frame times are CENTRES, so a run from frame i to frame j spans
    [t_i - dt/2, t_j + dt/2]. Event tables carry their own durations and
    use those instead.
    """
    segs = []
    n = len(times)
    i = 0
    while i < n:
        if not mask[i]:
            i += 1
            continue
        j = i
        while j + 1 < n and mask[j + 1]:
            j += 1

        if frame_dur is not None:
            t0 = times[i] - frame_dur[i] / 2.0
            t1 = times[j] + frame_dur[j] / 2.0
        else:
            t0 = times[i] - dt / 2.0
            t1 = times[j] + dt / 2.0

        segs.append({
            "start": t0 - pad_s,
            "end": t1 + pad_s,
            "score": float(np.max(scores[i:j + 1])),
            "mean_score": float(np.mean(scores[i:j + 1])),
            "n_frames": j - i + 1,
        })
        i = j + 1

    # ── Merge segments separated by less than merge_gap ──────────────────
    merged = []
    for s in segs:
        if merged and s["start"] - merged[-1]["end"] <= merge_gap_s:
            prev = merged[-1]
            prev["end"] = max(prev["end"], s["end"])
            prev["score"] = max(prev["score"], s["score"])
            prev["mean_score"] = max(prev["mean_score"], s["mean_score"])
            prev["n_frames"] += s["n_frames"]
        else:
            merged.append(dict(s))

    # ── Clamp, split over-long, drop under-length ────────────────────────
    out = []
    n_short = 0
    for s in merged:
        s["start"] = max(0.0, s["start"])
        s["end"] = min(audio_dur, s["end"])
        if s["end"] - s["start"] < min_seg_s:
            n_short += 1
            continue
        if max_seg_s and (s["end"] - s["start"]) > max_seg_s:
            n_chunks = int(math.ceil((s["end"] - s["start"]) / max_seg_s))
            chunk = (s["end"] - s["start"]) / n_chunks
            for c in range(n_chunks):
                out.append({
                    "start": s["start"] + c * chunk,
                    "end": s["start"] + (c + 1) * chunk,
                    "score": s["score"],
                    "mean_score": s["mean_score"],
                    "n_frames": max(1, s["n_frames"] // n_chunks),
                })
        else:
            out.append(s)

    return out, n_short


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Slicing & windowing
# ═══════════════════════════════════════════════════════════════════════════

def tukey_taper(n, fade_samples, law="linear"):
    """Tukey window whose taper is exactly `fade_samples` long at each end.

    law='linear'      -> standard Tukey (raised-cosine taper), best for
                         anti-click on a slice heard in isolation.
    law='equal_power' -> sqrt of the same taper, so two overlapped tapers
                         hold constant POWER on uncorrelated material.
    """
    from scipy.signal import windows

    n = int(n)
    if n <= 0:
        return np.zeros(0)
    f = int(max(0, min(fade_samples, n // 2)))
    if f < 1:
        return np.ones(n)
    alpha = min(1.0, 2.0 * f / n)
    w = windows.tukey(n, alpha=alpha, sym=True)
    if law == "equal_power":
        w = np.sqrt(np.maximum(w, 0.0))
    return w


def extract_slices(audio, sr, segments, fade_ms, law):
    """Cut each segment out of the audio and taper it. Returns a list of
    (samples [n, ch], score) with the shortest possible guard against
    zero-length or out-of-range requests."""
    n_total, n_ch = audio.shape
    fade_samples = int(round(fade_ms * sr / 1000.0))
    slices = []
    n_dropped = 0

    for s in segments:
        i0 = int(round(s["start"] * sr))
        i1 = int(round(s["end"] * sr))
        i0 = max(0, min(i0, n_total))
        i1 = max(0, min(i1, n_total))
        if i1 - i0 < max(4, 2 * fade_samples + 2):
            n_dropped += 1
            continue
        clip = audio[i0:i1, :].copy()
        w = tukey_taper(clip.shape[0], fade_samples, law)
        clip *= w[:, None]
        slices.append({
            "audio": clip,
            "score": s["score"],
            "start": s["start"],
            "end": s["end"],
        })

    return slices, n_dropped, fade_samples


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Re-assembly
# ═══════════════════════════════════════════════════════════════════════════

def assemble_sequential(slices, fade_samples, join="xfade"):
    """chronological / sorted: lay slices end to end.

    With join='xfade' each slice starts `fade_samples` before the previous
    one ends, so the falling taper of A sits on top of the rising taper of
    B. Butt-joining them instead puts a full fade-out immediately followed
    by a full fade-in — an audible hole at every junction.
    """
    if not slices:
        return np.zeros((0, 1))

    n_ch = slices[0]["audio"].shape[1]
    hop = fade_samples if join == "xfade" else 0

    positions = []
    pos = 0
    for s in slices:
        positions.append(pos)
        pos += s["audio"].shape[0] - hop
    total = positions[-1] + slices[-1]["audio"].shape[0]

    out = np.zeros((total, n_ch), dtype=np.float64)
    for p, s in zip(positions, slices):
        clip = s["audio"]
        out[p:p + clip.shape[0], :] += clip
    return out


def assemble_granular(slices, fade_samples, overlap, jitter, seed):
    """granular: overlap-add the slices into a continuous texture.

    Hop is a fraction of each slice's own length, so long slices still
    advance and short ones still stack. Jitter randomizes the hop to break
    up the periodicity that a fixed hop imposes on the result.
    """
    if not slices:
        return np.zeros((0, 1))

    rng = np.random.default_rng(seed)
    n_ch = slices[0]["audio"].shape[1]
    overlap = float(min(0.95, max(0.0, overlap)))

    positions = []
    pos = 0
    for s in slices:
        positions.append(pos)
        step = s["audio"].shape[0] * (1.0 - overlap)
        if jitter > 0:
            step *= 1.0 + rng.uniform(-jitter, jitter)
        pos += max(fade_samples + 1, int(round(step)))

    total = max(p + s["audio"].shape[0] for p, s in zip(positions, slices))
    out = np.zeros((total, n_ch), dtype=np.float64)
    for p, s in zip(positions, slices):
        clip = s["audio"]
        out[p:p + clip.shape[0], :] += clip
    return out


# ── Texture / memory: output duration becomes an independent parameter ──
#
# chronological / sorted / granular all use each slice EXACTLY ONCE, so the
# output length is a function of how much anomalous material was found. With
# high overlap it is shorter still: ten 100 ms slices at 0.70 overlap render
# 0.370 s from 1.0 s of raw material, because the hop is 30 ms.
#
# texture and memory invert that. The slices become a CORPUS and the canvas
# length is asked for directly, so a 70 ms anomaly can populate 30 seconds.

def selection_weights(scores, bias):
    """Map slice anomaly scores to sampling weights.

    bias = 0  -> uniform: every anomaly is equally present
    bias ~ 2  -> stronger anomalies recur noticeably more often
    bias >= 6 -> the texture collapses onto the few most extreme objects

    The exponent is applied to the normalized score and the floor is added
    AFTER it, so the weakest slice keeps a real 5% share at any bias. Doing
    it the other way round - (floor + score) ** bias - drives the floor to
    0.05 ** bias, which is 0.0006 at bias 2.5: the weakest anomalies vanish
    from the corpus entirely rather than receding into the background.
    """
    s = np.asarray(scores, dtype=np.float64)
    if s.size == 0:
        return np.zeros(0)
    lo, hi = s.min(), s.max()
    s_hat = np.zeros_like(s) if (hi - lo) < EPS else (s - lo) / (hi - lo)
    w = 0.05 + 0.95 * (s_hat ** max(0.0, float(bias)))
    total = w.sum()
    return np.ones_like(w) / len(w) if total < EPS else w / total


def _render_events(events, slices, target_samples, n_ch, fade_samples):
    """Overlap-add scheduled events onto a fixed-length canvas.

    Events are placed on a canvas long enough to hold the last one whole,
    then trimmed to the requested length, so nothing wraps. The trim can
    cut an event mid-way, so the tail gets its own fade-out.
    """
    if not events:
        return np.zeros((0, n_ch))

    max_len = max(slices[i]["audio"].shape[0] for _, i in events)
    canvas = np.zeros((target_samples + max_len + 1, n_ch), dtype=np.float64)
    for onset, idx in events:
        clip = slices[idx]["audio"]
        o = max(0, int(onset))
        canvas[o:o + clip.shape[0], :] += clip

    out = canvas[:target_samples, :]
    f = min(fade_samples, out.shape[0] // 2)
    if f > 1:
        ramp = np.linspace(1.0, 0.0, f)
        out[-f:, :] *= ramp[:, None]
    return out


def assemble_texture(slices, target_samples, fade_samples, overlap, jitter,
                     bias, anti_repeat, seed):
    """Stochastic anomaly cloud of a requested length.

    Slices are drawn with replacement, weighted by anomaly score, until the
    canvas is full. A cooldown queue holds recently used slices out of the
    draw so a single loud event cannot repeat a dozen times in a row - with
    a high bias and no cooldown, weighted sampling degenerates into exactly
    that.
    """
    if not slices:
        return np.zeros((0, 1)), {}

    rng = np.random.default_rng(seed)
    n = len(slices)
    n_ch = slices[0]["audio"].shape[1]
    base_w = selection_weights([s["score"] for s in slices], bias)

    cool_len = int(min(n - 1, max(0, round(float(anti_repeat) * n))))
    recent = []
    counts = np.zeros(n, dtype=int)
    events = []
    pos = 0

    while pos < target_samples:
        w = base_w.copy()
        if cool_len > 0 and recent:
            w[recent] = 0.0
            if w.sum() < EPS:                 # cooldown swallowed everything
                w = base_w.copy()
        w = w / w.sum()

        idx = int(rng.choice(n, p=w))
        events.append((pos, idx))
        counts[idx] += 1

        recent.append(idx)
        if len(recent) > cool_len:
            recent.pop(0)

        step = slices[idx]["audio"].shape[0] * (1.0 - overlap)
        if jitter > 0:
            step *= 1.0 + rng.uniform(-jitter, jitter)
        pos += max(fade_samples + 1, int(round(step)))

    out = _render_events(events, slices, target_samples, n_ch, fade_samples)
    return out, {
        "n_events": len(events),
        "distinct_slices": int(np.count_nonzero(counts)),
        "max_repeats": int(counts.max()) if counts.size else 0,
    }


def assemble_memory(slices, target_samples, fade_samples, overlap, jitter,
                    bias, seed):
    """Recurrence rather than a cloud.

    Each slice gets a RECURRENCE BUDGET from its anomaly score, and its
    occurrences are spread evenly across the whole canvas rather than drawn
    independently. A sharp 70 ms anomaly therefore comes back as a motif
    across the texture instead of clustering in one region.

    A drift of at least 10% of each slice's own return interval is always
    applied, so a recurring slice reads as a trace and not as a loop. That
    is a floor, not a default: raising jitter widens it further.
    """
    if not slices:
        return np.zeros((0, 1)), {}

    rng = np.random.default_rng(seed)
    n = len(slices)
    n_ch = slices[0]["audio"].shape[1]
    w = selection_weights([s["score"] for s in slices], bias)

    mean_len = float(np.mean([s["audio"].shape[0] for s in slices]))
    hop = max(fade_samples + 1, mean_len * (1.0 - overlap))
    total_events = int(max(n, round(target_samples / hop)))

    # Largest-remainder apportionment, with every slice guaranteed one
    # appearance so a high bias concentrates the texture without erasing
    # any of the detected anomalies.
    raw = w * (total_events - n)
    counts = np.floor(raw).astype(int) + 1
    remainder = total_events - int(counts.sum())
    if remainder > 0:
        order = np.argsort(-(raw - np.floor(raw)))
        for k in range(remainder):
            counts[order[k % n]] += 1

    drift = max(0.10, float(jitter))
    events = []
    for i in range(n):
        n_i = int(counts[i])
        if n_i < 1:
            continue
        interval = target_samples / float(n_i)
        phase = rng.uniform(0.0, 1.0)
        for k in range(n_i):
            t = (k + phase) * interval
            t += rng.normal(0.0, drift * interval)
            t = min(max(0.0, t), float(target_samples - 1))
            events.append((int(round(t)), i))

    events.sort(key=lambda e: e[0])
    out = _render_events(events, slices, target_samples, n_ch, fade_samples)
    return out, {
        "n_events": len(events),
        "distinct_slices": int(np.count_nonzero(counts)),
        "max_repeats": int(counts.max()) if counts.size else 0,
    }


def normalize_peak(x, target_dbfs):
    """Scale so the absolute peak sits at target_dbfs. Returns (x, gain,
    peak_before). Silent input is passed through untouched."""
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    if peak < EPS:
        return x, 1.0, peak
    target = db_to_lin(target_dbfs)
    gain = target / peak
    return x * gain, gain, peak


# ═══════════════════════════════════════════════════════════════════════════
# Stage 8 — Stats handoff
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, info):
    """key=value lines, parsed by the Praat front-end.

    Also writes decimated score points and segment rows so Praat can draw
    the score curve and the outlier regions without re-reading the CSV.
    """
    times = info["times"]
    scores = info["scores"]
    segs = info["segments"]

    with open(path, "w") as f:
        f.write("algorithm=%s\n"          % info["algorithm"])
        f.write("score_kind=%s\n"         % info["score_kind"])
        f.write("mode=%s\n"               % info["mode"])
        f.write("join=%s\n"               % info["join"])
        f.write("n_frames=%d\n"           % len(times))
        f.write("n_features=%d\n"         % info["n_features"])
        f.write("feature_names=%s\n"      % " ".join(info["feature_names"]))
        f.write("time_step=%.6f\n"        % info["dt"])
        f.write("threshold=%.6f\n"        % info["threshold"])
        f.write("score_cut=%.6f\n"        % info["score_cut"])
        f.write("n_flagged_frames=%d\n"   % info["n_flagged"])
        f.write("n_segments=%d\n"         % len(segs))
        f.write("outlier_duration=%.4f\n" % info["outlier_dur"])
        f.write("input_duration=%.4f\n"   % info["input_dur"])
        f.write("output_duration=%.4f\n"  % info["output_dur"])
        f.write("coverage_percent=%.2f\n" % info["coverage_pct"])
        f.write("fade_ms=%.2f\n"          % info["fade_ms"])
        f.write("mean_seg_dur=%.4f\n"     % info["mean_seg_dur"])
        f.write("score_mean=%.6f\n"       % float(np.mean(scores)))
        f.write("score_max=%.6f\n"        % float(np.max(scores)))
        f.write("peak_before=%.6f\n"      % info["peak_before"])
        f.write("peak_gain_db=%.2f\n"     % info["peak_gain_db"])
        f.write("rms_input=%.6f\n"        % info["rms_input"])
        f.write("rms_output=%.6f\n"       % info["rms_output"])
        f.write("sample_rate=%d\n"        % info["sr"])
        f.write("n_channels=%d\n"         % info["n_channels"])
        for k, v in sorted(info.get("extra", {}).items()):
            f.write("%s=%s\n" % (k, v))
        tx = info.get("texture") or {}
        if tx:
            f.write("n_events=%d\n"        % tx["n_events"])
            f.write("distinct_slices=%d\n" % tx["distinct_slices"])
            f.write("max_repeats=%d\n"     % tx["max_repeats"])

        # ── Decimated score curve for the Praat panel ────────────────────
        n = len(times)
        step = max(1, int(math.ceil(n / float(MAX_STATS_POINTS))))
        idx = list(range(0, n, step))
        f.write("n_score_pts=%d\n" % len(idx))
        for k, i in enumerate(idx):
            f.write("sc_%d=%.4f,%.4f\n" % (k, times[i], scores[i]))

        # ── Segment rows ─────────────────────────────────────────────────
        n_seg = min(len(segs), MAX_STATS_SEGMENTS)
        f.write("n_seg_pts=%d\n" % n_seg)
        for k in range(n_seg):
            s = segs[k]
            f.write("sg_%d=%.4f,%.4f,%.4f\n" % (k, s["start"], s["end"], s["score"]))

        if info["warnings"]:
            f.write("warning=%s\n" % "; ".join(info["warnings"]))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def build_parser():
    import argparse

    p = argparse.ArgumentParser(
        description="Acoustic anomaly extraction & resynthesis engine "
                    "(Praat AudioTools backend)")

    # ── Required I/O ─────────────────────────────────────────────────────
    p.add_argument("--audio_in",  required=True, help="Input WAV from Praat")
    p.add_argument("--csv_in",    required=True, help="Praat feature table CSV")
    p.add_argument("--audio_out", required=True, help="Output WAV to write")

    # ── Core controls ────────────────────────────────────────────────────
    p.add_argument("--algorithm",
                   choices=["IsolationForest", "Mahalanobis", "Autoencoder"],
                   default="IsolationForest")
    p.add_argument("--threshold", type=float, default=0.05,
                   help="FRACTION of frames to flag (0.05 = top 5%%). "
                        "Not an absolute score cut.")
    p.add_argument("--mode",
                   choices=["chronological", "sorted", "granular",
                            "texture", "memory"],
                   default="chronological")

    # ── Optional ─────────────────────────────────────────────────────────
    p.add_argument("--stats_out", default=None,
                   help="key=value stats file for the Praat front-end")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--deltas", action="store_true",
                   help="Append first-difference features (detects "
                        "transitions as well as static extremes)")
    p.add_argument("--smooth_frames", type=int, default=3,
                   help="Median-filter width on A(t), in frames (0 = off)")

    p.add_argument("--fade_ms",      type=float, default=DEFAULT_FADE_MS)
    p.add_argument("--min_seg_ms",   type=float, default=40.0)
    p.add_argument("--merge_gap_ms", type=float, default=30.0)
    p.add_argument("--max_seg_ms",   type=float, default=2000.0)
    p.add_argument("--pad_ms",       type=float, default=0.0,
                   help="Symmetric context added to every segment")

    p.add_argument("--join", choices=["xfade", "butt"], default="xfade")
    p.add_argument("--xfade_law", choices=["equal_power", "linear"],
                   default="equal_power")
    p.add_argument("--granular_overlap", type=float, default=0.5,
                   help="Density for granular / texture / memory: fraction "
                        "of each slice that overlaps the next")
    p.add_argument("--granular_jitter",  type=float, default=0.0)

    # texture / memory only
    p.add_argument("--texture_duration", type=float, default=20.0,
                   help="Canvas length in seconds. In these modes the output "
                        "duration is a parameter, not a consequence of how "
                        "much anomalous material was found.")
    p.add_argument("--anomaly_bias", type=float, default=1.5,
                   help="0 = every anomaly equally present; higher values "
                        "give stronger anomalies more presence")
    p.add_argument("--anti_repeat", type=float, default=0.5,
                   help="texture only: fraction of the corpus held in "
                        "cooldown after use, to stop back-to-back repeats")

    p.add_argument("--peak_dbfs", type=float, default=PEAK_TARGET_DBFS)
    p.add_argument("--cleanup", action="store_true",
                   help="Delete Praat-created temp inputs after writing")
    return p


def run(args):
    import soundfile as sf

    warnings_list = []

    # ── Stage 1: Ingest ──────────────────────────────────────────────────
    print("  [Py 1/7] Loading audio + feature table...")
    audio, sr, subtype = load_audio(args.audio_in)
    n_samples, n_ch = audio.shape
    input_dur = n_samples / float(sr)
    rms_input = _rms(audio)

    times, frame_dur, X_raw, names, n_bad_rows = load_feature_table(args.csv_in)
    dt = infer_time_step(times)
    print("    Audio: %.2fs  SR=%d  Ch=%d  |  Frames: %d  Features: %d  dt=%.4fs"
          % (input_dur, sr, n_ch, len(times), len(names), dt))
    if n_bad_rows:
        warnings_list.append("%d CSV rows had no usable time" % n_bad_rows)

    if times[-1] > input_dur + 1.0:
        warnings_list.append("Feature times exceed audio duration — "
                             "CSV/WAV mismatch?")

    # ── Stage 2: Condition ───────────────────────────────────────────────
    print("  [Py 2/7] Conditioning features...")
    X, names, n_filled, n_const = condition_features(X_raw, names, args.deltas)
    print("    Matrix: %s  |  interpolated cells: %d  |  constant cols dropped: %d"
          % (str(X.shape), n_filled, n_const))
    if n_filled > 0.5 * X_raw.size:
        warnings_list.append("Over half of feature cells were undefined")

    # ── Stage 3: Score ───────────────────────────────────────────────────
    print("  [Py 3/7] Scoring frames (%s)..." % args.algorithm)
    scores, raw, score_kind, extras = compute_scores(X, args.algorithm, args.seed)
    scores = smooth_scores(scores, args.smooth_frames)
    scores = np.clip(scores, 0.0, 1.0)
    print("    A(t): mean=%.4f  max=%.4f  (%s)"
          % (float(np.mean(scores)), float(np.max(scores)), score_kind))

    # ── Stage 4: Threshold -> segments ───────────────────────────────────
    print("  [Py 4/7] Thresholding + segmenting...")
    thr = float(min(0.99, max(0.001, args.threshold)))
    if thr != args.threshold:
        warnings_list.append("threshold clamped to %.3f" % thr)
    score_cut = float(np.quantile(scores, 1.0 - thr))
    mask = scores >= score_cut
    n_flagged = int(mask.sum())

    stats_extra = {}
    if "chi2_tail" in extras and n_flagged > 0:
        # Tail probability of the least extreme flagged frame — i.e.
        # "a normal frame would be this far out p of the time".
        stats_extra["chi2_tail_at_cut"] = "%.3e" % float(
            np.max(extras["chi2_tail"][mask]))

    segments, n_short = segments_from_mask(
        times, scores, mask, dt, frame_dur,
        min_seg_s=args.min_seg_ms / 1000.0,
        merge_gap_s=args.merge_gap_ms / 1000.0,
        max_seg_s=args.max_seg_ms / 1000.0 if args.max_seg_ms > 0 else None,
        audio_dur=input_dur,
        pad_s=args.pad_ms / 1000.0,
    )
    print("    Cut=%.4f  flagged %d/%d frames  ->  %d segments (%d too short)"
          % (score_cut, n_flagged, len(times), len(segments), n_short))

    # Fallback: never hand Praat a zero-length WAV. If nothing survived the
    # length filter, keep the single highest-scoring region and say so.
    if not segments:
        peak_i = int(np.argmax(scores))
        half = max(args.min_seg_ms / 1000.0, 4 * dt) / 2.0
        segments = [{
            "start": max(0.0, times[peak_i] - half),
            "end": min(input_dur, times[peak_i] + half),
            "score": float(scores[peak_i]),
            "mean_score": float(scores[peak_i]),
            "n_frames": 1,
        }]
        warnings_list.append(
            "No segment survived min_seg_ms — fell back to the single "
            "highest-scoring frame. Raise threshold or lower min_seg_ms.")

    # ── Stage 5: Slice + taper ───────────────────────────────────────────
    print("  [Py 5/7] Slicing + Tukey taper (%.1f ms, %s)..."
          % (args.fade_ms, args.xfade_law))
    law = args.xfade_law if args.join == "xfade" else "linear"
    slices, n_dropped, fade_samples = extract_slices(
        audio, sr, segments, args.fade_ms, law)
    if n_dropped:
        warnings_list.append("%d slices shorter than the taper were dropped"
                             % n_dropped)
    if not slices:
        raise ValueError("Every candidate slice was shorter than the "
                         "%.1f ms taper. Lower --fade_ms or raise "
                         "--min_seg_ms." % args.fade_ms)

    # ── Stage 6: Assemble ────────────────────────────────────────────────
    print("  [Py 6/7] Assembling (%s)..." % args.mode)
    if args.mode == "sorted":
        ordered = sorted(slices, key=lambda s: s["score"])
    else:
        # texture / memory order the corpus by score internally via the
        # weights, so their slice list stays in source order.
        ordered = sorted(slices, key=lambda s: s["start"])

    texture_info = {}
    if args.mode in ("texture", "memory"):
        tgt_dur = float(min(300.0, max(0.5, args.texture_duration)))
        if tgt_dur != args.texture_duration:
            warnings_list.append("texture_duration clamped to %.1f s" % tgt_dur)
        target_texture = int(round(tgt_dur * sr))
        if args.mode == "texture":
            out, texture_info = assemble_texture(
                ordered, target_texture, fade_samples,
                args.granular_overlap, args.granular_jitter,
                args.anomaly_bias, args.anti_repeat, args.seed)
        else:
            out, texture_info = assemble_memory(
                ordered, target_texture, fade_samples,
                args.granular_overlap, args.granular_jitter,
                args.anomaly_bias, args.seed)
        print("    %d events from %d/%d slices | max repeats %d | %.1f events/s"
              % (texture_info["n_events"], texture_info["distinct_slices"],
                 len(ordered), texture_info["max_repeats"],
                 texture_info["n_events"] / max(tgt_dur, EPS)))
    elif args.mode == "granular":
        out = assemble_granular(ordered, fade_samples,
                                args.granular_overlap,
                                args.granular_jitter, args.seed)
    else:
        out = assemble_sequential(ordered, fade_samples, args.join)

    if out.shape[0] < 2:
        raise ValueError("Assembled output is empty.")

    out, gain, peak_before = normalize_peak(out, args.peak_dbfs)
    if peak_before < EPS:
        warnings_list.append("Assembled output was silent — nothing to "
                             "normalize")
    out_dur = out.shape[0] / float(sr)
    rms_output = _rms(out)
    print("    Output: %.2fs  %d ch  |  peak %.4f -> %.2f dBFS (%.2f dB)"
          % (out_dur, out.shape[1], peak_before, args.peak_dbfs,
             20 * math.log10(max(gain, EPS))))

    # ── Stage 7: Write ───────────────────────────────────────────────────
    print("  [Py 7/7] Writing output + stats...")
    write_kwargs = {}
    if subtype:
        try:
            if sf.check_format("WAV", subtype):
                write_kwargs["subtype"] = subtype
        except Exception:
            pass
    sf.write(args.audio_out, out, sr, **write_kwargs)

    outlier_dur = float(sum(s["end"] - s["start"] for s in segments))
    if args.stats_out:
        write_stats(args.stats_out, {
            "times": times, "scores": scores, "segments": segments,
            "algorithm": args.algorithm, "score_kind": score_kind,
            "mode": args.mode, "join": args.join,
            "n_features": X.shape[1], "feature_names": names,
            "dt": dt, "threshold": thr, "score_cut": score_cut,
            "n_flagged": n_flagged,
            "outlier_dur": outlier_dur, "input_dur": input_dur,
            "output_dur": out_dur,
            "coverage_pct": 100.0 * outlier_dur / max(input_dur, EPS),
            "fade_ms": args.fade_ms,
            "mean_seg_dur": outlier_dur / max(len(segments), 1),
            "peak_before": peak_before,
            "peak_gain_db": 20 * math.log10(max(gain, EPS)),
            "rms_input": rms_input, "rms_output": rms_output,
            "sr": sr, "n_channels": out.shape[1],
            "warnings": warnings_list,
            "extra": stats_extra,
            "texture": texture_info,
        })

    # ── Stage 8: Cleanup ─────────────────────────────────────────────────
    # Only files Praat created for this run (temp_ prefix) may be removed,
    # and never the output, which Praat still has to read back.
    if args.cleanup:
        for path in [args.audio_in, args.csv_in]:
            if _is_praat_temp(path) and os.path.exists(path):
                os.remove(path)
                print("    Deleted: %s" % path)

    for w in warnings_list:
        print("    WARNING: %s" % w)
    print("OK: wrote %s" % args.audio_out)


def main():
    parser = build_parser()
    args = parser.parse_args()
    check_dependencies(args.algorithm)

    if not os.path.isfile(args.audio_in):
        print("ERROR: audio not found: %s" % args.audio_in, file=sys.stderr)
        return 1
    if not os.path.isfile(args.csv_in):
        print("ERROR: feature CSV not found: %s" % args.csv_in, file=sys.stderr)
        return 1

    try:
        run(args)
    except Exception as exc:                             # noqa: BLE001
        import traceback
        print("ERROR: %s" % exc, file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
