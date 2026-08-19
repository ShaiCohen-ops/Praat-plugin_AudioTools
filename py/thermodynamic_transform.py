"""
thermodynamic_transform.py — Thermodynamic event relocation engine
Version: 2.3

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python thermodynamic_transform.py input.wav features.csv output.wav
        regimes.txt stats.txt
        thermo_intensity memory convection preserve_duration
        ai_mode ai_strength seed hop_sec

Architecture:
    Stage 1 — Load features + compute spectral descriptors
    Stage 2 — Build thermodynamic fields + AI state discovery
    Stage 3 — Event segmentation (200 ms – 3 s musically coherent segments)
    Stage 4 — Deterministic regime-dependent event relocation
    Stage 5 — Time-domain reconstruction with click-free splicing

No spectral smoothing, phase randomization, STFT transforms, or time stretching.
All operations are on complete audio events in the time domain.

Changelog v2.3 (2026):
    - CORRECTNESS: exact time-grid alignment for spectral features; silent
      frames no longer masquerade as maximally flat/noisy spectra.
    - MULTICHANNEL: spectral analysis uses the strongest-RMS real channel.
    - CONTROL INVARIANTS: AI_strength=0 disables the direct AI regime vote;
      Thermo_intensity=0 is identity unless Convection is explicitly active.
      The default AI_strength=0.5 preserves the old confidence threshold.
    - RELOCATION: Gas now actually moves through the global event order, rather
      than only permuting identities inside pre-existing Gas slots. Plasma
      anchoring is continuously interpolated by intensity.
    - RECONSTRUCTION: contiguous source neighbours are joined without a
      needless fade-to-zero/crossfade; only discontinuous relocations crossfade.
      Removed post-splice median click rewriting; equal-power splicing is the
      sole anti-click mechanism. The final event always includes the true audio
      tail instead of replacing the last fractional hop with silence.
    - OUTPUT: FLOAT WAV; more accurate relocation/crossfade diagnostics.
    - ROBUSTNESS: Mode C uses the actual hop_sec rather than hard-coded 10 ms,
      and AI cluster/component counts are safe for short inputs.

Changelog v2.2 (2026):
    - SPEED: ai_mode_b (predictive instability) replaced its per-frame
      Ridge.predict() loop with a single batched prediction.  On
      typical inputs (1000-3000 frames) this saves ~150ms of sklearn
      call overhead per Mode B run.  Output is mathematically identical
      to v2.1 — same Ridge fit, same per-frame predictions, just
      computed in one matmul instead of N.
    - SPEED: Vectorised the spectral-rolloff per-frame loop in
      compute_spectral_features().  Replaced np.searchsorted-in-loop
      with np.argmax(cumsum >= threshold[None, :], axis=0).
      Mathematically equivalent for monotonically non-decreasing
      cumsum (which it always is here).
    - SPEED: Vectorised the pitch-derivative loop in construct_fields()
      and the pitch-discontinuity loop in compute_novelty_curve().
      Both were ~1000-iteration Python loops over scalar conditions.
      Output is identical (verified at numpy float64 precision).
"""

import sys
import os
import math

# Windows/Praat console safety: status text must never abort DSP.
try:
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
except Exception:
    pass

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
REGIME_CRYSTAL = 0
REGIME_FLUID = 1
REGIME_GAS = 2
REGIME_PLASMA = 3
REGIME_NAMES = ["Crystal", "Fluid", "Gas", "Plasma"]

# Event duration constraints (seconds)
EVENT_MIN_DUR = 0.200
EVENT_MAX_DUR = 3.000

# Energy budget
H_MAX = 2.0
H_HEAT_RATES = [0.002, 0.005, 0.010, 0.020]
H_COOL_BASE = 0.015

# Crossfade for click prevention (seconds)
XFADE_SEC = 0.008  # 8 ms


def check_dependencies():
    """Verify required packages are installed."""
    missing = []
    for pkg in ["numpy", "soundfile", "scipy", "sklearn"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg if pkg != "sklearn" else "scikit-learn")
    if missing:
        print("ERROR: Missing Python packages: " + ", ".join(missing),
              file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing),
              file=sys.stderr)
        sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════
# Feature Loading & Spectral Analysis
# ═══════════════════════════════════════════════════════════════════════════

def load_praat_features(csv_path):
    """Load Praat-exported feature CSV into a dict of arrays."""
    import numpy as np

    data = {}
    with open(csv_path, "r") as f:
        header = f.readline().strip().split(",")
        cols = {h.strip(): [] for h in header}
        for line in f:
            vals = line.strip().split(",")
            if len(vals) != len(header):
                continue
            for h, v in zip(header, vals):
                h = h.strip()
                try:
                    cols[h].append(float(v))
                except ValueError:
                    cols[h].append(0.0)
    for k in cols:
        data[k] = np.array(cols[k], dtype=np.float64)
    return data


