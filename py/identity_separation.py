"""
identity_separation.py — Acoustic Identity Separation & Resynthesis

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python identity_separation.py input.wav features.csv output.wav
        stats.txt mode n_identities output_format seed hop_sec

Modes:
    A — Layered reconstruction (original order, identities separated)
    B — Identity alternation (one identity at a time)
    C — Identity recomposition (group events by identity)
    D — Identity morphing (crossfade between layers by confidence)
    E — Hybridization (spectral envelope of one shapes another)

Architecture:
    Stage 2 — Spectral feature extraction + merge with Praat features
    Stage 3 — Latent identity discovery via GMM
    Stage 4 — Identity characterization (data-driven behavioral types)
    Stage 5 — Identity-based audio separation into layers
    Stage 6 — Resynthesis (5 selectable modes)
    Stage 7 — Output
"""

import sys
import os
import math

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
EVENT_MIN_DUR = 0.200   # seconds
EVENT_MAX_DUR = 3.000
XFADE_SEC = 0.008       # 8 ms click prevention


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
# Stage 2 — Feature Loading & Spectral Analysis
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
    Compute spectral descriptors aligned to Praat time grid:
    flatness, flux, centroid, bandwidth, rolloff, ZCR, 8-band energy.

    Vectorized via scipy.signal.stft — the full spectrogram is computed
    once, features are derived from the 2D magnitude matrix, then
    interpolated to the Praat time grid.
    """
    import numpy as np
    from scipy.signal import stft as sp_stft

    n_fft = 2048
    half = n_fft // 2 + 1
    n_frames = len(times)
    n_samples = len(audio)
    hop_samples = int((times[1] - times[0]) * sr) if n_frames > 1 else 512

    # ---- Full STFT in one call ----
    stft_f, stft_t, Zxx = sp_stft(
        audio, fs=sr, window="hann", nperseg=n_fft,
        noverlap=n_fft - hop_samples, boundary="zeros")

    mag = np.abs(Zxx) + 1e-12                       # (half, n_stft)
    freqs = stft_f                                   # (half,)
    n_stft = mag.shape[1]

    # ---- Spectral flatness (vectorized) ----
    log_mag = np.log(mag)
    geo_mean = np.exp(np.mean(log_mag, axis=0))      # (n_stft,)
    arith_mean = np.mean(mag, axis=0) + 1e-12
    flat_stft = geo_mean / arith_mean

    # ---- Spectral flux ----
    flux_stft = np.zeros(n_stft)
    flux_stft[1:] = np.sqrt(np.mean((mag[:, 1:] - mag[:, :-1]) ** 2,
                                     axis=0))

    # ---- Centroid + bandwidth ----
    total = np.sum(mag, axis=0) + 1e-12              # (n_stft,)
    cent_stft = np.dot(freqs, mag) / total            # (n_stft,)
    deviation = freqs[:, None] - cent_stft[None, :]   # (half, n_stft)
    bw_stft = np.sqrt(np.sum(mag * deviation ** 2, axis=0) / total)

    # ---- Rolloff (85%) ----
    cumsum = np.cumsum(mag, axis=0)                   # (half, n_stft)
    thresholds = 0.85 * cumsum[-1, :]                 # (n_stft,)
    # Per-frame searchsorted: find first bin exceeding threshold
    rolloff_stft = np.zeros(n_stft)
    for j in range(n_stft):
        idx = np.searchsorted(cumsum[:, j], thresholds[j])
        rolloff_stft[j] = freqs[min(idx, len(freqs) - 1)]

    # ---- Band energies (8 bands, vectorized slice) ----
    n_bands = 8
    band_edges = np.linspace(0, half, n_bands + 1, dtype=int)
    be_stft = np.zeros((n_stft, n_bands))
    for b in range(n_bands):
        be_stft[:, b] = np.mean(
            mag[band_edges[b]:band_edges[b + 1], :] ** 2, axis=0)

    # ---- ZCR (vectorized, on raw unwindowed frames) ----
    zcr_out = np.zeros(n_frames)
    for i, t in enumerate(times):
        center = int(t * sr)
        start = center - n_fft // 2
        end = start + n_fft
        if start < 0 or end > n_samples:
            frame = np.zeros(n_fft, dtype=np.float64)
            src_s = max(0, start)
            src_e = min(n_samples, end)
            dst_s = src_s - start
            dst_e = dst_s + (src_e - src_s)
            frame[dst_s:dst_e] = audio[src_s:src_e]
        else:
            frame = audio[start:end]
        signs = np.sign(frame)
        zcr_out[i] = np.sum(np.abs(np.diff(signs)) > 0) / (n_fft - 1)

    # ---- Interpolate STFT-grid features to Praat time grid ----
    def _interp(stft_vals):
        return np.interp(times, stft_t, stft_vals)

    flatness   = _interp(flat_stft)
    flux       = _interp(flux_stft)
    centroid   = _interp(cent_stft)
    bandwidth  = _interp(bw_stft)
    rolloff    = _interp(rolloff_stft)
    band_energy = np.column_stack(
        [_interp(be_stft[:, b]) for b in range(n_bands)])

    return {
        "flatness": flatness, "flux": flux, "centroid": centroid,
        "bandwidth": bandwidth, "rolloff": rolloff, "zcr": zcr_out,
        "band_energy": band_energy,
    }


def merge_and_normalize(praat_feats, spec_feats):
    """Merge all features into unified matrix X(t), robustly normalized."""
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

    for key in ["flatness", "flux", "centroid", "bandwidth",
                "rolloff", "zcr"]:
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
# Stage 3 — Latent Identity Discovery
# ═══════════════════════════════════════════════════════════════════════════

def discover_identities(X_norm, n_identities, seed):
    """
    Discover latent acoustic identities via Gaussian Mixture Model.

    Returns:
        Z      : int array — identity label per frame
        C      : float array — confidence (max posterior) per frame
        probs  : (n_frames, n_id) — full posterior matrix
        gmm    : fitted model
    """
    import numpy as np
    from sklearn.mixture import GaussianMixture

    gmm = GaussianMixture(
        n_components=n_identities,
        covariance_type="full",
        n_init=5,
        max_iter=300,
        random_state=seed,
    )
    gmm.fit(X_norm)

    probs = gmm.predict_proba(X_norm)
    Z = gmm.predict(X_norm)
    C = np.max(probs, axis=1)

    return Z, C, probs, gmm


# ═══════════════════════════════════════════════════════════════════════════
# Stage 4 — Identity Characterization
# ═══════════════════════════════════════════════════════════════════════════

# Behavioral types (data-driven assignment, not hard-coded)
BEHAVIOR_TYPES = [
    "harmonic-stable",
    "sustained-resonant",
    "attack-dominant",
    "noisy-transitional",
    "chaotic",
]


def characterize_identities(Z, praat_feats, spec_feats, n_identities):
    """
    Compute per-identity statistics and assign behavioral types.

    Returns list of dicts, one per identity, sorted by assigned type.
    """
    import numpy as np

    n_frames = len(Z)
    identities = []

    pitch = praat_feats["pitch"].copy()
    hnr = np.nan_to_num(praat_feats["hnr"], nan=0.0)
    intensity = np.nan_to_num(praat_feats["intensity"], nan=0.0)
    voiced = praat_feats.get("voiced", np.ones(n_frames))
    flatness = spec_feats["flatness"]
    flux = spec_feats["flux"]
    centroid = spec_feats["centroid"]

    for k in range(n_identities):
        mask = Z == k
        n_k = int(np.sum(mask))
        if n_k == 0:
            identities.append({
                "id": k, "n_frames": 0, "pct": 0.0,
                "behavior": "empty",
                "mean_hnr": 0, "pitch_stability": 0,
                "mean_flatness": 0, "mean_flux": 0,
                "mean_intensity": 0, "mean_centroid": 0,
                "voiced_ratio": 0,
            })
            continue

        # Pitch stability: low std/mean of pitched frames
        p = pitch[mask]
        p_voiced = p[p > 0]
        if len(p_voiced) > 2:
            pitch_stab = 1.0 - min(1.0, np.std(p_voiced) /
                                   (np.mean(p_voiced) + 1e-6))
        else:
            pitch_stab = 0.0

        # Compute onset density (flux peaks per second)
        flux_k = flux[mask]
        flux_thresh = np.mean(flux_k) + np.std(flux_k)
        n_onsets = int(np.sum(flux_k > flux_thresh))

        # Intensity envelope variation
        int_k = intensity[mask]
        int_var = np.std(int_k) / (np.mean(int_k) + 1e-6)

        stats = {
            "id": k,
            "n_frames": n_k,
            "pct": 100.0 * n_k / n_frames,
            "mean_hnr": float(np.mean(hnr[mask])),
            "pitch_stability": float(pitch_stab),
            "mean_flatness": float(np.mean(flatness[mask])),
            "mean_flux": float(np.mean(flux_k)),
            "mean_intensity": float(np.mean(int_k)),
            "mean_centroid": float(np.mean(centroid[mask])),
            "voiced_ratio": float(np.mean(voiced[mask])),
            "onset_density": n_onsets,
            "intensity_variation": float(int_var),
        }

        # Data-driven behavioral classification
        # Score each behavior type and assign the best fit
        scores = _score_behaviors(stats)
        stats["behavior"] = scores[0][0]
        stats["behavior_scores"] = scores

        identities.append(stats)

    # Resolve duplicates: if two identities get the same behavior,
    # reassign the weaker one to its second-best type
    _resolve_duplicate_behaviors(identities)

    return identities


def _score_behaviors(stats):
    """
    Score each behavioral type for an identity based on its stats.
    Returns sorted list of (type, score) from best to worst.
    """
    scores = {}

    hnr = stats["mean_hnr"]
    ps = stats["pitch_stability"]
    flat = stats["mean_flatness"]
    flux = stats["mean_flux"]
    vr = stats["voiced_ratio"]
    iv = stats["intensity_variation"]
    od = stats["onset_density"]

    # harmonic-stable: high HNR, high pitch stability, low flatness
    scores["harmonic-stable"] = (
        0.35 * min(1, hnr / 15.0)
        + 0.30 * ps
        + 0.20 * (1.0 - flat)
        + 0.15 * vr
    )

    # sustained-resonant: high HNR, low flux, low onset density
    scores["sustained-resonant"] = (
        0.30 * min(1, hnr / 12.0)
        + 0.25 * (1.0 - min(1, flux / 0.5))
        + 0.25 * (1.0 - min(1, od / 20.0))
        + 0.20 * (1.0 - iv)
    )

    # attack-dominant: high onset density, high flux, high intensity var
    scores["attack-dominant"] = (
        0.35 * min(1, od / 15.0)
        + 0.30 * min(1, flux / 0.3)
        + 0.20 * iv
        + 0.15 * (1.0 - ps)
    )

    # noisy-transitional: high flatness, low HNR, moderate flux
    scores["noisy-transitional"] = (
        0.35 * flat
        + 0.30 * (1.0 - min(1, hnr / 10.0))
        + 0.20 * (1.0 - vr)
        + 0.15 * min(1, flux / 0.3)
    )

    # chaotic: low pitch stability, high flatness, high flux, high var
    scores["chaotic"] = (
        0.25 * (1.0 - ps)
        + 0.25 * flat
        + 0.25 * min(1, flux / 0.4)
        + 0.25 * iv
    )

    return sorted(scores.items(), key=lambda x: -x[1])


def _resolve_duplicate_behaviors(identities):
    """If multiple identities share the same behavior, reassign weaker ones."""
    assigned = {}
    # Sort by frame count descending — larger identities get priority
    by_size = sorted(
        [i for i in identities if i["n_frames"] > 0],
        key=lambda x: -x["n_frames"])

    for ident in by_size:
        behavior = ident["behavior"]
        if behavior not in assigned:
            assigned[behavior] = ident["id"]
        else:
            # Find next best unassigned behavior
            for btype, _ in ident.get("behavior_scores", []):
                if btype not in assigned:
                    ident["behavior"] = btype
                    assigned[btype] = ident["id"]
                    break


# ═══════════════════════════════════════════════════════════════════════════
# Stage 5 — Identity-Based Event Segmentation & Audio Separation
# ═══════════════════════════════════════════════════════════════════════════

def build_identity_events(Z, C, sr, hop_sec, n_samples):
    """
    Group consecutive frames with the same identity into events.
    Enforce duration constraints (200 ms – 3 s).

    Returns list of event dicts:
        {identity, start_sample, end_sample, mean_confidence, duration}
    """
    import numpy as np

    n_frames = len(Z)
    min_frames = max(2, int(EVENT_MIN_DUR / hop_sec))
    max_frames = max(min_frames + 1, int(EVENT_MAX_DUR / hop_sec))

    # Group consecutive same-identity runs
    runs = []
    run_start = 0
    for i in range(1, n_frames):
        if Z[i] != Z[run_start]:
            runs.append((run_start, i, int(Z[run_start])))
            run_start = i
    runs.append((run_start, n_frames, int(Z[run_start])))

    # Merge short runs into neighbors
    merged = []
    for start, end, ident in runs:
        if merged and (end - start) < min_frames:
            # Merge into previous run
            prev = merged[-1]
            merged[-1] = (prev[0], end, prev[2])
        else:
            merged.append((start, end, ident))

    # Split long runs
    final_runs = []
    for start, end, ident in merged:
        run_len = end - start
        if run_len <= max_frames:
            final_runs.append((start, end, ident))
        else:
            n_splits = int(math.ceil(run_len / max_frames))
            chunk = run_len // n_splits
            for s in range(n_splits):
                cs = start + s * chunk
                ce = start + (s + 1) * chunk if s < n_splits - 1 else end
                final_runs.append((cs, ce, ident))

    # Build event list
    events = []
    for f_start, f_end, ident in final_runs:
        start_samp = min(int(f_start * hop_sec * sr), n_samples)
        end_samp = min(int(f_end * hop_sec * sr), n_samples)
        if end_samp - start_samp < int(0.010 * sr):
            continue

        seg_C = C[f_start:f_end]
        events.append({
            "identity": ident,
            "start_sample": start_samp,
            "end_sample": end_samp,
            "f_start": f_start,
            "f_end": f_end,
            "mean_confidence": float(np.mean(seg_C)),
            "duration": (end_samp - start_samp) / sr,
        })

    return events


def extract_event_audio(audio, events):
    """Extract audio clips for each event."""
    clips = []
    for ev in events:
        s, e = ev["start_sample"], ev["end_sample"]
        if audio.ndim == 1:
            clips.append(audio[s:e].copy())
        else:
            clips.append(audio[s:e, :].copy())
    return clips


def build_identity_layers(events, clips, n_identities, n_samples,
                          n_channels, sr=44100):
    """
    Build per-identity audio layers: each layer contains only
    events belonging to that identity, placed at original time positions,
    with silence elsewhere.
    """
    import numpy as np

    if n_channels == 1:
        layers = [np.zeros(n_samples, dtype=np.float32)
                  for _ in range(n_identities)]
    else:
        layers = [np.zeros((n_samples, n_channels), dtype=np.float32)
                  for _ in range(n_identities)]

    xfade = max(4, int(XFADE_SEC * sr))

    for ev, clip in zip(events, clips):
        ident = ev["identity"]
        s = ev["start_sample"]
        e = ev["end_sample"]
        clip_f = clip.astype(np.float32)

        # Apply tiny fade-in/out for click prevention
        fade_len = min(xfade, len(clip_f) // 4)
        if fade_len > 1:
            fade_in = np.linspace(0, 1, fade_len, dtype=np.float32)
            fade_out = np.linspace(1, 0, fade_len, dtype=np.float32)
            if clip_f.ndim == 1:
                clip_f[:fade_len] *= fade_in
                clip_f[-fade_len:] *= fade_out
            else:
                for ch in range(n_channels):
                    clip_f[:fade_len, ch] *= fade_in
                    clip_f[-fade_len:, ch] *= fade_out

        if e <= n_samples:
            layers[ident][s:e] += clip_f

    return layers


# ═══════════════════════════════════════════════════════════════════════════
# Stage 6 — Resynthesis Modes
# ═══════════════════════════════════════════════════════════════════════════

def resynthesize(mode, events, clips, layers, identities,
                 probs, sr, n_samples, n_channels, n_identities,
                 Z=None, hop_sec=0.01):
    """
    Dispatch to the selected resynthesis mode.
    Returns output audio array.
    """
    mode = mode.upper()
    if mode == "A":
        return _mode_a_layered(layers, n_samples, n_channels,
                               n_identities)
    elif mode == "B":
        return _mode_b_alternation(layers, Z, sr, hop_sec, n_samples,
                                   n_channels, n_identities)
    elif mode == "C":
        return _mode_c_recomposition(events, clips, identities, sr,
                                     n_samples, n_channels, n_identities)
    elif mode == "D":
        return _mode_d_morphing(layers, probs, n_samples, n_channels,
                                n_identities)
    elif mode == "E":
        return _mode_e_hybridization(layers, sr, n_samples, n_channels,
                                     n_identities)
    else:
        return _mode_a_layered(layers, n_samples, n_channels,
                               n_identities)


def _mode_a_layered(layers, n_samples, n_channels, n_id):
    """
    Mode A — Layered Reconstruction.
    Sum all identity layers back together (= original order).
    Spatial separation: pan identities across stereo field.
    """
    import numpy as np

    if n_channels >= 2 or True:
        # Always output stereo with spatial separation
        output = np.zeros((n_samples, 2), dtype=np.float32)
        for i, layer in enumerate(layers):
            # Pan position: spread identities evenly across L-R
            pan = i / max(1, n_id - 1)  # 0=left, 1=right
            gain_l = np.cos(pan * np.pi / 2).astype(np.float32)
            gain_r = np.sin(pan * np.pi / 2).astype(np.float32)

            mono = layer if layer.ndim == 1 else np.mean(layer, axis=1)
            output[:len(mono), 0] += mono * gain_l
            output[:len(mono), 1] += mono * gain_r

    _normalize_output(output)
    return output


def _mode_b_alternation(layers, Z, sr, hop_sec, n_samples,
                        n_channels, n_id):
    """
    Mode B — Identity Alternation.
    Only one identity is audible at any moment — the identity assigned
    by the GMM for that time region.  At identity transitions, a short
    equal-power crossfade is applied between the outgoing and incoming
    layers so that only the active identity's audio is heard cleanly.
    """
    import numpy as np
    from scipy.ndimage import gaussian_filter1d

    # Build per-identity gate envelopes at frame rate
    n_frames = len(Z)
    gates = np.zeros((n_frames, n_id), dtype=np.float32)
    for k in range(n_id):
        gates[:, k] = (Z == k).astype(np.float32)

    # Smooth gates to create crossfades at transitions
    sigma_frames = max(1.0, XFADE_SEC / hop_sec)
    for k in range(n_id):
        gates[:, k] = gaussian_filter1d(gates[:, k], sigma=sigma_frames,
                                        mode="nearest")

    # Renormalize so gates sum to 1 at every frame (equal-power xfade)
    row_sums = gates.sum(axis=1, keepdims=True) + 1e-12
    gates /= row_sums

    # Upsample gate envelopes from frame rate to sample rate
    frame_times = np.linspace(0, n_samples - 1, n_frames)
    sample_idx = np.arange(n_samples, dtype=np.float64)

    if n_channels == 1:
        output = np.zeros(n_samples, dtype=np.float32)
    else:
        output = np.zeros((n_samples, n_channels), dtype=np.float32)

    for k in range(n_id):
        w = np.interp(sample_idx, frame_times,
                       gates[:, k]).astype(np.float32)
        layer = layers[k]
        n_l = min(len(layer), n_samples)
        if layer.ndim == 1:
            output[:n_l] += layer[:n_l] * w[:n_l]
        else:
            for ch in range(n_channels):
                output[:n_l, ch] += layer[:n_l, ch] * w[:n_l]

    _normalize_output(output)
    return output


def _mode_c_recomposition(events, clips, identities, sr, n_samples,
                          n_channels, n_id):
    """
    Mode C — Identity Recomposition.
    Group events by identity, then concatenate identity blocks
    sequentially: all events of identity 0, then identity 1, etc.
    Creates a new timeline organized by acoustic personality.
    """
    import numpy as np

    xfade = max(4, int(XFADE_SEC * sr))
    angle = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fade_in = np.sin(angle)
    fade_out = np.cos(angle)

    # Sort identities by behavioral hierarchy
    id_order = sorted(
        range(n_id),
        key=lambda k: next(
            (i for i, ident in enumerate(identities) if ident["id"] == k),
            k))

    # Gather events per identity
    groups = {k: [] for k in range(n_id)}
    for ev, clip in zip(events, clips):
        groups[ev["identity"]].append(clip)

    # Concatenate
    all_clips = []
    for k in id_order:
        all_clips.extend(groups[k])

    output = _concatenate_clips(all_clips, sr, n_samples, n_channels)
    _normalize_output(output)
    return output


def _mode_d_morphing(layers, probs, n_samples, n_channels, n_id):
    """
    Mode D — Identity Morphing.
    At each sample, blend identity layers weighted by posterior
    probabilities. Creates smooth transitions between identities.
    """
    import numpy as np
    from scipy.ndimage import gaussian_filter1d

    # Smooth probabilities to avoid rapid flickering
    smooth_probs = np.zeros_like(probs)
    for k in range(n_id):
        smooth_probs[:, k] = gaussian_filter1d(
            probs[:, k], sigma=5, mode="nearest")

    # Normalize rows to sum to 1
    row_sums = smooth_probs.sum(axis=1, keepdims=True)
    smooth_probs = smooth_probs / (row_sums + 1e-12)

    # Output: weighted sum of layers at each time
    if n_channels == 1:
        output = np.zeros(n_samples, dtype=np.float32)
    else:
        output = np.zeros((n_samples, n_channels), dtype=np.float32)

    hop_samples = max(1, n_samples // len(probs))

    for k in range(n_id):
        layer = layers[k]
        weights = smooth_probs[:, k]

        # Upsample weights from frame rate to sample rate
        w_upsampled = np.interp(
            np.arange(n_samples),
            np.linspace(0, n_samples - 1, len(weights)),
            weights
        ).astype(np.float32)

        if layer.ndim == 1:
            output[:len(layer)] += layer * w_upsampled[:len(layer)]
        else:
            for ch in range(n_channels):
                output[:len(layer), ch] += (
                    layer[:, ch] * w_upsampled[:len(layer)])

    _normalize_output(output)
    return output


def _mode_e_hybridization(layers, sr, n_samples, n_channels, n_id):
    """
    Mode E — Hybridization.
    Use spectral envelope of identity 0 (most harmonic) as a
    shaping filter applied to identity 1 (most noisy/chaotic).
    Output the filtered result plus remaining identities untouched.
    """
    import numpy as np

    if n_id < 2:
        # Not enough identities — fall back to layered
        return _mode_a_layered(layers, n_samples, n_channels, n_id)

    # Use identity 0 as envelope source, identity 1 as excitation
    source = layers[0]
    excitation = layers[1]

    if source.ndim > 1:
        source_mono = np.mean(source, axis=1)
    else:
        source_mono = source.copy()

    if excitation.ndim > 1:
        exc_mono = np.mean(excitation, axis=1)
    else:
        exc_mono = excitation.copy()

    # STFT-based spectral envelope transfer
    n_fft = 2048
    hop = 512

    from scipy.signal import stft as sp_stft, istft as sp_istft

    _, _, Z_src = sp_stft(source_mono, fs=sr, window="hann",
                          nperseg=n_fft, noverlap=n_fft - hop)
    _, _, Z_exc = sp_stft(exc_mono, fs=sr, window="hann",
                          nperseg=n_fft, noverlap=n_fft - hop)

    # Smooth source magnitude to get envelope
    from scipy.ndimage import gaussian_filter1d
    src_mag = np.abs(Z_src)
    src_envelope = gaussian_filter1d(src_mag, sigma=3, axis=0)

    # Normalize envelope per frame
    frame_max = np.max(src_envelope, axis=0, keepdims=True) + 1e-12
    src_envelope = src_envelope / frame_max

    # Apply source envelope to excitation magnitude
    exc_mag = np.abs(Z_exc)
    exc_phase = np.angle(Z_exc)
    hybrid_mag = exc_mag * src_envelope

    Z_hybrid = hybrid_mag * np.exp(1j * exc_phase)
    _, hybrid = sp_istft(Z_hybrid, fs=sr, window="hann",
                         nperseg=n_fft, noverlap=n_fft - hop)

    # Combine: hybrid + remaining identity layers
    if n_channels == 1:
        output = np.zeros(n_samples, dtype=np.float32)
    else:
        output = np.zeros((n_samples, n_channels), dtype=np.float32)

    # Add hybrid
    n_h = min(len(hybrid), n_samples)
    if output.ndim == 1:
        output[:n_h] += hybrid[:n_h].astype(np.float32)
    else:
        output[:n_h, 0] += hybrid[:n_h].astype(np.float32)
        output[:n_h, 1] += hybrid[:n_h].astype(np.float32)

    # Add remaining identities
    for k in range(2, n_id):
        layer = layers[k]
        n_l = min(len(layer), n_samples)
        if output.ndim == 1:
            output[:n_l] += layer[:n_l]
        else:
            output[:n_l] += layer[:n_l]

    _normalize_output(output)
    return output


def _concatenate_clips(clips, sr, n_samples, n_channels):
    """Concatenate clips with tiny crossfades, preserve duration."""
    import numpy as np

    if not clips:
        if n_channels == 1:
            return np.zeros(n_samples, dtype=np.float32)
        return np.zeros((n_samples, n_channels), dtype=np.float32)

    xfade = max(4, int(XFADE_SEC * sr))
    angle = np.linspace(0, np.pi / 2, xfade, dtype=np.float32)
    fi = np.sin(angle)
    fo = np.cos(angle)

    total = sum(len(c) for c in clips)
    mc = clips[0].ndim > 1
    nc = clips[0].shape[1] if mc else 1

    if mc:
        output = np.zeros((total + xfade, nc), dtype=np.float32)
    else:
        output = np.zeros(total + xfade, dtype=np.float32)

    wp = 0
    for ci, clip in enumerate(clips):
        c = clip.astype(np.float32)
        cl = len(c)
        if cl < xfade * 3:
            end = wp + cl
            if end > len(output):
                pad = end - len(output)
                if mc:
                    output = np.pad(output, ((0, pad), (0, 0)))
                else:
                    output = np.pad(output, (0, pad))
            output[wp:end] += c
            wp = end
            continue

        if ci > 0:
            if mc:
                for ch in range(nc):
                    c[:xfade, ch] *= fi
            else:
                c[:xfade] *= fi
        if ci < len(clips) - 1:
            if mc:
                for ch in range(nc):
                    c[-xfade:, ch] *= fo
            else:
                c[-xfade:] *= fo

        end = wp + cl
        if end > len(output):
            pad = end - len(output)
            if mc:
                output = np.pad(output, ((0, pad), (0, 0)))
            else:
                output = np.pad(output, (0, pad))
        output[wp:end] += c
        wp = end - xfade if ci < len(clips) - 1 else end

    output = output[:wp]

    # Pad or truncate to original length
    if len(output) > n_samples:
        output = output[:n_samples]
    elif len(output) < n_samples:
        pad = n_samples - len(output)
        if mc:
            output = np.pad(output, ((0, pad), (0, 0)))
        else:
            output = np.pad(output, (0, pad))

    return output


def _normalize_output(output):
    """In-place normalize to prevent clipping."""
    import numpy as np
    peak = np.max(np.abs(output))
    if peak > 0.95:
        output *= (0.95 / peak)


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Output
# ═══════════════════════════════════════════════════════════════════════════

def write_stats_file(path, identities, events, Z, n_identities, mode,
                     hop_sec=0.01):
    """Write summary statistics for Praat info panel."""
    import numpy as np

    n_frames = len(Z)
    n_events = len(events)

    # Per-identity event durations
    id_durations = {}
    for ev in events:
        k = ev["identity"]
        if k not in id_durations:
            id_durations[k] = []
        id_durations[k].append(ev["duration"])

    transitions = int(np.sum(np.diff(Z) != 0))

    # Build run-length encoded identity timeline (for Praat drawing)
    runs = []
    run_start = 0
    for i in range(1, n_frames):
        if Z[i] != Z[run_start]:
            runs.append((int(Z[run_start]),
                          run_start * hop_sec,
                          i * hop_sec))
            run_start = i
    runs.append((int(Z[run_start]),
                  run_start * hop_sec,
                  n_frames * hop_sec))

    with open(path, "w") as f:
        f.write("mode=%s\n" % mode)
        f.write("n_identities=%d\n" % n_identities)
        f.write("n_events=%d\n" % n_events)
        f.write("transitions=%d\n" % transitions)
        f.write("mean_event_dur=%.3f\n" %
                float(np.mean([e["duration"] for e in events])))

        for ident in identities:
            k = ident["id"]
            f.write("id_%d_pct=%.1f\n" % (k, ident["pct"]))
            f.write("id_%d_behavior=%s\n" % (k, ident["behavior"]))
            f.write("id_%d_hnr=%.1f\n" % (k, ident["mean_hnr"]))
            f.write("id_%d_flatness=%.3f\n" % (k, ident["mean_flatness"]))
            durs = id_durations.get(k, [0])
            f.write("id_%d_mean_dur=%.3f\n" % (k, float(np.mean(durs))))

        # Identity timeline as run-length encoding
        # Format: "id,start_sec,end_sec" per run, one per line
        f.write("n_timeline_runs=%d\n" % len(runs))
        for ri, (rid, rstart, rend) in enumerate(runs):
            f.write("tl_%d=%d,%.4f,%.4f\n" % (ri, rid, rstart, rend))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) != 10:
        print("Usage: python identity_separation.py "
              "input.wav features.csv output.wav stats.txt "
              "mode n_identities output_format seed hop_sec",
              file=sys.stderr)
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav       = sys.argv[1]
    feat_csv     = sys.argv[2]
    out_wav      = sys.argv[3]
    stats_file   = sys.argv[4]
    mode         = sys.argv[5].upper()
    n_identities = int(sys.argv[6])
    out_format   = sys.argv[7]   # "stereo" or "multi"
    seed         = int(sys.argv[8])
    hop_sec      = float(sys.argv[9])

    n_identities = max(2, min(8, n_identities))
    np.random.seed(seed)

    if not os.path.isfile(in_wav):
        print("ERROR: input not found: %s" % in_wav, file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(feat_csv):
        print("ERROR: features not found: %s" % feat_csv, file=sys.stderr)
        sys.exit(1)

    # ---- Load ----
    print("  [Py 1/6] Loading audio + features...")
    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    praat_feats = load_praat_features(feat_csv)
    times = praat_feats["time"]
    n_frames = len(times)
    n_samples = len(audio) if audio.ndim == 1 else audio.shape[0]
    n_channels = 1 if audio.ndim == 1 else audio.shape[1]

    print("    Audio: %.2fs  SR=%d  Ch=%d  Shape=%s" % (
        n_samples / sr, sr, n_channels, audio.shape))

    # ---- Spectral features ----
    print("  [Py 2/6] Computing spectral features...")
    audio_mono = audio if audio.ndim == 1 else audio[:, 0]
    spec_feats = compute_spectral_features(
        audio_mono.astype(np.float64), sr, times)

    # ---- Merge + normalize ----
    X_norm, feat_names = merge_and_normalize(praat_feats, spec_feats)

    # ---- Identity discovery ----
    print("  [Py 3/6] Discovering %d acoustic identities..." % n_identities)
    Z, C, probs, gmm = discover_identities(X_norm, n_identities, seed)

    print("    Mean confidence: %.3f" % np.mean(C))

    # ---- Characterization ----
    print("  [Py 4/6] Characterizing identities...")
    identities = characterize_identities(Z, praat_feats, spec_feats,
                                         n_identities)

    for ident in identities:
        if ident["n_frames"] > 0:
            print("    ID %d: %5.1f%% | %-20s | HNR=%.1f  flat=%.3f" % (
                ident["id"], ident["pct"], ident["behavior"],
                ident["mean_hnr"], ident["mean_flatness"]))

    # ---- Event segmentation + separation ----
    print("  [Py 5/6] Segmenting events + building layers...")
    events = build_identity_events(Z, C, sr, hop_sec, n_samples)

    print("    Events: %d  (%.3f – %.3f s)" % (
        len(events),
        min(e["duration"] for e in events),
        max(e["duration"] for e in events)))

    clips = extract_event_audio(audio, events)
    layers = build_identity_layers(events, clips, n_identities,
                                   n_samples, n_channels, sr)

    # ---- Resynthesis ----
    print("  [Py 6/6] Resynthesizing (mode %s)..." % mode)
    output = resynthesize(mode, events, clips, layers, identities,
                          probs, sr, n_samples, n_channels, n_identities,
                          Z=Z, hop_sec=hop_sec)

    # ---- Multi-channel output ----
    if out_format == "multi" and n_identities > 1:
        # Stack identity layers as channels
        mono_layers = []
        for layer in layers:
            if layer.ndim > 1:
                mono_layers.append(np.mean(layer, axis=1))
            else:
                mono_layers.append(layer)
        max_len = max(len(m) for m in mono_layers)
        multi = np.zeros((max_len, n_identities), dtype=np.float32)
        for i, m in enumerate(mono_layers):
            multi[:len(m), i] = m
        peak = np.max(np.abs(multi))
        if peak > 0.95:
            multi *= (0.95 / peak)
        sf.write(out_wav, multi, sr)
    else:
        sf.write(out_wav, output, sr)

    # ---- Stats ----
    write_stats_file(stats_file, identities, events, Z,
                     n_identities, mode, hop_sec)

    # ---- Console summary ----
    transitions = int(np.sum(np.diff(Z) != 0))
    out_shape = output.shape if hasattr(output, 'shape') else '?'
    print("    Transitions: %d  |  Events: %d" % (
        transitions, len(events)))
    print("OK: wrote %s  (%s)" % (out_wav, out_format))


if __name__ == "__main__":
    main()
