"""
reflect_analyze.py — Self-Reflective Feedback Analysis Engine v1.2

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Called by SelfReflectiveFeedback.praat each iteration.

Usage:
    python reflect_analyze.py wav_path stage_name
        params_in_json params_out_json params_out_txt
        [--metrics-out metrics.json]
        [--prev-metrics prev_metrics.json]
        [--status-file ok.txt]
        [--debug]

Stage names:  mds | freeze | cascade | canon

params_out.txt line format (fixed order, one value per line):
    MDS:    stop_flag, silence_threshold, min_sounding_interval,
            silence_between_words_s
    Freeze: stop_flag, freeze_points,
            freeze_repeat_divisor, artifact_amplitude
"""

import sys
import os
import json
import math
import argparse
import numpy as np


# ═══════════════════════════════════════════════════════════════════════════
# Audio loading
# ═══════════════════════════════════════════════════════════════════════════

def load_audio(wav_path):
    """Load as samples x channels; never phase-cancel channels by averaging."""
    import soundfile as sf
    audio, sr = sf.read(wav_path, always_2d=True, dtype="float32")
    if audio.shape[0] == 0:
        raise ValueError("input audio contains zero samples")
    return np.asarray(audio, dtype=np.float32), int(sr)


def _representative_channel(audio):
    """Return the strongest-RMS real channel and its zero-based index."""
    x = np.asarray(audio, dtype=np.float32)
    if x.ndim == 1:
        return x, 0
    rms = np.sqrt(np.mean(x.astype(np.float64) ** 2, axis=0))
    idx = int(np.argmax(rms)) if rms.size else 0
    return x[:, idx], idx


# ═══════════════════════════════════════════════════════════════════════════
# Preview window construction  (duration-aware + adaptive flux shift)
# ═══════════════════════════════════════════════════════════════════════════

def _spectral_flux_curve(audio, sr, hop=512, n_fft=1024):
    """Amplitude-normalised positive spectral flux for anchor finding."""
    from scipy.signal import stft
    x = np.asarray(audio, dtype=np.float32).reshape(-1)
    if x.size < n_fft:
        x = np.pad(x, (0, n_fft - x.size))
    _, times, S = stft(x, fs=sr, nperseg=n_fft, noverlap=n_fft - hop,
                       boundary=None, padded=False)
    mag = np.abs(S)
    if mag.shape[1] < 2:
        return np.asarray([], dtype=float), np.asarray([], dtype=float)
    pos = np.sum(np.maximum(np.diff(mag, axis=1), 0.0), axis=0)
    den = np.sum(mag[:, :-1] + mag[:, 1:], axis=0) + 1e-12
    return times[1:], pos / den


def _top_peaks(values, times, n=3, min_dist_frac=0.10):
    """Find top-N positive peaks; zero-only curves return no anchors."""
    values = np.asarray(values, dtype=float)
    times = np.asarray(times, dtype=float)
    if values.size == 0 or times.size == 0 or float(np.max(values)) <= 0.0:
        return []
    min_dist = max(1, int(min_dist_frac * len(values)))
    buf = values.copy()
    peaks = []
    for _ in range(min(n, len(values))):
        idx = int(np.argmax(buf))
        if not np.isfinite(buf[idx]) or buf[idx] <= 0.0:
            break
        peaks.append(float(times[idx]))
        lo = max(0, idx - min_dist)
        hi = min(len(buf), idx + min_dist + 1)
        buf[lo:hi] = -np.inf
    return peaks