def compute_spectral_features(audio, sr, times):
    """
    Compute spectral descriptors aligned exactly to the Praat time grid.

    v2.3: scipy.signal.stft with boundary="zeros" is centered on times
    0, hop, 2*hop, ... while Praat samples at half-hop centers
    (e.g. 5, 15, 25 ms for a 10 ms grid).  The old code simply took the
    first N STFT frames, introducing a systematic half-hop offset.  We now
    linearly interpolate magnitudes to the requested Praat times.

    Silent/near-silent frames are treated as featureless (flatness=0,
    centroid/bandwidth/rolloff=0).  Flatness of digital silence is undefined;
    flooring every FFT bin to the same epsilon makes it spuriously equal to 1.
    """
    import numpy as np
    from scipy.signal import stft as scipy_stft

    n_fft = 2048
    half = n_fft // 2 + 1
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sr)
    n_frames = len(times)

    if n_frames > 1:
        hop_samples = max(1, int(round((times[1] - times[0]) * sr)))
    else:
        hop_samples = n_fft // 4
    hop_samples = min(hop_samples, n_fft - 1)

    t_stft, _, Zxx = None, None, None
    f_stft, t_stft, Zxx = scipy_stft(
        audio, fs=sr, window="hann", nperseg=n_fft,
        noverlap=n_fft - hop_samples, nfft=n_fft,
        boundary="zeros", padded=True)
    mag_all = np.abs(Zxx)

    # Interpolate the entire magnitude spectrum to exact Praat frame times.
    if mag_all.shape[1] == 1:
        mag = np.repeat(mag_all, n_frames, axis=1)
    else:
        t_req = np.asarray(times, dtype=np.float64)
        hi = np.searchsorted(t_stft, t_req, side="left")
        hi = np.clip(hi, 1, len(t_stft) - 1)
        lo = hi - 1
        den = np.maximum(t_stft[hi] - t_stft[lo], 1e-12)
        w = (t_req - t_stft[lo]) / den
        w = np.clip(w, 0.0, 1.0)
        mag = mag_all[:, lo] * (1.0 - w[None, :]) + mag_all[:, hi] * w[None, :]

    # Energy/activity gate.  Frames below -80 dB power relative to the
    # strongest frame are spectrally undefined, not white noise.
    power = np.sum(mag ** 2, axis=0)
    pmax = float(np.max(power)) if power.size else 0.0
    active = power > max(pmax * 1e-8, 1e-20)

    # Spectral flux on raw magnitudes preserves real onset/offset novelty.
    flux = np.zeros(n_frames)
    if n_frames > 1:
        diff = np.diff(mag, axis=1)
        flux[1:] = np.sqrt(np.mean(diff ** 2, axis=0))

    mag_safe = np.maximum(mag, 1e-20)
    log_mag = np.log(mag_safe)
    geo = np.exp(np.mean(log_mag, axis=0))
    ari = np.mean(mag, axis=0)
    flatness = np.zeros(n_frames)
    flatness[active] = geo[active] / (ari[active] + 1e-20)

    total = np.sum(mag, axis=0)
    centroid = np.zeros(n_frames)
    centroid[active] = (np.dot(freqs, mag[:, active]) /
                        (total[active] + 1e-20))

    bandwidth = np.zeros(n_frames)
    if np.any(active):
        dev = freqs[:, None] - centroid[None, active]
        bandwidth[active] = np.sqrt(
            np.sum(mag[:, active] * dev ** 2, axis=0) /
            (total[active] + 1e-20))

    cumsum = np.cumsum(mag, axis=0)
    threshold = 0.85 * cumsum[-1, :]
    mask = cumsum >= threshold[None, :]
    idx = np.argmax(mask, axis=0)
    idx = np.minimum(idx, len(freqs) - 1)
    rolloff = freqs[idx]
    rolloff[~active] = 0.0

    n_bands = 8
    band_edges = np.linspace(0, half, n_bands + 1, dtype=int)
    band_energy = np.zeros((n_frames, n_bands))
    for b in range(n_bands):
        band_energy[:, b] = np.mean(
            mag[band_edges[b]:band_edges[b + 1], :] ** 2, axis=0)
    band_energy[~active, :] = 0.0

    return {
        "flatness": flatness,
        "flux": flux,
        "centroid": centroid,
        "bandwidth": bandwidth,
        "rolloff": rolloff,
        "band_energy": band_energy,
        "active": active.astype(np.float64),
    }


def strongest_rms_channel(audio):
    """Return (mono_analysis_signal, zero_based_channel_index)."""
    import numpy as np
    if audio.ndim == 1:
        return audio, 0
    rms = np.sqrt(np.mean(np.asarray(audio, dtype=np.float64) ** 2, axis=0))
    idx = int(np.argmax(rms))
    return audio[:, idx], idx


def merge_and_normalize(praat_feats, spec_feats):
    """Merge Praat + spectral features into unified robust-scaled matrix X(t)."""
    import numpy as np
    from sklearn.preprocessing import RobustScaler

    columns = []
    names = []

    for key in ["pitch", "hnr", "intensity", "f1", "f2", "f3", "f4"]:
        if key in praat_feats:
            col = np.nan_to_num(praat_feats[key].copy(), nan=0.0,
                                posinf=0.0, neginf=0.0)
            columns.append(col)
            names.append(key)

    for key in ["flatness", "flux", "centroid", "bandwidth", "rolloff"]:
        col = np.nan_to_num(spec_feats[key].copy(), nan=0.0,
                            posinf=0.0, neginf=0.0)
        columns.append(col)
        names.append(key)

    for b in range(spec_feats["band_energy"].shape[1]):
        col = np.nan_to_num(spec_feats["band_energy"][:, b].copy(),
                            nan=0.0, posinf=0.0, neginf=0.0)
        columns.append(col)
        names.append("band_%d" % b)

    X = np.column_stack(columns)
    scaler = RobustScaler()
    X_norm = scaler.fit_transform(X)
    X_norm = np.clip(X_norm, -5, 5)
    return X_norm, names


# ═══════════════════════════════════════════════════════════════════════════
# Thermodynamic Field Construction
# ═══════════════════════════════════════════════════════════════════════════

def gaussian_smooth(x, sigma_samples):
    """1-D Gaussian smoothing."""
    from scipy.ndimage import gaussian_filter1d
    if sigma_samples < 1:
        return x.copy()
    return gaussian_filter1d(x, sigma=sigma_samples, mode="nearest")


def multiscale_smooth(x, hop_sec):
    """Return micro (30 ms) and macro (2 s) smoothed versions."""
    micro_sigma = max(1, int(0.030 / hop_sec))
    macro_sigma = max(1, int(2.0 / hop_sec))
    return gaussian_smooth(x, micro_sigma), gaussian_smooth(x, macro_sigma)


