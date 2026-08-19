"""
pitch_tracked_additive.py — IRCAM-style Pitch-Tracked Additive Resynthesizer
Version: 1.5 (2026)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python pitch_tracked_additive.py input.wav f0.csv intensity.csv
        output.wav stats.txt [options]

Synthesis is sample-accurate phase-accumulation additive synthesis:

    phase_k[n] = phase_k[n-1] + 2*pi*freq_k[n] / sr
    y[n]       = envelope[n] * sum_k amp_k[n] * sin(phase_k[n] + offset_k)

Partial families: harmonic, odd_only, even_only, subharmonic,
                  inharmonic_power, frequency_shifted, ring_sidebands,
                  fm_sidebands

Amplitude laws:   1_over_k, 1_over_k_squared, equal,
                  spectral_tilt_db_per_octave, gaussian_formant_band,
                  random_static, random_slow

Voicing policies: silence_unvoiced, noise_unvoiced, copy_original_unvoiced

Research modes:   none (default; full artistic engine, unchanged), and
                  prosody_only (constrained preset for unintelligible,
                  speech-derived prosodic stimuli — synthesized from the
                  extracted F0 + intensity envelope only; no formant
                  modeling, no reuse of the original waveform, voicing/
                  pause structure and duration preserved).

No external model downloads. No internet. No PyTorch/TensorFlow/sklearn.

Version 1.5 correctness / robustness changes:
  - Analysis channel is explicit (--analysis_channel, 1-based), so Praat pitch/
    intensity extraction and Python envelope/RMS/copy-original paths use the
    same representative channel instead of channel-1 vs stereo-average.
  - Non-original --duration now time-scales the complete F0 / voicing /
    intensity trajectories to the requested duration instead of cropping or
    holding the final analysis frame.
  - F0 median/low-pass smoothing is performed independently inside each voiced
    segment; pitch no longer bleeds across pauses.
  - Voiced fades are constrained to voiced segments, fixing leakage from very
    short voiced islands into surrounding unvoiced regions.
  - 1/k and 1/k^2 use paired order ranks for ring/FM sidebands, so matching
    upper/lower sidebands receive matching law weights.
  - random_slow amplitude modulation is generated one partial at a time; the
    engine no longer allocates a P x N amplitude matrix.
  - Partial-frequency statistics are also computed one row at a time, keeping
    the long-file memory design O(N) rather than accidentally rebuilding P x N.
  - Oscillator phase keeps advancing while a voiced partial is temporarily
    outside the render band, so re-entry does not resume from a frozen phase.
"""

import sys
import os
import csv
import math

PRAAT_TEMP_PREFIX = "temp_ptadd_"


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