def build_preview(audio, sr):
    """
    Build duration-aware preview WINDOWS, not one concatenated signal.

    Keeping windows separate prevents artificial spectral-flux events at joins
    between distant regions of the output.
    """
    x = np.asarray(audio, dtype=np.float32)
    duration = x.shape[0] / float(sr)
    if duration < 4.0:
        return [x]

    rep, _ = _representative_channel(x)
    win_samples = max(int(0.5 * sr),
                      min(int(3.0 * sr), int(0.10 * duration * sr)))
    flux_times, flux = _spectral_flux_curve(rep, sr)
    top3 = _top_peaks(flux, flux_times, n=3) if len(flux_times) else []
    base_fracs = [0.25, 0.75] if duration < 8.0 else [0.25, 0.50, 0.75]

    windows = []
    for frac in base_fracs:
        center_t = frac * duration
        nearby = [pt for pt in top3 if abs(pt - center_t) < 0.10 * duration]
        if nearby:
            center_t = min(nearby, key=lambda pt: abs(pt - center_t))
        center_s = int(round(center_t * sr))
        half = win_samples // 2
        start = max(0, center_s - half)
        end = min(x.shape[0], start + win_samples)
        start = max(0, end - win_samples)
        if end > start:
            windows.append(x[start:end])

    return windows if windows else [x]