def construct_fields(X_norm, praat_feats, spec_feats, hop_sec):
    """Construct baseline thermodynamic fields S0, O0, T0."""
    import numpy as np

    n = len(praat_feats["time"])

    flatness_n = _safe_normalize(spec_feats["flatness"])
    flux_n = _safe_normalize(spec_feats["flux"])

    hnr = np.nan_to_num(praat_feats["hnr"], nan=0.0)
    hnr_inv = 1.0 - _safe_normalize(np.clip(hnr, 0, 40))

    pitch = praat_feats["pitch"].copy()
    pitch[pitch <= 0] = np.nan
    # v2.2: vectorised pitch-derivative computation. Was a per-frame
    # Python loop with NaN-checks. Now pure numpy.
    dp = np.zeros(n)
    if n > 1:
        valid_pair = ~(np.isnan(pitch[1:]) | np.isnan(pitch[:-1]))
        # Use nan_to_num to make np.diff well-defined; valid_pair
        # masks out positions where either neighbour was NaN.
        safe_pitch = np.nan_to_num(pitch, nan=0.0)
        abs_diff = np.abs(np.diff(safe_pitch))
        denom = safe_pitch[1:] + 1e-6
        dp[1:] = np.where(valid_pair, abs_diff / denom, 0.0)
    dp = np.nan_to_num(dp)
    pitch_instab = _safe_normalize(dp)

    S0 = (0.30 * flatness_n + 0.25 * flux_n
          + 0.25 * hnr_inv + 0.20 * pitch_instab)
    S0 = np.clip(S0, 0, 1)

    hnr_n = _safe_normalize(np.clip(hnr, 0, 40))
    voiced = praat_feats.get("voiced", np.ones(n))
    pitch_stab = 1.0 - pitch_instab
    low_flat = 1.0 - flatness_n

    O0 = (0.35 * hnr_n + 0.25 * pitch_stab
          + 0.20 * low_flat + 0.20 * voiced)
    O0 = np.clip(O0, 0, 1)

    dS = np.gradient(S0)
    abs_dS_n = _safe_normalize(np.abs(dS))
    intensity = np.nan_to_num(praat_feats["intensity"], nan=0.0)
    dI_n = _safe_normalize(np.abs(np.gradient(intensity)))

    T0 = 0.40 * abs_dS_n + 0.35 * flux_n + 0.25 * dI_n
    T0 = np.clip(T0, 0, 1)

    S0_micro, S0_macro = multiscale_smooth(S0, hop_sec)
    T0_micro, T0_macro = multiscale_smooth(T0, hop_sec)
    S0 = 0.7 * S0_micro + 0.3 * S0_macro
    T0 = 0.6 * T0_micro + 0.4 * T0_macro

    return S0, O0, T0


def _safe_normalize(x):
    """Normalize to [0, 1] safely."""
    import numpy as np
    mn, mx = np.min(x), np.max(x)
    if mx - mn < 1e-12:
        return np.zeros_like(x)
    return (x - mn) / (mx - mn)


# ═══════════════════════════════════════════════════════════════════════════
# AI Modes
# ═══════════════════════════════════════════════════════════════════════════

def ai_mode_a(X_norm, S0, seed, n_clusters=6):
    """Mode A — Unsupervised state discovery via GMM."""
    import numpy as np
    from sklearn.mixture import GaussianMixture

    n_clusters = max(1, min(int(n_clusters), len(X_norm)))
    gmm = GaussianMixture(
        n_components=n_clusters, covariance_type="full",
        n_init=3, max_iter=200, random_state=seed)
    gmm.fit(X_norm)

    probs = gmm.predict_proba(X_norm)
    labels = gmm.predict(X_norm)
    C = np.max(probs, axis=1)

    cluster_entropy = np.zeros(n_clusters)
    for k in range(n_clusters):
        mask = labels == k
        if np.any(mask):
            cluster_entropy[k] = np.mean(S0[mask])

    sorted_clusters = np.argsort(cluster_entropy)
    cluster_to_regime = np.zeros(n_clusters, dtype=int)
    boundaries = np.linspace(0, n_clusters, 5, dtype=int)
    for i in range(4):
        for j in range(boundaries[i], boundaries[i + 1]):
            cluster_to_regime[sorted_clusters[j]] = i

    Z = cluster_to_regime[labels]
    return Z, C, n_clusters


def ai_mode_b(X_norm, S0, hop_sec, seed):
    """Mode B — Predictive instability via Ridge regression.

    v2.2: Batched the per-frame predict() call into a single
    matrix prediction. Output is mathematically identical to v2.1
    — same Ridge fit, same per-frame predictions, just computed in
    one matmul instead of N separate sklearn calls.
    """
    import numpy as np
    from sklearn.linear_model import Ridge

    n = len(S0)
    lookback = max(1, int(0.5 / hop_sec))
    lookahead = max(1, int(0.2 / hop_sec))

    # Build training matrix once.
    indices = np.arange(lookback, n - lookahead)
    if len(indices) == 0:
        # Too short for prediction — fall back to clustering on S0
        return ai_mode_a(X_norm, S0, seed)

    X_all = np.array([X_norm[i - lookback:i].flatten() for i in indices])
    y_all = S0[indices + lookahead]

    model = Ridge(alpha=1.0, random_state=seed)
    model.fit(X_all, y_all)

    # v2.2: single batched prediction over the same matrix.
    # Was looping model.predict() per frame which incurs ~50us
    # sklearn dispatch overhead per call; for n~3000 frames this
    # accumulates to ~150ms wasted in Python.
    preds = model.predict(X_all)

    S_pred = S0.copy()
    S_pred[indices] = preds
    S_pred = np.clip(S_pred, 0, 1)

    Z, C, n_cl = ai_mode_a(X_norm, S_pred, seed)
    return Z, C, n_cl