def check_dependencies():
    missing = []
    for pkg in ["numpy", "soundfile", "scipy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


def _is_praat_temp(path):
    return os.path.basename(path).startswith(PRAAT_TEMP_PREFIX)


def load_csv_two_cols(path, col_a, col_b, col_c=None):
    """Load CSV; return list of dicts."""
    rows = []
    with open(path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                a = float(row[col_a])
                b = float(row[col_b])
                if col_c is not None:
                    c = float(row[col_c])
                    rows.append((a, b, c))
                else:
                    rows.append((a, b))
            except (ValueError, KeyError):
                continue
    return rows


# ═══════════════════════════════════════════════════════════════════════════
# F0 + envelope interpolation/smoothing
# ═══════════════════════════════════════════════════════════════════════════

def interpolate_f0_to_samplerate(f0_rows, n_samples, sr, time_scale=1.0):
    """
    f0_rows: list of (time, f0_hz, voiced) tuples on the SOURCE time axis.
    Returns (f0_arr, voiced_arr), both length n_samples.

    time_scale maps output sample time back to source-analysis time.  A value
    source_duration / output_duration therefore stretches/compresses the full
    tracked contour to the requested output duration.  time_scale=1 preserves
    the historical same-duration behaviour.
    """
    import numpy as np

    if not f0_rows:
        return (np.zeros(n_samples, dtype=np.float64),
                np.zeros(n_samples, dtype=np.float64))

    times = np.array([r[0] for r in f0_rows], dtype=np.float64)
    f0s   = np.array([r[1] for r in f0_rows], dtype=np.float64)
    vois  = np.array([r[2] for r in f0_rows], dtype=np.float64)

    sample_times = (np.arange(n_samples, dtype=np.float64) / sr) * float(time_scale)

    # Linear interpolation + threshold is equivalent to nearest-boundary
    # switching for the binary voiced flag, while supporting time scaling.
    voiced_arr = np.interp(sample_times, times, vois)
    voiced_arr = (voiced_arr >= 0.5).astype(np.float64)

    voiced_idx = np.where(vois > 0.5)[0]
    if len(voiced_idx) == 0:
        return np.zeros(n_samples, dtype=np.float64), voiced_arr

    voiced_times = times[voiced_idx]
    voiced_f0    = f0s[voiced_idx]
    f0_arr = np.interp(sample_times, voiced_times, voiced_f0,
                       left=voiced_f0[0], right=voiced_f0[-1])
    f0_arr *= voiced_arr
    return f0_arr, voiced_arr


def _true_runs(mask):
    """Return half-open [start, end) runs where a boolean mask is True."""
    import numpy as np
    m = np.asarray(mask, dtype=np.int8)
    if m.size == 0:
        return []
    edges = np.diff(np.concatenate(([0], m, [0])))
    starts = np.where(edges == 1)[0]
    ends   = np.where(edges == -1)[0]
    return list(zip(starts.tolist(), ends.tolist()))


def smooth_f0(f0_arr, voiced_arr, sr,
              median_window_ms=20.0, lowpass_cutoff_hz=12.0):
    """
    Median-filter then low-pass smooth EACH contiguous voiced segment.
    Unvoiced samples remain exactly zero, and pitch information cannot bleed
    across a pause into the next voiced segment.
    """
    import numpy as np
    from scipy.ndimage import median_filter
    from scipy.signal import butter, sosfiltfilt

    out = np.zeros_like(f0_arr, dtype=np.float64)
    voiced_mask = np.asarray(voiced_arr) > 0.5
    if not np.any(voiced_mask):
        return out

    base_win = max(3, int(median_window_ms * 1e-3 * sr))
    if base_win % 2 == 0:
        base_win += 1

    nyq = sr / 2.0
    cutoff = min(lowpass_cutoff_hz, nyq * 0.45)
    sos = None
    if cutoff > 0.5:
        try:
            sos = butter(2, cutoff / nyq, btype="low", output="sos")
        except Exception:
            sos = None

    for start, end in _true_runs(voiced_mask):
        seg = np.asarray(f0_arr[start:end], dtype=np.float64).copy()
        L = len(seg)
        if L == 0:
            continue

        # Nearest-edge median filtering avoids the zero-padding edge sag of
        # scipy.signal.medfilt and never consults samples across a pause.
        win = min(base_win, L if L % 2 == 1 else max(1, L - 1))
        if win >= 3:
            seg = median_filter(seg, size=win, mode="nearest")

        if sos is not None and L > 16:
            try:
                seg = sosfiltfilt(sos, seg)
            except Exception:
                pass

        seg[~np.isfinite(seg)] = 0.0
        seg[seg < 0.0] = 0.0
        out[start:end] = seg

    return out


def interpolate_intensity_to_samplerate(int_rows, n_samples, sr, time_scale=1.0):
    """Interpolate source-time intensity dB onto the requested output time axis."""
    import numpy as np
    if not int_rows:
        return np.zeros(n_samples, dtype=np.float64)

    times = np.array([r[0] for r in int_rows], dtype=np.float64)
    db    = np.array([r[1] for r in int_rows], dtype=np.float64)
    sample_times = (np.arange(n_samples, dtype=np.float64) / sr) * float(time_scale)
    return np.interp(sample_times, times, db, left=db[0], right=db[-1])


def db_to_envelope(db_arr, sr, ar_smoothing_ms):
    """
    Convert intensity dB curve to a linear envelope normalised to peak 1.0,
    then apply attack/release smoothing (one-pole asymmetric IIR).
    """
    import numpy as np

    # Replace -inf / very low with a floor
    valid = db_arr[np.isfinite(db_arr)]
    if len(valid) == 0:
        return np.zeros_like(db_arr)
    max_db = float(np.max(valid))
    if max_db <= 0:
        max_db = float(np.max(db_arr))

    norm_db = db_arr - max_db
    norm_db = np.clip(norm_db, -60.0, 0.0)
    env = 10.0 ** (norm_db / 20.0)
    env[~np.isfinite(env)] = 0.0
    env = np.clip(env, 0.0, 1.0)

    # Attack/release smoothing — one-pole IIR via lfilter (C speed)
    if ar_smoothing_ms > 0:
        from scipy.signal import lfilter
        tau = max(1e-4, ar_smoothing_ms * 1e-3)
        alpha = math.exp(-1.0 / (tau * sr))
        b = [1.0 - alpha]
        a = [1.0, -alpha]
        out = lfilter(b, a, env).astype(np.float64)
        return out
    return env


def rms_envelope(audio_mono, sr, window_ms=20.0):
    """RMS-based envelope at sample rate."""
    import numpy as np
    win = max(8, int(window_ms * 1e-3 * sr))
    sq = audio_mono.astype(np.float64) ** 2
    # Vectorised sliding RMS via cumsum — no Python loop
    cs = np.concatenate(([0.0], np.cumsum(sq)))
    half = win // 2
    lo = np.maximum(0, np.arange(len(sq)) - half)
    hi = np.minimum(len(sq), np.arange(len(sq)) + half)
    window_sum = cs[hi] - cs[lo]
    window_len = (hi - lo).astype(np.float64)
    out = np.sqrt(np.maximum(0.0, window_sum / window_len))
    peak = np.max(out)
    if peak > 0:
        out /= peak
    return out


# ═══════════════════════════════════════════════════════════════════════════
# Partial generation
# ═══════════════════════════════════════════════════════════════════════════

def build_partial_freqs(f0_arr, num_partials, family,
                        beta=1.03, freq_shift=0.0,
                        ring_mod_hz=80.0,
                        fm_ratio=2.0, fm_index=2.0):
    """
    Returns a (P, N) array of instantaneous partial frequencies, where P is
    the actual number of generated partials (may differ from num_partials
    for ring_sidebands and fm_sidebands).

    Also returns a (P,) array of base amplitude weights (used for FM/ring
    bias before the amplitude law is applied).
    """
    import numpy as np

    n = len(f0_arr)
    f0 = f0_arr  # (N,)

    if family == "harmonic":
        ks = np.arange(1, num_partials + 1, dtype=np.float64)
        freqs = ks[:, None] * f0[None, :]
        weights = np.ones(num_partials, dtype=np.float64)

    elif family == "odd_only":
        ks = (2 * np.arange(1, num_partials + 1) - 1).astype(np.float64)
        freqs = ks[:, None] * f0[None, :]
        weights = np.ones(num_partials, dtype=np.float64)

    elif family == "even_only":
        ks = (2 * np.arange(1, num_partials + 1)).astype(np.float64)
        freqs = ks[:, None] * f0[None, :]
        weights = np.ones(num_partials, dtype=np.float64)

    elif family == "subharmonic":
        ks = np.arange(1, num_partials + 1, dtype=np.float64)
        freqs = f0[None, :] / ks[:, None]
        weights = np.ones(num_partials, dtype=np.float64)

    elif family == "inharmonic_power":
        ks = np.arange(1, num_partials + 1, dtype=np.float64)
        freqs = (ks[:, None] ** beta) * f0[None, :]
        weights = np.ones(num_partials, dtype=np.float64)

    elif family == "frequency_shifted":
        ks = np.arange(1, num_partials + 1, dtype=np.float64)
        freqs = ks[:, None] * f0[None, :] + freq_shift
        freqs = np.abs(freqs)
        weights = np.ones(num_partials, dtype=np.float64)

    elif family == "ring_sidebands":
        # For each k from 1..num_partials produce upper & lower sideband
        ks = np.arange(1, num_partials + 1, dtype=np.float64)
        base = ks[:, None] * f0[None, :]
        upper = np.abs(base + ring_mod_hz)
        lower = np.abs(base - ring_mod_hz)
        freqs = np.concatenate([upper, lower], axis=0)
        # Sidebands come in pairs at half amplitude (classic ring-mod)
        weights = np.full(2 * num_partials, 0.5, dtype=np.float64)

    elif family == "fm_sidebands":
        # carrier = f0, modulator = fm_ratio * f0
        # sideband_n = carrier +/- n * modulator, n=0..num_partials
        # amplitude weights ≈ Bessel-like decay |J_n(fm_index)|
        # We approximate with simple decay so we don't pull in scipy.special
        order_max = num_partials
        ns = np.arange(0, order_max + 1)  # 0..N
        carrier = f0
        mod     = fm_ratio * f0
        # n=0 (single)
        f_zero = np.abs(carrier)[None, :]  # (1, N)
        # n>=1 (pairs)
        ns_pos = ns[1:]
        upper = np.abs(carrier[None, :] + ns_pos[:, None] * mod[None, :])
        lower = np.abs(carrier[None, :] - ns_pos[:, None] * mod[None, :])
        freqs = np.concatenate([f_zero, upper, lower], axis=0)
        # Bessel-like decay: weight_n = (fm_index/2)^n / n!
        decay = []
        for n_idx in ns:
            n_fact = math.factorial(n_idx)
            w = (fm_index / 2.0) ** n_idx / max(1.0, n_fact)
            decay.append(w)
        decay = np.array(decay, dtype=np.float64)
        # Normalise so peak weight = 1
        if np.max(decay) > 0:
            decay = decay / np.max(decay)
        # Order: [n=0, n=1 upper, n=2 upper, ..., n=1 lower, n=2 lower, ...]
        w_zero  = np.array([decay[0]])
        w_upper = decay[1:].copy()
        w_lower = decay[1:].copy()
        weights = np.concatenate([w_zero, w_upper, w_lower])

    else:
        # Fallback to harmonic
        ks = np.arange(1, num_partials + 1, dtype=np.float64)
        freqs = ks[:, None] * f0[None, :]
        weights = np.ones(num_partials, dtype=np.float64)

    return freqs, weights


def partial_count(num_partials, family):
    """Actual oscillator count for a requested family."""
    n = max(1, int(num_partials))
    if family == "ring_sidebands":
        return 2 * n
    if family == "fm_sidebands":
        return 1 + 2 * n
    return n


def partial_order_ranks(num_partials, family):
    """
    Order coordinate used by the abstract 1/k and 1/k^2 amplitude laws.

    Ring/FM upper and lower sidebands of the SAME modulation order share a
    rank.  This fixes the old flattened-array asymmetry where a lower sideband
    was quieter merely because it appeared later in memory.
    """
    import numpy as np
    n = max(1, int(num_partials))
    if family == "ring_sidebands":
        base = np.arange(1, n + 1, dtype=np.float64)
        return np.concatenate([base, base])
    if family == "fm_sidebands":
        sb = np.arange(2, n + 2, dtype=np.float64)  # carrier rank=1, n-th SB rank=n+1
        return np.concatenate([np.array([1.0]), sb, sb])
    return np.arange(1, partial_count(n, family) + 1, dtype=np.float64)


def partial_frequency_row(f0_arr, p_idx, num_partials, family,
                          beta=1.03, freq_shift=0.0,
                          ring_mod_hz=80.0, fm_ratio=2.0):
    """Compute one instantaneous-frequency row without allocating P x N."""
    import numpy as np
    f0 = np.asarray(f0_arr, dtype=np.float32)
    p_idx = int(p_idx)
    n = max(1, int(num_partials))

    if family == "harmonic":
        return np.float32(p_idx + 1) * f0
    if family == "odd_only":
        return np.float32(2 * (p_idx + 1) - 1) * f0
    if family == "even_only":
        return np.float32(2 * (p_idx + 1)) * f0
    if family == "subharmonic":
        return f0 / np.float32(p_idx + 1)
    if family == "inharmonic_power":
        return np.float32(float(p_idx + 1) ** beta) * f0
    if family == "frequency_shifted":
        return np.abs(np.float32(p_idx + 1) * f0 + np.float32(freq_shift))
    if family == "ring_sidebands":
        half = n
        base_k = float((p_idx % half) + 1)
        base = np.float32(base_k) * f0
        return (np.abs(base + np.float32(ring_mod_hz)) if p_idx < half
                else np.abs(base - np.float32(ring_mod_hz)))
    if family == "fm_sidebands":
        mod = np.float32(fm_ratio) * f0
        if p_idx == 0:
            return np.abs(f0)
        if p_idx <= n:
            return np.abs(f0 + np.float32(p_idx) * mod)
        order = p_idx - n
        return np.abs(f0 - np.float32(order) * mod)
    return np.float32(p_idx + 1) * f0


def amplitude_law_weights(freqs_mean, num_partials_actual, law, sr,
                          tilt_db_per_oct=-6.0,
                          formant_center=1200.0,
                          formant_bw=500.0,
                          seed=42, n_samples=0, order_ranks=None):
    """
    Returns either:
        - a (P,) static weight array, or
        - a (P, N) time-varying weight array (for random_slow).
    Static weights are still applied per sample as a (P, 1) broadcast.

    freqs_mean: mean frequency per partial (P,) used for spectral tilt /
                formant emphasis weighting.
    """
    import numpy as np
    rng = np.random.RandomState(seed)
    P = num_partials_actual

    if order_ranks is None:
        order_ranks = np.arange(1, P + 1, dtype=np.float64)
    else:
        order_ranks = np.asarray(order_ranks, dtype=np.float64)
        if len(order_ranks) != P:
            order_ranks = np.arange(1, P + 1, dtype=np.float64)
    order_ranks = np.maximum(order_ranks, 1.0)

    if law == "1_over_k":
        return 1.0 / order_ranks

    if law == "1_over_k_squared":
        return 1.0 / (order_ranks ** 2)

    if law == "equal":
        return np.ones(P, dtype=np.float64)

    if law == "spectral_tilt_db_per_octave":
        ref = max(1.0, float(np.min(freqs_mean[freqs_mean > 0]) if np.any(freqs_mean > 0) else 1.0))
        f = np.maximum(1.0, freqs_mean)
        octaves = np.log2(f / ref)
        db = tilt_db_per_oct * octaves
        return 10.0 ** (db / 20.0)

    if law == "gaussian_formant_band":
        bw = max(1.0, formant_bw)
        out = np.exp(-0.5 * ((freqs_mean - formant_center) / bw) ** 2)
        return out

    if law == "random_static":
        return rng.uniform(0.1, 1.0, size=P)

    if law == "random_slow":
        if n_samples <= 0:
            return rng.uniform(0.1, 1.0, size=P)
        # Vectorised: generate all partial LFOs in one shot
        f_lfo  = rng.uniform(0.2, 2.0,       size=(P, 1))  # (P, 1)
        phase0 = rng.uniform(0,   2*np.pi,   size=(P, 1))
        depth  = rng.uniform(0.3, 1.0,       size=(P, 1))
        base   = rng.uniform(0.3, 1.0,       size=(P, 1))
        t = np.arange(n_samples, dtype=np.float64) / max(1.0, sr)  # (N,)
        out = base + depth * 0.5 * np.sin(2 * np.pi * f_lfo * t + phase0)  # (P, N)
        return np.clip(out, 0.0, None)

    # Unknown
    return np.ones(P, dtype=np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Main synthesis
# ═══════════════════════════════════════════════════════════════════════════

def synthesise_additive(f0_arr, voiced_arr, env_arr, sr,
                         num_partials, family,
                         beta, freq_shift,
                         ring_mod_hz, fm_ratio, fm_index,
                         amp_law, tilt_db_per_oct,
                         formant_center, formant_bw,
                         seed):
    """
    Sample-accurate phase-accumulation additive synthesis.

    Peak working memory is O(N), not O(P*N): frequency rows and random-slow
    amplitude LFOs are generated one partial at a time.
    """
    import numpy as np
    rng = np.random.RandomState(seed)

    n = len(f0_arr)
    if n == 0:
        return np.zeros(0, dtype=np.float32), np.zeros(0, dtype=np.float64)

    nyq   = sr / 2.0
    f_max = nyq * 0.95
    f_min = 20.0
    tpsr  = np.float32(2.0 * np.pi / sr)

    voiced_mask = np.asarray(voiced_arr) > 0.5
    fade_len = max(8, int(0.005 * sr))
    fade_mask = _build_voiced_fade(voiced_mask, fade_len).astype(np.float32)
    master_env = (env_arr * fade_mask).astype(np.float32)

    # Tiny downsampled matrix only for mean-frequency amplitude laws and the
    # existing FM/ring family base weights.
    stride = 64
    f0_ds = f0_arr[::stride]
    freqs_ds, base_w = build_partial_freqs(
        f0_ds, num_partials, family,
        beta=beta, freq_shift=freq_shift,
        ring_mod_hz=ring_mod_hz,
        fm_ratio=fm_ratio, fm_index=fm_index,
    )
    P = freqs_ds.shape[0]

    if np.any(voiced_mask):
        voiced_ds = voiced_mask[::stride]
        if np.any(voiced_ds):
            fv = freqs_ds[:, voiced_ds]
            in_band_ds = (fv >= f_min) & (fv <= f_max)
            f_masked = np.where(in_band_ds, fv, np.nan)
            with np.errstate(all="ignore"):
                mean_f = np.nanmean(f_masked, axis=1)
            mean_f = np.where(np.isfinite(mean_f), mean_f, 0.0)
        else:
            mean_f = np.zeros(P, dtype=np.float64)
    else:
        mean_f = np.zeros(P, dtype=np.float64)

    ranks = partial_order_ranks(num_partials, family)
    time_varying_amp = (amp_law == "random_slow")
    if time_varying_amp:
        # Same RNG draw order as the old vectorised P x N implementation, but
        # only four P-length descriptor vectors are retained.
        rng_amp = np.random.RandomState(seed)
        lfo_f     = rng_amp.uniform(0.2, 2.0, size=P)
        lfo_phase = rng_amp.uniform(0.0, 2.0 * np.pi, size=P)
        lfo_depth = rng_amp.uniform(0.3, 1.0, size=P)
        lfo_base  = rng_amp.uniform(0.3, 1.0, size=P)
        t = np.arange(n, dtype=np.float64) / max(1.0, sr)
        combined_amp = None
    else:
        amp_w = amplitude_law_weights(
            mean_f, P, amp_law, sr,
            tilt_db_per_oct=tilt_db_per_oct,
            formant_center=formant_center,
            formant_bw=formant_bw,
            seed=seed, n_samples=0, order_ranks=ranks,
        )
        combined_amp = (amp_w * base_w).astype(np.float32)

    phase_offsets = rng.uniform(0, 2 * np.pi, size=P).astype(np.float32)
    voiced_f32 = voiced_mask.astype(np.float32)
    y = np.zeros(n, dtype=np.float32)

    for p_idx in range(P):
        freq = partial_frequency_row(
            f0_arr, p_idx, num_partials, family,
            beta=beta, freq_shift=freq_shift,
            ring_mod_hz=ring_mod_hz, fm_ratio=fm_ratio,
        )
        freq = np.nan_to_num(freq, nan=0.0, posinf=0.0, neginf=0.0).astype(np.float32)
        in_band = (freq >= np.float32(f_min)) & (freq <= np.float32(f_max))

        # Advance phase throughout each voiced region even when a partial is
        # temporarily out of the audible/render band.  Only its AMPLITUDE is
        # gated.  The old code froze phase out-of-band, causing arbitrary phase
        # on re-entry.
        phase_freq = freq * voiced_f32
        phase = np.cumsum(phase_freq * tpsr, dtype=np.float64) + float(phase_offsets[p_idx])
        osc = np.sin(phase).astype(np.float32)
        osc *= in_band.astype(np.float32)

        if time_varying_amp:
            slow = (lfo_base[p_idx]
                    + lfo_depth[p_idx] * 0.5
                    * np.sin(2.0 * np.pi * lfo_f[p_idx] * t + lfo_phase[p_idx]))
            slow = np.clip(slow, 0.0, None).astype(np.float32)
            osc *= slow * np.float32(base_w[p_idx])
        else:
            osc *= combined_amp[p_idx]

        y += osc

    y /= max(1.0, math.sqrt(P))
    y *= master_env
    y = np.nan_to_num(y, nan=0.0, posinf=0.0, neginf=0.0)
    return y, mean_f


def _build_voiced_fade(voiced_mask, fade_len):
    """
    Build a [0..1] fade envelope strictly INSIDE voiced runs.

    Short voiced islands become a short triangular envelope rather than writing
    a fade beyond the run into surrounding unvoiced samples.
    """
    import numpy as np
    voiced_mask = np.asarray(voiced_mask, dtype=bool)
    out = np.zeros(len(voiced_mask), dtype=np.float64)
    if fade_len < 2:
        return voiced_mask.astype(np.float64)

    denom = float(max(1, fade_len - 1))
    for start, end in _true_runs(voiced_mask):
        L = end - start
        if L <= 0:
            continue
        idx = np.arange(L, dtype=np.float64)
        fade_in  = np.minimum(1.0, idx / denom)
        fade_out = np.minimum(1.0, (L - 1 - idx) / denom)
        out[start:end] = np.minimum(fade_in, fade_out)
    return out


# ═══════════════════════════════════════════════════════════════════════════
# Voicing-policy handling for unvoiced regions
# ═══════════════════════════════════════════════════════════════════════════

def apply_voicing_policy(y, audio_orig_mono, voiced_arr, env_arr, sr,
                         policy, seed):
    """
    y:                synthesised voiced signal (mono float32)
    audio_orig_mono:  original mono input (same length, padded/trimmed)
    voiced_arr:       0/1 voiced flag per sample
    env_arr:          envelope (used to shape unvoiced noise)
    """
    import numpy as np
    from scipy.signal import butter, filtfilt
    rng = np.random.RandomState(seed + 1)

    voiced_mask = voiced_arr > 0.5
    unvoiced_mask = ~voiced_mask

    if policy == "silence_unvoiced":
        return y  # already silent in unvoiced regions (voiced fade mask)

    if policy == "noise_unvoiced":
        if not np.any(unvoiced_mask):
            return y
        # Filtered white noise shaped by envelope, only in unvoiced regions
        noise = rng.randn(len(y)).astype(np.float64)
        nyq = sr / 2.0
        try:
            b, a = butter(2, [200.0 / nyq, min(0.95, 6000.0 / nyq)],
                          btype="band")
            noise = filtfilt(b, a, noise)
        except Exception:
            pass
        # Normalise noise to ~0.3 amplitude before envelope
        peak = float(np.max(np.abs(noise)))
        if peak > 0:
            noise = noise * (0.3 / peak)
        # Apply envelope and unvoiced mask only
        noise = noise * env_arr * unvoiced_mask.astype(np.float64)
        # Smooth the unvoiced mask to avoid clicks at boundaries
        from scipy.signal import lfilter
        fade_len = max(8, int(0.005 * sr))
        smooth = unvoiced_mask.astype(np.float64).copy()
        # Simple two-pass moving average smoothing on the mask
        if fade_len >= 2:
            kernel = np.ones(fade_len) / fade_len
            smooth = np.convolve(smooth, kernel, mode="same")
        noise = noise * smooth
        return (y + noise.astype(np.float32)).astype(np.float32)

    if policy == "copy_original_unvoiced":
        if len(audio_orig_mono) != len(y):
            # Should not happen — caller should align lengths
            return y
        # Mix the original waveform back in only where unvoiced
        m = unvoiced_mask.astype(np.float32)
        # Smooth boundaries
        fade_len = max(8, int(0.005 * sr))
        if fade_len >= 2:
            kernel = np.ones(fade_len, dtype=np.float32) / fade_len
            m = np.convolve(m, kernel, mode="same")
        return (y + audio_orig_mono.astype(np.float32) * m).astype(np.float32)

    return y


# ═══════════════════════════════════════════════════════════════════════════
# Stereo rendering
# ═══════════════════════════════════════════════════════════════════════════

def render_stereo(mono, sr, mode):
    """Return (N, 2) float32 stereo array."""
    import numpy as np
    n = len(mono)
    out = np.zeros((n, 2), dtype=np.float32)

    if mode == "mono":
        out[:, 0] = mono
        out[:, 1] = mono
        return out

    if mode == "haas_width":
        delay = max(1, int(sr * 0.0008))   # ~0.8 ms Haas
        out[:, 0] = mono
        if delay < n:
            out[delay:, 1] = mono[: n - delay]
        return out

    # partial_spread: subtle decorrelation via short cross-comb
    if mode == "partial_spread":
        d1 = max(1, int(sr * 0.0004))
        d2 = max(1, int(sr * 0.0009))
        out[:, 0] = mono
        if d1 < n:
            out[d1:, 0] = 0.85 * mono[: n - d1] + 0.15 * mono[d1:]
        out[:, 1] = mono
        if d2 < n:
            out[d2:, 1] = 0.85 * mono[: n - d2] + 0.15 * mono[d2:]
        return out

    out[:, 0] = mono
    out[:, 1] = mono
    return out


# ═══════════════════════════════════════════════════════════════════════════
# Loudness compensation (same pattern as latent_barycentric)
# ═══════════════════════════════════════════════════════════════════════════

def apply_loudness_compensation(stereo, ref_rms, mode="rms"):
    import numpy as np
    PEAK_CEILING = 0.891   # -1 dBFS

    if mode == "none":
        return stereo

    out = stereo.astype(np.float32)
    peak = float(np.max(np.abs(out)))
    if peak < 1e-9:
        return out

    if mode == "peak":
        out *= PEAK_CEILING / peak
        return out

    out_rms = float(np.sqrt(np.mean(out ** 2)))
    if out_rms < 1e-9:
        return out

    if ref_rms > 1e-9:
        out *= ref_rms / out_rms

    peak_after = float(np.max(np.abs(out)))
    if peak_after > PEAK_CEILING:
        out *= PEAK_CEILING / peak_after
    return out


# ═══════════════════════════════════════════════════════════════════════════
# Stats writer
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, n_samples, sr, duration,
                voiced_percent, f0_stats,
                num_partials, partial_family, amp_law,
                normalize_mode,
                rms_in, rms_out, peak_out,
                warnings,
                partial_freq_table,
                f0_trace=None,
                research_info=None,
                analysis_channel=1):
    """
    f0_stats: dict with mean, median, min, max
    partial_freq_table: list of (min, max, mean) per partial (up to 16)
    f0_trace: optional list of (time, f0_hz) tuples (downsampled for plot)
    """
    with open(path, "w") as f:
        f.write("n_samples=%d\n"      % n_samples)
        f.write("sample_rate=%d\n"    % sr)
        f.write("duration=%.3f\n"     % duration)
        f.write("analysis_channel=%d\n" % int(analysis_channel))
        f.write("voiced_percent=%.2f\n" % voiced_percent)
        f.write("f0_mean_hz=%.3f\n"   % f0_stats["mean"])
        f.write("f0_median_hz=%.3f\n" % f0_stats["median"])
        f.write("f0_min_hz=%.3f\n"    % f0_stats["min"])
        f.write("f0_max_hz=%.3f\n"    % f0_stats["max"])
        f.write("num_partials=%d\n"   % num_partials)
        f.write("partial_family=%s\n" % partial_family)
        f.write("amplitude_law=%s\n"  % amp_law)
        f.write("normalize_mode=%s\n" % normalize_mode)
        f.write("rms_input=%.6f\n"    % rms_in)
        f.write("rms_output=%.6f\n"   % rms_out)
        f.write("peak_output=%.6f\n"  % peak_out)

        # ── Research-mode / safety / QC block (additive keys) ──
        # Key names deliberately avoid containing any existing stat key as a
        # substring (e.g. eff_partials, not effective_num_partials) so the
        # Praat substring-based stats parser cannot mis-match them.
        if research_info is not None:
            def _b(x):
                return "true" if bool(x) else "false"
            f.write("research_mode=%s\n"            % research_info.get("research_mode", "none"))
            f.write("prosody_carrier=%s\n"          % research_info.get("prosody_carrier", "none"))
            f.write("prosody_only_safety=%s\n"      % _b(research_info.get("prosody_only_safety", False)))
            f.write("copied_original_waveform=%s\n" % _b(research_info.get("copied_original_waveform", False)))
            f.write("formant_modeling_used=%s\n"    % _b(research_info.get("formant_modeling_used", False)))
            f.write("original_unvoiced_copied=%s\n" % _b(research_info.get("original_unvoiced_copied", False)))
            f.write("duration_preserved=%s\n"       % _b(research_info.get("duration_preserved", False)))
            # Final EFFECTIVE synthesis parameters (after research overrides):
            f.write("eff_partials=%d\n"  % int(research_info.get("eff_partials", 0)))
            f.write("eff_family=%s\n"    % research_info.get("eff_family", ""))
            f.write("eff_amplaw=%s\n"    % research_info.get("eff_amplaw", ""))
            f.write("eff_envsource=%s\n" % research_info.get("eff_envsource", ""))
            f.write("eff_voicing=%s\n"   % research_info.get("eff_voicing", ""))
            f.write("eff_stereo=%s\n"    % research_info.get("eff_stereo", ""))
            f.write("eff_normmode=%s\n"  % research_info.get("eff_normmode", ""))
            f.write("eff_carrier=%s\n"   % research_info.get("eff_carrier", "none"))

        # Partial table
        n_entries = min(16, len(partial_freq_table))
        f.write("n_partial_entries=%d\n" % n_entries)
        for i in range(n_entries):
            pmin, pmax, pmean = partial_freq_table[i]
            f.write("partial_%d=%.3f,%.3f,%.3f\n" % (i + 1, pmin, pmax, pmean))

        # F0 trace (downsampled) for plotting
        if f0_trace is not None:
            n_pts = min(400, len(f0_trace))
            f.write("n_f0_pts=%d\n" % n_pts)
            for i in range(n_pts):
                t, v = f0_trace[i]
                f.write("f0pt_%d=%.4f,%.3f\n" % (i, t, v))

        if warnings:
            f.write("warnings=%s\n" % "; ".join(warnings))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════
# Research-mode safety constraints (prosody-only stimuli)
# ═══════════════════════════════════════════════════════════════════════════

def apply_research_mode_constraints(args, warnings_list):
    """
    Enforce a safe, constrained preset for "prosody-only" research stimuli.

    Goal of prosody_only: an unintelligible, speech-derived rendering that
    preserves F0 movement, intensity envelope, voicing/pause structure and
    duration, but does NOT preserve recognizable words, phonemes, formant
    trajectories, or the original unvoiced consonants. The audible output is
    synthesized from the extracted F0 + envelope ONLY — the original speech
    waveform is never reused as audio.

    This function (called before anything reads args.*):
      * forces the safe synthesis parameters listed below,
      * appends a warning whenever a user-supplied option is overridden,
      * raises ValueError if a requested setting would reintroduce linguistic
        information (copying original material or modeling formants),
      * explicitly forbids copy_original_unvoiced.

    Returns a dict of safety flags for the stats / QC output. In
    research_mode=none it is a no-op and returns all-false flags.
    """
    safety = {
        "prosody_only_safety": False,
        "copied_original_waveform": False,
        "formant_modeling_used": False,
        "original_unvoiced_copied": False,
    }

    if args.research_mode != "prosody_only":
        # research_mode=none -> behave EXACTLY like the original script.
        return safety

    safety["prosody_only_safety"] = True

    def _override(name, safe_value):
        current = getattr(args, name)
        if current != safe_value:
            warnings_list.append(
                "prosody_only: %s forced from '%s' to '%s'"
                % (name, current, safe_value))
        setattr(args, name, safe_value)

    # ── Hard rejections: settings that reintroduce linguistic information ──
    # copy_original_unvoiced literally mixes the ORIGINAL unvoiced waveform
    # back into the output. Unvoiced segments carry consonantal/segmental
    # (phonetic) information, so this is unsafe for prosody-only stimuli and
    # is never permitted here.
    if args.voicing_policy == "copy_original_unvoiced":
        raise ValueError(
            "prosody_only: copy_original_unvoiced is forbidden — it reuses "
            "the original unvoiced waveform and preserves consonant/segmental "
            "(linguistic) information.")
    # gaussian_formant_band imposes a formant-like spectral envelope, i.e.
    # speech-like coloration. Not allowed in a prosody-only stimulus.
    if args.amplitude_law == "gaussian_formant_band":
        raise ValueError(
            "prosody_only: amplitude_law 'gaussian_formant_band' is forbidden "
            "— it models a formant band (speech-like spectral coloration).")

    # ── Forced safe parameters (regardless of user input) ──
    _override("partial_family", "harmonic")
    # Rolloff is selectable (--prosody_rolloff) between two formant-free
    # harmonic laws: 1_over_k_squared (default; stricter, duller, least
    # speech-like) or 1_over_k (brighter, makes prosody_max_partials clearly
    # audible). Neither introduces formants or original spectral material.
    # This override also disables random_slow / random_static / spectral_tilt
    # / gaussian_formant_band.
    _override("amplitude_law", args.prosody_rolloff)
    _override("envelope_source", "intensity")
    _override("stereo_mode", "mono")
    _override("normalize_mode", "rms")

    # ── Carrier: sets harmonic count and unvoiced handling ──
    carrier = args.prosody_carrier
    if carrier == "hum":
        # Strictest: a single sine following the cleaned F0; silence unvoiced.
        _override("num_partials", 1)
        _override("voicing_policy", "silence_unvoiced")
    elif carrier == "soft_hum":
        # 2-4 harmonics (rolloff via --prosody_rolloff); still no formants.
        n = min(4, max(2, int(args.prosody_max_partials)))
        _override("num_partials", n)
        _override("voicing_policy", "silence_unvoiced")

    # Belt-and-suspenders: never leave a policy that copies original audio.
    if args.voicing_policy == "copy_original_unvoiced":
        _override("voicing_policy", "silence_unvoiced")

    # In this mode the formant_* params are inert (only used by the rejected
    # gaussian_formant_band law); record that no formant modeling is used.
    safety["formant_modeling_used"] = False
    safety["copied_original_waveform"] = False
    safety["original_unvoiced_copied"] = False
    return safety


def main():
    import argparse
    import numpy as np
    import soundfile as sf

    parser = argparse.ArgumentParser(
        description="IRCAM-style pitch-tracked additive resynthesizer"
    )
    parser.add_argument("input_wav")
    parser.add_argument("f0_csv")
    parser.add_argument("intensity_csv")
    parser.add_argument("output_wav")
    parser.add_argument("stats_txt")

    parser.add_argument("--events_csv", default="")
    parser.add_argument("--duration", type=float, default=0.0)
    parser.add_argument("--analysis_channel", type=int, default=1,
                        help="1-based input channel used for RMS/original-waveform paths; "
                             "Praat pitch/intensity analysis should use the same channel")
    parser.add_argument("--num_partials", type=int, default=16)
    parser.add_argument("--partial_family",
        choices=["harmonic", "odd_only", "even_only", "subharmonic",
                 "inharmonic_power", "frequency_shifted",
                 "ring_sidebands", "fm_sidebands"],
        default="harmonic")
    parser.add_argument("--amplitude_law",
        choices=["1_over_k", "1_over_k_squared", "equal",
                 "spectral_tilt_db_per_octave", "gaussian_formant_band",
                 "random_static", "random_slow"],
        default="1_over_k")
    parser.add_argument("--spectral_tilt", type=float, default=-6.0)
    parser.add_argument("--inharmonic_beta", type=float, default=1.03)
    parser.add_argument("--frequency_shift", type=float, default=0.0)
    parser.add_argument("--ring_mod", type=float, default=80.0)
    parser.add_argument("--fm_ratio", type=float, default=2.0)
    parser.add_argument("--fm_index", type=float, default=2.0)
    parser.add_argument("--formant_center", type=float, default=1200.0)
    parser.add_argument("--formant_bw", type=float, default=500.0)
    parser.add_argument("--voicing_policy",
        choices=["silence_unvoiced", "noise_unvoiced",
                 "copy_original_unvoiced"],
        default="silence_unvoiced")
    parser.add_argument("--envelope_source",
        choices=["intensity", "rms", "flat"],
        default="intensity")
    parser.add_argument("--ar_smoothing_ms", type=float, default=15.0)
    parser.add_argument("--stereo_mode",
        choices=["mono", "haas_width", "partial_spread"],
        default="mono")
    parser.add_argument("--normalize_mode",
        choices=["none", "peak", "rms", "loudness"],
        default="rms")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cleanup", action="store_true")

    # ── Research mode (constrained "prosody-only" stimuli) ────────────────
    # research_mode=none behaves EXACTLY like the original artistic engine.
    # research_mode=prosody_only locks a safe preset (see
    # apply_research_mode_constraints): output is synthesized from F0 +
    # intensity only, with no recognizable words/phonemes/formants and no
    # reuse of the original speech waveform.
    parser.add_argument("--research_mode",
        choices=["none", "prosody_only"], default="none")
    # Carrier for prosody_only (ignored when research_mode=none):
    #   hum       -> single sine on F0 (strictest, least intelligible)
    #   soft_hum  -> 2-4 harmonics (see --prosody_rolloff), no formants
    parser.add_argument("--prosody_carrier",
        choices=["hum", "soft_hum"], default="hum")
    # Separate parameter that "explicitly allows" >1 harmonic in prosody_only.
    # hum forces 1; soft_hum clamps this to [2, 4].
    parser.add_argument("--prosody_max_partials", type=int, default=1)
    # Amplitude rolloff for the prosody-only harmonic stack. Both choices are
    # formant-free: 1_over_k_squared is the stricter / duller / least
    # speech-like default; 1_over_k is brighter and makes prosody_max_partials
    # clearly audible. (hum uses a single partial, so rolloff is moot for it.)
    parser.add_argument("--prosody_rolloff",
        choices=["1_over_k_squared", "1_over_k"], default="1_over_k_squared")

    args = parser.parse_args()
    check_dependencies()

    np.random.seed(args.seed)
    warnings_list = []

    # Lock the safe preset BEFORE anything reads args.* (mutates args in place).
    # In research_mode=none this is a no-op and returns all-false safety flags.
    research_safety = apply_research_mode_constraints(args, warnings_list)

    # ── Stage 1: Load ─────────────────────────────────────────────────────
    print("  [Py 1/6] Loading audio + analysis data...")

    if not os.path.exists(args.input_wav):
        print("ERROR: Missing input audio: %s" % args.input_wav, file=sys.stderr)
        sys.exit(1)

    audio, sr = sf.read(args.input_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    if audio.size == 0:
        print("ERROR: Input audio is empty", file=sys.stderr)
        sys.exit(1)

    if audio.ndim == 1:
        analysis_channel = 1
        audio_mono = audio
    else:
        analysis_channel = max(1, min(int(args.analysis_channel), audio.shape[1]))
        audio_mono = audio[:, analysis_channel - 1].astype(np.float32)
    n_in = len(audio_mono)
    orig_dur = n_in / sr

    # Target output length
    out_dur = args.duration if args.duration > 0 else orig_dur
    # prosody_only must preserve the input recording's duration exactly.
    if args.research_mode == "prosody_only":
        if args.duration > 0 and abs(args.duration - orig_dur) > 1e-3:
            warnings_list.append(
                "prosody_only: output duration forced to input "
                "(%.3fs); --duration %.3f ignored" % (orig_dur, args.duration))
        out_dur = orig_dur
    n_out = max(1, int(round(out_dur * sr)))
    duration_preserved = abs(out_dur - orig_dur) < 1e-3
    time_scale = (orig_dur / out_dur) if out_dur > 0 else 1.0

    # Load F0
    if not os.path.exists(args.f0_csv):
        print("ERROR: Missing F0 CSV: %s" % args.f0_csv, file=sys.stderr)
        sys.exit(1)
    f0_rows = load_csv_two_cols(args.f0_csv, "time", "f0_hz", "voiced")
    if not f0_rows:
        print("ERROR: F0 CSV is empty or malformed: %s" % args.f0_csv,
              file=sys.stderr)
        sys.exit(1)

    # Load intensity
    int_rows = []
    if os.path.exists(args.intensity_csv):
        int_rows = load_csv_two_cols(args.intensity_csv,
                                     "time", "intensity_db")
    else:
        warnings_list.append("intensity_csv missing; using flat envelope")

    print("    Audio: %.2fs SR=%d | Output: %.2fs | F0 frames: %d | analysis ch=%d" %
          (orig_dur, sr, out_dur, len(f0_rows), analysis_channel))

    # ── Stage 2: Build sample-rate F0 + envelope ──────────────────────────
    print("  [Py 2/6] Interpolating + smoothing F0 and envelope...")

    f0_arr, voiced_arr = interpolate_f0_to_samplerate(
        f0_rows, n_out, sr, time_scale=time_scale)
    f0_arr = smooth_f0(f0_arr, voiced_arr, sr,
                       median_window_ms=20.0,
                       lowpass_cutoff_hz=12.0)

    voiced_pct = 100.0 * float(np.mean(voiced_arr > 0.5))
    print("    Voiced: %.1f%%" % voiced_pct)

    if voiced_pct < 0.5:
        warnings_list.append("almost no voiced F0 detected")

    # Envelope
    if args.envelope_source == "intensity" and int_rows:
        db_arr = interpolate_intensity_to_samplerate(
            int_rows, n_out, sr, time_scale=time_scale)
        env_arr = db_to_envelope(db_arr, sr, args.ar_smoothing_ms)
    elif args.envelope_source == "rms":
        # Compute RMS envelope from original audio, then resample to n_out
        if n_in > 0:
            rms_in_env = rms_envelope(audio_mono, sr, window_ms=20.0)
            t_src = np.linspace(0, n_in - 1, n_out)
            env_arr = np.interp(t_src, np.arange(n_in), rms_in_env)
        else:
            env_arr = np.ones(n_out, dtype=np.float64)
        if args.ar_smoothing_ms > 0:
            tau = max(1e-4, args.ar_smoothing_ms * 1e-3)
            alpha = math.exp(-1.0 / (tau * sr))
            tmp = np.zeros_like(env_arr)
            prev = env_arr[0]
            for i in range(len(env_arr)):
                prev = alpha * prev + (1.0 - alpha) * env_arr[i]
                tmp[i] = prev
            env_arr = tmp
    else:
        env_arr = np.ones(n_out, dtype=np.float64)

    env_arr[~np.isfinite(env_arr)] = 0.0
    env_arr = np.clip(env_arr, 0.0, 1.0)

    # Reference RMS (for loudness compensation)
    ref_rms = float(np.sqrt(np.mean(audio_mono.astype(np.float64) ** 2)))

    # ── Stage 3: Synthesise ───────────────────────────────────────────────
    print("  [Py 3/6] Additive synthesis (%s, %d partials, %s)..." %
          (args.partial_family, args.num_partials, args.amplitude_law))

    y_mono, mean_partial_f = synthesise_additive(
        f0_arr, voiced_arr, env_arr, sr,
        num_partials=args.num_partials,
        family=args.partial_family,
        beta=args.inharmonic_beta,
        freq_shift=args.frequency_shift,
        ring_mod_hz=args.ring_mod,
        fm_ratio=args.fm_ratio,
        fm_index=args.fm_index,
        amp_law=args.amplitude_law,
        tilt_db_per_oct=args.spectral_tilt,
        formant_center=args.formant_center,
        formant_bw=args.formant_bw,
        seed=args.seed,
    )

    # ── Stage 4: Voicing policy ───────────────────────────────────────────
    print("  [Py 4/6] Applying voicing policy: %s" % args.voicing_policy)

    # Align original mono to n_out for copy_original_unvoiced
    if args.voicing_policy == "copy_original_unvoiced":
        if n_in == n_out:
            orig_aligned = audio_mono.copy()
        else:
            t_src = np.linspace(0, n_in - 1, n_out)
            orig_aligned = np.interp(t_src, np.arange(n_in),
                                     audio_mono).astype(np.float32)
    else:
        orig_aligned = audio_mono

    y_mono = apply_voicing_policy(
        y_mono, orig_aligned, voiced_arr, env_arr, sr,
        args.voicing_policy, args.seed,
    )

    # Final safety
    y_mono = np.nan_to_num(y_mono, nan=0.0, posinf=0.0, neginf=0.0)

    # ── Stage 5: Stereo + normalise ───────────────────────────────────────
    print("  [Py 5/6] Stereo render (%s) + normalise (%s)..." %
          (args.stereo_mode, args.normalize_mode))

    stereo = render_stereo(y_mono, sr, args.stereo_mode)
    stereo = apply_loudness_compensation(stereo, ref_rms, args.normalize_mode)
    stereo = np.nan_to_num(stereo, nan=0.0, posinf=0.0, neginf=0.0)

    out_rms  = float(np.sqrt(np.mean(stereo.astype(np.float64) ** 2)))
    peak_out = float(np.max(np.abs(stereo)))

    sf.write(args.output_wav, stereo, sr, subtype="FLOAT")
    print("    Wrote: %s | RMS: %.4f | Peak: %.4f" %
          (args.output_wav, out_rms, peak_out))

    # ── Stage 6: Stats ────────────────────────────────────────────────────
    print("  [Py 6/6] Writing stats...")

    voiced_idx = np.where(voiced_arr > 0.5)[0]
    if len(voiced_idx) > 0:
        f0_voiced = f0_arr[voiced_idx]
        f0_voiced = f0_voiced[f0_voiced > 0]
        if len(f0_voiced) > 0:
            f0_stats = {
                "mean":   float(np.mean(f0_voiced)),
                "median": float(np.median(f0_voiced)),
                "min":    float(np.min(f0_voiced)),
                "max":    float(np.max(f0_voiced)),
            }
        else:
            f0_stats = {"mean": 0, "median": 0, "min": 0, "max": 0}
    else:
        f0_stats = {"mean": 0, "median": 0, "min": 0, "max": 0}

    # Partial frequency table (first 16), one row at a time: O(N) memory.
    P = partial_count(args.num_partials, args.partial_family)
    nyq = sr / 2.0
    table = []
    voiced_bool = voiced_arr > 0.5
    for p in range(min(16, P)):
        row_full = partial_frequency_row(
            f0_arr, p, args.num_partials, args.partial_family,
            beta=args.inharmonic_beta,
            freq_shift=args.frequency_shift,
            ring_mod_hz=args.ring_mod, fm_ratio=args.fm_ratio,
        )
        row = row_full[voiced_bool]
        row = row[(row >= 20.0) & (row <= nyq * 0.95)]
        if len(row) > 0:
            table.append((float(np.min(row)),
                          float(np.max(row)),
                          float(np.mean(row))))
        else:
            table.append((0.0, 0.0, 0.0))

    # Downsampled F0 trace for visualization
    n_trace = min(400, n_out)
    if n_trace > 0:
        idxs = np.linspace(0, n_out - 1, n_trace).astype(int)
        trace = [(idxs[i] / sr, float(f0_arr[idxs[i]])) for i in range(n_trace)]
    else:
        trace = []

    # Effective synthesis parameters reflect any research-mode overrides,
    # because apply_research_mode_constraints mutated args in place.
    eff_carrier = args.prosody_carrier if args.research_mode == "prosody_only" else "none"
    research_info = {
        "research_mode":            args.research_mode,
        "prosody_carrier":          eff_carrier,
        "prosody_only_safety":      research_safety["prosody_only_safety"],
        "copied_original_waveform": research_safety["copied_original_waveform"],
        "formant_modeling_used":    research_safety["formant_modeling_used"],
        "original_unvoiced_copied": research_safety["original_unvoiced_copied"],
        "duration_preserved":       duration_preserved,
        "eff_partials":             args.num_partials,
        "eff_family":               args.partial_family,
        "eff_amplaw":               args.amplitude_law,
        "eff_envsource":            args.envelope_source,
        "eff_voicing":              args.voicing_policy,
        "eff_stereo":               args.stereo_mode,
        "eff_normmode":             args.normalize_mode,
        "eff_carrier":              eff_carrier,
    }

    write_stats(
        args.stats_txt,
        n_samples=n_out, sr=sr, duration=out_dur,
        voiced_percent=voiced_pct,
        f0_stats=f0_stats,
        num_partials=P,
        partial_family=args.partial_family,
        amp_law=args.amplitude_law,
        normalize_mode=args.normalize_mode,
        rms_in=ref_rms, rms_out=out_rms, peak_out=peak_out,
        warnings=warnings_list,
        partial_freq_table=table,
        f0_trace=trace,
        research_info=research_info,
        analysis_channel=analysis_channel,
    )

    # ── QC summary ────────────────────────────────────────────────────────
    print("")
    print("  -- QC summary --")
    print("    research_mode:            %s" % args.research_mode)
    print("    effective_carrier:        %s" % eff_carrier)
    print("    analysis_channel:         %d" % analysis_channel)
    print("    duration:                 %.3f s (preserved: %s)"
          % (out_dur, "true" if duration_preserved else "false"))
    print("    voiced_percent:           %.1f%%" % voiced_pct)
    print("    original_waveform_copied: %s"
          % ("true" if research_safety["copied_original_waveform"] else "false"))
    print("    original_unvoiced_copied: %s"
          % ("true" if research_safety["original_unvoiced_copied"] else "false"))
    print("    output:                   %s" % args.output_wav)
    print("    stats:                    %s" % args.stats_txt)
    if args.research_mode == "prosody_only":
        print("    Prosody-only mode: synthesized from F0 and intensity "
              "envelope. Original waveform was not used as audible output.")

    # ── Cleanup ───────────────────────────────────────────────────────────
    if args.cleanup:
        for path in [args.input_wav, args.f0_csv, args.intensity_csv,
                     args.events_csv]:
            if path and _is_praat_temp(path) and os.path.exists(path):
                os.remove(path)
                print("    Deleted: %s" % path)

    print("OK: wrote %s" % args.output_wav)


if __name__ == "__main__":
    main()