def _compute_metrics_mono(audio, sr):
    """Silence-aware metrics for one mono window."""
    from scipy.signal import stft
    from numpy.lib.stride_tricks import as_strided

    x = np.asarray(audio, dtype=np.float32).reshape(-1)
    n_fft, hop = 1024, 256
    if x.size == 0:
        return {
            "centroid_mean": 0.0, "centroid_var": 0.0,
            "spectral_flatness": 0.0, "rms_energy_var": 0.0,
            "spectral_flux": 0.0, "active_fraction": 0.0,
            "_rms_mean": 0.0,
        }
    if x.size < n_fft:
        x = np.pad(x, (0, n_fft - x.size))

    freqs, _, S = stft(x, fs=sr, nperseg=n_fft, noverlap=n_fft - hop,
                       boundary=None, padded=False)
    mag = np.abs(S).astype(np.float64)

    n_frames = max(1, 1 + (len(x) - n_fft) // hop)
    usable = (n_frames - 1) * hop + n_fft
    frames = as_strided(
        x[:usable],
        shape=(n_frames, n_fft),
        strides=(hop * x.strides[0], x.strides[0]),
    )
    rms_vals = np.sqrt(np.mean(frames.astype(np.float64) ** 2, axis=1))
    rms_max = float(np.max(rms_vals)) if rms_vals.size else 0.0
    if rms_max <= 1e-12:
        return {
            "centroid_mean": 0.0, "centroid_var": 0.0,
            "spectral_flatness": 0.0, "rms_energy_var": 0.0,
            "spectral_flux": 0.0, "active_fraction": 0.0,
            "_rms_mean": 0.0,
        }

    active = rms_vals >= max(rms_max * 1e-3, 1e-12)  # 60 dB below strongest
    active_fraction = float(np.mean(active))
    if not np.any(active):
        active[:] = True

    mag = mag[:, :len(active)]
    mag_a = mag[:, active]
    total = np.sum(mag_a, axis=0) + 1e-20
    centroid = np.sum(freqs[:, None] * mag_a, axis=0) / total
    centroid_mean = float(np.mean(centroid))
    centroid_var = float(np.var(centroid))

    frame_floor = np.maximum(np.max(mag_a, axis=0, keepdims=True) * 1e-12, 1e-20)
    safe_mag = np.maximum(mag_a, frame_floor)
    geom = np.exp(np.mean(np.log(safe_mag), axis=0))
    arith = np.mean(mag_a, axis=0) + 1e-20
    flatness = float(np.clip(np.mean(geom / arith), 0.0, 1.0))

    rms_active = rms_vals[active]
    rms_energy_var = float(np.var(rms_active)) if rms_active.size else 0.0
    rms_mean = float(np.mean(rms_active)) if rms_active.size else 0.0

    if mag.shape[1] >= 2:
        pos = np.sum(np.maximum(np.diff(mag, axis=1), 0.0), axis=0)
        den = np.sum(mag[:, :-1] + mag[:, 1:], axis=0) + 1e-12
        pair_active = active[:-1] | active[1:]
        flux_vals = pos / den
        spectral_flux = float(np.mean(flux_vals[pair_active])) if np.any(pair_active) else 0.0
    else:
        spectral_flux = 0.0

    return {
        "centroid_mean": centroid_mean,
        "centroid_var": centroid_var,
        "spectral_flatness": flatness,
        "rms_energy_var": rms_energy_var,
        "spectral_flux": spectral_flux,
        "active_fraction": active_fraction,
        "_rms_mean": rms_mean,
    }


def compute_metrics(preview_windows, sr):
    """
    Aggregate metrics across windows and channels without concatenating distant
    regions and without cancellation-prone mono fold-down.
    """
    windows = [preview_windows] if isinstance(preview_windows, np.ndarray) else list(preview_windows)
    records, weights = [], []

    for w in windows:
        arr = np.asarray(w, dtype=np.float32)
        if arr.ndim == 1:
            arr = arr[:, None]
        for ch in range(arr.shape[1]):
            m = _compute_metrics_mono(arr[:, ch], sr)
            wt = max(m["_rms_mean"], 1e-12) * max(1, arr.shape[0])
            records.append(m)
            weights.append(wt)

    if not records or sum(weights) <= 1e-9:
        return {
            "centroid_mean": 0.0, "centroid_var": 0.0,
            "spectral_flatness": 0.0, "rms_energy_var": 0.0,
            "spectral_flux": 0.0, "active_fraction": 0.0,
        }

    ww = np.asarray(weights, dtype=np.float64)
    ww /= np.sum(ww)
    means = np.asarray([r["centroid_mean"] for r in records], dtype=float)
    vars_ = np.asarray([r["centroid_var"] for r in records], dtype=float)
    centroid_mean = float(np.sum(ww * means))
    centroid_var = float(max(0.0, np.sum(ww * (vars_ + means * means)) - centroid_mean ** 2))

    def avg(key):
        return float(np.sum(ww * np.asarray([r[key] for r in records], dtype=float)))

    return {
        "centroid_mean": centroid_mean,
        "centroid_var": centroid_var,
        "spectral_flatness": avg("spectral_flatness"),
        "rms_energy_var": avg("rms_energy_var"),
        "spectral_flux": avg("spectral_flux"),
        "active_fraction": avg("active_fraction"),
    }


# ═══════════════════════════════════════════════════════════════════════════
# Early stop  (relative metric stabilisation)
# ═══════════════════════════════════════════════════════════════════════════

TOLERANCE_DEFAULTS = {
    "centroid_mean":     0.03,
    "centroid_var":      0.03,
    "spectral_flatness": 0.02,
    "rms_energy_var":    0.02,
    "spectral_flux":     0.03,
}

STABILITY_FLOORS = {
    "centroid_mean":     50.0,
    "centroid_var":      100.0,
    "spectral_flatness": 0.01,
    "rms_energy_var":    1e-6,
    "spectral_flux":     0.002,
}


def check_early_stop(current, previous, tol_override=None):
    """Stop when all metric changes are small on a symmetric relative scale."""
    if previous is None:
        return False
    tol = dict(TOLERANCE_DEFAULTS)
    if tol_override:
        tol.update(tol_override)
    for key, threshold in tol.items():
        curr = float(current.get(key, 0.0))
        prev = float(previous.get(key, 0.0))
        denom = max(abs(curr), abs(prev), STABILITY_FLOORS.get(key, 1e-10))
        if abs(curr - prev) / denom > threshold:
            return False
    return True


# ═══════════════════════════════════════════════════════════════════════════
# Stage-specific parameter update rules
# ═══════════════════════════════════════════════════════════════════════════

# --- MDS Space Navigator ----------------------------------------------------
# Reflective params (adjusted each iteration):
#   silence_threshold_db, min_sounding_interval_s, silence_between_words_s
# Fixed params passed as constants by Praat:
#   Minimum_silent_interval_s, Similarity_metric, Max_formant_Hz,
#   Number_of_formants, Number_of_MFCC_Coefficients, Ordering, Play_result

_MDS_DEFAULTS = {
    "silence_threshold_db":    25.0,
    "min_sounding_interval_s":  0.10,
    "silence_between_words_s":  0.10,
}
_MDS_BOUNDS = {
    "silence_threshold_db":    (5.0,  55.0),
    "min_sounding_interval_s": (0.02,  0.50),
    "silence_between_words_s": (0.02,  1.50),
}

def _mds_clamp(p):
    out = dict(p)
    for k, (lo, hi) in _MDS_BOUNDS.items():
        if k in out:
            out[k] = max(lo, min(hi, out[k]))
    return out

def update_params_mds(params, metrics, prev_metrics):
    p = dict(params)

    flux       = metrics["spectral_flux"]
    cvar       = metrics["centroid_var"]
    reason     = "stable"

    LOW_FLUX   = 0.002
    HIGH_FLUX  = 0.050
    LOW_CVAR   = 300.0
    HIGH_CVAR  = 8000.0

    if prev_metrics:
        dflux = (flux - prev_metrics["spectral_flux"]) / (abs(prev_metrics["spectral_flux"]) + 1e-10)
        novelty_low  = dflux <  0.02 and flux < LOW_FLUX * 2
        novelty_high = dflux >  0.40 or  flux > HIGH_FLUX
    else:
        novelty_low  = flux < LOW_FLUX  or  cvar < LOW_CVAR
        novelty_high = flux > HIGH_FLUX or  cvar > HIGH_CVAR

    if novelty_low:
        # Lower threshold dB = more sensitive (catches quieter segments)
        p["silence_threshold_db"]    = p.get("silence_threshold_db",    25.0) - 3.0
        p["min_sounding_interval_s"] = p.get("min_sounding_interval_s",  0.10) - 0.01
        reason = "novelty_too_low: increased segmentation sensitivity"
    elif novelty_high:
        p["silence_between_words_s"] = p.get("silence_between_words_s",  0.10) + 0.05
        p["silence_threshold_db"]    = p.get("silence_threshold_db",    25.0) + 3.0
        reason = "novelty_too_high: reduced segmentation sensitivity"

    return _mds_clamp(p), reason


# --- Spectral Freeze & Glitch -----------------------------------------------
# Reflective params (adjusted each iteration):
#   freeze_points (int), freeze_repeat_divisor (float), artifact_amplitude (float)
# Fixed params passed as constants by Praat:
#   Preset, Freeze_duration_divisor, Freeze_length_min/max_factor,
#   Scale_peak, Draw_visualization, Play_result

_FREEZE_DEFAULTS = {
    "freeze_points":          12,
    "freeze_repeat_divisor":   3.0,
    "artifact_amplitude":      0.10,
}
_FREEZE_BOUNDS = {
    "freeze_points":          (1,    30),
    "freeze_repeat_divisor":  (1.0,  8.0),
    "artifact_amplitude":     (0.01, 1.0),
}

def _freeze_clamp(p):
    out = dict(p)
    for k, (lo, hi) in _FREEZE_BOUNDS.items():
        if k in out:
            out[k] = max(lo, min(hi, out[k]))
    out["freeze_points"] = int(round(out["freeze_points"]))
    return out

def update_params_freeze(params, metrics, prev_metrics):
    p = dict(params)

    flatness = metrics["spectral_flatness"]
    flux     = metrics["spectral_flux"]
    reason   = "stable"

    HIGH_FLATNESS = 0.15
    LOW_FLUX      = 0.001

    if flatness > HIGH_FLATNESS:
        # Too noisy: reduce artifact amplitude, fewer freeze points
        p["artifact_amplitude"]    = p.get("artifact_amplitude",    0.10) - 0.02
        p["freeze_points"]         = p.get("freeze_points",           12) - 1
        reason = "flatness_too_high: reduced artifact + fewer freeze points"
    elif flux < LOW_FLUX:
        # Too static: more freeze points, shorter repeat wait
        p["freeze_points"]         = p.get("freeze_points",           12) + 2
        p["freeze_repeat_divisor"] = p.get("freeze_repeat_divisor",   3.0) - 0.5
        reason = "flux_too_low: increased freeze points + shorter repeat"

    return _freeze_clamp(p), reason


# --- Crystalline Cascade ----------------------------------------------------
# Reflective params: modulation_depth, convolution_mix, wet_dry_percent

_CASCADE_DEFAULTS = {
    "modulation_depth":  0.6,
    "convolution_mix":   0.35,
    "wet_dry_percent":   50.0,
}
_CASCADE_BOUNDS = {
    "modulation_depth":  (0.0,  1.0),
    "convolution_mix":   (0.0,  1.0),
    "wet_dry_percent":   (0.0, 100.0),
}

def _cascade_clamp(p):
    out = dict(p)
    for k, (lo, hi) in _CASCADE_BOUNDS.items():
        if k in out:
            out[k] = max(lo, min(hi, out[k]))
    return out

def update_params_cascade(params, metrics, prev_metrics):
    p = dict(params)
    flatness = metrics["spectral_flatness"]
    cvar     = metrics["centroid_var"]
    reason   = "stable"

    HIGH_FLATNESS = 0.20
    LOW_CVAR      = 200.0
    HIGH_CVAR     = 9000.0

    if flatness > HIGH_FLATNESS or cvar > HIGH_CVAR:
        # Too washed out: reduce wet signal and modulation
        p["wet_dry_percent"]  = p.get("wet_dry_percent",  50.0) - 8.0
        p["modulation_depth"] = p.get("modulation_depth",  0.6) - 0.05
        reason = "too_wet_or_chaotic: reduced wet mix + modulation depth"
    elif cvar < LOW_CVAR:
        # Too static: push more wet shimmer in
        p["wet_dry_percent"]  = p.get("wet_dry_percent",  50.0) + 8.0
        p["convolution_mix"]  = p.get("convolution_mix",  0.35) + 0.05
        reason = "too_static: increased wet mix + convolution"

    return _cascade_clamp(p), reason


# --- 4-Channel Canon --------------------------------------------------------
# Reflective params: shift_percent_1..4, delay_2..4 (delay_1 always 0)

_CANON_DEFAULTS = {
    "shift_percent_1":  0.0,
    "shift_percent_2":  6.0,
    "shift_percent_3": 12.0,
    "shift_percent_4": -5.5,
    "delay_2":          0.3,
    "delay_3":          0.6,
    "delay_4":          0.9,
}
_CANON_BOUNDS = {
    "shift_percent_1": (-50.0, 50.0),
    "shift_percent_2": (-50.0, 50.0),
    "shift_percent_3": (-50.0, 50.0),
    "shift_percent_4": (-50.0, 50.0),
    "delay_2":          (0.05,  5.0),
    "delay_3":          (0.05,  5.0),
    "delay_4":          (0.05,  5.0),
}

def _canon_clamp(p):
    out = dict(p)
    for k, (lo, hi) in _CANON_BOUNDS.items():
        if k in out:
            out[k] = max(lo, min(hi, out[k]))

    # Enforce delay_2 < delay_3 < delay_4 WITHOUT pushing values back outside
    # the documented 5 s upper bound.
    step = 0.1
    d2 = min(out.get("delay_2", 0.3), _CANON_BOUNDS["delay_2"][1] - 2 * step)
    d3 = max(out.get("delay_3", 0.6), d2 + step)
    d3 = min(d3, _CANON_BOUNDS["delay_3"][1] - step)
    d4 = max(out.get("delay_4", 0.9), d3 + step)
    d4 = min(d4, _CANON_BOUNDS["delay_4"][1])
    out["delay_2"] = d2
    out["delay_3"] = d3
    out["delay_4"] = d4
    return out

def update_params_canon(params, metrics, prev_metrics):
    p = dict(params)
    flux = metrics["spectral_flux"]
    cvar = metrics["centroid_var"]
    reason = "stable"

    LOW_FLUX  = 0.001
    HIGH_FLUX = 0.050

    if flux < LOW_FLUX:
        # Too homogeneous: spread the pitch intervals and delays wider
        p["shift_percent_2"] = p.get("shift_percent_2",  6.0) + 2.0
        p["shift_percent_3"] = p.get("shift_percent_3", 12.0) + 2.0
        p["delay_2"]         = p.get("delay_2",          0.3) + 0.05
        p["delay_3"]         = p.get("delay_3",          0.6) + 0.05
        p["delay_4"]         = p.get("delay_4",          0.9) + 0.05
        reason = "flux_too_low: widened pitch intervals and delays"
    elif flux > HIGH_FLUX:
        # Too chaotic: pull pitch offsets monotonically TOWARD zero and shrink
        # the total canon delay spread. Simple subtraction would cross zero and
        # start widening the interval again after several iterations.
        def toward_zero(v, step):
            v = float(v)
            return math.copysign(max(0.0, abs(v) - step), v) if v != 0 else 0.0

        p["shift_percent_2"] = toward_zero(p.get("shift_percent_2",  6.0), 2.0)
        p["shift_percent_3"] = toward_zero(p.get("shift_percent_3", 12.0), 2.0)
        p["shift_percent_4"] = toward_zero(p.get("shift_percent_4", -5.5), 2.0)
        p["delay_2"] = max(0.05, p.get("delay_2", 0.3) - 0.05)
        p["delay_3"] = max(0.15, p.get("delay_3", 0.6) - 0.05)
        p["delay_4"] = max(0.25, p.get("delay_4", 0.9) - 0.05)
        reason = "flux_too_high: tightened pitch intervals + canon spread"

    return _canon_clamp(p), reason

def write_params_txt(path, stop_flag, stage, params):
    """
    Write params_out.txt for Praat to parse.
    One value per line, fixed order documented in both scripts.
    """
    lines = [str(1 if stop_flag else 0)]
    if stage == "mds":
        lines += [
            "%.6f" % params["silence_threshold_db"],
            "%.6f" % params["min_sounding_interval_s"],
            "%.6f" % params["silence_between_words_s"],
        ]
    elif stage == "freeze":
        lines += [
            "%d"   % int(params["freeze_points"]),
            "%.6f" % params["freeze_repeat_divisor"],
            "%.6f" % params["artifact_amplitude"],
        ]
    elif stage == "cascade":
        lines += [
            "%.6f" % params["modulation_depth"],
            "%.6f" % params["convolution_mix"],
            "%.6f" % params["wet_dry_percent"],
        ]
    elif stage == "canon":
        lines += [
            "%.6f" % params["shift_percent_1"],
            "%.6f" % params["shift_percent_2"],
            "%.6f" % params["shift_percent_3"],
            "%.6f" % params["shift_percent_4"],
            "%.6f" % params["delay_2"],
            "%.6f" % params["delay_3"],
            "%.6f" % params["delay_4"],
        ]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="Self-reflective feedback analysis engine for Praat AudioTools"
    )
    parser.add_argument("wav_path")
    parser.add_argument("stage_name", choices=["mds", "freeze", "cascade", "canon"])
    parser.add_argument("params_in_json")
    parser.add_argument("params_out_json")
    parser.add_argument("params_out_txt")
    parser.add_argument("--metrics-out",   default=None)
    parser.add_argument("--prev-metrics",  default=None,
        help="Path to metrics JSON from previous iteration for early-stop check")
    parser.add_argument("--status-file",   default=None)
    parser.add_argument("--debug",         action="store_true")
    args = parser.parse_args()

    # Dependency check
    missing = []
    for pkg in ["numpy", "scipy", "soundfile"]:
        try: __import__(pkg)
        except ImportError: missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)

    # ── Load params_in ──────────────────────────────────────────────────
    with open(args.params_in_json, encoding="utf-8") as f:
        params_in = json.load(f)

    params    = params_in.get("params", {})
    tolerance = params_in.get("tolerance", {})
    stage     = args.stage_name.lower()

    # Fill in defaults for any missing params
    defaults = (_MDS_DEFAULTS     if stage == "mds"     else
                _FREEZE_DEFAULTS  if stage == "freeze"  else
                _CASCADE_DEFAULTS if stage == "cascade" else
                _CANON_DEFAULTS)
    for k, v in defaults.items():
        params.setdefault(k, v)

    # ── Load prev metrics ───────────────────────────────────────────────
    prev_metrics = None
    if args.prev_metrics and os.path.isfile(args.prev_metrics):
        with open(args.prev_metrics, encoding="utf-8") as f:
            prev_metrics = json.load(f)

    # ── Load audio + build preview ──────────────────────────────────────
    audio, sr = load_audio(args.wav_path)
    preview_windows = build_preview(audio, sr)
    duration = audio.shape[0] / float(sr)
    preview_dur = sum(w.shape[0] for w in preview_windows) / float(sr)

    if args.debug:
        _, rep_idx = _representative_channel(audio)
        print("  Audio: %.2fs  SR=%d  channels=%d  anchor_ch=%d"
              % (duration, sr, audio.shape[1], rep_idx + 1))
        print("  Preview: %d separate window(s), %.2fs total"
              % (len(preview_windows), preview_dur))

    # ── Compute metrics ─────────────────────────────────────────────────
    metrics = compute_metrics(preview_windows, sr)

    if args.debug:
        print("  Metrics: centroid=%.1f cvar=%.1f flatness=%.4f "
              "rms_var=%.6f flux=%.6f active=%.3f"
              % (metrics["centroid_mean"], metrics["centroid_var"],
                 metrics["spectral_flatness"], metrics["rms_energy_var"],
                 metrics["spectral_flux"], metrics.get("active_fraction", 0.0)))

    # ── Reflective update + guarded early stop ───────────────────────────
    # A stochastic stage can produce two similar metric snapshots by chance.
    # Therefore "metrics stable" alone is insufficient: stop only when the
    # controller ALSO proposes no parameter change.
    metrics_stable = check_early_stop(
        metrics, prev_metrics,
        tol_override=tolerance if tolerance else None)

    if stage == "mds":
        candidate_params, reason = update_params_mds(params, metrics, prev_metrics)
    elif stage == "freeze":
        candidate_params, reason = update_params_freeze(params, metrics, prev_metrics)
    elif stage == "cascade":
        candidate_params, reason = update_params_cascade(params, metrics, prev_metrics)
    else:
        candidate_params, reason = update_params_canon(params, metrics, prev_metrics)

    keys = sorted(set(params) | set(candidate_params))
    params_unchanged = all(
        abs(float(candidate_params.get(k, 0.0)) - float(params.get(k, 0.0))) <= 1e-12
        for k in keys
    )
    stop_flag = bool(metrics_stable and params_unchanged)

    if stop_flag:
        new_params = dict(params)
        reason = "metrics_and_parameters_stabilised"
    else:
        new_params = candidate_params

    if args.debug:
        print("  Reason:", reason)
        print("  Stop:  ", stop_flag)
        print("  New params:", json.dumps(new_params, indent=4))

    # ── Write outputs ───────────────────────────────────────────────────
    out_json = {
        "stop_flag": bool(stop_flag),
        "stage":     stage,
        "reason":    reason,
        "params":    new_params,
        "metrics":   metrics,
    }
    with open(args.params_out_json, "w", encoding="utf-8") as f:
        json.dump(out_json, f, indent=2)

    write_params_txt(args.params_out_txt, stop_flag, stage, new_params)

    if args.metrics_out:
        with open(args.metrics_out, "w", encoding="utf-8") as f:
            json.dump(metrics, f, indent=2)

    if args.status_file:
        with open(args.status_file, "w", encoding="utf-8") as f:
            f.write("ok")

    # Summary line for Praat info window (via redirect)
    print("Iter OK | stage=%s | reason=%s | stop=%s | "
          "centroid=%.1f | flux=%.5f | flatness=%.4f"
          % (stage, reason, stop_flag,
             metrics["centroid_mean"], metrics["spectral_flux"],
             metrics["spectral_flatness"]))


if __name__ == "__main__":
    main()