def ai_mode_c(X_norm, S0, seed, hop_sec):
    """Mode C — Learned entropy via PCA latent space."""
    import numpy as np
    from sklearn.decomposition import PCA
    from sklearn.mixture import GaussianMixture

    n_components = max(1, min(6, X_norm.shape[1], X_norm.shape[0]))
    pca = PCA(n_components=n_components, random_state=seed)
    L = pca.fit_transform(X_norm)

    window = max(3, int(round(0.3 / max(hop_sec, 1e-6))))
    # Vectorized rolling std via uniform_filter
    from scipy.ndimage import uniform_filter1d
    # Mean of per-component std in a sliding window:
    # Compute local variance via E[x²] - E[x]² for each component
    half_w = window // 2
    w_size = 2 * half_w + 1
    S_learned = np.zeros(len(L))
    for d in range(L.shape[1]):
        col = L[:, d]
        local_mean = uniform_filter1d(col, size=w_size, mode="nearest")
        local_sq = uniform_filter1d(col ** 2, size=w_size, mode="nearest")
        local_var = np.maximum(local_sq - local_mean ** 2, 0.0)
        S_learned += np.sqrt(local_var)
    S_learned /= L.shape[1]

    S_learned = _safe_normalize(S_learned)
    S_blend = 0.6 * S_learned + 0.4 * S0
    S_blend = np.clip(S_blend, 0, 1)

    n_clusters = max(1, min(6, len(L)))
    gmm = GaussianMixture(
        n_components=n_clusters, covariance_type="full",
        n_init=3, random_state=seed)
    gmm.fit(L)
    labels = gmm.predict(L)
    C = np.max(gmm.predict_proba(L), axis=1)

    cluster_entropy = np.zeros(n_clusters)
    for k in range(n_clusters):
        mask = labels == k
        if np.any(mask):
            cluster_entropy[k] = np.mean(S_blend[mask])

    sorted_clusters = np.argsort(cluster_entropy)
    cluster_to_regime = np.zeros(n_clusters, dtype=int)
    boundaries = np.linspace(0, n_clusters, 5, dtype=int)
    for i in range(4):
        for j in range(boundaries[i], boundaries[i + 1]):
            cluster_to_regime[sorted_clusters[j]] = i

    Z = cluster_to_regime[labels]
    return Z, C, n_clusters


def run_ai(X_norm, S0, O0, T0, ai_mode_str, ai_strength, seed, hop_sec):
    """Run the selected AI mode and blend with physics fields."""
    import numpy as np

    mode = ai_mode_str.upper()
    if mode == "B":
        Z_ai, C_ai, n_cl = ai_mode_b(X_norm, S0, hop_sec, seed)
    elif mode == "C":
        Z_ai, C_ai, n_cl = ai_mode_c(X_norm, S0, seed, hop_sec)
    else:
        Z_ai, C_ai, n_cl = ai_mode_a(X_norm, S0, seed)

    S_ai = np.array([
        {REGIME_CRYSTAL: 0.1, REGIME_FLUID: 0.4,
         REGIME_GAS: 0.7, REGIME_PLASMA: 0.95}[z]
        for z in Z_ai])
    O_ai = 1.0 - S_ai

    a = ai_strength
    S = (1 - a) * S0 + a * S_ai
    O = (1 - a) * O0 + a * O_ai
    T = T0 * (1 + 0.3 * a * np.abs(S - S0))
    T = np.clip(T, 0, 1)

    return S, T, O, Z_ai, C_ai, n_cl


# ═══════════════════════════════════════════════════════════════════════════
# Thermodynamic State Machine
# ═══════════════════════════════════════════════════════════════════════════

def thermodynamic_state_machine(S, T, O, Z_ai, C_ai,
                                memory_param, thermo_intensity, ai_strength, hop_sec):
    """State machine with hysteresis, memory, and energy budget."""
    import numpy as np

    n = len(S)
    Z = np.zeros(n, dtype=int)
    H = np.zeros(n)

    thresh_heat = np.array([0.20, 0.42, 0.65])
    thresh_cool = np.array([0.12, 0.30, 0.50])

    mem_window = max(3, int(memory_param * 2.0 / hop_sec))
    S_mem = gaussian_smooth(S, mem_window)

    current_regime = REGIME_CRYSTAL
    heat = 0.0
    dwell_time = 0.0

    for i in range(n):
        s = S_mem[i]
        ds = S_mem[i] - S_mem[max(0, i - 1)]
        heating = ds > 0

        min_dwell = memory_param * 0.15
        can_transition = dwell_time >= min_dwell

        th = thresh_heat if heating else thresh_cool
        if s < th[0]:
            target = REGIME_CRYSTAL
        elif s < th[1]:
            target = REGIME_FLUID
        elif s < th[2]:
            target = REGIME_GAS
        else:
            target = REGIME_PLASMA

        ai_vote = Z_ai[i]
        c = C_ai[i]
        # v2.3: direct regime vote is strength-weighted.  The 0.35
        # threshold preserves v2.2 exactly at the default ai_strength=0.5
        # (0.5*c > 0.35 <=> c > 0.7), while ai_strength=0 is truly off.
        vote_strength = float(np.clip(ai_strength, 0.0, 1.0)) * c
        if vote_strength > 0.35 and ai_vote != target:
            if ai_vote > target:
                target = min(target + 1, REGIME_PLASMA)
            elif ai_vote < target:
                target = max(target - 1, REGIME_CRYSTAL)

        if heat > H_MAX * 0.9:
            target = min(target, current_regime)
            if heat > H_MAX:
                target = max(REGIME_CRYSTAL, current_regime - 1)

        if target != current_regime and can_transition:
            if target > current_regime:
                current_regime += 1
            else:
                current_regime -= 1
            dwell_time = 0.0
        else:
            dwell_time += hop_sec

        Z[i] = current_regime

        heat_rate = H_HEAT_RATES[current_regime] * thermo_intensity
        cool_rate = H_COOL_BASE * (1.0 - s) * (1 + dwell_time * 0.5)
        heat = max(0, heat + heat_rate - cool_rate)
        H[i] = heat

    return Z, H


# ═══════════════════════════════════════════════════════════════════════════
# Stage 3 — Event Segmentation
# ═══════════════════════════════════════════════════════════════════════════

