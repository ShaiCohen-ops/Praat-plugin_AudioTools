"""
phase_space_compose.py — Phase-Space Composition Engine  v1.4
    v1.4: mapping-distance weighting now follows the documented w*d^2 law,
    position and velocity distances share a 0..1 scale, low-temperature
    stochastic selection uses a numerically stable log-softmax, analysis can
    be pinned to a representative channel, source event IDs survive any
    filtering, and visualization projects the two most strongly weighted
    active dimensions.

    v1.3: --dim_weights is now resolved onto the active feature columns
    BY NAME (see CANONICAL_FEATURE_ORDER / resolve_dim_weights), fixing
    a bug where weight presets were silently mismatched to the wrong
    feature at state_dims < 5. Added --weight_preset_name for accurate
    stats.txt display, and stats.txt now also emits the selected-event
    path in plan order (n_sel_pts / psel_*) for visualization.

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat — not directly):
    python phase_space_compose.py
        --wav         input.wav
        --events      events.csv
        --out_plan    plan.csv
        --out_stats   stats.txt
        --attractor   Lorenz          # Hopf | Lorenz | Rossler | LogisticMap
        --state_dims  3               # 2 | 3 | 4 | 5
        --n_output    300
        --tabu        12
        --temperature 0.15
        --seed        1234
        --min_event_dur_ms 30
        --analysis_channel 1         # 1-based; 0 = auto strongest-RMS channel
        --dim_weights "1.0,1.0,1.0,1.0,1.0"  # ALWAYS canonical order:
                                              # centroid,flatness,entropy,flux,rms
                                              # — resolved by name onto whatever
                                              # columns --state_dims actually has
        --weight_preset_name "Brightness"    # optional; for stats.txt display only
        --velocity_weight 0.0        # 0=position only, 1=direction only
        --coupling    0.0            # feedback pull: events bend the trajectory
        [--debug]

Architecture:
    A — Load WAV + event boundary CSV
    B — Extract per-event features (centroid, flatness, entropy, flux, rms)
    C — Robust-normalize features to [0, 1]
    D — Generate deterministic dynamical trajectory
    E — Map trajectory steps → events
          · weighted Euclidean distance (dim_weights)
          · velocity / direction alignment (velocity_weight)
          · feedback coupling (coupling)
          · tabu anti-repetition + temperature softmax
    F — Write plan.csv + stats.txt

State vectors:
    2D:  centroid, flatness
    3D:  centroid, flatness, flux
    4D:  centroid, flatness, entropy, flux
    5D:  centroid, flatness, entropy, flux, rms

Attractors:
    Hopf        — limit cycle (RK4); embed to D dims via smooth extensions
    Lorenz      — strange attractor σ=10 ρ=28 β=8/3 (RK4)
    Rossler     — single-scroll attractor a=0.2 b=0.2 c=5.7 (RK4)
    LogisticMap — r=3.9 chaotic map; D-dim via time-delay embedding
"""

import sys
import os
import math
import argparse
from collections import deque

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────
N_FFT            = 1024     # FFT window size for feature extraction
HOP_SAMPLES      = 256      # hop between analysis frames
LORENZ_DT        = 0.02     # integration step — Lorenz
ROSSLER_DT       = 0.05     # integration step — Rössler
HOPF_DT          = 0.05     # integration step — Hopf
LORENZ_BURNIN    = 1000     # transient steps discarded — Lorenz
ROSSLER_BURNIN   = 2000     # transient steps discarded — Rössler
HOPF_BURNIN      = 500      # transient steps discarded — Hopf
LOGISTIC_BURNIN  = 500      # transient steps discarded — Logistic map
LOGISTIC_R       = 3.9      # logistic parameter (chaotic regime)
HOPF_ALPHA       = 0.5      # Hopf growth rate (limit cycle radius = sqrt(α))
HOPF_OMEGA       = 2.0 * math.pi   # Hopf angular frequency

# Canonical name order that --dim_weights values are always given in,
# regardless of --state_dims. This lets weight presets stay meaningful
# across dimensionalities (see resolve_dim_weights below).
CANONICAL_FEATURE_ORDER = ["centroid", "flatness", "entropy", "flux", "rms"]


# ─────────────────────────────────────────────────────────────────────────────
# Dependency check
# ─────────────────────────────────────────────────────────────────────────────

def check_deps():
    missing = []
    for pkg in ["numpy", "soundfile", "scipy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# A — Data loading
# ─────────────────────────────────────────────────────────────────────────────

def load_audio(wav_path):
    """Load WAV preserving channel count.  Returns (float32 array, sr)."""
    import soundfile as sf
    audio, sr = sf.read(wav_path, always_2d=True)
    return audio.astype("float32"), int(sr)


def load_events(csv_path, min_dur_s):
    """
    Parse event CSV written by Praat:
        index, start_s, end_s, duration_s
    Returns list of dicts with keys: idx, start, end, dur.
    Only keeps events with dur >= min_dur_s.
    """
    events = []
    with open(csv_path, "r") as f:
        f.readline()  # skip header
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) < 4:
                continue
            try:
                idx   = int(float(parts[0]))
                start = float(parts[1])
                end   = float(parts[2])
                dur   = float(parts[3])
            except ValueError:
                continue
            if dur >= min_dur_s:
                events.append({"idx": idx, "start": start,
                                "end": end, "dur": dur})
    return events


