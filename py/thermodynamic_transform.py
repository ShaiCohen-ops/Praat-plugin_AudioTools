"""
thermodynamic_transform.py — Thermodynamic event relocation engine

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
"""

import sys
import os
import math

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
    Compute spectral descriptors aligned to the Praat time grid.
    Returns dict with: flatness, flux, centroid, bandwidth, rolloff,
    and multi-band energies (8 bands).
    """
    import numpy as np

    n_fft = 2048
    half = n_fft // 2 + 1
    freqs = np.linspace(0, sr / 2, half)
    window = np.hanning(n_fft)

    n_frames = len(times)
    flatness = np.zeros(n_frames)
    flux = np.zeros(n_frames)
    centroid = np.zeros(n_frames)
    bandwidth = np.zeros(n_frames)
    rolloff = np.zeros(n_frames)

    n_bands = 8
    band_edges = np.linspace(0, half, n_bands + 1, dtype=int)
    band_energy = np.zeros((n_frames, n_bands))

    prev_mag = None
    n_samples = len(audio)

    for i, t in enumerate(times):
        center = int(t * sr)
        start = center - n_fft // 2
        end = start + n_fft

        if start < 0 or end > n_samples:
            frame = np.zeros(n_fft, dtype=np.float64)
            src_start = max(0, start)
            src_end = min(n_samples, end)
            dst_start = src_start - start
            dst_end = dst_start + (src_end - src_start)
            frame[dst_start:dst_end] = audio[src_start:src_end]
        else:
            frame = audio[start:end].copy()

        frame *= window
        spec = np.fft.rfft(frame)
        mag = np.abs(spec) + 1e-12

        log_mag = np.log(mag)
        geo = np.exp(np.mean(log_mag))
        ari = np.mean(mag)
        flatness[i] = geo / (ari + 1e-12)

        if prev_mag is not None:
            diff = mag - prev_mag
            flux[i] = np.sqrt(np.mean(diff ** 2))
        prev_mag = mag.copy()

        total = np.sum(mag)
        centroid[i] = np.sum(freqs * mag) / (total + 1e-12)

        c = centroid[i]
        bandwidth[i] = np.sqrt(
            np.sum(mag * (freqs - c) ** 2) / (total + 1e-12))

        cumsum = np.cumsum(mag)
        threshold = 0.85 * cumsum[-1]
        idx = np.searchsorted(cumsum, threshold)
        rolloff[i] = freqs[min(idx, len(freqs) - 1)]

        for b in range(n_bands):
            band_energy[i, b] = np.mean(
                mag[band_edges[b]:band_edges[b + 1]] ** 2)

    return {
        "flatness": flatness,
        "flux": flux,
        "centroid": centroid,
        "bandwidth": bandwidth,
        "rolloff": rolloff,
        "band_energy": band_energy,
    }


def merge_and_normalize(praat_feats, spec_feats):
    """Merge Praat + spectral features into unified matrix X(t)."""
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
    dp = np.zeros(n)
    for i in range(1, n):
        if not (np.isnan(pitch[i]) or np.isnan(pitch[i - 1])):
            dp[i] = abs(pitch[i] - pitch[i - 1]) / (pitch[i] + 1e-6)
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
    """Mode B — Predictive instability via Ridge regression."""
    import numpy as np
    from sklearn.linear_model import Ridge

    n = len(S0)
    lookback = max(1, int(0.5 / hop_sec))
    lookahead = max(1, int(0.2 / hop_sec))

    X_train, y_train = [], []
    for i in range(lookback, n - lookahead):
        X_train.append(X_norm[i - lookback:i].flatten())
        y_train.append(S0[i + lookahead])

    model = Ridge(alpha=1.0, random_state=seed)
    model.fit(np.array(X_train), np.array(y_train))

    S_pred = S0.copy()
    for i in range(lookback, n - lookahead):
        hist = X_norm[i - lookback:i].flatten()
        S_pred[i] = model.predict(hist.reshape(1, -1))[0]

    S_pred = np.clip(S_pred, 0, 1)
    Z, C, n_cl = ai_mode_a(X_norm, S_pred, seed)
    return Z, C, n_cl


def ai_mode_c(X_norm, S0, seed):
    """Mode C — Learned entropy via PCA latent space."""
    import numpy as np
    from sklearn.decomposition import PCA
    from sklearn.mixture import GaussianMixture

    n_components = min(6, X_norm.shape[1])
    pca = PCA(n_components=n_components, random_state=seed)
    L = pca.fit_transform(X_norm)

    window = max(3, int(0.3 / 0.01))
    S_learned = np.zeros(len(L))
    for i in range(len(L)):
        lo = max(0, i - window // 2)
        hi = min(len(L), i + window // 2 + 1)
        S_learned[i] = np.mean(np.std(L[lo:hi], axis=0))

    S_learned = _safe_normalize(S_learned)
    S_blend = 0.6 * S_learned + 0.4 * S0
    S_blend = np.clip(S_blend, 0, 1)

    n_clusters = 6
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
        Z_ai, C_ai, n_cl = ai_mode_c(X_norm, S0, seed)
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
                                memory_param, thermo_intensity, hop_sec):
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
        if c > 0.7 and ai_vote != target:
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
    pitch = praat_feats["pitch"].copy()
    voiced = praat_feats.get("voiced", np.ones(n))
    pitch_disc = np.zeros(n)
    for i in range(1, n):
        # Voiced/unvoiced boundary
        if voiced[i] != voiced[i - 1]:
            pitch_disc[i] = 1.0
        # Large pitch jump (> ~2.5 semitones)
        elif voiced[i] > 0 and voiced[i - 1] > 0:
            if pitch[i] > 0 and pitch[i - 1] > 0:
                ratio = pitch[i] / (pitch[i - 1] + 1e-6)
                if ratio > 1.15 or ratio < 0.87:
                    pitch_disc[i] = min(1.0, abs(ratio - 1.0) * 3.0)
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
    Gas: displace events proportionally to their entropy magnitude.
    Higher entropy → larger displacement in the entropy gradient direction.
    Low-entropy events stay near their original position.
    """
    import numpy as np

    gas_entries = []
    for pos, idx in enumerate(order):
        if idx < len(regimes) and regimes[idx] == REGIME_GAS:
            gas_entries.append((pos, idx))

    if not gas_entries:
        return order

    n_total = len(order)

    # Compute target positions for Gas events
    targets = []
    for pos, idx in gas_entries:
        s = entropies[idx]
        direction = 1.0 if gradients[idx] >= 0 else -1.0
        displacement = intensity * s * direction * n_total * 0.4
        target = pos + displacement
        targets.append((target, idx))

    # Sort Gas events by their target position
    targets.sort(key=lambda x: x[0])

    # Re-insert Gas events into their original slot positions
    result = list(order)
    gas_slots = sorted([gp[0] for gp in gas_entries])

    for slot, (_, idx) in zip(gas_slots, targets):
        result[slot] = idx

    return result