def compute_novelty_curve(praat_feats, spec_feats, S, T, hop_sec):
    """
    Combine multiple cues into a single novelty function for segmentation.

    Cues:
        1. Intensity derivative (onset energy)
        2. Pitch discontinuity (voiced/unvoiced boundaries, jumps)
        3. HNR drops (timbral transitions)
        4. Spectral flux peaks
        5. Entropy gradient magnitude (|dS/dt|)
    """
    import numpy as np

    n = len(praat_feats["time"])

    # 1. Intensity derivative (positive = onset)
    intensity = np.nan_to_num(praat_feats["intensity"], nan=0.0)
    dI = np.gradient(intensity)
    dI_pos = np.maximum(dI, 0)
    c_intensity = _safe_normalize(dI_pos)

    # 2. Pitch discontinuity
    # v2.2: vectorised the per-frame conditional. Original logic:
    #   - voiced[i] != voiced[i-1] → 1.0
    #   - else if both voiced and both pitched and ratio outside
    #     [0.87, 1.15] → min(1.0, |ratio - 1| * 3.0)
    #   - else → 0
    pitch = praat_feats["pitch"].copy()
    voiced = praat_feats.get("voiced", np.ones(n))
    pitch_disc = np.zeros(n)
    if n > 1:
        # Voicing boundary
        v_change = np.zeros(n, dtype=bool)
        v_change[1:] = voiced[1:] != voiced[:-1]

        # Both voiced AND both pitched
        both_voiced = np.zeros(n, dtype=bool)
        both_voiced[1:] = (voiced[1:] > 0) & (voiced[:-1] > 0)
        both_pitched = np.zeros(n, dtype=bool)
        both_pitched[1:] = (pitch[1:] > 0) & (pitch[:-1] > 0)
        pair_ok = both_voiced & both_pitched & (~v_change)

        # Ratio computation (safe — denominator clamped via 1e-6)
        # We compute for all positions; the where() below masks out
        # invalid pairs.
        ratio = np.ones(n)
        ratio[1:] = pitch[1:] / (pitch[:-1] + 1e-6)
        big_jump = (ratio > 1.15) | (ratio < 0.87)
        jump_value = np.minimum(1.0, np.abs(ratio - 1.0) * 3.0)

        # Compose: voicing change wins; else pitch jump on valid pair
        pitch_disc = np.where(v_change, 1.0,
            np.where(pair_ok & big_jump, jump_value, 0.0))
    c_pitch = _safe_normalize(pitch_disc)

    # 3. HNR drop (harmonic → noisy transition)
    hnr = np.nan_to_num(praat_feats["hnr"], nan=0.0)
    dHNR = -np.gradient(hnr)
    dHNR_pos = np.maximum(dHNR, 0)
    c_hnr = _safe_normalize(dHNR_pos)

    # 4. Spectral flux
    c_flux = _safe_normalize(spec_feats["flux"])

    # 5. Entropy gradient
    dS = np.abs(np.gradient(S))
    c_entropy = _safe_normalize(dS)

    # Weighted combination
    novelty = (0.30 * c_intensity
               + 0.20 * c_pitch
               + 0.15 * c_hnr
               + 0.20 * c_flux
               + 0.15 * c_entropy)

    # Light smoothing
    novelty = gaussian_smooth(novelty, max(1, int(0.015 / hop_sec)))

    return novelty