# ─────────────────────────────────────────────────────────────────────────────
# B — Per-event feature extraction
# ─────────────────────────────────────────────────────────────────────────────

def choose_analysis_channel(audio, requested_channel=0):
    """Return a zero-based representative analysis channel.

    requested_channel is 1-based when >0 (matching Praat/user-facing channel
    numbering).  With 0, choose the channel with the largest whole-file RMS.
    This avoids phase-cancelling stereo fold-downs while keeping segmentation
    and feature extraction tied to one real signal channel.
    """
    import numpy as np
    n_ch = int(audio.shape[1])
    if requested_channel > 0:
        if requested_channel > n_ch:
            raise ValueError("analysis_channel %d exceeds channel count %d" %
                             (requested_channel, n_ch))
        return int(requested_channel - 1)
    rms = np.sqrt(np.mean(np.asarray(audio, dtype="float64") ** 2, axis=0) + 1e-20)
    return int(np.argmax(rms))


def _analysis_slice(audio, start_s, end_s, sr, analysis_ch):
    """Return a float64 slice from the selected representative channel."""
    import numpy as np
    s = max(0, int(start_s * sr))
    e = min(audio.shape[0], int(end_s * sr))
    if e <= s:
        return np.zeros(256, dtype="float64")
    return audio[s:e, analysis_ch].astype("float64")