def _apply_plasma_rule(order, events, entropies, regimes, intensity):
    """
    Plasma: evaporate top X% highest-entropy Plasma events (removal),
    then relocate remaining Plasma events toward structural anchors
    (beginning / midpoint / end) based on entropy level.
    """
    import numpy as np

    plasma_entries = [
        (pos, idx) for pos, idx in enumerate(order)
        if idx < len(regimes) and regimes[idx] == REGIME_PLASMA
    ]

    if not plasma_entries:
        return order

    # --- Evaporation: remove the highest-entropy Plasma events ---
    evap_fraction = intensity * 0.3  # up to 30%
    n_plasma = len(plasma_entries)
    n_evap = max(0, int(n_plasma * evap_fraction))

    evap_set = set()
    if n_evap > 0:
        by_entropy = sorted(plasma_entries,
                            key=lambda x: entropies[x[1]], reverse=True)
        evap_set = set(x[1] for x in by_entropy[:n_evap])
        order = [idx for idx in order if idx not in evap_set]

    # --- Anchor remaining Plasma events ---
    remaining_plasma = [
        (pos, idx) for pos, idx in enumerate(order)
        if idx < len(regimes) and regimes[idx] == REGIME_PLASMA
    ]

    if remaining_plasma:
        non_plasma = [idx for idx in order
                      if not (idx < len(regimes)
                              and regimes[idx] == REGIME_PLASMA)]
        n_np = len(non_plasma)

        result = list(non_plasma)
        for _, idx in remaining_plasma:
            s = entropies[idx]
            # Low entropy → anchor at start; high → end
            if s < 0.4:
                anchor = 0
            elif s < 0.7:
                anchor = max(0, len(result) // 2)
            else:
                anchor = len(result)
            anchor = min(anchor, len(result))
            result.insert(anchor, idx)

        return result

    return order


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


def reconstruct(clips, order, sr, original_length, preserve_duration):
    """
    Concatenate relocated events with click-free splicing.

    Uses equal-power (cosine) crossfade at splice points,
    plus a post-splice click detector that smooths any remaining
    transients at event boundaries.
    """
    import numpy as np

    xfade = int(XFADE_SEC * sr)
    xfade = max(4, xfade)

    multichannel = clips[0].ndim > 1
    if multichannel:
        n_ch = clips[0].shape[1]

    relocated = [clips[idx].copy().astype(np.float32) for idx in order]

    # Equal-power crossfade (cosine) — sums to constant power
    angle = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in = np.sin(angle)        # 0 → 1
    fade_out = np.cos(angle)       # 1 → 0
    # sin²+cos² = 1, so overlap region maintains constant energy

    # Estimate total length
    total = sum(len(c) for c in relocated)
    n_splices = max(0, len(relocated) - 1)
    total -= n_splices * xfade

    if multichannel:
        output = np.zeros((total + xfade * 2, n_ch), dtype=np.float32)
    else:
        output = np.zeros(total + xfade * 2, dtype=np.float32)

    write_pos = 0
    splice_positions = []

    for ci, clip in enumerate(relocated):
        clip_len = len(clip)

        # Very short clips: place without fading
        if clip_len < xfade * 3:
            end_pos = write_pos + clip_len
            if end_pos > len(output):
                pad = end_pos - len(output)
                if multichannel:
                    output = np.pad(output, ((0, pad), (0, 0)))
                else:
                    output = np.pad(output, (0, pad))
            output[write_pos:end_pos] += clip
            splice_positions.append(write_pos)
            write_pos = end_pos
            continue

        # Apply fade-in (skip on first clip)
        if ci > 0:
            if multichannel:
                for ch in range(n_ch):
                    clip[:xfade, ch] *= fade_in
            else:
                clip[:xfade] *= fade_in

        # Apply fade-out (skip on last clip)
        if ci < len(relocated) - 1:
            if multichannel:
                for ch in range(n_ch):
                    clip[-xfade:, ch] *= fade_out
            else:
                clip[-xfade:] *= fade_out

        # Write with overlap-add
        end_pos = write_pos + clip_len
        if end_pos > len(output):
            pad = end_pos - len(output)
            if multichannel:
                output = np.pad(output, ((0, pad), (0, 0)))
            else:
                output = np.pad(output, (0, pad))

        output[write_pos:end_pos] += clip

        # Track splice point for click detection
        if ci > 0:
            splice_positions.append(write_pos)

        # Next clip overlaps by xfade samples
        if ci < len(relocated) - 1:
            write_pos = end_pos - xfade
        else:
            write_pos = end_pos

    # Trim trailing silence
    output = output[:write_pos]

    # ---- Post-splice click smoothing ----
    # Detect and smooth any remaining transients at splice boundaries
    smooth_radius = max(4, xfade // 4)
    for sp in splice_positions:
        region_start = max(0, sp - smooth_radius)
        region_end = min(len(output), sp + xfade + smooth_radius)
        if region_end - region_start < 4:
            continue
        if multichannel:
            for ch in range(n_ch):
                seg = output[region_start:region_end, ch]
                _smooth_clicks(seg, smooth_radius)
                output[region_start:region_end, ch] = seg
        else:
            seg = output[region_start:region_end]
            _smooth_clicks(seg, smooth_radius)
            output[region_start:region_end] = seg

    # Duration preservation
    if preserve_duration:
        if len(output) > original_length:
            output = output[:original_length]
        elif len(output) < original_length:
            pad = original_length - len(output)
            if multichannel:
                output = np.pad(output, ((0, pad), (0, 0)))
            else:
                output = np.pad(output, (0, pad))

    # Normalize only if clipping
    peak = np.max(np.abs(output))
    if peak > 0.95:
        output = output * (0.95 / peak)

    return output


def _smooth_clicks(seg, radius):
    """
    Detect and smooth sample-level clicks within a short segment.
    A click is a sample-to-sample jump larger than a threshold
    relative to the local RMS.
    """
    import numpy as np

    if len(seg) < 3:
        return

    local_rms = max(0.001, np.sqrt(np.mean(seg ** 2)))
    threshold = local_rms * 4.0  # jump > 4× local RMS = click

    diffs = np.abs(np.diff(seg))
    for i in range(len(diffs)):
        if diffs[i] > threshold:
            # Smooth this sample with its neighbors using a 5-tap median
            lo = max(0, i - 2)
            hi = min(len(seg), i + 3)
            seg[i] = np.median(seg[lo:hi])


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
                     events, order):
    """Write summary statistics for Praat info panel."""
    import numpy as np

    n = len(Z)
    counts = [int(np.sum(Z == r)) for r in range(4)]
    pcts = [100.0 * c / n for c in counts]
    transitions = int(np.sum(np.diff(Z) != 0))

    n_events = len(events)
    n_relocated = sum(1 for i, o in enumerate(order[:n_events])
                      if i < len(order) and o != i)
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
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
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
        S, T, O, Z_ai, C_ai, memory, thermo_int, hop_sec)

    # ---- Event segmentation ----
    print("  [Py 5/6] Segmenting events...")
    novelty = compute_novelty_curve(praat_feats, spec_feats, S, T, hop_sec)
    events = segment_events(
        novelty, S, T, O, Z_final, sr, hop_sec, n_samples)

    print("    Events: %d  (%.3f – %.3f s, mean %.3f s)" % (
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
    n_relocated = sum(1 for i, o in enumerate(order[:n_events])
                      if i < len(order) and o != i)
    n_evaporated = max(0, n_events - n_unique_in_order)
    n_duplicated = max(0, len(order) - n_unique_in_order)

    print("    Relocated: %d/%d  |  Evaporated: %d  |  Duplicated: %d"
          % (n_relocated, n_events, n_evaporated, n_duplicated))

    # ---- Reconstruction ----
    output = reconstruct(
        clips, order, sr, n_samples, bool(preserve_dur))

    sf.write(out_wav, output, sr)
    write_regime_file(regime_file, Z_final, hop_sec)
    write_stats_file(stats_file, Z_final, S, T, ai_mode_str, n_cl,
                     events, order)

    # Console summary
    counts = [int(np.sum(Z_final == r)) for r in range(4)]
    pcts = [100.0 * c / n_frames_feat for c in counts]
    trans = int(np.sum(np.diff(Z_final) != 0))
    out_dur = (len(output) / sr if output.ndim == 1
               else output.shape[0] / sr)
    print("    Regimes: Crystal=%.1f%%  Fluid=%.1f%%  "
          "Gas=%.1f%%  Plasma=%.1f%%" % tuple(pcts))
    print("    Transitions: %d  |  Output: %.2fs" % (trans, out_dur))
    print("OK: wrote %s" % out_wav)


if __name__ == "__main__":
    main()