def segment_events(novelty, S, T, O, Z, sr, hop_sec, n_samples):
    """
    Segment audio into musically coherent events (200 ms – 3 s).

    Algorithm:
        1. Find novelty peaks as candidate boundaries
        2. Enforce minimum duration by merging short segments
        3. Enforce maximum duration by splitting at local novelty maxima
        4. Compute per-event thermodynamic statistics

    Returns list of event dicts.
    """
    import numpy as np
    from scipy.signal import find_peaks

    n_frames = len(novelty)
    min_frames = max(2, int(EVENT_MIN_DUR / hop_sec))
    max_frames = max(min_frames + 1, int(EVENT_MAX_DUR / hop_sec))

    # --- Find candidate boundaries from novelty peaks ---
    threshold = np.mean(novelty) + 0.5 * np.std(novelty)
    peaks, _ = find_peaks(novelty, height=threshold,
                          distance=min_frames // 2)

    # Always include start and end
    boundaries = sorted(set([0] + list(peaks) + [n_frames]))

    # --- Enforce minimum duration ---
    merged = [boundaries[0]]
    for b in boundaries[1:]:
        if b - merged[-1] >= min_frames:
            merged.append(b)
    if merged[-1] != n_frames:
        merged.append(n_frames)
    boundaries = merged

    # --- Enforce maximum duration ---
    final_bounds = [boundaries[0]]
    for i in range(1, len(boundaries)):
        seg_start = final_bounds[-1]
        seg_end = boundaries[i]
        seg_len = seg_end - seg_start

        if seg_len <= max_frames:
            final_bounds.append(seg_end)
        else:
            n_splits = int(math.ceil(seg_len / max_frames))
            chunk = seg_len // n_splits
            for s in range(1, n_splits):
                ideal = seg_start + s * chunk
                search_lo = max(seg_start + min_frames,
                                ideal - min_frames // 2)
                search_hi = min(seg_end - min_frames,
                                ideal + min_frames // 2)
                if search_lo < search_hi:
                    window = novelty[search_lo:search_hi]
                    best = search_lo + int(np.argmax(window))
                else:
                    best = ideal
                if best - final_bounds[-1] >= min_frames:
                    final_bounds.append(best)
            final_bounds.append(seg_end)

    final_bounds = sorted(set(final_bounds))

    # --- Build event list ---
    events = []
    dS = np.gradient(S)

    for i in range(len(final_bounds) - 1):
        f_start = final_bounds[i]
        f_end = final_bounds[i + 1]
        if f_end <= f_start:
            continue

        start_sample = int(f_start * hop_sec * sr)
        end_sample = int(f_end * hop_sec * sr)
        start_sample = max(0, min(start_sample, n_samples))
        if f_end >= n_frames:
            end_sample = n_samples
        end_sample = max(start_sample, min(end_sample, n_samples))

        if end_sample - start_sample < int(0.010 * sr):
            continue

        seg_S = S[f_start:f_end]
        seg_T = T[f_start:f_end]
        seg_O = O[f_start:f_end]
        seg_Z = Z[f_start:f_end]
        seg_dS = dS[f_start:f_end]

        regime_counts = [int(np.sum(seg_Z == r)) for r in range(4)]
        regime = int(np.argmax(regime_counts))

        events.append({
            "idx": len(events),
            "start_sample": start_sample,
            "end_sample": end_sample,
            "f_start": f_start,
            "f_end": f_end,
            "mean_entropy": float(np.mean(seg_S)),
            "mean_temperature": float(np.mean(seg_T)),
            "mean_order": float(np.mean(seg_O)),
            "regime": regime,
            "entropy_gradient": float(np.mean(seg_dS)),
            "duration": (end_sample - start_sample) / sr,
        })

    # Fallback: single event
    if not events:
        events.append({
            "idx": 0,
            "start_sample": 0,
            "end_sample": n_samples,
            "f_start": 0,
            "f_end": n_frames,
            "mean_entropy": float(np.mean(S)),
            "mean_temperature": float(np.mean(T)),
            "mean_order": float(np.mean(O)),
            "regime": int(np.argmax(
                [int(np.sum(Z == r)) for r in range(4)])),
            "entropy_gradient": 0.0,
            "duration": n_samples / sr,
        })

    return events


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Deterministic Event Relocation
# ═══════════════════════════════════════════════════════════════════════════

def relocate_events(events, thermo_intensity, convection):
    """
    Deterministic event relocation based on thermodynamic regime.

    Processing order: Crystal → Fluid → Gas → Plasma → Convection.
    Each pass modifies the running order list.

    Returns: new list of event indices (may differ in length from input
    if Crystal duplicates or Plasma evaporates events).
    """
    import numpy as np

    n = len(events)
    if n <= 1:
        return list(range(n))

    entropies = np.array([e["mean_entropy"] for e in events])
    gradients = np.array([e["entropy_gradient"] for e in events])
    regimes = np.array([e["regime"] for e in events])

    order = list(range(n))

    order = _apply_crystal_rule(order, events, entropies, regimes,
                                thermo_intensity)
    order = _apply_fluid_rule(order, events, entropies, regimes,
                              thermo_intensity)
    order = _apply_gas_rule(order, events, entropies, gradients, regimes,
                            thermo_intensity)
    order = _apply_plasma_rule(order, events, entropies, regimes,
                               thermo_intensity)

    if convection > 0.05:
        order = _apply_convection(order, events, entropies, convection)

    return order


def _apply_crystal_rule(order, events, entropies, regimes, intensity):
    """
    Crystal: keep original order.
    At intensity >= 0.3, duplicate the lowest-entropy Crystal event
    by inserting a copy right after the original.
    """
    import numpy as np

    crystal_mask = regimes == REGIME_CRYSTAL
    if not np.any(crystal_mask) or intensity < 0.3:
        return order

    crystal_indices = np.where(crystal_mask)[0]
    crystal_entropies = entropies[crystal_indices]
    lowest_idx = int(crystal_indices[np.argmin(crystal_entropies)])

    if lowest_idx in order:
        pos = order.index(lowest_idx)
        return order[:pos + 1] + [lowest_idx] + order[pos + 1:]

    return order


def _apply_fluid_rule(order, events, entropies, regimes, intensity):
    """
    Fluid: swap adjacent event pairs when both are Fluid and the
    first has higher entropy (bubble-sort pass → lower entropy leads).
    Displacement limited to +/-1 position.
    """
    if intensity < 0.1:
        return order

    threshold = 0.3 + 0.3 * (1.0 - intensity)
    result = list(order)
    i = 0
    while i < len(result) - 1:
        a_idx = result[i]
        b_idx = result[i + 1]

        if (a_idx < len(regimes) and b_idx < len(regimes)
                and regimes[a_idx] == REGIME_FLUID
                and regimes[b_idx] == REGIME_FLUID
                and entropies[a_idx] > threshold
                and entropies[a_idx] > entropies[b_idx]):
            result[i], result[i + 1] = result[i + 1], result[i]
            i += 2  # skip swapped pair
        else:
            i += 1

    return result


def _apply_gas_rule(order, events, entropies, gradients, regimes, intensity):
    """
    Gas: displace events through the GLOBAL order.

    v2.2 computed target positions but then wrote Gas identities back only into
    the original Gas slots, so Gas could not actually cross non-Gas material.
    v2.3 assigns every event a sortable position key; Gas keys are shifted by
    entropy, gradient direction and intensity.  At intensity=0 keys are the
    original integer positions exactly.
    """
    if intensity <= 0.0 or len(order) <= 1:
        return list(order)

    n_total = len(order)
    keyed = []
    for pos, idx in enumerate(order):
        key = float(pos)
        if idx < len(regimes) and regimes[idx] == REGIME_GAS:
            s = entropies[idx]
            direction = 1.0 if gradients[idx] >= 0 else -1.0
            key += intensity * s * direction * n_total * 0.4
        keyed.append((key, pos, idx))
    keyed.sort(key=lambda x: (x[0], x[1]))
    return [idx for _, _, idx in keyed]


def _apply_plasma_rule(order, events, entropies, regimes, intensity):
    """
    Plasma: evaporate high-entropy Plasma events, then pull survivors toward
    structural anchors.  Anchor movement is continuous in intensity; intensity
    0 is exact identity.
    """
    if intensity <= 0.0:
        return list(order)

    plasma_entries = [
        (pos, idx) for pos, idx in enumerate(order)
        if idx < len(regimes) and regimes[idx] == REGIME_PLASMA
    ]
    if not plasma_entries:
        return list(order)

    evap_fraction = intensity * 0.3
    n_plasma = len(plasma_entries)
    n_evap = max(0, int(n_plasma * evap_fraction))
    evap_set = set()
    if n_evap > 0:
        by_entropy = sorted(plasma_entries,
                            key=lambda x: entropies[x[1]], reverse=True)
        evap_set = set(x[1] for x in by_entropy[:n_evap])

    survivors = [idx for idx in order if idx not in evap_set]
    if not survivors:
        return survivors

    n = len(survivors)
    keyed = []
    for pos, idx in enumerate(survivors):
        key = float(pos)
        if idx < len(regimes) and regimes[idx] == REGIME_PLASMA:
            s = entropies[idx]
            if s < 0.4:
                anchor = 0.0
            elif s < 0.7:
                anchor = (n - 1) * 0.5
            else:
                anchor = float(n - 1)
            key = (1.0 - intensity) * pos + intensity * anchor
        keyed.append((key, pos, idx))
    keyed.sort(key=lambda x: (x[0], x[1]))
    return [idx for _, _, idx in keyed]


def _apply_convection(order, events, entropies, convection):
    """
    Convection: global re-sort bias.
    High entropy events rise toward the beginning.
    Low entropy events sink toward the end.
    Strength controlled by convection parameter [0, 1].
    """
    n = len(order)
    if n <= 1:
        return order

    keys = []
    for pos, idx in enumerate(order):
        original_pos = pos / max(1, n - 1)
        # High entropy → low key → rises to front
        entropy_rank = 1.0 - entropies[idx] if idx < len(entropies) else 0.5
        key = (1.0 - convection) * original_pos + convection * entropy_rank
        keys.append((key, idx))

    keys.sort(key=lambda x: x[0])
    return [idx for _, idx in keys]


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Time-Domain Reconstruction
# ═══════════════════════════════════════════════════════════════════════════

def extract_event_audio(audio, events):
    """Extract audio samples for each event as a list of arrays."""
    clips = []
    for ev in events:
        s = ev["start_sample"]
        e = ev["end_sample"]
        if audio.ndim == 1:
            clips.append(audio[s:e].copy())
        else:
            clips.append(audio[s:e, :].copy())
    return clips


def reconstruct(clips, order, events, sr, original_length, preserve_duration):
    """
    Concatenate relocated events with equal-power crossfades ONLY where the
    source is discontinuous.  Consecutive original neighbours are butt-joined
    sample-exactly, preserving intact runs instead of fading them unnecessarily.
    """
    import numpy as np

    if not order:
        if clips and clips[0].ndim > 1:
            return np.zeros((0, clips[0].shape[1]), dtype=np.float32), 0, 0
        return np.zeros(0, dtype=np.float32), 0, 0

    xfade_nom = max(4, int(XFADE_SEC * sr))
    relocated = [clips[idx].copy().astype(np.float32) for idx in order]

    # Determine per-transition overlap.  Forward-adjacent original events are
    # already sample-contiguous and need no crossfade.
    overlaps = []
    contiguous_joins = 0
    for i in range(len(order) - 1):
        a = order[i]
        b = order[i + 1]
        contiguous = (b == a + 1 and
                      events[a]["end_sample"] == events[b]["start_sample"])
        if contiguous:
            overlaps.append(0)
            contiguous_joins += 1
        else:
            ov = min(xfade_nom, len(relocated[i]) // 2, len(relocated[i + 1]) // 2)
            overlaps.append(max(0, ov))

    total = sum(len(c) for c in relocated) - sum(overlaps)
    multichannel = relocated[0].ndim > 1
    if multichannel:
        n_ch = relocated[0].shape[1]
        output = np.zeros((max(total, 0), n_ch), dtype=np.float32)
    else:
        output = np.zeros(max(total, 0), dtype=np.float32)

    write_pos = 0
    for ci, clip in enumerate(relocated):
        clip = clip.copy()
        prev_ov = overlaps[ci - 1] if ci > 0 else 0
        next_ov = overlaps[ci] if ci < len(overlaps) else 0

        if prev_ov > 0:
            ang = np.linspace(0.0, np.pi / 2.0, prev_ov, dtype=np.float32)
            fi = np.sin(ang)
            if multichannel:
                clip[:prev_ov, :] *= fi[:, None]
            else:
                clip[:prev_ov] *= fi
        if next_ov > 0:
            ang = np.linspace(0.0, np.pi / 2.0, next_ov, dtype=np.float32)
            fo = np.cos(ang)
            if multichannel:
                clip[-next_ov:, :] *= fo[:, None]
            else:
                clip[-next_ov:] *= fo

        end_pos = write_pos + len(clip)
        output[write_pos:end_pos] += clip
        if ci < len(relocated) - 1:
            write_pos = end_pos - next_ov
        else:
            write_pos = end_pos

    output = output[:write_pos]

    if preserve_duration:
        if len(output) > original_length:
            output = output[:original_length]
        elif len(output) < original_length:
            pad = original_length - len(output)
            if multichannel:
                output = np.pad(output, ((0, pad), (0, 0)))
            else:
                output = np.pad(output, (0, pad))

    peak = float(np.max(np.abs(output))) if output.size else 0.0
    if peak > 0.95:
        output = output * (0.95 / peak)

    n_crossfades = int(sum(1 for ov in overlaps if ov > 0))
    return output.astype(np.float32), n_crossfades, contiguous_joins


# ═══════════════════════════════════════════════════════════════════════════
# Output Files
# ═══════════════════════════════════════════════════════════════════════════

def write_regime_file(path, Z, hop_sec):
    """Write regime timeline for Praat visualization."""
    with open(path, "w") as f:
        f.write("hop_sec=%s\n" % hop_sec)
        for z in Z:
            f.write("%d\n" % z)


def write_stats_file(path, Z, S, T, ai_mode_str, n_clusters,
                     events, order, analysis_channel=1,
                     n_crossfades=0, contiguous_joins=0, output_duration=0.0):
    """Write summary statistics for Praat info panel."""
    import numpy as np

    n = len(Z)
    counts = [int(np.sum(Z == r)) for r in range(4)]
    pcts = [100.0 * c / n for c in counts]
    transitions = int(np.sum(np.diff(Z) != 0))

    n_events = len(events)
    n_relocated = sum(
        1 for idx in range(n_events)
        if idx in order and order.index(idx) != idx)
    n_evaporated = max(0, n_events - len(set(order)))
    n_duplicated = max(0, len(order) - len(set(order)))
    durations = [e["duration"] for e in events]

    with open(path, "w") as f:
        f.write("crystal_pct=%.1f\n" % pcts[0])
        f.write("fluid_pct=%.1f\n" % pcts[1])
        f.write("gas_pct=%.1f\n" % pcts[2])
        f.write("plasma_pct=%.1f\n" % pcts[3])
        f.write("transitions=%d\n" % transitions)
        f.write("mean_entropy=%.4f\n" % np.mean(S))
        f.write("peak_entropy=%.4f\n" % np.max(S))
        f.write("mean_temp=%.4f\n" % np.mean(T))
        f.write("ai_mode=%s\n" % ai_mode_str)
        f.write("clusters=%d\n" % n_clusters)
        f.write("n_events=%d\n" % n_events)
        f.write("n_relocated=%d\n" % n_relocated)
        f.write("n_evaporated=%d\n" % n_evaporated)
        f.write("n_duplicated=%d\n" % n_duplicated)
        f.write("analysis_channel=%d\n" % analysis_channel)
        f.write("crossfades=%d\n" % n_crossfades)
        f.write("contiguous_joins=%d\n" % contiguous_joins)
        f.write("output_duration=%.4f\n" % output_duration)
        f.write("min_event_dur=%.3f\n" % min(durations))
        f.write("max_event_dur=%.3f\n" % max(durations))
        f.write("mean_event_dur=%.3f\n" % float(np.mean(durations)))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) != 14:
        print("Usage: python thermodynamic_transform.py "
              "input.wav features.csv output.wav regimes.txt stats.txt "
              "thermo_intensity memory convection preserve_duration "
              "ai_mode ai_strength seed hop_sec",
              file=sys.stderr)
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav       = sys.argv[1]
    feat_csv     = sys.argv[2]
    out_wav      = sys.argv[3]
    regime_file  = sys.argv[4]
    stats_file   = sys.argv[5]
    thermo_int   = float(sys.argv[6])
    memory       = float(sys.argv[7])
    convection   = float(sys.argv[8])
    preserve_dur = int(float(sys.argv[9]))
    ai_mode_str  = sys.argv[10]
    ai_strength  = float(sys.argv[11])
    seed         = int(sys.argv[12])
    hop_sec      = float(sys.argv[13])

    thermo_int  = max(0, min(1, thermo_int))
    memory      = max(0, min(1, memory))
    convection  = max(0, min(1, convection))
    ai_strength = max(0, min(1, ai_strength))

    np.random.seed(seed)

    if not os.path.isfile(in_wav):
        print("ERROR: input not found: %s" % in_wav, file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(feat_csv):
        print("ERROR: feature CSV not found: %s" % feat_csv,
              file=sys.stderr)
        sys.exit(1)

    # ---- Load ----
    print("  [Py 1/6] Loading audio + features...")
    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    praat_feats = load_praat_features(feat_csv)
    times = praat_feats["time"]
    n_frames_feat = len(times)
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]

    print("    Audio: %.2fs  SR=%d  Shape=%s" % (
        n_samples / sr, sr, audio.shape))
    print("    Features: %d frames at %.0f ms hop" % (
        n_frames_feat, hop_sec * 1000))

    # ---- Spectral features (for field construction only — no STFT output) ----
    print("  [Py 2/6] Computing spectral features...")
    audio_mono, analysis_ch0 = strongest_rms_channel(audio)
    print("    Analysis channel: %d" % (analysis_ch0 + 1))
    spec_feats = compute_spectral_features(
        audio_mono.astype(np.float64), sr, times)

    # ---- Thermodynamic fields + AI ----
    print("  [Py 3/6] Building thermodynamic fields + AI analysis...")
    X_norm, feat_names = merge_and_normalize(praat_feats, spec_feats)
    S0, O0, T0 = construct_fields(X_norm, praat_feats, spec_feats, hop_sec)

    S, T, O, Z_ai, C_ai, n_cl = run_ai(
        X_norm, S0, O0, T0, ai_mode_str, ai_strength, seed, hop_sec)

    print("    AI mode %s: %d clusters | mean S=%.3f | mean T=%.3f" % (
        ai_mode_str, n_cl, np.mean(S), np.mean(T)))

    # ---- State machine ----
    print("  [Py 4/6] Running state machine...")
    Z_final, H = thermodynamic_state_machine(
        S, T, O, Z_ai, C_ai, memory, thermo_int, ai_strength, hop_sec)

    # ---- Event segmentation ----
    print("  [Py 5/6] Segmenting events...")
    novelty = compute_novelty_curve(praat_feats, spec_feats, S, T, hop_sec)
    events = segment_events(
        novelty, S, T, O, Z_final, sr, hop_sec, n_samples)

    print("    Events: %d  (%.3f - %.3f s, mean %.3f s)" % (
        len(events),
        min(e["duration"] for e in events),
        max(e["duration"] for e in events),
        np.mean([e["duration"] for e in events])))

    regime_evt = [sum(1 for e in events if e["regime"] == r)
                  for r in range(4)]
    print("    Per regime: Crystal=%d  Fluid=%d  Gas=%d  Plasma=%d"
          % tuple(regime_evt))

    # ---- Relocation ----
    print("  [Py 6/6] Relocating events + reconstructing...")
    clips = extract_event_audio(audio, events)
    order = relocate_events(events, thermo_int, convection)

    n_events = len(events)
    n_unique_in_order = len(set(order))
    n_relocated = sum(
        1 for idx in range(n_events)
        if idx in order and order.index(idx) != idx)
    n_evaporated = max(0, n_events - n_unique_in_order)
    n_duplicated = max(0, len(order) - n_unique_in_order)

    print("    Relocated: %d/%d  |  Evaporated: %d  |  Duplicated: %d"
          % (n_relocated, n_events, n_evaporated, n_duplicated))

    # ---- Reconstruction ----
    output, n_crossfades, contiguous_joins = reconstruct(
        clips, order, events, sr, n_samples, bool(preserve_dur))

    sf.write(out_wav, output, sr, subtype="FLOAT")
    write_regime_file(regime_file, Z_final, hop_sec)
    out_dur_metric = len(output) / float(sr)
    write_stats_file(stats_file, Z_final, S, T, ai_mode_str, n_cl,
                     events, order, analysis_channel=analysis_ch0 + 1,
                     n_crossfades=n_crossfades,
                     contiguous_joins=contiguous_joins,
                     output_duration=out_dur_metric)

    # Console summary
    counts = [int(np.sum(Z_final == r)) for r in range(4)]
    pcts = [100.0 * c / n_frames_feat for c in counts]
    trans = int(np.sum(np.diff(Z_final) != 0))
    out_dur = (len(output) / sr if output.ndim == 1
               else output.shape[0] / sr)
    print("    Regimes: Crystal=%.1f%%  Fluid=%.1f%%  "
          "Gas=%.1f%%  Plasma=%.1f%%" % tuple(pcts))
    print("    Transitions: %d  |  Output: %.2fs" % (trans, out_dur))
    print("    Splices: %d crossfades | %d contiguous joins" %
          (n_crossfades, contiguous_joins))
    print("OK: wrote %s" % out_wav)


if __name__ == "__main__":
    main()