def extract_features(audio, events, sr, analysis_ch=0):
    """
    Compute 5 spectral/energy features per event.

    Features:
      centroid  — spectral centroid [Hz], weighted by magnitude
      flatness  — spectral flatness (geometric / arithmetic mean of |X(f)|)
                  close to 0 = tonal, close to 1 = noise-like
      entropy   — Shannon spectral entropy normalised to [0, 1]
      flux      — mean frame-to-frame spectral change (onset / transientness proxy)
      rms       — root mean square energy

    All computed on one representative real channel (normally the strongest-
    RMS channel selected by Praat).  This avoids destructive stereo fold-down.
    FFT window is halved for very short events.
    """
    import numpy as np

    n_ev     = len(events)
    centroid = np.zeros(n_ev)
    flatness = np.zeros(n_ev)
    entropy  = np.zeros(n_ev)
    flux     = np.zeros(n_ev)
    rms      = np.zeros(n_ev)

    for i, ev in enumerate(events):
        x = _analysis_slice(audio, ev["start"], ev["end"], sr, analysis_ch)
        n_samp = len(x)

        # RMS — robust even for 1 sample
        rms[i] = float(np.sqrt(np.mean(x ** 2) + 1e-12))

        # Adapt FFT size to event length
        nf = N_FFT
        while nf > n_samp and nf > 64:
            nf //= 2
        hop_cur = max(1, nf // 4)
        half    = nf // 2 + 1
        freqs   = np.linspace(0.0, sr / 2.0, half)

        # Vectorized STFT via scipy
        from scipy.signal import stft as scipy_stft
        if n_samp >= nf:
            _, _, Zxx = scipy_stft(x, fs=sr, window="hann",
                                   nperseg=nf, noverlap=nf - hop_cur,
                                   nfft=nf, boundary=None, padded=False)
            mags = np.abs(Zxx) + 1e-12  # (half, n_frames)
        else:
            # Pad single frame
            frame = np.zeros(nf, dtype="float64")
            frame[:n_samp] = x
            frame *= np.hanning(nf)
            mags = (np.abs(np.fft.rfft(frame)) + 1e-12).reshape(-1, 1)

        mean_mag = mags.mean(axis=1)  # mean spectrum across frames

        # ---- Centroid ----
        total        = np.sum(mean_mag)
        centroid[i]  = float(np.sum(freqs * mean_mag) / (total + 1e-12))

        # ---- Flatness (geometric/arithmetic mean ratio) ----
        log_mean    = float(np.mean(np.log(mean_mag)))
        arith_mean  = float(np.mean(mean_mag))
        flatness[i] = float(np.exp(log_mean) / (arith_mean + 1e-12))
        flatness[i] = min(max(flatness[i], 0.0), 1.0)

        # ---- Spectral entropy ----
        p          = mean_mag / (total + 1e-12)
        p          = np.maximum(p, 1e-12)
        ent_raw    = float(-np.sum(p * np.log2(p)))
        entropy[i] = ent_raw / math.log2(len(p))

        # ---- Spectral flux (mean RMS of frame-to-frame mag diff) ----
        if mags.shape[1] > 1:
            diffs   = np.diff(mags, axis=1)
            flux[i] = float(np.mean(np.sqrt(np.mean(diffs ** 2, axis=0))))
        else:
            flux[i] = 0.0

    return {"centroid": centroid, "flatness": flatness,
            "entropy": entropy, "flux": flux, "rms": rms}


# ─────────────────────────────────────────────────────────────────────────────
# C — Normalisation
# ─────────────────────────────────────────────────────────────────────────────

def build_state_matrix(feats, state_dims):
    """
    Select feature columns for the chosen state dimension and stack into X.

    2D: centroid, flatness
    3D: centroid, flatness, flux
    4D: centroid, flatness, entropy, flux
    5D: centroid, flatness, entropy, flux, rms
    """
    import numpy as np
    if state_dims == 2:
        names = ["centroid", "flatness"]
    elif state_dims == 3:
        names = ["centroid", "flatness", "flux"]
    elif state_dims == 4:
        names = ["centroid", "flatness", "entropy", "flux"]
    else:   # 5
        names = ["centroid", "flatness", "entropy", "flux", "rms"]

    cols = [feats[n] for n in names]
    X    = np.column_stack(cols).astype("float64")
    return X, names


def resolve_dim_weights(dim_weights_list, col_names):
    """
    Map a --dim_weights vector (always given in CANONICAL_FEATURE_ORDER,
    i.e. centroid, flatness, entropy, flux, rms) onto the actual columns
    present at this state_dims, by NAME rather than by position.

    Fixes a semantic bug: because the feature order in build_state_matrix()
    changes across state_dims (e.g. 3D omits entropy but 4D/5D include it),
    truncating the weight vector positionally silently applied the wrong
    weight to the wrong feature (e.g. the entropy weight landing on flux
    in 3D). Resolving by name keeps a preset like "Transient focus"
    (high flux weight) correct at every dimensionality, and makes it
    explicit when a preset's target dimension (e.g. rms for "Energy
    focus") simply isn't part of the state space.

    Returns a list of length len(col_names), aligned to col_names order.
    """
    if not dim_weights_list:
        return [1.0] * len(col_names)

    padded = list(dim_weights_list[:len(CANONICAL_FEATURE_ORDER)])
    while len(padded) < len(CANONICAL_FEATURE_ORDER):
        padded.append(1.0)

    lut = dict(zip(CANONICAL_FEATURE_ORDER, padded))
    return [lut.get(name, 1.0) for name in col_names]


def robust_normalize_01(X):
    """
    Robust-normalise each column to [0, 1].

    Method: subtract median, divide by IQR, clamp to [-3, 3],
    then shift/scale to [0, 1].  Keeps outlier events from dominating
    the feature space.
    """
    import numpy as np
    X_out = X.copy()
    for d in range(X_out.shape[1]):
        col  = X_out[:, d]
        med  = float(np.median(col))
        q25, q75 = np.percentile(col, [25.0, 75.0])
        iqr  = max(q75 - q25, 1e-8)
        scaled   = (col - med) / iqr
        clamped  = np.clip(scaled, -3.0, 3.0)
        X_out[:, d] = (clamped + 3.0) / 6.0
    return X_out


# ─────────────────────────────────────────────────────────────────────────────
# D — Dynamical systems
# ─────────────────────────────────────────────────────────────────────────────

# ── RK4 helper ──────────────────────────────────────────────────────────────

def _rk4_2d(x, y, f, dt):
    k1x, k1y = f(x, y)
    k2x, k2y = f(x + dt * 0.5 * k1x, y + dt * 0.5 * k1y)
    k3x, k3y = f(x + dt * 0.5 * k2x, y + dt * 0.5 * k2y)
    k4x, k4y = f(x + dt * k3x, y + dt * k3y)
    return (x + dt / 6.0 * (k1x + 2*k2x + 2*k3x + k4x),
            y + dt / 6.0 * (k1y + 2*k2y + 2*k3y + k4y))


def _rk4_3d(x, y, z, f, dt):
    k1x, k1y, k1z = f(x, y, z)
    k2x, k2y, k2z = f(x + dt*0.5*k1x, y + dt*0.5*k1y, z + dt*0.5*k1z)
    k3x, k3y, k3z = f(x + dt*0.5*k2x, y + dt*0.5*k2y, z + dt*0.5*k2z)
    k4x, k4y, k4z = f(x + dt*k3x, y + dt*k3y, z + dt*k3z)
    return (x + dt / 6.0 * (k1x + 2*k2x + 2*k3x + k4x),
            y + dt / 6.0 * (k1y + 2*k2y + 2*k3y + k4y),
            z + dt / 6.0 * (k1z + 2*k2z + 2*k3z + k4z))


# ── Hopf limit cycle ─────────────────────────────────────────────────────────

def _generate_hopf_raw(n_steps):
    """
    Hopf normal form:
        dx/dt = α·x − ω·y − x·(x²+y²)
        dy/dt = ω·x + α·y − y·(x²+y²)

    Stable limit cycle of radius √α; ω controls angular frequency.
    """
    import numpy as np
    alpha = HOPF_ALPHA
    omega = HOPF_OMEGA
    dt    = HOPF_DT

    def f(x, y):
        r2 = x*x + y*y
        return (alpha*x - omega*y - x*r2,
                omega*x + alpha*y - y*r2)

    x, y = 0.5, 0.1
    for _ in range(HOPF_BURNIN):
        x, y = _rk4_2d(x, y, f, dt)

    traj = []
    for _ in range(n_steps):
        x, y = _rk4_2d(x, y, f, dt)
        traj.append([x, y])

    return traj   # list of 2-element lists


# ── Lorenz attractor ─────────────────────────────────────────────────────────

def _generate_lorenz_raw(n_steps, sigma=10.0, rho=28.0, beta=8.0/3.0):
    """
    Lorenz system — classical strange attractor:
        dx/dt = σ(y − x)
        dy/dt = x(ρ − z) − y
        dz/dt = xy − βz
    Parameters: σ=10, ρ=28, β=8/3 (standard chaotic regime).
    """
    import numpy as np
    dt = LORENZ_DT

    def f(x, y, z):
        return sigma*(y - x), x*(rho - z) - y, x*y - beta*z

    x, y, z = 0.1, 0.0, 0.0
    for _ in range(LORENZ_BURNIN):
        x, y, z = _rk4_3d(x, y, z, f, dt)

    traj = []
    for _ in range(n_steps):
        x, y, z = _rk4_3d(x, y, z, f, dt)
        traj.append([x, y, z])

    return traj


# ── Rössler attractor ────────────────────────────────────────────────────────

def _generate_rossler_raw(n_steps, a=0.2, b=0.2, c=5.7):
    """
    Rössler system — single-scroll chaotic attractor:
        dx/dt = −y − z
        dy/dt = x + a·y
        dz/dt = b + z·(x − c)
    Parameters: a=0.2, b=0.2, c=5.7 (standard spiral chaos).
    """
    import numpy as np
    dt = ROSSLER_DT

    def f(x, y, z):
        return -y - z, x + a*y, b + z*(x - c)

    x, y, z = 0.1, 0.0, 0.0
    for _ in range(ROSSLER_BURNIN):
        x, y, z = _rk4_3d(x, y, z, f, dt)

    traj = []
    for _ in range(n_steps):
        x, y, z = _rk4_3d(x, y, z, f, dt)
        traj.append([x, y, z])

    return traj


# ── Logistic map with delay embedding ────────────────────────────────────────

def _generate_logistic_raw(n_steps, D, seed):
    """
    Logistic map:
        x_{n+1} = r · x_n · (1 − x_n)   r=3.9 (fully chaotic)

    Lifted to D dimensions by time-delay (Takens) embedding:
        state_k = [x_k, x_{k-1}, ..., x_{k-(D-1)}]

    This preserves the topology of the underlying 1-D chaos while
    producing a D-dimensional trajectory.
    """
    import numpy as np

    rng  = np.random.default_rng(seed)
    x    = float(rng.uniform(0.1, 0.9))
    r    = LOGISTIC_R

    total   = n_steps + D - 1 + LOGISTIC_BURNIN
    samples = []
    for _ in range(total):
        x = r * x * (1.0 - x)
        samples.append(x)

    samples = samples[LOGISTIC_BURNIN:]   # length: n_steps + D - 1

    traj = []
    for k in range(n_steps):
        # Ascending time order within each state vector
        point = [samples[k + (D - 1 - d)] for d in range(D)]
        traj.append(point)

    return traj


# ── Dimension adjustment ─────────────────────────────────────────────────────

def _adjust_dims(traj_list, D):
    """
    Given a list of N points in d_raw dimensions, return a numpy array
    of shape (N, D).

    d_raw > D : use first D coordinates
    d_raw < D : extend with smooth deterministic nonlinear combinations
                sin(π·a + 0.5π·b) for pairs of existing dims — bounded,
                smooth, and deterministic.
    """
    import numpy as np
    arr = np.array(traj_list, dtype="float64")   # (N, d_raw)
    n, d_raw = arr.shape

    if d_raw == D:
        return arr
    if d_raw > D:
        return arr[:, :D]

    # Extend
    extra = []
    for i in range(D - d_raw):
        j = i % d_raw
        k = (i + 1) % d_raw
        col = np.sin(np.pi * arr[:, j] + 0.5 * np.pi * arr[:, k])
        extra.append(col.reshape(-1, 1))

    return np.hstack([arr] + extra)


def _normalize_traj_01(traj):
    """Min-max normalise each dimension of the trajectory to [0, 1]."""
    import numpy as np
    out = traj.copy()
    for d in range(out.shape[1]):
        lo   = out[:, d].min()
        hi   = out[:, d].max()
        span = max(hi - lo, 1e-8)
        out[:, d] = (out[:, d] - lo) / span
    return out


def generate_trajectory(attractor, D, n_steps, seed):
    """
    Main entry point for trajectory generation.

    Returns numpy array of shape (n_steps, D), normalised to [0, 1].
    """
    import numpy as np

    if attractor == "Hopf":
        raw = _generate_hopf_raw(n_steps)
    elif attractor == "Lorenz":
        raw = _generate_lorenz_raw(n_steps)
    elif attractor == "Rossler":
        raw = _generate_rossler_raw(n_steps)
    else:   # LogisticMap
        raw = _generate_logistic_raw(n_steps, D, seed)
        arr = np.array(raw, dtype="float64")
        return _normalize_traj_01(arr)   # already D-dimensional

    arr = _adjust_dims(raw, D)
    return _normalize_traj_01(arr)


# ─────────────────────────────────────────────────────────────────────────────
# E — Trajectory → event mapping
# ─────────────────────────────────────────────────────────────────────────────

def map_to_events(traj, X_norm, n_output, tabu_len, temperature, seed,
                  dim_weights=None, velocity_weight=0.0, coupling=0.0,
                  return_trace=False):
    """
    Map n_output trajectory steps to event indices.

    Position distance uses the documented weighted RMS metric:
        d_pos = sqrt(sum_d(w[d] * delta[d]^2) / sum_d(w[d]))
    Because all normalized coordinates lie in [0,1], d_pos also lies in [0,1].
    This keeps it on the same scale as d_vel=(1-cosine)/2, so velocity_weight
    has the same meaning in 2D through 5D.

    Temperature > 0 uses the historical inverse-distance distribution, but in
    log space for numerical stability:
        p(i) proportional to exp(-log(distance_i + eps) / temperature)
    which is algebraically equivalent to (1/distance)^(1/temperature).
    """
    import numpy as np

    rng    = np.random.default_rng(seed)
    n_ev   = X_norm.shape[0]
    D      = X_norm.shape[1]
    n_traj = traj.shape[0]
    tabu   = deque(maxlen=tabu_len)
    plan   = []
    trace  = []

    # ---- Dimension weights ----
    if dim_weights is None or len(dim_weights) == 0:
        W = np.ones(D, dtype="float64")
    else:
        W = np.array(dim_weights[:D], dtype="float64")
        if len(W) < D:
            W = np.concatenate([W, np.ones(D - len(W))])
    W = np.where(np.isfinite(W), W, 0.0)
    W = np.maximum(W, 0.0)
    if float(W.sum()) <= 1e-12:
        W = np.ones(D, dtype="float64")
    W_sum = float(W.sum())

    prev_chosen = None

    for k in range(n_output):
        raw_pos = traj[k % n_traj]

        # ---- Feedback coupling: causal pull toward the previous event ----
        if coupling > 1e-6 and prev_chosen is not None:
            target = raw_pos + coupling * (X_norm[prev_chosen] - raw_pos)
        else:
            target = raw_pos.copy()

        # ---- Weighted position distance, normalized to [0,1] ----
        diff  = X_norm - target
        d_pos = np.sqrt(np.sum(W * (diff ** 2), axis=1) / W_sum)

        d_vel = None
        # ---- Velocity alignment (only from step 1 onwards) ----
        if velocity_weight > 1e-6 and k > 0 and prev_chosen is not None:
            v_traj = traj[k % n_traj] - traj[(k - 1) % n_traj]
            v_norm_scalar = float(np.linalg.norm(v_traj))

            if v_norm_scalar > 1e-8:
                ev_deltas   = X_norm - X_norm[prev_chosen]
                delta_norms = np.sqrt(np.sum(ev_deltas ** 2, axis=1))
                valid       = delta_norms > 1e-8
                cos_sim     = np.zeros(n_ev, dtype="float64")
                cos_sim[valid] = (np.dot(ev_deltas[valid], v_traj) /
                                  (delta_norms[valid] * v_norm_scalar))
                cos_sim     = np.clip(cos_sim, -1.0, 1.0)
                d_vel       = (1.0 - cos_sim) / 2.0
                dists       = ((1.0 - velocity_weight) * d_pos +
                               velocity_weight * d_vel)
            else:
                dists = d_pos
        else:
            dists = d_pos

        sorted_idx = list(np.argsort(dists))

        # ---- Tabu filter ----
        tabu_set   = set(tabu)
        candidates = [i for i in sorted_idx if i not in tabu_set]
        if not candidates:
            candidates = sorted_idx

        # ---- Deterministic or stochastic selection ----
        if temperature < 1e-6:
            chosen = int(candidates[0])
        else:
            K       = max(1, min(int(temperature * 20) + 1, len(candidates)))
            top_idx = np.asarray(candidates[:K], dtype=int)
            if K == 1:
                chosen = int(top_idx[0])
            else:
                top_dist = np.asarray(dists[top_idx], dtype="float64")
                log_w    = -np.log(top_dist + 1e-7) / max(temperature, 1e-6)
                log_w   -= float(np.max(log_w))
                probs    = np.exp(log_w)
                p_sum    = float(np.sum(probs))
                if (not np.isfinite(p_sum)) or p_sum <= 0.0:
                    chosen = int(top_idx[0])
                else:
                    probs  /= p_sum
                    chosen  = int(rng.choice(top_idx, p=probs))

        if return_trace:
            dv = float(d_vel[chosen]) if d_vel is not None else float("nan")
            trace.append({
                "target": np.asarray(target, dtype="float64").copy(),
                "raw_pos": np.asarray(raw_pos, dtype="float64").copy(),
                "d_pos": float(d_pos[chosen]),
                "d_vel": dv,
                "d_final": float(dists[chosen]),
            })

        plan.append(chosen)
        tabu.append(chosen)
        prev_chosen = chosen

    return (plan, trace) if return_trace else plan


# ─────────────────────────────────────────────────────────────────────────────
# F — Output
# ─────────────────────────────────────────────────────────────────────────────

def write_plan(path, plan, events):
    """Write plan CSV using original Praat event IDs (0-based in the file).

    Internal plan indices address the filtered Python event list.  Writing the
    original source ID prevents an index shift if a CSV row is filtered out.
    """
    with open(path, "w") as f:
        f.write("step,event_index,gain\n")
        for i, idx in enumerate(plan):
            source_idx_0 = max(0, int(events[idx]["idx"]) - 1)
            f.write("%d,%d,1.0000\n" % (i + 1, source_idx_0))


def write_stats(path, events, plan, attractor, state_dims,
                n_output, tabu_len, temperature, seed,
                mean_speed, col_names,
                weight_preset="Uniform", velocity_weight=0.0, coupling=0.0,
                X_norm=None, traj=None, resolved_weights=None, mapping_trace=None,
                analysis_channel=1):
    """Write key=value stats file for Praat info panel."""
    import numpy as np

    n_ev  = len(events)
    n_out = len(plan)

    # Unique events used + repetition rate
    seen   = set()
    repits = 0
    for idx in plan:
        if idx in seen:
            repits += 1
        seen.add(idx)
    rep_rate = repits / max(1, n_out)

    # ── 2D projection for visualization ───────────────────────────────
    # Show the two most strongly weighted ACTIVE dimensions.  Uniform weights
    # naturally fall back to the first two dimensions.  This makes presets such
    # as Transient or Energy visible instead of always plotting centroid/flatness.
    ev_x, ev_y, tr_x, tr_y = [], [], [], []
    proj0, proj1 = 0, 1 if len(col_names) > 1 else 0
    if resolved_weights is not None and len(resolved_weights) == len(col_names):
        order = sorted(range(len(col_names)),
                       key=lambda i: (-float(resolved_weights[i]), i))
        if order:
            proj0 = order[0]
        if len(order) > 1:
            proj1 = order[1]
    if X_norm is not None and traj is not None:
        ev_x = X_norm[:, proj0].tolist()
        ev_y = X_norm[:, proj1].tolist() if X_norm.shape[1] > 1 else [0.0] * len(ev_x)
        tr_x = traj[:, proj0].tolist()
        tr_y = traj[:, proj1].tolist() if traj.shape[1] > 1 else [0.0] * len(tr_x)

    with open(path, "w") as f:
        f.write("attractor=%s\n"            % attractor)
        f.write("state_dims=%d\n"           % state_dims)
        f.write("state_features=%s\n"       % "+".join(col_names))
        f.write("n_source_events=%d\n"      % n_ev)
        f.write("n_output_events=%d\n"      % n_out)
        f.write("unique_events_used=%d\n"   % len(seen))
        f.write("repetition_rate=%.4f\n"    % rep_rate)
        f.write("mean_trajectory_speed=%.6f\n" % mean_speed)
        f.write("tabu_length=%d\n"          % tabu_len)
        f.write("temperature=%.4f\n"        % temperature)
        f.write("seed=%d\n"                 % seed)
        f.write("weight_preset=%s\n"        % weight_preset)
        f.write("velocity_weight=%.4f\n"    % velocity_weight)
        f.write("coupling=%.4f\n"           % coupling)
        f.write("analysis_channel=%d\n"    % analysis_channel)
        if mapping_trace:
            pos_vals = [r["d_pos"] for r in mapping_trace]
            fin_vals = [r["d_final"] for r in mapping_trace]
            vel_vals = [r["d_vel"] for r in mapping_trace if np.isfinite(r["d_vel"])]
            f.write("mean_mapping_distance=%.6f\n" % float(np.mean(pos_vals)))
            f.write("mean_final_distance=%.6f\n"   % float(np.mean(fin_vals)))
            if vel_vals:
                mean_align = float(np.mean([1.0 - 2.0 * v for v in vel_vals]))
                f.write("mean_velocity_alignment=%.6f\n" % mean_align)
            else:
                f.write("mean_velocity_alignment=na\n")

        # ── Trajectory + event positions ──────────────────────────────
        # Axis labels for the weighted 2D projection
        ax0 = col_names[proj0] if len(col_names) > 0 else "dim0"
        ax1 = col_names[proj1] if len(col_names) > 1 else "dim1"
        f.write("proj_axis0=%s\n" % ax0)
        f.write("proj_axis1=%s\n" % ax1)

        # Evenly sample large clouds/paths so the visualization represents the
        # WHOLE run instead of silently truncating to its first 200 points.
        if len(ev_x) > 0:
            ev_sampled = np.linspace(0, len(ev_x) - 1,
                                     min(len(ev_x), 200), dtype=int).tolist()
            ev_sampled = list(dict.fromkeys(ev_sampled))
        else:
            ev_sampled = []
        f.write("n_ev_pts=%d\n" % len(ev_sampled))
        for oi, si in enumerate(ev_sampled):
            f.write("pev_%d=%.4f,%.4f\n" % (oi, ev_x[si], ev_y[si]))

        n_tr = len(tr_x)
        if n_tr > 0:
            sampled = np.linspace(0, n_tr - 1, min(n_tr, 200), dtype=int).tolist()
            sampled = list(dict.fromkeys(sampled))
        else:
            sampled = []
        f.write("n_traj_pts=%d\n" % len(sampled))
        for ti, si in enumerate(sampled):
            f.write("ptr_%d=%.4f,%.4f\n" % (ti, tr_x[si], tr_y[si]))

        # ── Selected-event compositional path ──────────────────────────
        # The 2D projections above show the source corpus (grey) and the
        # attractor trajectory (blue) but never the actual sequence of
        # DECISIONS: trajectory point -> selected event -> next selected
        # event. That sequence is exactly what makes this a "compositional
        # controller" rather than a static scatter, so we sample it here
        # in plan order (order-preserving, not sorted by feature value)
        # and let Praat draw it as its own path.
        if X_norm is not None and len(plan) > 0:
            n_plan_pts = len(plan)
            sel_steps  = np.linspace(0, n_plan_pts - 1,
                                     min(n_plan_pts, 200), dtype=int).tolist()
            sel_steps  = list(dict.fromkeys(sel_steps))
            sel_x = [float(X_norm[plan[i], proj0]) for i in sel_steps]
            sel_y = [float(X_norm[plan[i], proj1]) if X_norm.shape[1] > 1 else 0.0
                     for i in sel_steps]
        else:
            sel_x, sel_y = [], []

        n_sel = len(sel_x)
        f.write("n_sel_pts=%d\n" % n_sel)
        for i in range(n_sel):
            f.write("psel_%d=%.4f,%.4f\n" % (i, sel_x[i], sel_y[i]))


def write_debug_log(path, events, plan, traj, X_norm, mapping_trace=None):
    """Verbose log of the ACTUAL mapping target and distances."""
    import numpy as np
    with open(path, "w") as f:
        f.write("step,event_index,event_start,event_end,"
                "position_distance,velocity_distance,final_distance,target_x0,target_x1\n")
        n_traj = traj.shape[0]
        for i, idx in enumerate(plan):
            ev = events[idx]
            if mapping_trace is not None and i < len(mapping_trace):
                r = mapping_trace[i]
                target = r["target"]
                dp, dv, df = r["d_pos"], r["d_vel"], r["d_final"]
            else:
                target = traj[i % n_traj]
                dp = float(np.sqrt(np.mean((X_norm[idx] - target) ** 2)))
                dv, df = float("nan"), dp
            f.write("%d,%d,%.4f,%.4f,%.6f,%s,%.6f,%.4f,%.4f\n" % (
                i + 1, int(events[idx]["idx"]), ev["start"], ev["end"], dp,
                ("%.6f" % dv) if np.isfinite(dv) else "na", df,
                float(target[0]),
                float(target[1]) if len(target) > 1 else 0.0))


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Phase-Space Composition Engine — Praat AudioTools")

    parser.add_argument("--wav",          required=True,
                        help="Input WAV path")
    parser.add_argument("--events",       required=True,
                        help="Event boundary CSV (index,start_s,end_s,duration_s)")
    parser.add_argument("--out_plan",     required=True,
                        help="Output plan CSV path")
    parser.add_argument("--out_stats",    required=True,
                        help="Output stats TXT path (key=value per line)")
    parser.add_argument("--attractor",    default="Lorenz",
                        choices=["Hopf", "Lorenz", "Rossler", "LogisticMap"])
    parser.add_argument("--state_dims",   type=int, default=3,
                        choices=[2, 3, 4, 5])
    parser.add_argument("--n_output",     type=int,   default=300,
                        help="Number of output events in plan")
    parser.add_argument("--tabu",         type=int,   default=12,
                        help="Anti-repetition window length")
    parser.add_argument("--temperature",  type=float, default=0.15,
                        help="Stochastic neighbour choice [0..1]")
    parser.add_argument("--seed",         type=int,   default=1234)
    parser.add_argument("--min_event_dur_ms", type=float, default=30.0,
                        help="Minimum event duration in milliseconds")
    parser.add_argument("--analysis_channel", type=int, default=0,
                        help="1-based representative channel; 0=auto strongest RMS")
    parser.add_argument("--dim_weights",    type=str, default="",
                        help="Comma-separated distance weights, always given "
                             "in canonical order (centroid,flatness,entropy,"
                             "flux,rms) regardless of --state_dims. Resolved "
                             "onto the active feature columns by name, not "
                             "position. Missing values default to 1.0.")
    parser.add_argument("--weight_preset_name", type=str, default="",
                        help="Human-readable name of the weight preset "
                             "(e.g. 'Brightness'), for display in stats.txt "
                             "only. Falls back to the raw --dim_weights "
                             "string, then 'Uniform', if omitted.")
    parser.add_argument("--velocity_weight", type=float, default=0.0,
                        help="0=position only, 1=direction only, "
                             "intermediate blends both [0..1]")
    parser.add_argument("--coupling",        type=float, default=0.0,
                        help="Feedback strength: events bend the attractor "
                             "trajectory toward selected corpus states [0..1]")
    parser.add_argument("--debug",        action="store_true",
                        help="Write verbose debug log")

    args = parser.parse_args()

    # ── Clamp parameters ──────────────────────────────────────────────────
    args.n_output       = max(10, min(2000, args.n_output))
    args.tabu           = max(0,  min(500,  args.tabu))
    args.temperature    = max(0.0, min(1.0, args.temperature))
    args.state_dims     = max(2, min(5, args.state_dims))
    args.velocity_weight = max(0.0, min(1.0, args.velocity_weight))
    args.coupling        = max(0.0, min(1.0, args.coupling))

    # Parse dim_weights string → list of floats (length ≥ 1)
    if args.dim_weights.strip():
        try:
            dim_weights_list = [float(x) for x in args.dim_weights.split(",")
                                if x.strip()]
        except ValueError:
            dim_weights_list = []
    else:
        dim_weights_list = []

    check_deps()
    import numpy as np

    # ── A: Load ────────────────────────────────────────────────────────────
    print("  [Py 1/5] Loading audio + events...")

    if not os.path.isfile(args.wav):
        print("ERROR: WAV not found: %s" % args.wav, file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(args.events):
        print("ERROR: Events CSV not found: %s" % args.events, file=sys.stderr)
        sys.exit(1)

    audio, sr = load_audio(args.wav)
    try:
        analysis_ch = choose_analysis_channel(audio, args.analysis_channel)
    except ValueError as e:
        print("ERROR: %s" % e, file=sys.stderr)
        sys.exit(1)
    min_dur_s = args.min_event_dur_ms / 1000.0
    events    = load_events(args.events, min_dur_s)

    n_ev = len(events)
    print("    Audio: %.2fs  SR=%d  Ch=%d  |  Events: %d (≥%.0f ms)" % (
        audio.shape[0] / sr, sr, audio.shape[1], n_ev, args.min_event_dur_ms))
    print("    Analysis channel: %d (representative real channel)" % (analysis_ch + 1))

    if n_ev < 3:
        print("ERROR: Need at least 3 valid events (found %d)." % n_ev,
              file=sys.stderr)
        print("  Tip: lower --min_event_dur_ms or adjust segmentation "
              "thresholds in Praat.", file=sys.stderr)
        sys.exit(1)

    # Clamp tabu so it is always < n_ev (otherwise tabu empties the pool)
    tabu_eff = min(args.tabu, max(0, n_ev - 1))
    if tabu_eff != args.tabu:
        print("    Tabu clamped to %d (= n_events - 1)" % tabu_eff)

    # ── B: Feature extraction ──────────────────────────────────────────────
    print("  [Py 2/5] Extracting %dD features per event..." % args.state_dims)

    feats        = extract_features(audio, events, sr, analysis_ch=analysis_ch)
    X_raw, names = build_state_matrix(feats, args.state_dims)
    X_norm       = robust_normalize_01(X_raw)

    # Resolve the canonical-order weight vector onto this state_dims'
    # actual feature columns, BY NAME. Previously this was a positional
    # truncation of dim_weights_list, which silently mismatched weights
    # to features whenever state_dims < 5 (e.g. "Transient focus"'s flux
    # weight landing on entropy's old slot in 3D, or "Energy focus"
    # applying to a column that doesn't exist below 5D).
    resolved_weights = resolve_dim_weights(dim_weights_list, names)
    if dim_weights_list and "rms" not in names and \
            any(abs(w - 1.0) > 1e-9 for w in dim_weights_list[4:5]):
        print("    NOTE: weight preset targets 'rms', which is not part "
              "of the %dD state space (%s) — that weight has no effect "
              "here." % (args.state_dims, "+".join(names)))

    print("    X shape: %s  |  features: %s" % (
        str(X_norm.shape), ", ".join(names)))
    print("    Centroid range: %.1f – %.1f Hz" % (
        float(feats["centroid"].min()), float(feats["centroid"].max())))
    print("    Flatness range: %.3f – %.3f" % (
        float(feats["flatness"].min()), float(feats["flatness"].max())))

    # ── C: Trajectory generation ───────────────────────────────────────────
    print("  [Py 3/5] Generating %s trajectory (%d steps, %dD)..." % (
        args.attractor, args.n_output, args.state_dims))

    np.random.seed(args.seed)
    traj = generate_trajectory(args.attractor, args.state_dims,
                               args.n_output, args.seed)

    # Trajectory speed (mean step-to-step distance)
    speeds     = np.sqrt(np.sum(np.diff(traj, axis=0) ** 2, axis=1))
    mean_speed = float(np.mean(speeds))

    print("    Traj range: [%.4f, %.4f]  |  mean speed: %.4f" % (
        float(traj.min()), float(traj.max()), mean_speed))

    # ── D: Map trajectory → events ─────────────────────────────────────────
    print("  [Py 4/5] Mapping trajectory → events "
          "(tabu=%d, temp=%.3f, vel=%.2f, cpl=%.2f)..." % (
          tabu_eff, args.temperature, args.velocity_weight, args.coupling))

    plan, mapping_trace = map_to_events(
                         traj, X_norm, args.n_output,
                         tabu_eff, args.temperature, args.seed,
                         dim_weights=resolved_weights,
                         velocity_weight=args.velocity_weight,
                         coupling=args.coupling, return_trace=True)

    used = set(plan)
    rep_rate = sum(1 for i, idx in enumerate(plan)
                   if idx in set(plan[:i])) / max(1, len(plan))

    print("    Plan: %d steps  |  unique events: %d / %d  |  rep rate: %.3f" % (
        len(plan), len(used), n_ev, rep_rate))

    # ── E: Write outputs ────────────────────────────────────────────────────
    print("  [Py 5/5] Writing plan + stats...")

    write_plan(args.out_plan, plan, events)
    weight_preset_display = (args.weight_preset_name.strip()
                              or args.dim_weights.strip()
                              or "Uniform")
    write_stats(args.out_stats, events, plan, args.attractor,
                args.state_dims, args.n_output, tabu_eff,
                args.temperature, args.seed, mean_speed, names,
                weight_preset=weight_preset_display,
                velocity_weight=args.velocity_weight,
                coupling=args.coupling,
                X_norm=X_norm, traj=traj,
                resolved_weights=resolved_weights, mapping_trace=mapping_trace,
                analysis_channel=analysis_ch + 1)

    if args.debug:
        if args.out_stats.endswith("_stats.txt"):
            debug_path = args.out_stats[:-10] + "_debug.csv"
        else:
            debug_path = os.path.splitext(args.out_stats)[0] + "_debug.csv"
        write_debug_log(debug_path, events, plan, traj, X_norm, mapping_trace)
        print("    Debug log → %s" % debug_path)

    print("OK: plan → %s" % args.out_plan)


if __name__ == "__main__":
    main()
