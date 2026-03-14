"""
reflect_analyze.py — Self-Reflective Feedback Analysis Engine

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

Stage names:  mds | freeze

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
    import soundfile as sf
    audio, sr = sf.read(wav_path, always_2d=False)
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    return audio.astype(np.float32), int(sr)


# ═══════════════════════════════════════════════════════════════════════════
# Preview window construction  (duration-aware + adaptive flux shift)
# ═══════════════════════════════════════════════════════════════════════════

def _spectral_flux_curve(audio, sr, hop=512, n_fft=1024):
    """Fast spectral flux over entire audio. Returns (times, flux)."""
    from scipy.signal import stft
    _, times, S = stft(audio, fs=sr, nperseg=n_fft, noverlap=n_fft - hop,
                       boundary="zeros", padded=True)
    mag  = np.abs(S)
    diff = np.diff(mag, axis=1)
    flux = np.sum(np.maximum(diff, 0.0), axis=0)
    return times[1:], flux          # flux is between consecutive frames


def _top_peaks(values, times, n=3, min_dist_frac=0.10):
    """
    Find top-N peaks in `values` with minimum separation of
    min_dist_frac * len(values) samples.
    Returns list of peak times (float, seconds).
    """
    if len(values) == 0:
        return []
    min_dist = max(1, int(min_dist_frac * len(values)))
    buf      = values.copy()
    peaks    = []
    for _ in range(n):
        idx = int(np.argmax(buf))
        peaks.append(float(times[idx]))
        lo = max(0, idx - min_dist)
        hi = min(len(buf), idx + min_dist + 1)
        buf[lo:hi] = 0.0
    return peaks


def build_preview(audio, sr):
    """
    Build adaptive preview buffer:
    - duration < 4s  → full audio
    - 4–8s           → windows at 25% + 75%
    - ≥ 8s           → windows at 25% + 50% + 75%

    Window length = min(3s, 10% of duration).
    Each base position is shifted to the nearest spectral-flux peak
    within ±10% of duration (if one exists).
    """
    duration   = len(audio) / sr

    if duration < 4.0:
        return audio

    win_samples = max(int(0.5 * sr),
                      min(int(3.0 * sr), int(0.10 * duration * sr)))

    # Adaptive shift anchors
    flux_times, flux = _spectral_flux_curve(audio, sr)
    top3 = _top_peaks(flux, flux_times, n=3) if len(flux_times) > 0 else []

    base_fracs = [0.25, 0.75] if duration < 8.0 else [0.25, 0.50, 0.75]

    windows = []
    for frac in base_fracs:
        center_t = frac * duration
        # Shift to nearest flux peak within ±10% duration
        for pt in top3:
            if abs(pt - center_t) < 0.10 * duration:
                center_t = pt
                break

        center_s = int(center_t * sr)
        half     = win_samples // 2
        start    = max(0, center_s - half)
        end      = min(len(audio), start + win_samples)
        if end > start:
            windows.append(audio[start:end])

    return np.concatenate(windows) if windows else audio


# ═══════════════════════════════════════════════════════════════════════════
# Metrics  (numpy + scipy only)
# ═══════════════════════════════════════════════════════════════════════════

def compute_metrics(audio, sr):
    """
    Returns dict with:
        centroid_mean, centroid_var   — spectral centroid statistics
        spectral_flatness             — mean Wiener entropy (0=tonal, 1=noise)
        rms_energy_var                — variance of per-frame RMS
        spectral_flux                 — mean positive spectral change
    """
    from scipy.signal import stft

    n_fft = 1024
    hop   = 256
    _, _, S = stft(audio, fs=sr, nperseg=n_fft, noverlap=n_fft - hop,
                   boundary="zeros", padded=True)
    mag   = np.abs(S) + 1e-10          # [F, T]
    freqs = np.linspace(0.0, sr / 2.0, mag.shape[0])

    # Spectral centroid
    total   = mag.sum(axis=0) + 1e-10
    centroid = (freqs[:, np.newaxis] * mag).sum(axis=0) / total
    centroid_mean = float(np.mean(centroid))
    centroid_var  = float(np.var(centroid))

    # Spectral flatness  (geometric mean / arithmetic mean per frame)
    log_mag    = np.log(mag)
    geom_mean  = np.exp(log_mag.mean(axis=0))
    arith_mean = mag.mean(axis=0)
    flatness   = float(np.mean(geom_mean / (arith_mean + 1e-10)))
    flatness   = float(np.clip(flatness, 0.0, 1.0))

    # RMS energy variance over short frames
    frame_len = n_fft
    n_rms_frames = max(1, (len(audio) - frame_len) // hop + 1)
    # Truncate audio to fit exact frames, reshape, compute per-frame RMS
    usable = n_rms_frames * hop + (frame_len - hop)
    if usable <= len(audio) and n_rms_frames > 0:
        # Use stride tricks for overlapping frames
        from numpy.lib.stride_tricks import as_strided
        itemsize = audio.strides[0]
        frames = as_strided(audio[:usable],
                            shape=(n_rms_frames, frame_len),
                            strides=(hop * itemsize, itemsize))
        rms_vals = np.sqrt(np.mean(frames.astype(np.float64) ** 2, axis=1))
        rms_energy_var = float(np.var(rms_vals))
    else:
        rms_energy_var = 0.0

    # Spectral flux (mean positive inter-frame difference)
    diff = np.diff(mag, axis=1)
    spectral_flux = float(np.mean(np.sum(np.maximum(diff, 0.0), axis=0)))

    return {
        "centroid_mean":    centroid_mean,
        "centroid_var":     centroid_var,
        "spectral_flatness": flatness,
        "rms_energy_var":   rms_energy_var,
        "spectral_flux":    spectral_flux,
    }


# ═══════════════════════════════════════════════════════════════════════════
# Early stop  (relative metric stabilisation)
# ═══════════════════════════════════════════════════════════════════════════

TOLERANCE_DEFAULTS = {
    "centroid_mean":    0.03,
    "centroid_var":     0.03,
    "spectral_flatness": 0.02,
    "rms_energy_var":   0.02,
    "spectral_flux":    0.03,
}

def check_early_stop(current, previous, tol_override=None):
    """
    Return True (stop) when ALL metric relative changes are below threshold.
    """
    if previous is None:
        return False
    tol = dict(TOLERANCE_DEFAULTS)
    if tol_override:
        tol.update(tol_override)
    for key, threshold in tol.items():
        curr = current.get(key, 0.0)
        prev = previous.get(key, 0.0)
        denom = max(abs(prev), 1e-10)
        if abs(curr - prev) / denom > threshold:
            return False                 # still changing — keep going
    return True                          # all stable — stop


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

    LOW_FLUX   = 0.005
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
    LOW_FLUX      = 0.003

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
    # Enforce delay ordering: delay_2 < delay_3 < delay_4
    d2 = out.get("delay_2", 0.3)
    d3 = out.get("delay_3", 0.6)
    d4 = out.get("delay_4", 0.9)
    step = 0.1
    d3 = max(d3, d2 + step)
    d4 = max(d4, d3 + step)
    out["delay_3"] = d3
    out["delay_4"] = d4
    return out

def update_params_canon(params, metrics, prev_metrics):
    p = dict(params)
    flux = metrics["spectral_flux"]
    cvar = metrics["centroid_var"]
    reason = "stable"

    LOW_FLUX  = 0.002
    HIGH_FLUX = 0.060

    if flux < LOW_FLUX:
        # Too homogeneous: spread the pitch intervals and delays wider
        p["shift_percent_2"] = p.get("shift_percent_2",  6.0) + 2.0
        p["shift_percent_3"] = p.get("shift_percent_3", 12.0) + 2.0
        p["delay_2"]         = p.get("delay_2",          0.3) + 0.05
        p["delay_3"]         = p.get("delay_3",          0.6) + 0.05
        p["delay_4"]         = p.get("delay_4",          0.9) + 0.05
        reason = "flux_too_low: widened pitch intervals and delays"
    elif flux > HIGH_FLUX:
        # Too chaotic: pull intervals and delays closer together
        p["shift_percent_2"] = p.get("shift_percent_2",  6.0) - 2.0
        p["shift_percent_3"] = p.get("shift_percent_3", 12.0) - 2.0
        p["delay_2"]         = max(0.1, p.get("delay_2", 0.3) - 0.05)
        reason = "flux_too_high: tightened pitch intervals"

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
    preview   = build_preview(audio, sr)
    duration  = len(audio) / sr

    if args.debug:
        print("  Audio: %.2fs  SR=%d  Preview: %.2fs"
              % (duration, sr, len(preview) / sr))

    # ── Compute metrics ─────────────────────────────────────────────────
    metrics = compute_metrics(preview, sr)

    if args.debug:
        print("  Metrics: centroid=%.1f cvar=%.1f flatness=%.4f "
              "rms_var=%.6f flux=%.6f"
              % (metrics["centroid_mean"], metrics["centroid_var"],
                 metrics["spectral_flatness"], metrics["rms_energy_var"],
                 metrics["spectral_flux"]))

    # ── Early stop ──────────────────────────────────────────────────────
    stop_flag = check_early_stop(metrics, prev_metrics,
                                 tol_override=tolerance if tolerance else None)

    # ── Update params ───────────────────────────────────────────────────
    if stage == "mds":
        new_params, reason = update_params_mds(params, metrics, prev_metrics)
    elif stage == "freeze":
        new_params, reason = update_params_freeze(params, metrics, prev_metrics)
    elif stage == "cascade":
        new_params, reason = update_params_cascade(params, metrics, prev_metrics)
    else:
        new_params, reason = update_params_canon(params, metrics, prev_metrics)

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
