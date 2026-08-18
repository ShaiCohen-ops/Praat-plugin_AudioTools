"""
identity_separation.py — Acoustic Identity Separation & Resynthesis

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 1.4 (2026)

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

Changelog v1.4:
    Correctness / continuity pass with conservative stereo analysis fallback.
    - Modes A/B no longer double-fade every identity boundary. Mode A now
      reconstructs the raw classified timeline and applies a smooth equal-power
      pan trajectory derived from the identity labels; Mode B reconstructs the
      one-identity-at-a-time timeline directly. This removes artificial boundary
      dips while preserving the discovered identity sequence.
    - Mode C and the continuous material streams used by Modes D/E now
      concatenate compactly. Mode C no longer pads the crossfade-shortened
      recomposition with artificial trailing silence; D/E no longer loop that
      padding as part of their source material. The previous helper padded each crossfade-shortened
      identity block back to its raw length with silence, so those artificial
      silent tails were periodically looped into morph/hybrid streams.
    - The final classified event is extended to the true final sample, avoiding
      loss of the <1 hop tail when duration is not an exact multiple of hop_sec.
    - Optional analysis_channel CLI argument keeps Praat and Python spectral
      analysis on the same representative input channel. Default remains channel 1
      for backward compatibility.
    - Behavioral `onset_density` is now a true peaks-per-second rate instead
      of a raw peak count, removing a size bias in identity labels. This affects
      characterization text only; resynthesis does not use the behavior label.
    - Output WAVs are written as 32-bit FLOAT to avoid an unnecessary PCM16
      quantization round-trip before Praat re-imports the result.

Changelog v1.3:
    Resynthesis correctness pass. Mode A is bit-identical to v1.2.
    Mode B's per-channel samples are unchanged (mono input under
    "stereo" format is now duplicated to two identical channels — see
    the upmix note). Modes C, D, E and the multi-channel path change.

    AUDIO-CHANGING:
    - Mode D (Morphing) REDESIGNED. v1.2 blended the per-identity
      *event layers*, which are time-disjoint by construction (each
      frame belongs to exactly one identity), so at any instant only
      one layer had audio and the "blend" degenerated to a gated
      original — no actual morph. v1.3 builds a CONTINUOUS material
      stream per identity (that identity's events concatenated and
      loop-tiled to full length with equal-power wrap crossfades),
      then blends those continuous streams by the smoothed posterior.
      Now there is real cross-identity material to morph between.
    - Mode E (Hybridization) REDESIGNED. v1.2 took layers[0]/layers[1]
      as source/excitation; being disjoint, the harmonic source was
      silent exactly where the noisy excitation had energy, so the
      STFT envelope transfer produced near-silence (measured peak
      ~0.08 vs ~0.95 for other modes). v1.3 (a) selects source =
      highest-mean-HNR identity and excitation = highest-flatness
      identity (so the docstring's "most harmonic / most noisy" is
      now actually true), and (b) feeds CONTINUOUS streams for both,
      so the envelope transfer has overlapping material to act on.
      Mode E also gets makeup gain (scales to a target peak rather than
      only attenuating), since envelope masking sheds energy and v1.2's
      attenuate-only normalizer left it drastically quiet.
    - Mode C (Recomposition): the v1.2 "behavioral hierarchy" sort
      was a no-op (the key reduced to the identity index, giving
      plain numeric order). v1.3 orders identity blocks by DESCENDING
      mean HNR (harmonic blocks first, noisy last), making the
      ordering claim true. Same events, different block order.
    - Mono input + "stereo" format now upmixes mono -> dual-mono so
      "Stereo mix" actually yields a 2-channel file for every mode
      (previously only Mode A force-upmixed; B/C/D/E followed the
      input and could return mono). Perceptually identical (L == R).

    BUG FIX:
    - Multi-channel output no longer silently ignores the Mode.
      v1.2 computed `output = resynthesize(...)` then DISCARDED it
      whenever out_format == "multi", writing raw layers regardless;
      mode-B-multi and mode-C-multi were byte-identical. v1.3 skips
      the wasted resynthesis call for multi output and the console +
      stats now state plainly that multi-channel writes one identity
      per channel and the resynthesis Mode is not applied to audio.

    NON-AUDIO:
    - Removed dead `hop_samples` variable in Mode D.
    - Mode B docstring: "equal-power" -> "constant-sum (equal-
      amplitude)" crossfade, matching what the code actually does
      (linear normalization of summed gates). No audio change.

Changelog v1.2:
    Cosmetic-only change for AudioTools v1.2 release.
    - _mode_a_layered: removed `or True` dead-code condition that
      made an if-branch unconditional. Behavior and output unchanged.
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


def characterize_identities(Z, praat_feats, spec_feats, n_identities,
                            hop_sec=0.01):
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

        # Compute onset density as flux peaks per second.  v1.3 stored the raw
        # peak COUNT under this name, which biased behavior labels toward large
        # identities simply because they contained more frames.
        flux_k = flux[mask]
        flux_thresh = np.mean(flux_k) + np.std(flux_k)
        n_onsets = int(np.sum(flux_k > flux_thresh))
        ident_dur_s = max(n_k * hop_sec, hop_sec)
        onset_density = n_onsets / ident_dur_s

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
            "onset_density": float(onset_density),
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

    # Praat's analysis grid uses a fixed hop and can end <1 hop before the true
    # final sample.  Extend the last classified event to the file boundary so
    # the resynthesis/layer export never drops that unclassified tail.
    if events and events[-1]["end_sample"] < n_samples:
        events[-1]["end_sample"] = n_samples
        events[-1]["duration"] = (n_samples - events[-1]["start_sample"]) / sr

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
                          n_channels, sr=44100, fade_edges=True):
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

        # Optional tiny fade-in/out for isolated-layer export.  Resynthesis
        # Modes A/B deliberately use raw, non-faded layers so adjacent classified
        # events reconstruct continuously instead of creating a dip at every
        # identity boundary.
        fade_len = min(xfade, len(clip_f) // 4) if fade_edges else 0
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
        return _mode_a_layered(layers, Z, sr, hop_sec, n_samples,
                               n_channels, n_identities)
    elif mode == "B":
        return _mode_b_alternation(layers, Z, sr, hop_sec, n_samples,
                                   n_channels, n_identities)
    elif mode == "C":
        return _mode_c_recomposition(events, clips, identities, sr,
                                     n_samples, n_channels, n_identities)
    elif mode == "D":
        return _mode_d_morphing(events, clips, probs, sr, n_samples,
                                n_channels, n_identities)
    elif mode == "E":
        return _mode_e_hybridization(events, clips, identities, sr,
                                     n_samples, n_channels, n_identities)
    else:
        return _mode_a_layered(layers, n_samples, n_channels,
                               n_identities)


def _sum_identity_layers(layers, n_samples, n_channels):
    """Sum time-disjoint raw identity layers back to the classified timeline."""
    import numpy as np
    if n_channels == 1:
        out = np.zeros(n_samples, dtype=np.float32)
    else:
        out = np.zeros((n_samples, n_channels), dtype=np.float32)
    for layer in layers:
        n_l = min(len(layer), n_samples)
        out[:n_l] += layer[:n_l]
    return out


def _mode_a_layered(layers, Z, sr, hop_sec, n_samples, n_channels, n_id):
    """
    Mode A — Layered Reconstruction with spatial identity separation.

    The classified source timeline is reconstructed from RAW (non-faded)
    identity layers, then its pan position follows the active identity.  The
    discrete identity labels are smoothed around boundaries before equal-power
    panning, so identity changes move through the stereo field without the
    amplitude holes produced by independently fading time-disjoint layers.

    As in v1.3, Mode A deliberately renders a stereo spatialization even for a
    multichannel source; the source channels are collapsed to a representative
    mono timeline before identity panning.
    """
    import numpy as np
    from scipy.ndimage import gaussian_filter1d

    reconstructed = _sum_identity_layers(layers, n_samples, n_channels)
    mono = reconstructed if reconstructed.ndim == 1 else np.mean(reconstructed, axis=1)

    if Z is None or len(Z) == 0 or n_id <= 1:
        pan_sample = np.full(n_samples, 0.5, dtype=np.float64)
    else:
        pan_frame = np.asarray(Z, dtype=np.float64) / max(1, n_id - 1)
        sigma_frames = max(0.5, XFADE_SEC / max(hop_sec, 1e-6))
        pan_frame = gaussian_filter1d(pan_frame, sigma=sigma_frames, mode="nearest")
        frame_grid = np.linspace(0, n_samples - 1, len(pan_frame))
        pan_sample = np.interp(np.arange(n_samples, dtype=np.float64),
                               frame_grid, pan_frame)
        pan_sample = np.clip(pan_sample, 0.0, 1.0)

    gain_l = np.cos(pan_sample * np.pi / 2.0).astype(np.float32)
    gain_r = np.sin(pan_sample * np.pi / 2.0).astype(np.float32)
    output = np.column_stack([mono * gain_l, mono * gain_r]).astype(np.float32)
    _normalize_output(output)
    return output


def _mode_b_alternation(layers, Z, sr, hop_sec, n_samples,
                         n_channels, n_id):
    """
    Mode B — Identity Alternation.

    Exactly one discovered identity owns each classified time region.  The raw
    time-disjoint layers therefore already implement the intended alternation;
    summing them reconstructs that one-identity-at-a-time timeline directly.
    v1.3 additionally faded every event edge and then multiplied the sparse
    layers by smoothed gates, producing artificial ~boundary-level attenuation
    even though there was no overlapping material to crossfade.
    """
    output = _sum_identity_layers(layers, n_samples, n_channels)
    _normalize_output(output)
    return output


def _mode_c_recomposition(events, clips, identities, sr, n_samples,
                          n_channels, n_id):
    """
    Mode C — Identity Recomposition.
    Group events by identity, then concatenate identity blocks ordered
    by DESCENDING mean HNR (most harmonic identity first, noisiest
    last). Creates a new timeline organized by acoustic personality.
    """
    import numpy as np

    # Order identities by descending mean HNR (harmonic -> noisy).
    # Identities with no frames sort last.
    def _hnr_key(k):
        for ident in identities:
            if ident["id"] == k:
                if ident.get("n_frames", 0) <= 0:
                    return -1e9
                return ident.get("mean_hnr", 0.0)
        return -1e9

    id_order = sorted(range(n_id), key=_hnr_key, reverse=True)

    # Gather events per identity
    groups = {k: [] for k in range(n_id)}
    for ev, clip in zip(events, clips):
        groups[ev["identity"]].append(clip)

    # Concatenate
    all_clips = []
    for k in id_order:
        all_clips.extend(groups[k])

    output = _concatenate_clips(
        all_clips, sr, n_samples, n_channels, compact=True)
    _normalize_output(output)
    return output


def _mode_d_morphing(events, clips, probs, sr, n_samples, n_channels,
                     n_id):
    """
    Mode D — Identity Morphing.
    Build a CONTINUOUS material stream per identity (that identity's
    events looped to full length), then blend the streams at each sample
    by the smoothed posterior probabilities. Because every identity now
    has material present at every instant, the posterior weighting
    produces a genuine cross-identity morph rather than a gated original.
    """
    import numpy as np
    from scipy.ndimage import gaussian_filter1d

    streams = _continuous_identity_streams(
        events, clips, n_id, n_samples, n_channels, sr)

    # Smooth probabilities to avoid rapid flickering
    smooth_probs = np.zeros_like(probs)
    for k in range(n_id):
        smooth_probs[:, k] = gaussian_filter1d(
            probs[:, k], sigma=5, mode="nearest")

    # Normalize rows to sum to 1
    row_sums = smooth_probs.sum(axis=1, keepdims=True)
    smooth_probs = smooth_probs / (row_sums + 1e-12)

    if n_channels == 1:
        output = np.zeros(n_samples, dtype=np.float32)
    else:
        output = np.zeros((n_samples, n_channels), dtype=np.float32)

    frame_grid = np.linspace(0, n_samples - 1, len(probs))
    sample_idx = np.arange(n_samples)

    for k in range(n_id):
        weights = smooth_probs[:, k]
        w_up = np.interp(sample_idx, frame_grid, weights).astype(np.float32)
        stream = streams[k]
        if stream.ndim == 1:
            output += stream * w_up
        else:
            for ch in range(stream.shape[1]):
                output[:, ch] += stream[:, ch] * w_up

    _normalize_output(output)
    return output


def _mode_e_hybridization(events, clips, identities, sr, n_samples,
                          n_channels, n_id):
    """
    Mode E — Hybridization.
    Use the spectral envelope of the most-harmonic identity (highest
    mean HNR) to shape the most-noisy identity (highest spectral
    flatness). Both are rendered as CONTINUOUS full-length streams so
    the envelope of one actually overlaps the excitation of the other;
    otherwise (disjoint event layers) the transfer has nothing to act on.
    Remaining identities are mixed in from their original sparse layers.
    """
    import numpy as np

    if n_id < 2:
        # Not enough identities — fall back to a continuous single stream
        streams = _continuous_identity_streams(
            events, clips, n_id, n_samples, n_channels, sr)
        out = streams[0] if streams else np.zeros(n_samples, dtype=np.float32)
        _normalize_output(out)
        return out

    # Select source (most harmonic) and excitation (most noisy) by stats.
    def _stat(k, key, default):
        for ident in identities:
            if ident["id"] == k:
                return ident.get(key, default)
        return default

    valid = [k for k in range(n_id) if _stat(k, "n_frames", 0) > 0]
    if len(valid) < 2:
        valid = list(range(n_id))
    src_id = max(valid, key=lambda k: _stat(k, "mean_hnr", 0.0))
    exc_id = max(valid, key=lambda k: _stat(k, "mean_flatness", 0.0))
    if exc_id == src_id:
        # Pick a different excitation if HNR and flatness peak coincide
        others = [k for k in valid if k != src_id]
        if others:
            exc_id = max(others, key=lambda k: _stat(k, "mean_flatness", 0.0))

    streams = _continuous_identity_streams(
        events, clips, n_id, n_samples, n_channels, sr)

    def _mono(sig):
        return sig if sig.ndim == 1 else np.mean(sig, axis=1)

    source_mono = _mono(streams[src_id]).astype(np.float64)
    exc_mono = _mono(streams[exc_id]).astype(np.float64)

    # STFT-based spectral envelope transfer
    n_fft = 2048
    hop = 512
    from scipy.signal import stft as sp_stft, istft as sp_istft
    from scipy.ndimage import gaussian_filter1d

    _, _, Z_src = sp_stft(source_mono, fs=sr, window="hann",
                          nperseg=n_fft, noverlap=n_fft - hop)
    _, _, Z_exc = sp_stft(exc_mono, fs=sr, window="hann",
                          nperseg=n_fft, noverlap=n_fft - hop)

    # Align frame counts (continuous streams are equal length, but
    # STFT framing can differ by one).
    n_common = min(Z_src.shape[1], Z_exc.shape[1])
    Z_src = Z_src[:, :n_common]
    Z_exc = Z_exc[:, :n_common]

    src_mag = np.abs(Z_src)
    src_envelope = gaussian_filter1d(src_mag, sigma=3, axis=0)
    frame_max = np.max(src_envelope, axis=0, keepdims=True) + 1e-12
    src_envelope = src_envelope / frame_max

    exc_mag = np.abs(Z_exc)
    exc_phase = np.angle(Z_exc)
    hybrid_mag = exc_mag * src_envelope

    Z_hybrid = hybrid_mag * np.exp(1j * exc_phase)
    _, hybrid = sp_istft(Z_hybrid, fs=sr, window="hann",
                         nperseg=n_fft, noverlap=n_fft - hop)

    if n_channels == 1:
        output = np.zeros(n_samples, dtype=np.float32)
    else:
        output = np.zeros((n_samples, n_channels), dtype=np.float32)

    n_h = min(len(hybrid), n_samples)
    if output.ndim == 1:
        output[:n_h] += hybrid[:n_h].astype(np.float32)
    else:
        for ch in range(output.shape[1]):
            output[:n_h, ch] += hybrid[:n_h].astype(np.float32)

    # Mix in the remaining identities from their sparse event layers so
    # the rest of the cast is still present in the timeline.
    layers = build_identity_layers(events, clips, n_id, n_samples,
                                   n_channels, sr)
    for k in range(n_id):
        if k == src_id or k == exc_id:
            continue
        layer = layers[k]
        n_l = min(len(layer), n_samples)
        if output.ndim == 1:
            output[:n_l] += (layer[:n_l] if layer.ndim == 1
                             else np.mean(layer[:n_l], axis=1)) * 0.6
        else:
            if layer.ndim == 1:
                for ch in range(output.shape[1]):
                    output[:n_l, ch] += layer[:n_l] * 0.6
            else:
                output[:n_l] += layer[:n_l] * 0.6

    _normalize_peak(output, target=0.9)
    return output


def _concatenate_clips(clips, sr, n_samples, n_channels, compact=False):
    """Concatenate clips with tiny crossfades.

    compact=True returns the actual overlap-added material length.  The default
    preserves the historical fixed-duration behavior used by Mode C.
    """
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

    if compact:
        return output

    # Pad or truncate to requested length
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


def _normalize_peak(output, target=0.9, floor=1e-5):
    """
    Scale to a target peak (both boost and attenuate). Used by modes
    whose processing sheds energy (e.g. Mode E's spectral-envelope
    masking), so they don't come out drastically quieter than the
    other modes. No-op for essentially silent output.
    """
    import numpy as np
    peak = np.max(np.abs(output))
    if peak > floor:
        output *= (target / peak)
    return output


def _loop_to_length(sig, n_samples, sr):
    """
    Loop-tile a (possibly short) signal to exactly n_samples, using a
    short equal-power crossfade at each wrap so the loop point doesn't
    click. Used to turn an identity's concatenated event material into a
    CONTINUOUS full-length stream for the blend/hybrid modes (D, E).
    Mono or multichannel.
    """
    import numpy as np

    mc = sig.ndim > 1
    base = len(sig)
    if base == 0:
        if mc:
            return np.zeros((n_samples, sig.shape[1]), dtype=np.float32)
        return np.zeros(n_samples, dtype=np.float32)
    if base >= n_samples:
        return sig[:n_samples].astype(np.float32)

    xf = max(4, int(XFADE_SEC * sr))
    xf = min(xf, base // 4) if base // 4 > 1 else 0

    if mc:
        out = np.zeros((n_samples, sig.shape[1]), dtype=np.float32)
    else:
        out = np.zeros(n_samples, dtype=np.float32)

    if xf > 1:
        ang = np.linspace(0, np.pi / 2, xf, dtype=np.float32)
        fi = np.sin(ang)
        fo = np.cos(ang)

    wp = 0
    first = True
    while wp < n_samples:
        c = sig.astype(np.float32).copy()
        if xf > 1 and not first:
            # Fade in the head of this repetition over the tail already
            # written, so the wrap is an equal-power crossfade.
            head = c[:xf]
            if mc:
                for ch in range(c.shape[1]):
                    head[:, ch] *= fi
            else:
                head[:] = head * fi
            ov_s = max(0, wp - xf)
            ov_e = wp
            ln = ov_e - ov_s
            if ln > 0:
                if mc:
                    for ch in range(c.shape[1]):
                        out[ov_s:ov_e, ch] *= fo[:ln]
                else:
                    out[ov_s:ov_e] *= fo[:ln]
            wp = ov_s  # overlap the head onto the faded tail
        end = min(wp + len(c), n_samples)
        seg = end - wp
        out[wp:end] += c[:seg]
        wp = end
        first = False

    return out[:n_samples].astype(np.float32)


def _continuous_identity_streams(events, clips, n_identities,
                                 n_samples, n_channels, sr):
    """
    For each identity, concatenate all of its event clips (with tiny
    crossfades) and loop-tile to full length, producing a continuous
    per-identity material stream. Identities with no events return
    silence. Returns a list of n_identities arrays.
    """
    import numpy as np

    groups = {k: [] for k in range(n_identities)}
    for ev, clip in zip(events, clips):
        groups[ev["identity"]].append(clip)

    streams = []
    for k in range(n_identities):
        gk = groups[k]
        if not gk:
            if n_channels == 1:
                streams.append(np.zeros(n_samples, dtype=np.float32))
            else:
                streams.append(
                    np.zeros((n_samples, n_channels), dtype=np.float32))
            continue
        # Concatenate this identity's material (no truncation to a
        # fixed length here — we want the raw concatenated material).
        total = sum(len(c) for c in gk)
        concat = _concatenate_clips(gk, sr, total, n_channels, compact=True)
        streams.append(_loop_to_length(concat, n_samples, sr))
    return streams


def _ensure_stereo(output):
    """Upmix a mono array to dual-mono stereo (L == R) for 'stereo' format."""
    import numpy as np
    if output.ndim == 1:
        return np.column_stack([output, output]).astype(np.float32)
    return output


# ═══════════════════════════════════════════════════════════════════════════
# Stage 7 — Output
# ═══════════════════════════════════════════════════════════════════════════

def write_stats_file(path, identities, events, Z, n_identities, mode,
                     hop_sec=0.01, analysis_channel=1, mean_confidence=0.0,
                     n_features=0, output_format="stereo"):

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
        f.write("analysis_channel=%d\n" % analysis_channel)
        f.write("mean_confidence=%.4f\n" % mean_confidence)
        f.write("n_features=%d\n" % n_features)
        f.write("output_format=%s\n" % output_format)
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
    if len(sys.argv) not in (10, 11):
        print("Usage: python identity_separation.py "
              "input.wav features.csv output.wav stats.txt "
              "mode n_identities output_format seed hop_sec [analysis_channel]",
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
    analysis_channel = int(sys.argv[10]) if len(sys.argv) > 10 else 1

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
    if audio.ndim == 1:
        audio_mono = audio
        analysis_channel = 1
    else:
        analysis_channel = max(1, min(n_channels, analysis_channel))
        audio_mono = audio[:, analysis_channel - 1]
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
    identities = characterize_identities(
        Z, praat_feats, spec_feats, n_identities, hop_sec=hop_sec)

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
    layers = build_identity_layers(
        events, clips, n_identities, n_samples, n_channels, sr,
        fade_edges=(out_format == "multi"))

    # ---- Output ----
    if out_format == "multi" and n_identities > 1:
        # Multi-channel = one identity per channel. This is a raw
        # per-identity separation; the resynthesis Mode does NOT apply
        # here, so we skip the (otherwise discarded) resynthesis call.
        print("    [multi] Writing one identity per channel; "
              "resynthesis mode %s is NOT applied to audio." % mode)
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
        sf.write(out_wav, multi, sr, subtype="FLOAT")
        output = multi  # for the console summary below
    else:
        # ---- Resynthesis (only needed for non-multi output) ----
        print("  [Py 6/6] Resynthesizing (mode %s)..." % mode)
        output = resynthesize(mode, events, clips, layers, identities,
                              probs, sr, n_samples, n_channels,
                              n_identities, Z=Z, hop_sec=hop_sec)
        # "stereo" format guarantees a 2-channel file for every mode.
        if out_format == "stereo":
            output = _ensure_stereo(output)
        sf.write(out_wav, output, sr, subtype="FLOAT")

    # ---- Stats ----
    write_stats_file(
        stats_file, identities, events, Z, n_identities, mode, hop_sec,
        analysis_channel=analysis_channel, mean_confidence=float(np.mean(C)),
        n_features=len(feat_names), output_format=out_format)

    # ---- Console summary ----
    transitions = int(np.sum(np.diff(Z) != 0))
    out_shape = output.shape if hasattr(output, 'shape') else '?'
    print("    Transitions: %d  |  Events: %d" % (
        transitions, len(events)))
    print("OK: wrote %s  (%s)" % (out_wav, out_format))


if __name__ == "__main__":
    main()
