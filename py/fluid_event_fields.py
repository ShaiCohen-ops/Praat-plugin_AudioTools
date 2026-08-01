#!/usr/bin/env python3
"""
fluid_event_fields.py
-----------------------------------------------------------------------------
Fluid Event Fields -- Version 0.4 processing engine.

Positional arguments:
    input.wav        field_plan.csv        output.wav        stats.txt

Companion engine to fluid_vector_fields.py (which remains, unmodified, as
"Fluid Spectral Warp": a continuous per-bin STFT phase-warp effect). This
engine implements a different instrument: whole time-domain EVENTS are
segmented out of the source, treated as points in a (time, descriptor)
plane, carried forward through the same analytic vortex/sink/source/shear
vector field, and re-rendered as discrete grains -- reordered, dispersed,
collided, duplicated -- rather than having their spectral phase continuously
deformed in place.

Praat is responsible for the musical/user-facing side (selection, presets,
temp files, visualization). This script performs the numerical
transformation and reports exactly what happened, mirroring the
Praat/Python split used throughout AudioTools.
"""

import sys
import os
import csv
import math
import time
import argparse
import traceback

import numpy as np

try:
    from scipy.signal import find_peaks, medfilt
except ImportError:
    print("ERROR: the 'scipy' package is required (pip install scipy)",
          file=sys.stderr)
    sys.exit(1)

try:
    import soundfile as sf
except ImportError:
    print("ERROR: the 'soundfile' package is required (pip install soundfile)",
          file=sys.stderr)
    sys.exit(1)

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

ENGINE_VERSION = "0.4.0"

FREQ_FLOOR_HZ = 20.0             # low-frequency safety floor for log coordinates
NYQUIST_MARGIN = 0.95

MAX_LOCAL_BOOST_DB = 6.0         # density-compensation safety limits (reused
MAX_LOCAL_ATTEN_DB = 18.0        # convention from fluid_vector_fields.py)

ANALYSIS_MS = {"draft": 60.0, "standard": 40.0, "high": 28.0}
WSOLA_FRAME_MS = {"draft": 50.0, "standard": 40.0, "high": 30.0}
FIELD_TYPES = ("vortex", "sink", "source", "shear")
VERTICAL_AXES = ("centroid", "dominant", "rms")
VERTICAL_RESPONSE_MODES = ("none", "pitch", "gain", "duration")
CANVAS_POLICIES = ("preserve", "expand", "wrap")
COLLISION_POLICIES = ("layer", "repel", "queue")
BOUNDARY_MODES = ("clip", "wrap", "reflect", "open")

DURATION_MIN_FACTOR = 0.15       # duration-expand clamp, relative to original
DURATION_MAX_FACTOR = 6.0

PITCH_MAX_SEMITONES = 24.0

FADE_MIN_SEC = 0.003
FADE_MAX_SEC = 0.08

DUPLICATE_GENERATION_DB = -3.0   # gain reduction per duplicate generation
DUPLICATE_INTEGRATION_GROWTH = 0.6  # extra integration_amount per generation

MAX_CANVAS_EXPANSION = 4.0       # output length safety cap, x source duration
MAX_EVENTS = 4000                # safety cap on segmented event count
MAX_VIZ_EVENTS = 200             # cap on per-event rows written for plotting


# ----------------------------------------------------------------------------
# Small utilities
# ----------------------------------------------------------------------------

def log_stage(n, text):
    print(f"[Stage {n}] {text}", flush=True)


def db_to_lin(db):
    return 10.0 ** (db / 20.0)


def lin_to_db(x, floor=1e-9):
    return 20.0 * math.log10(max(x, floor))


def next_pow2(n):
    return 1 << max(1, int(n - 1)).bit_length()


def clamp(x, lo, hi):
    return max(lo, min(hi, x))


class EngineError(Exception):
    """Raised for any condition that must abort processing cleanly."""
    pass


class Stats(dict):
    """Ordered key=value accumulator for the statistics report."""

    def set(self, key, value):
        self[key] = value

    def write(self, path):
        with open(path, "w", encoding="utf-8") as f:
            for k, v in self.items():
                f.write(f"{k}={v}\n")


# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------

def parse_args():
    p = argparse.ArgumentParser(
        description="Fluid Event Fields -- v0.3 engine")
    p.add_argument("input_wav")
    p.add_argument("field_plan_csv")
    p.add_argument("output_wav")
    p.add_argument("stats_txt")

    p.add_argument("--segmentation", choices=["onset", "fixed"], default="onset")
    p.add_argument("--grain-size", type=float, default=0.25)
    p.add_argument("--onset-sensitivity", type=float, default=0.35)
    p.add_argument("--min-event-duration", type=float, default=0.05)
    p.add_argument("--sparse-onset-fallback", type=int, choices=[0, 1], default=1,
                   help="Use fixed particles when onset detection yields fewer than three events")
    p.add_argument("--pre-onset", type=float, default=0.008)
    p.add_argument("--post-tail", type=float, default=0.030)
    p.add_argument("--vertical-axis", choices=list(VERTICAL_AXES), default="centroid")

    p.add_argument("--integration-amount", type=float, default=1.0)
    p.add_argument("--flow-steps", type=int, default=8)

    p.add_argument("--canvas-policy", choices=list(CANVAS_POLICIES), default=None)
    # Backward-compatible alias used by the first prototype.
    p.add_argument("--duration-policy", choices=list(CANVAS_POLICIES),
                   dest="legacy_canvas_policy", default=None)
    p.add_argument("--duration-response", type=float, default=0.5)
    p.add_argument("--vertical-response-mode", choices=list(VERTICAL_RESPONSE_MODES),
                   default=None,
                   help="Independent response to vertical field motion: none, pitch, gain, or duration")
    # Legacy switch retained for older Praat frontends. It is used only when
    # --vertical-response-mode is omitted.
    p.add_argument("--preserve-pitch", type=int, choices=[0, 1], default=1)
    p.add_argument("--vertical-response", type=float, default=None)
    # Backward-compatible amount alias used by the first prototypes.
    p.add_argument("--pitch-response", type=float, dest="legacy_vertical_response",
                   default=None)

    p.add_argument("--collision-policy", choices=list(COLLISION_POLICIES), default="layer")
    p.add_argument("--min-spacing", type=float, default=0.0)
    p.add_argument("--event-overlap", type=float, default=0.3)
    p.add_argument("--boundary", choices=list(BOUNDARY_MODES), default="clip")
    p.add_argument("--preserve-order", type=int, choices=[0, 1], default=0)

    p.add_argument("--duplication-probability", type=float, default=0.0)
    p.add_argument("--duplication-count", type=int, default=0)

    p.add_argument("--density-gain-compensation", type=float, default=0.6)
    p.add_argument("--dry-event-inclusion", type=float, default=0.0)
    p.add_argument("--original-layer-amount", type=float, default=0.0)
    p.add_argument("--seed", type=int, default=0)

    p.add_argument("--quality", choices=["draft", "standard", "high"], default="standard")
    p.add_argument("--normalize", choices=["none", "peak", "rms"], default="rms")
    p.add_argument("--cleanup", action="store_true")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args()


# ----------------------------------------------------------------------------
# Field-plan CSV
# ----------------------------------------------------------------------------

def load_field_plan(path):
    if not os.path.isfile(path):
        raise EngineError(f"field plan not found: {path}")

    rows = []
    with open(path, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    enabled = [r for r in rows if str(r.get("enabled", "0")).strip() in ("1", "1.0", "true", "True")]

    if len(enabled) == 0:
        raise EngineError("field plan contains no enabled row")
    if len(enabled) > 1:
        raise EngineError(
            "field plan contains more than one enabled row; "
            "version 0.1 supports exactly one active field")

    row = enabled[0]
    field_type = str(row.get("field_type", "")).strip().lower()
    if field_type not in FIELD_TYPES:
        raise EngineError(f"unrecognized field_type '{field_type}'")

    direction = str(row.get("direction", "positive")).strip().lower()
    if direction not in ("positive", "negative"):
        direction = "positive"

    try:
        plan = dict(
            field_type=field_type,
            center_time_norm=clamp(float(row["center_time_norm"]), 0.0, 1.0),
            center_descriptor_norm=clamp(float(row["center_descriptor_norm"]), 0.0, 1.0),
            time_radius_sec=float(row["time_radius_sec"]),
            descriptor_radius_norm=clamp(float(row["descriptor_radius_norm"]), 0.01, 4.0),
            strength=clamp(float(row["strength"]), 0.0, 1.0),
            direction=direction,
            viscosity=clamp(float(row["viscosity"]), 0.0, 1.0),
        )
    except (KeyError, ValueError) as e:
        raise EngineError(f"malformed field plan row: {e}")

    return plan


# ----------------------------------------------------------------------------
# STFT / ISTFT (reused for onset detection and per-grain time-stretch)
# ----------------------------------------------------------------------------

def hann_window(n_fft):
    return 0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(n_fft) / n_fft)


def stft(x, n_fft, hop, window):
    pad = n_fft // 2
    xp = np.pad(x, (pad, pad), mode="reflect")
    n_frames = 1 + max(0, (len(xp) - n_fft) // hop)
    if n_frames < 1:
        n_frames = 1
        xp = np.pad(xp, (0, n_fft - len(xp)))
    frames = np.empty((n_frames, n_fft), dtype=np.float64)
    for i in range(n_frames):
        s = i * hop
        seg = xp[s:s + n_fft]
        if len(seg) < n_fft:
            seg = np.pad(seg, (0, n_fft - len(seg)))
        frames[i] = seg * window
    spec = np.fft.rfft(frames, axis=1)
    return spec


def istft(spec, n_fft, hop, window, length):
    n_frames = spec.shape[0]
    frames = np.fft.irfft(spec, n=n_fft, axis=1)
    pad = n_fft // 2
    out_len = (n_frames - 1) * hop + n_fft
    y = np.zeros(out_len, dtype=np.float64)
    wsum = np.zeros(out_len, dtype=np.float64)
    for i in range(n_frames):
        s = i * hop
        y[s:s + n_fft] += frames[i] * window
        wsum[s:s + n_fft] += window ** 2
    wsum[wsum < 1e-8] = 1e-8
    y = y / wsum
    y = y[pad:pad + length] if length <= len(y) else np.pad(y[pad:], (0, length - (len(y) - pad)))
    if len(y) < length:
        y = np.pad(y, (0, length - len(y)))
    return y[:length]


def choose_stft_params(sr, quality, ms=None):
    ms = ANALYSIS_MS[quality] if ms is None else ms
    n_fft = next_pow2(int(sr * ms / 1000.0))
    n_fft = int(clamp(n_fft, 256, 16384))
    hop = n_fft // 4
    window = hann_window(n_fft)
    return n_fft, hop, window


# ----------------------------------------------------------------------------
# Onset segmentation
# ----------------------------------------------------------------------------

def detect_onsets(mono, sr, sensitivity, min_event_sec, quality):
    n_fft, hop, window = choose_stft_params(sr, quality)
    if len(mono) < n_fft:
        return [0.0]

    spec = stft(mono, n_fft, hop, window)
    mag = np.abs(spec)
    flux = np.diff(mag, axis=0, prepend=mag[:1])
    flux = np.clip(flux, 0.0, None).sum(axis=1)
    if flux.max() > 1e-12:
        flux = flux / flux.max()

    win = int(round(0.4 * sr / hop))
    win = max(3, win + (1 - win % 2))  # force odd
    win = min(win, (len(flux) - 1) | 1) if len(flux) > 1 else 1
    win = max(win, 1)
    if win >= 3 and len(flux) >= win:
        baseline = medfilt(flux, kernel_size=win)
    else:
        baseline = np.zeros_like(flux)

    detect = np.clip(flux - baseline, 0.0, None)
    if detect.max() > 1e-12:
        detect = detect / detect.max()

    min_dist = max(1, int(round(min_event_sec * sr / hop)))
    height = clamp(sensitivity, 0.0, 1.0)
    peaks, _ = find_peaks(detect, height=height, distance=min_dist)
    onset_times = sorted(set((peaks * hop / sr).tolist()))

    if not onset_times or onset_times[0] > 1e-6:
        onset_times = [0.0] + onset_times
    return onset_times


def onsets_to_events(onset_times, duration, min_event_sec):
    times = sorted(set(t for t in onset_times if 0.0 <= t < duration))
    if not times or times[0] > 1e-9:
        times = [0.0] + times
    events = []
    for i, t0 in enumerate(times):
        t1 = times[i + 1] if i + 1 < len(times) else duration
        if t1 - t0 < min_event_sec * 0.5 and events:
            # too short to be its own event: fold into the previous one
            events[-1] = (events[-1][0], t1)
            continue
        events.append((t0, t1))
    return events


def fixed_grain_events(duration, grain_size):
    grain_size = max(grain_size, 0.01)
    n = max(1, int(math.ceil(duration / grain_size)))
    events = []
    for i in range(n):
        t0 = i * grain_size
        t1 = min(duration, t0 + grain_size)
        if t1 > t0:
            events.append((t0, t1))
    return events


# ----------------------------------------------------------------------------
# Per-event descriptors
# ----------------------------------------------------------------------------

def event_descriptors(mono_grain, sr):
    n = len(mono_grain)
    rms = float(np.sqrt(np.mean(mono_grain.astype(np.float64) ** 2))) if n else 0.0
    if n < 8:
        return dict(centroid_hz=FREQ_FLOOR_HZ, dominant_hz=FREQ_FLOOR_HZ, rms=rms)
    w = hann_window(n)
    spec = np.fft.rfft(mono_grain * w)
    mag = np.abs(spec)
    freqs = np.fft.rfftfreq(n, d=1.0 / sr)
    total = mag.sum()
    centroid = float(np.sum(freqs * mag) / total) if total > 1e-12 else FREQ_FLOOR_HZ
    dominant = float(freqs[int(np.argmax(mag))]) if mag.size else FREQ_FLOOR_HZ
    centroid = max(centroid, FREQ_FLOOR_HZ)
    dominant = max(dominant, FREQ_FLOOR_HZ)
    return dict(centroid_hz=centroid, dominant_hz=dominant, rms=rms)


# ----------------------------------------------------------------------------
# Analytic vector field (identical formulation to fluid_vector_fields.py,
# reused verbatim -- only the integration direction and what it is applied
# to differ: here it carries discrete event anchors forward in time, not
# STFT bins backward.)
# ----------------------------------------------------------------------------

def falloff_sigma(viscosity):
    return 0.35 + 1.15 * viscosity


def field_velocity(u, v, field_type, direction_sign, strength, viscosity):
    sigma = falloff_sigma(viscosity)
    r2 = u * u + v * v
    falloff = np.exp(-r2 / (2.0 * sigma * sigma))

    if field_type == "vortex":
        du = -v * falloff * strength * direction_sign
        dv = u * falloff * strength * direction_sign
    elif field_type == "sink":
        du = -u * falloff * strength
        dv = -v * falloff * strength
    elif field_type == "source":
        du = u * falloff * strength
        dv = v * falloff * strength
    elif field_type == "shear":
        time_envelope = np.exp(-(u * u) / (2.0 * sigma * sigma))
        du = direction_sign * strength * np.tanh(v / max(sigma, 1e-6)) * time_envelope
        dv = np.zeros_like(u) if hasattr(u, "shape") else 0.0
    else:
        raise EngineError(f"unhandled field_type '{field_type}'")
    return du, dv


def integrate_forward(u0, v0, field_type, direction_sign, strength, viscosity,
                       steps, total_ds):
    """Forward RK2 (midpoint) integration of event anchors through the
    field, for a total normalized flow-time of `total_ds`. u0/v0 may be
    scalars or numpy arrays (vectorized across all events at once)."""
    u = np.array(u0, dtype=np.float64, copy=True)
    v = np.array(v0, dtype=np.float64, copy=True)
    steps = max(1, int(steps))
    ds = total_ds / steps
    for _ in range(steps):
        k1u, k1v = field_velocity(u, v, field_type, direction_sign, strength, viscosity)
        mid_u = u + 0.5 * ds * k1u
        mid_v = v + 0.5 * ds * k1v
        k2u, k2v = field_velocity(mid_u, mid_v, field_type, direction_sign, strength, viscosity)
        u = u + ds * k2u
        v = v + ds * k2v
    return u, v


def local_map_metrics(u0, v0, field_type, direction_sign, strength,
                      viscosity, steps, total_ds, eps=1e-3):
    """Finite-difference metrics of the forward event map.

    Returns:
        det         2-D area change (useful as a diagnostic / density cue)
        time_scale  local derivative dU'/dU, i.e. temporal stretching
        u_c, v_c    mapped event coordinates

    Event duration must follow the temporal derivative, not sqrt(|det J|):
    a field can stretch time while compressing the descriptor axis and keep
    det J near one. The old prototype therefore missed real time stretching
    and sometimes changed duration for the wrong reason.
    """
    u_c, v_c = integrate_forward(u0, v0, field_type, direction_sign, strength, viscosity, steps, total_ds)
    u_u, v_u = integrate_forward(u0 + eps, v0, field_type, direction_sign, strength, viscosity, steps, total_ds)
    u_v, v_v = integrate_forward(u0, v0 + eps, field_type, direction_sign, strength, viscosity, steps, total_ds)
    du_du = (u_u - u_c) / eps
    dv_du = (v_u - v_c) / eps
    du_dv = (u_v - u_c) / eps
    dv_dv = (v_v - v_c) / eps
    det = du_du * dv_dv - du_dv * dv_du
    time_scale = np.abs(du_du)
    return det, time_scale, u_c, v_c


# ----------------------------------------------------------------------------
# Boundary handling
# ----------------------------------------------------------------------------

def apply_boundary(t, lo, hi, mode):
    span = hi - lo
    if span <= 0:
        return np.full_like(t, lo)
    if mode == "open":
        return np.asarray(t, dtype=np.float64).copy()
    if mode == "clip":
        return np.clip(t, lo, hi)
    elif mode == "wrap":
        return lo + np.mod(t - lo, span)
    elif mode == "reflect":
        period = 2.0 * span
        xm = np.mod(t - lo, period)
        xm = np.where(xm > span, period - xm, xm)
        return lo + xm
    else:
        raise EngineError(f"unhandled boundary mode '{mode}'")


# ----------------------------------------------------------------------------
# Grain rendering: linked multichannel WSOLA time stretch followed by a
# resample-based pitch shift. Composing the two decouples duration and pitch:
# stretch to duration*pitch_ratio, then resample by pitch_ratio.
# ----------------------------------------------------------------------------

def resample_linear(x, new_len):
    n = len(x)
    new_len = max(1, int(round(new_len)))
    if n == 0:
        return np.zeros(new_len, dtype=np.float64)
    if n == 1:
        return np.full(new_len, x[0], dtype=np.float64)
    src_idx = np.linspace(0.0, n - 1, new_len)
    return np.interp(src_idx, np.arange(n), x)


def pad_or_trim_linked(grain, target_len):
    """Change container length without resampling or changing pitch."""
    grain = np.asarray(grain, dtype=np.float64)
    if grain.ndim == 1:
        grain = grain[:, None]
    target_len = max(1, int(round(target_len)))
    n, n_ch = grain.shape
    if target_len == n:
        return grain.copy()
    if target_len < n:
        return grain[:target_len, :].copy()
    out = np.zeros((target_len, n_ch), dtype=np.float64)
    out[:n, :] = grain
    return out


def wsola_time_stretch_linked(grain, sr, target_len, quality="standard"):
    """Linked multichannel WSOLA time stretch.

    This is deliberately a time-domain renderer. Candidate analysis frames
    are chosen from a mono reference by waveform similarity, then the same
    positions and overlap-add envelope are applied to every channel. It
    preserves channel relationships and transient identity better than the
    prototype's independent phase-vocoder passes.
    """
    grain = np.asarray(grain, dtype=np.float64)
    if grain.ndim == 1:
        grain = grain[:, None]
    n, n_ch = grain.shape
    target_len = max(1, int(round(target_len)))
    if target_len == n:
        return grain.copy()
    if n < 96 or target_len < 48:
        return pad_or_trim_linked(grain, target_len)

    ratio = target_len / n
    frame_len = int(round(WSOLA_FRAME_MS.get(quality, 40.0) * 0.001 * sr))
    frame_len = int(clamp(frame_len, 96, min(2048, n)))
    if frame_len % 2:
        frame_len += 1
    frame_len = min(frame_len, n)
    if frame_len < 64:
        return pad_or_trim_linked(grain, target_len)

    synth_hop = max(16, frame_len // 2)
    overlap = frame_len - synth_hop
    analysis_hop = synth_hop / max(ratio, 1e-9)
    search = max(8, frame_len // 4)
    window = np.hanning(frame_len)
    # A small positive floor avoids completely unweighted end samples.
    window = np.maximum(window, 1e-6)

    out_len = target_len + frame_len
    out = np.zeros((out_len, n_ch), dtype=np.float64)
    norm = np.zeros(out_len, dtype=np.float64)
    mono = np.mean(grain, axis=1)

    max_input_start = max(0, n - frame_len)
    prev_input = 0
    syn_pos = 0
    frame_index = 0

    while syn_pos < target_len:
        if frame_index == 0:
            input_pos = 0
        else:
            predicted = prev_input + analysis_hop
            lo = max(0, int(round(predicted - search)))
            hi = min(max_input_start, int(round(predicted + search)))
            if hi <= lo or overlap < 8:
                input_pos = int(clamp(round(predicted), 0, max_input_start))
            else:
                existing_norm = norm[syn_pos:syn_pos + overlap]
                valid = existing_norm > 1e-8
                if np.count_nonzero(valid) < 8:
                    input_pos = int(clamp(round(predicted), 0, max_input_start))
                else:
                    existing = np.mean(out[syn_pos:syn_pos + overlap, :], axis=1)
                    existing = existing[valid] / existing_norm[valid]
                    existing = existing - np.mean(existing)
                    ex_norm = np.linalg.norm(existing) + 1e-12
                    divisor = 12 if quality == "draft" else (36 if quality == "high" else 24)
                    step = max(1, search // divisor)
                    best_score = -np.inf
                    best_pos = int(clamp(round(predicted), 0, max_input_start))
                    for cand in range(lo, hi + 1, step):
                        candidate = mono[cand:cand + overlap][valid]
                        candidate = candidate - np.mean(candidate)
                        score = float(np.dot(existing, candidate) /
                                      (ex_norm * (np.linalg.norm(candidate) + 1e-12)))
                        if score > best_score:
                            best_score = score
                            best_pos = cand
                    # Refine sample-by-sample around the coarse winner.
                    rlo = max(lo, best_pos - step)
                    rhi = min(hi, best_pos + step)
                    for cand in range(rlo, rhi + 1):
                        candidate = mono[cand:cand + overlap][valid]
                        candidate = candidate - np.mean(candidate)
                        score = float(np.dot(existing, candidate) /
                                      (ex_norm * (np.linalg.norm(candidate) + 1e-12)))
                        if score > best_score:
                            best_score = score
                            best_pos = cand
                    input_pos = best_pos

        frame = grain[input_pos:input_pos + frame_len, :]
        if frame.shape[0] < frame_len:
            frame = np.pad(frame, ((0, frame_len - frame.shape[0]), (0, 0)))
        out[syn_pos:syn_pos + frame_len, :] += frame * window[:, None]
        norm[syn_pos:syn_pos + frame_len] += window

        prev_input = input_pos
        syn_pos += synth_hop
        frame_index += 1
        if input_pos >= max_input_start and syn_pos >= target_len:
            break

    valid = norm[:target_len] > 1e-8
    result = np.zeros((target_len, n_ch), dtype=np.float64)
    result[valid, :] = out[:target_len, :][valid, :] / norm[:target_len][valid, None]
    return result


def render_grain(grain, sr, target_duration_sec, pitch_shift_semitones,
                 quality="standard"):
    """Render one multichannel event while avoiding needless resynthesis.

    Unchanged events are copied sample-for-sample. Linked WSOLA is invoked
    only when duration or pitch actually changes.
    """
    grain = np.asarray(grain, dtype=np.float64)
    if grain.ndim == 1:
        grain = grain[:, None]
    n = grain.shape[0]
    target_len = max(1, int(round(target_duration_sec * sr)))
    if abs(pitch_shift_semitones) < 0.02:
        pitch_shift_semitones = 0.0
    pitch_ratio = 2.0 ** (pitch_shift_semitones / 12.0)

    if target_len == n and abs(pitch_shift_semitones) < 1e-9:
        return grain.copy()

    # Avoid an expensive transform for sub-percent duration changes. Pad/trim
    # preserves pitch and the event body more faithfully than a full stretch.
    if (abs(target_len - n) <= max(1, int(round(0.003 * n)))
            and abs(pitch_shift_semitones) < 1e-9):
        return pad_or_trim_linked(grain, target_len)

    intermediate_len = max(1, int(round(target_len * pitch_ratio)))
    stretched = wsola_time_stretch_linked(
        grain, sr, intermediate_len, quality=quality)
    if abs(pitch_ratio - 1.0) < 1e-9:
        if len(stretched) == target_len:
            return stretched
        return np.column_stack([resample_linear(stretched[:, c], target_len)
                                for c in range(stretched.shape[1])])

    return np.column_stack([resample_linear(stretched[:, c], target_len)
                            for c in range(stretched.shape[1])])


def fade_grain(grain, sr, overlap_amount, pre_samples=0, post_samples=0,
               onset_segment=False):
    """Apply edge fades without attenuating the detected onset itself.

    For onset segmentation, fade-in is confined to captured pre-onset audio
    and fade-out to the captured tail. For fixed grains, symmetric fades are
    allowed. overlap_amount=0 is a true bypass.
    """
    if overlap_amount <= 0.0:
        return grain
    n = grain.shape[0]
    if n < 4:
        return grain
    dur = n / sr
    desired = int(round(clamp(overlap_amount * dur * 0.5,
                              0.0, FADE_MAX_SEC) * sr))
    if onset_segment:
        fade_in_n = min(desired, max(0, int(pre_samples)))
        fade_out_n = min(desired, max(0, int(post_samples)))
    else:
        floor_n = int(round(FADE_MIN_SEC * sr))
        desired = max(desired, floor_n)
        fade_in_n = min(desired, n // 2)
        fade_out_n = min(desired, n // 2)

    env = np.ones(n, dtype=np.float64)
    if fade_in_n >= 2:
        ramp = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, fade_in_n))
        env[:fade_in_n] *= ramp
    if fade_out_n >= 2:
        ramp = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, fade_out_n))
        env[-fade_out_n:] *= ramp[::-1]
    return grain * env[:, None]


# ----------------------------------------------------------------------------
# Collision resolution
# ----------------------------------------------------------------------------

def resolve_queue(times, durations, order, min_spacing):
    out = times.copy()
    cursor = -1e18
    for idx in order:
        if out[idx] < cursor + min_spacing:
            out[idx] = cursor + min_spacing
        cursor = out[idx] + durations[idx]
    return out


def resolve_repel(times, durations, order, min_spacing):
    out = times.copy()
    n = len(order)
    if n == 0:
        return out
    clusters = []
    current = [order[0]]
    cursor_end = times[order[0]] + durations[order[0]]
    for k in range(1, n):
        idx = order[k]
        if times[idx] < cursor_end + min_spacing:
            current.append(idx)
            cursor_end = max(cursor_end, times[idx] + durations[idx])
        else:
            clusters.append(current)
            current = [idx]
            cursor_end = times[idx] + durations[idx]
    clusters.append(current)

    for cluster in clusters:
        if len(cluster) == 1:
            continue
        total_span = sum(durations[i] for i in cluster) + min_spacing * (len(cluster) - 1)
        mean_t = float(np.mean([times[i] for i in cluster]))
        t = mean_t - total_span / 2.0
        for idx in cluster:
            out[idx] = t
            t += durations[idx] + min_spacing
    return out


def resolve_collisions(times, durations, orig_order_key, policy, min_spacing, preserve_order):
    n = len(times)
    if n == 0:
        return times.copy()
    if policy == "layer":
        if not preserve_order:
            return times.copy()
        # Preserve the source order while still allowing overlaps. Only the
        # event-anchor starts are made monotonic; unlike Queue, event ends do
        # not push following events forward.
        out = times.copy()
        order = list(np.argsort(orig_order_key))
        cursor = -1e18
        for idx in order:
            out[idx] = max(out[idx], cursor + min_spacing)
            cursor = out[idx]
        return out
    if preserve_order:
        order = list(np.argsort(orig_order_key))
    else:
        order = list(np.argsort(times))
    if policy == "queue":
        return resolve_queue(times, durations, order, min_spacing)
    elif policy == "repel":
        return resolve_repel(times, durations, order, min_spacing)
    else:
        raise EngineError(f"unhandled collision policy '{policy}'")


# ----------------------------------------------------------------------------
# Density-based gain compensation
# ----------------------------------------------------------------------------

def kde_rate(times_ref, eval_points, bandwidth):
    if len(times_ref) == 0 or len(eval_points) == 0:
        return np.zeros(len(eval_points))
    diffs = eval_points[:, None] - times_ref[None, :]
    weights = np.exp(-0.5 * (diffs / bandwidth) ** 2)
    return weights.sum(axis=1) / (bandwidth * math.sqrt(2.0 * math.pi))


def kde_rate_circular(times_ref, eval_points, bandwidth, period):
    """Gaussian event-rate estimate on a circular time canvas."""
    if period <= 0:
        return kde_rate(times_ref, eval_points, bandwidth)
    ref = np.mod(np.asarray(times_ref), period)
    eval_mod = np.mod(np.asarray(eval_points), period)
    extended = np.concatenate([ref - period, ref, ref + period])
    return kde_rate(extended, eval_mod, bandwidth)


def add_to_canvas(output, segment, start_sample, wrap=False):
    """Add a multichannel segment to the output, safely handling boundaries.

    In wrap mode the canvas is circular and arbitrarily long segments may
    cross the boundary more than once. Returns True when any material had to
    be discarded in non-wrap mode.
    """
    canvas_len = output.shape[0]
    seg_len = segment.shape[0]
    if canvas_len <= 0 or seg_len <= 0:
        return False

    if wrap:
        pos = int(start_sample) % canvas_len
        src = 0
        remaining = seg_len
        while remaining > 0:
            chunk = min(remaining, canvas_len - pos)
            output[pos:pos + chunk, :] += segment[src:src + chunk, :]
            src += chunk
            remaining -= chunk
            pos = 0
        return False

    write_start = max(0, int(start_sample))
    skip = write_start - int(start_sample)
    write_end = min(int(start_sample) + seg_len, canvas_len)
    truncated = (int(start_sample) < 0 or int(start_sample) + seg_len > canvas_len)
    if write_end > write_start and skip < seg_len:
        output[write_start:write_end, :] += segment[
            skip:skip + (write_end - write_start), :]
    return truncated


# ----------------------------------------------------------------------------
# Main processing
# ----------------------------------------------------------------------------

def process(args):
    stats = Stats()
    warnings = []
    t_wall_start = time.time()
    effective_seed = (int(args.seed) if int(args.seed) != 0
                      else int.from_bytes(os.urandom(8), "little") % (2 ** 32))
    rng = np.random.default_rng(effective_seed)

    stats.set("engine_version", ENGINE_VERSION)
    stats.set("status", "error")

    # ---------------- Stage 1: Load and validate ----------------
    log_stage(1, "Load and validate")

    if not os.path.isfile(args.input_wav):
        raise EngineError(f"input WAV not found: {args.input_wav}")

    data, sr = sf.read(args.input_wav, always_2d=True)
    n_samples, n_channels = data.shape
    if n_samples < 4:
        raise EngineError("input has no usable samples")
    if sr <= 0:
        raise EngineError("invalid sample rate")
    if not np.all(np.isfinite(data)):
        raise EngineError("input audio contains NaN or infinite samples")

    working = data.astype(np.float64)
    duration = n_samples / sr
    mono = working.mean(axis=1)

    input_rms = float(np.sqrt(np.mean(working ** 2)))
    input_peak = float(np.max(np.abs(working))) if n_samples else 0.0

    plan = load_field_plan(args.field_plan_csv)

    if plan["time_radius_sec"] < 0.02:
        warnings.append(f"time_radius_sec too small, raised {plan['time_radius_sec']:.4f}->0.02")
        plan["time_radius_sec"] = 0.02
    if plan["time_radius_sec"] > duration:
        plan["time_radius_sec"] = duration

    field_type = plan["field_type"]
    direction_sign = 1.0 if plan["direction"] == "positive" else -1.0
    strength = plan["strength"]
    viscosity = plan["viscosity"]
    Rt = plan["time_radius_sec"]
    t0 = plan["center_time_norm"] * duration

    integration_amount = max(0.0, args.integration_amount)
    flow_steps = max(1, int(args.flow_steps))
    canvas_policy = (args.canvas_policy or args.legacy_canvas_policy or "preserve")
    duration_response = clamp(args.duration_response, 0.0, 1.0)
    vertical_response_raw = (args.vertical_response
                             if args.vertical_response is not None
                             else args.legacy_vertical_response)
    vertical_response = clamp(0.5 if vertical_response_raw is None
                              else vertical_response_raw, 0.0, 1.0)
    if args.vertical_response_mode is not None:
        vertical_response_mode = args.vertical_response_mode
    else:
        # Backward compatibility with v0.3 callers: spectral axes used the
        # preserve-pitch switch, while RMS used vertical response as gain.
        if vertical_response <= 0.0:
            vertical_response_mode = "none"
        elif args.vertical_axis == "rms":
            vertical_response_mode = "gain"
        elif not bool(args.preserve_pitch):
            vertical_response_mode = "pitch"
        else:
            vertical_response_mode = "none"
    pre_onset = max(0.0, float(args.pre_onset))
    post_tail = max(0.0, float(args.post_tail))
    collision_policy = args.collision_policy
    min_spacing = max(0.0, args.min_spacing)
    event_overlap = clamp(args.event_overlap, 0.0, 1.0)
    boundary = args.boundary
    preserve_order = bool(args.preserve_order)
    dup_prob = clamp(args.duplication_probability, 0.0, 1.0)
    dup_count = max(0, int(args.duplication_count))
    density_comp = clamp(args.density_gain_compensation, 0.0, 1.0)
    dry_inclusion = clamp(args.dry_event_inclusion, 0.0, 1.0)
    orig_layer_amount = clamp(args.original_layer_amount, 0.0, 2.0)
    quality = args.quality

    # ---------------- Stage 2: Segmentation ----------------
    log_stage(2, f"Segment events ({args.segmentation})")

    segmentation_used = args.segmentation
    if args.segmentation == "onset":
        onset_times = detect_onsets(mono, sr, args.onset_sensitivity,
                                     args.min_event_duration, quality)
        raw_events = onsets_to_events(onset_times, duration, args.min_event_duration)
        # A compositional event field cannot create meaningful internal motion
        # from one undivided event. Named presets therefore fall back to a
        # modest fixed-particle grid when onset analysis finds fewer than three
        # events. Custom mode disables this through the CLI flag.
        if (bool(args.sparse_onset_fallback) and len(raw_events) < 3
                and duration >= 0.20):
            original_count = len(raw_events)
            fallback_grain = min(0.25, max(0.08, duration / 16.0))
            raw_events = fixed_grain_events(duration, fallback_grain)
            segmentation_used = "fixed_fallback"
            warnings.append(
                f"onset detection found only {original_count} event(s); "
                f"used {len(raw_events)} fixed particles of "
                f"{fallback_grain:.3f}s for audible field motion")
    else:
        raw_events = fixed_grain_events(duration, args.grain_size)

    if len(raw_events) == 0:
        raise EngineError("segmentation produced no events")
    if len(raw_events) > MAX_EVENTS:
        warnings.append(f"event count {len(raw_events)} exceeded safety cap, truncated to {MAX_EVENTS}")
        raw_events = raw_events[:MAX_EVENTS]

    n_events = len(raw_events)
    stats.set("segmentation_requested", args.segmentation)
    stats.set("segmentation_mode", segmentation_used)
    stats.set("n_events_detected", n_events)

    # ---------------- Stage 3: Per-event descriptors ----------------
    log_stage(3, "Compute per-event descriptors")

    # `starts` are compositional anchors (detected onsets or fixed-grain
    # starts). Extraction may include pre-onset material and a post-event
    # tail, but the anchor remains fixed at the actual event start.
    starts = np.array([e[0] for e in raw_events], dtype=np.float64)
    core_ends = np.array([e[1] for e in raw_events], dtype=np.float64)
    if args.segmentation == "onset":
        extract_starts = np.maximum(0.0, starts - pre_onset)
        extract_ends = np.minimum(duration, core_ends + post_tail)
    else:
        # Fixed grains receive genuine source overlap, not merely independent
        # edge attenuation. Adjacent unchanged grains therefore crossfade
        # through shared material instead of leaving amplitude holes.
        fixed_margin = max(0.0, float(args.grain_size)) * event_overlap * 0.5
        extract_starts = np.maximum(0.0, starts - fixed_margin)
        extract_ends = np.minimum(duration, core_ends + fixed_margin)
    durations0 = np.maximum(extract_ends - extract_starts, 1.0 / sr)
    anchor_offsets0 = starts - extract_starts
    post_tail0 = extract_ends - core_ends

    centroid_hz = np.zeros(n_events)
    dominant_hz = np.zeros(n_events)
    rms_lin = np.zeros(n_events)
    for i in range(n_events):
        a = int(round(starts[i] * sr))
        b = int(round(core_ends[i] * sr))
        a = clamp(a, 0, n_samples - 1)
        b = clamp(b, a + 1, n_samples)
        desc = event_descriptors(mono[a:b], sr)
        centroid_hz[i] = desc["centroid_hz"]
        dominant_hz[i] = desc["dominant_hz"]
        rms_lin[i] = desc["rms"]

    if args.vertical_axis == "centroid":
        raw_descriptor = np.log2(np.maximum(centroid_hz, FREQ_FLOOR_HZ))
        axis_unit = "hz_log2"
    elif args.vertical_axis == "dominant":
        raw_descriptor = np.log2(np.maximum(dominant_hz, FREQ_FLOOR_HZ))
        axis_unit = "hz_log2"
    else:
        raw_descriptor = np.array([lin_to_db(r) for r in rms_lin])
        axis_unit = "db"

    raw_d_min = float(np.min(raw_descriptor))
    raw_d_max = float(np.max(raw_descriptor))
    # Robust bounds keep one silent or unusually bright event from defining
    # the entire vertical field. With very small event sets, fall back to the
    # full observed range.
    if n_events >= 6:
        d_min = float(np.percentile(raw_descriptor, 5.0))
        d_max = float(np.percentile(raw_descriptor, 95.0))
    else:
        d_min, d_max = raw_d_min, raw_d_max
    if d_max - d_min < 1e-6:
        d_min, d_max = raw_d_min, raw_d_max
    d_span = max(d_max - d_min, 1e-6)
    descriptor_for_field = np.clip(raw_descriptor, d_min, d_max)

    centre_value = d_min + plan["center_descriptor_norm"] * d_span
    radius_value = max(plan["descriptor_radius_norm"] * d_span, 1e-6)

    U0 = (starts - t0) / Rt
    V0 = (descriptor_for_field - centre_value) / radius_value

    # ---------------- Stage 4: Forward field integration ----------------
    log_stage(4, "Integrate event anchors forward through the field")

    U1, V1 = integrate_forward(U0, V0, field_type, direction_sign, strength,
                                viscosity, flow_steps, integration_amount)
    det, local_time_scale, _, _ = local_map_metrics(
        U0, V0, field_type, direction_sign, strength, viscosity,
        flow_steps, integration_amount)

    new_t_raw = t0 + U1 * Rt
    new_t = apply_boundary(new_t_raw, 0.0, duration, boundary)

    displacement_v = V1 - V0

    # ---------------- Stage 5: Duration and pitch mapping ----------------
    log_stage(5, "Map duration and pitch response")

    stretch_factor = 1.0 + (local_time_scale - 1.0) * duration_response
    stretch_factor = np.clip(stretch_factor,
                             DURATION_MIN_FACTOR, DURATION_MAX_FACTOR)
    new_duration = durations0 * stretch_factor

    descriptor_shift_native = displacement_v * radius_value
    pitch_shift = np.zeros(n_events)
    descriptor_gain_db = np.zeros(n_events)
    vertical_duration_factor = np.ones(n_events)

    # The analysis coordinate and its sonic response are independent.
    # `displacement_v` is the common normalized movement produced by the
    # field; native descriptor units are used where they have a meaningful
    # acoustic interpretation.
    if vertical_response_mode == "pitch":
        if axis_unit == "hz_log2":
            pitch_delta = descriptor_shift_native * 12.0
        else:
            pitch_delta = displacement_v * PITCH_SEMITONE_SCALE
        pitch_shift = np.clip(pitch_delta * vertical_response,
                              -PITCH_MAX_SEMITONES, PITCH_MAX_SEMITONES)
    elif vertical_response_mode == "gain":
        if axis_unit == "db":
            gain_delta_db = descriptor_shift_native
        else:
            gain_delta_db = displacement_v * MAX_LOCAL_BOOST_DB
        descriptor_gain_db = np.clip(gain_delta_db * vertical_response,
                                     -MAX_LOCAL_ATTEN_DB, MAX_LOCAL_BOOST_DB)
    elif vertical_response_mode == "duration":
        vertical_duration_factor = np.clip(
            np.exp2(displacement_v * vertical_response),
            DURATION_MIN_FACTOR, DURATION_MAX_FACTOR)
        new_duration = np.clip(
            new_duration * vertical_duration_factor,
            durations0 * DURATION_MIN_FACTOR,
            durations0 * DURATION_MAX_FACTOR)

    # ---------------- Stage 6: Duplication ----------------
    log_stage(6, "Resolve duplicates")

    instances = []  # dicts: source, generation, u0, v0, order_key
    for i in range(n_events):
        instances.append(dict(source=i, generation=0, order_key=float(i)))
        gen = 1
        while gen <= dup_count and rng.random() < dup_prob:
            instances.append(dict(source=i, generation=gen, order_key=float(i) + 0.001 * gen))
            gen += 1

    n_inst = len(instances)
    src_idx = np.array([inst["source"] for inst in instances], dtype=int)
    gens = np.array([inst["generation"] for inst in instances], dtype=int)
    order_keys = np.array([inst["order_key"] for inst in instances], dtype=np.float64)

    if np.any(gens > 0):
        extra_ds = integration_amount * (1.0 + DUPLICATE_INTEGRATION_GROWTH * gens)
        Ui1, Vi1 = integrate_forward(U0[src_idx], V0[src_idx], field_type, direction_sign,
                                      strength, viscosity, flow_steps, extra_ds)
        _, inst_time_scale, _, _ = local_map_metrics(
            U0[src_idx], V0[src_idx], field_type, direction_sign,
            strength, viscosity, flow_steps, extra_ds)
        inst_t_raw = t0 + Ui1 * Rt
        inst_t = apply_boundary(inst_t_raw, 0.0, duration, boundary)
        inst_disp_v = Vi1 - V0[src_idx]
        inst_desc_shift_native = inst_disp_v * radius_value
        inst_pitch = np.zeros(n_inst)
        inst_descriptor_gain_db = np.zeros(n_inst)
        inst_vertical_duration_factor = np.ones(n_inst)

        if vertical_response_mode == "pitch":
            if axis_unit == "hz_log2":
                inst_pitch_delta = inst_desc_shift_native * 12.0
            else:
                inst_pitch_delta = inst_disp_v * PITCH_SEMITONE_SCALE
            inst_pitch = np.clip(inst_pitch_delta * vertical_response,
                                 -PITCH_MAX_SEMITONES, PITCH_MAX_SEMITONES)
        elif vertical_response_mode == "gain":
            if axis_unit == "db":
                inst_gain_delta_db = inst_desc_shift_native
            else:
                inst_gain_delta_db = inst_disp_v * MAX_LOCAL_BOOST_DB
            inst_descriptor_gain_db = np.clip(
                inst_gain_delta_db * vertical_response,
                -MAX_LOCAL_ATTEN_DB, MAX_LOCAL_BOOST_DB)
        elif vertical_response_mode == "duration":
            inst_vertical_duration_factor = np.clip(
                np.exp2(inst_disp_v * vertical_response),
                DURATION_MIN_FACTOR, DURATION_MAX_FACTOR)

        inst_stretch_factor = np.clip(
            1.0 + (inst_time_scale - 1.0) * duration_response,
            DURATION_MIN_FACTOR, DURATION_MAX_FACTOR)
        inst_duration = durations0[src_idx] * inst_stretch_factor
        if vertical_response_mode == "duration":
            inst_duration = np.clip(
                inst_duration * inst_vertical_duration_factor,
                durations0[src_idx] * DURATION_MIN_FACTOR,
                durations0[src_idx] * DURATION_MAX_FACTOR)
    else:
        inst_t = new_t[src_idx].copy()
        inst_pitch = pitch_shift[src_idx].copy()
        inst_duration = new_duration[src_idx].copy()
        inst_descriptor_gain_db = descriptor_gain_db[src_idx].copy()

    inst_gain_db = (gens.astype(np.float64) * DUPLICATE_GENERATION_DB
                    + inst_descriptor_gain_db)

    # Convert onset-anchor times into actual rendered segment starts. The
    # captured pre-onset offset scales with any duration transformation.
    offset_ratio = anchor_offsets0[src_idx] / np.maximum(durations0[src_idx], 1.0 / sr)
    inst_anchor_offset = offset_ratio * inst_duration
    inst_render_start = inst_t - inst_anchor_offset

    # ---------------- Stage 7: Collision resolution ----------------
    log_stage(7, "Resolve collisions")

    inst_render_start_resolved = resolve_collisions(
        inst_render_start, inst_duration, order_keys,
        collision_policy, min_spacing, preserve_order)
    inst_t_resolved = inst_render_start_resolved + inst_anchor_offset

    # ---------------- Stage 8: Density-based gain compensation ----------------
    log_stage(8, "Estimate density and compensate gain")

    avg_spacing = duration / max(n_events, 1)
    bandwidth = max(0.05, avg_spacing * 1.5, args.min_event_duration * 1.5)
    density_times = (np.mod(inst_t_resolved, duration)
                     if canvas_policy == "wrap" and duration > 0
                     else inst_t_resolved)
    if canvas_policy == "wrap":
        before_rate = kde_rate_circular(
            starts, starts[src_idx], bandwidth, duration)
        after_rate = kde_rate_circular(
            density_times, density_times, bandwidth, duration)
    else:
        before_rate = kde_rate(starts, starts[src_idx], bandwidth)
        after_rate = kde_rate(density_times, density_times, bandwidth)
    ratio = after_rate / np.maximum(before_rate, 1e-6)
    comp_db = -density_comp * 10.0 * np.log10(np.maximum(ratio, 1e-6))
    comp_db = np.clip(comp_db, -MAX_LOCAL_ATTEN_DB, MAX_LOCAL_BOOST_DB)
    inst_gain_db = np.clip(inst_gain_db + comp_db,
                           -MAX_LOCAL_ATTEN_DB, MAX_LOCAL_BOOST_DB)

    # ---------------- Stage 9: Canvas sizing ----------------
    log_stage(9, "Size the output canvas")

    canvas_time_offset = 0.0
    if canvas_policy == "expand":
        min_start = float(np.min(inst_render_start_resolved)) if n_inst else 0.0
        if min_start < 0.0:
            canvas_time_offset = -min_start
            inst_render_start_resolved = inst_render_start_resolved + canvas_time_offset
            inst_t_resolved = inst_t_resolved + canvas_time_offset
        natural_end = (float(np.max(inst_render_start_resolved + inst_duration))
                       if n_inst else duration)
        # The whole original time coordinate is shifted when negative-time
        # events open the canvas to the left. Dry copies and the original
        # layer must share that same coordinate system.
        natural_end = max(natural_end, duration + canvas_time_offset)
        canvas_duration = min(natural_end, duration * MAX_CANVAS_EXPANSION)
        if natural_end > canvas_duration + 1e-9:
            warnings.append(f"output extent {natural_end:.3f}s exceeded the "
                            f"{MAX_CANVAS_EXPANSION:.0f}x safety cap and was truncated")
        canvas_len = max(n_samples, int(round(canvas_duration * sr)))
    else:
        # Preserve and Wrap are both closed canvases exactly equal to the
        # source duration. Queue/Repel may move events beyond the edge, but
        # they cannot silently lengthen the result.
        canvas_duration = duration
        canvas_len = n_samples

    output = np.zeros((canvas_len, n_channels), dtype=np.float64)

    # Strict identity shortcut: no field movement, no secondary composition,
    # no duration/pitch/gain response, and a preserved canvas. This guarantees
    # sample-equivalent output without segmentation-boundary coloration.
    identity_shortcut = (
        canvas_policy == "preserve"
        and n_inst == n_events
        and np.all(gens == 0)
        and collision_policy == "layer"
        and min_spacing == 0.0
        and dry_inclusion == 0.0
        and orig_layer_amount == 0.0
        and np.max(np.abs(inst_render_start_resolved - extract_starts)) <= 0.5 / sr
        and np.max(np.abs(inst_duration - durations0)) <= 0.5 / sr
        and np.max(np.abs(inst_pitch)) <= 1e-9
        and np.max(np.abs(inst_gain_db)) <= 1e-9
    )

    # ---------------- Stage 10: Render field-processed instances ----------------
    log_stage(10, "Render field-processed grains")

    n_truncated = 0
    if identity_shortcut:
        output[:, :] = working
    else:
        for k in range(n_inst):
            i = src_idx[k]
            a = int(round(extract_starts[i] * sr))
            b = int(round(extract_ends[i] * sr))
            a = int(clamp(a, 0, n_samples - 1))
            b = int(clamp(b, a + 1, n_samples))
            grain = working[a:b, :]

            tgt_dur = max(inst_duration[k], 1.0 / sr)
            rendered = render_grain(
                grain, sr, tgt_dur, inst_pitch[k], quality=quality)

            scale = rendered.shape[0] / max(1, grain.shape[0])
            pre_samples_scaled = int(round(anchor_offsets0[i] * sr * scale))
            post_samples_scaled = int(round(post_tail0[i] * sr * scale))
            rendered = fade_grain(
                rendered, sr, event_overlap,
                pre_samples=pre_samples_scaled,
                post_samples=post_samples_scaled,
                onset_segment=True)

            gain = db_to_lin(inst_gain_db[k])
            rendered = rendered * gain
            start_sample = int(round(inst_render_start_resolved[k] * sr))
            truncated = add_to_canvas(
                output, rendered, start_sample,
                wrap=(canvas_policy == "wrap"))
            if truncated:
                n_truncated += 1

    if n_truncated:
        warnings.append(f"{n_truncated} rendered grain(s) were truncated at the output boundary")

    # ---------------- Stage 11: Dry-event inclusion ----------------
    log_stage(11, "Include dry event copies")

    n_dry = 0
    if dry_inclusion > 0.0:
        for i in range(n_events):
            if rng.random() < dry_inclusion:
                a = int(round(extract_starts[i] * sr))
                b = int(round(extract_ends[i] * sr))
                a = int(clamp(a, 0, n_samples - 1))
                b = int(clamp(b, a + 1, n_samples))
                grain = fade_grain(
                    working[a:b, :].copy(), sr, event_overlap,
                    pre_samples=int(round(anchor_offsets0[i] * sr)),
                    post_samples=int(round(post_tail0[i] * sr)),
                    onset_segment=True)
                start_sample = a + int(round(canvas_time_offset * sr))
                add_to_canvas(output, grain, start_sample,
                              wrap=(canvas_policy == "wrap"))
                n_dry += 1
    stats.set("n_dry_events_included", n_dry)

    # ---------------- Stage 12: Original layer ----------------
    log_stage(12, "Add original layer")

    if orig_layer_amount > 0.0:
        original_start = int(round(canvas_time_offset * sr))
        add_to_canvas(output, orig_layer_amount * working, original_start,
                      wrap=(canvas_policy == "wrap"))

    if not np.all(np.isfinite(output)):
        raise EngineError("rendered output contains non-finite samples")

    # ---------------- Stage 13: Global output level ----------------
    log_stage(13, "Apply global output level policy")

    out_rms_pre = float(np.sqrt(np.mean(output.astype(np.float64) ** 2)) + 1e-12)
    out_peak_pre = float(np.max(np.abs(output))) if output.size else 0.0

    if identity_shortcut:
        # Preserve true bypass semantics. Global normalization is part of the
        # effect chain and would otherwise change an unchanged source.
        pass
    elif args.normalize == "peak":
        target_peak = db_to_lin(-1.0)
        if out_peak_pre > 1e-9:
            output = output * (target_peak / out_peak_pre)
    elif args.normalize == "rms":
        if out_rms_pre > 1e-9 and input_rms > 1e-9:
            output = output * (input_rms / out_rms_pre)
        peak_now = float(np.max(np.abs(output))) if output.size else 0.0
        ceiling = db_to_lin(-1.0)
        if peak_now > ceiling and peak_now > 1e-9:
            output = output * (ceiling / peak_now)
    else:
        peak_now = float(np.max(np.abs(output))) if output.size else 0.0
        if peak_now > 1.0 and peak_now > 1e-9:
            output = output * (0.999 / peak_now)

    if not np.all(np.isfinite(output)):
        raise EngineError("final output contains non-finite samples")

    output_rms = float(np.sqrt(np.mean(output.astype(np.float64) ** 2)))
    output_peak = float(np.max(np.abs(output))) if output.size else 0.0

    # ---------------- Stage 14: Write output and statistics ----------------
    log_stage(14, "Write output and statistics")

    # Float WAV avoids an unnecessary PCM16 quantization pass and preserves
    # true bypass / low-level event tails.
    sf.write(args.output_wav, output, sr, subtype="FLOAT")

    heard_inst_t = inst_t_resolved.copy()
    if canvas_policy == "wrap" and duration > 0:
        heard_inst_t = np.mod(heard_inst_t, duration)
    final_event_times = new_t.copy()
    for k in range(n_inst):
        if gens[k] == 0:
            final_event_times[src_idx[k]] = heard_inst_t[k]

    field_disp = np.abs(new_t - starts)
    final_disp = np.abs(final_event_times - starts)
    movement_threshold = max(0.010, min(0.050, duration * 0.0025))
    moved_fraction = float(np.mean(final_disp >= movement_threshold)) if n_events else 0.0
    max_pitch_abs = float(np.max(np.abs(inst_pitch))) if n_inst else 0.0
    max_desc_gain_abs = (float(np.max(np.abs(inst_descriptor_gain_db)))
                         if n_inst else 0.0)
    if (not identity_shortcut and moved_fraction < 0.10
            and max_pitch_abs < 0.25 and max_desc_gain_abs < 0.50
            and int(np.sum(gens > 0)) == 0):
        warnings.append(
            "the selected field produced little audible movement; increase "
            "Motion amount or use Fixed grain segmentation")

    stats.set("status", "ok")
    stats.set("field_type", field_type)
    stats.set("direction", plan["direction"] if field_type in ("vortex", "shear") else "not_applicable")
    stats.set("flow_strength", f"{strength:.4f}")
    stats.set("viscosity", f"{viscosity:.4f}")
    stats.set("integration_amount", f"{integration_amount:.4f}")
    stats.set("flow_steps", flow_steps)
    stats.set("center_time_sec", f"{t0:.6f}")
    stats.set("time_radius_sec", f"{Rt:.6f}")
    stats.set("descriptor_min", f"{d_min:.8f}")
    stats.set("descriptor_max", f"{d_max:.8f}")
    stats.set("descriptor_raw_min", f"{raw_d_min:.8f}")
    stats.set("descriptor_raw_max", f"{raw_d_max:.8f}")
    stats.set("descriptor_centre", f"{centre_value:.8f}")
    stats.set("descriptor_radius", f"{radius_value:.8f}")
    stats.set("vertical_axis", args.vertical_axis)
    stats.set("vertical_axis_unit", axis_unit)

    stats.set("canvas_policy", canvas_policy)
    stats.set("duration_policy", canvas_policy)  # legacy reader compatibility
    stats.set("duration_response", f"{duration_response:.4f}")
    stats.set("vertical_response_mode", vertical_response_mode)
    stats.set("preserve_pitch", int(vertical_response_mode != "pitch"))
    stats.set("vertical_response", f"{vertical_response:.4f}")
    stats.set("pitch_response", f"{vertical_response:.4f}")  # legacy key
    stats.set("pre_onset_sec", f"{pre_onset:.4f}")
    stats.set("post_tail_sec", f"{post_tail:.4f}")
    stats.set("collision_policy", collision_policy)
    stats.set("min_spacing_sec", f"{min_spacing:.4f}")
    stats.set("event_overlap", f"{event_overlap:.4f}")
    stats.set("boundary", boundary)
    stats.set("preserve_order", int(preserve_order))
    stats.set("duplication_probability", f"{dup_prob:.4f}")
    stats.set("duplication_count", dup_count)
    stats.set("density_gain_compensation", f"{density_comp:.4f}")
    stats.set("dry_event_inclusion", f"{dry_inclusion:.4f}")
    stats.set("original_layer_amount", f"{orig_layer_amount:.4f}")
    stats.set("quality", quality)
    stats.set("normalize_mode", args.normalize)
    stats.set("requested_seed", int(args.seed))
    stats.set("effective_seed", effective_seed)
    stats.set("identity_shortcut", int(identity_shortcut))
    stats.set("canvas_time_offset_sec", f"{canvas_time_offset:.6f}")

    stats.set("sample_rate", sr)
    stats.set("n_channels_input", n_channels)
    stats.set("n_channels_output", n_channels)
    stats.set("input_duration", f"{duration:.6f}")
    stats.set("output_duration", f"{output.shape[0] / sr:.6f}")
    stats.set("input_rms", f"{input_rms:.6f}")
    stats.set("output_rms", f"{output_rms:.6f}")
    stats.set("input_peak", f"{input_peak:.6f}")
    stats.set("output_peak", f"{output_peak:.6f}")
    stats.set("n_events_rendered", n_inst)
    stats.set("n_duplicates", int(np.sum(gens > 0)))
    stats.set("movement_threshold_sec", f"{movement_threshold:.4f}")
    stats.set("moved_event_fraction", f"{moved_fraction:.4f}")
    stats.set("mean_field_time_displacement_sec", f"{float(np.mean(field_disp)):.4f}")
    stats.set("max_field_time_displacement_sec", f"{float(np.max(field_disp)):.4f}")
    stats.set("mean_final_time_displacement_sec", f"{float(np.mean(final_disp)):.4f}")
    stats.set("max_final_time_displacement_sec", f"{float(np.max(final_disp)):.4f}")
    stats.set("mean_time_displacement_sec", f"{float(np.mean(final_disp)):.4f}")
    stats.set("max_time_displacement_sec", f"{float(np.max(final_disp)):.4f}")
    stats.set("mean_pitch_shift_semitones", f"{float(np.mean(np.abs(inst_pitch))):.4f}")
    stats.set("max_pitch_shift_semitones", f"{float(np.max(np.abs(inst_pitch))) if n_inst else 0.0:.4f}")
    stats.set("mean_descriptor_gain_db", f"{float(np.mean(np.abs(inst_descriptor_gain_db))):.4f}")
    stats.set("max_descriptor_gain_db", f"{float(np.max(np.abs(inst_descriptor_gain_db))) if n_inst else 0.0:.4f}")
    stats.set("mean_final_gain_db", f"{float(np.mean(inst_gain_db)):.4f}")
    stats.set("min_final_gain_db", f"{float(np.min(inst_gain_db)):.4f}")
    stats.set("max_final_gain_db", f"{float(np.max(inst_gain_db)):.4f}")
    effective_time_scale = inst_duration / np.maximum(durations0[src_idx], 1.0 / sr)
    stats.set("mean_time_scale", f"{float(np.mean(effective_time_scale)):.4f}")
    stats.set("min_time_scale", f"{float(np.min(effective_time_scale)):.4f}")
    stats.set("max_time_scale", f"{float(np.max(effective_time_scale)):.4f}")
    stats.set("jacobian_min", f"{float(np.min(det)):.4f}")
    stats.set("jacobian_max", f"{float(np.max(det)):.4f}")

    if warnings:
        stats.set("warning", ";".join(warnings))

    add_visualization_data(stats, starts, descriptor_for_field, new_t, final_event_times,
                            U0, V0, U1, V1, centre_value, radius_value, t0, Rt,
                            heard_inst_t, src_idx, gens, axis_unit,
                            field_type, direction_sign, strength, viscosity)

    stats.write(args.stats_txt)

    if args.cleanup:
        cleanup_temp_files(args)

    elapsed = time.time() - t_wall_start
    print(f"Done in {elapsed:.2f}s. status=ok, events={n_events}, instances={n_inst}", flush=True)
    return 0


def add_visualization_data(stats, starts, raw_descriptor, new_t, final_event_times,
                            U0, V0, U1, V1, centre_value, radius_value, t0, Rt,
                            inst_t_resolved, src_idx, gens, axis_unit,
                            field_type, direction_sign, strength, viscosity):
    n_events = len(starts)
    idxs = np.linspace(0, n_events - 1, min(MAX_VIZ_EVENTS, n_events)).astype(int)
    idxs = sorted(set(idxs.tolist()))

    stats.set("n_event_vectors", len(idxs))
    for j, i in enumerate(idxs):
        # display descriptor back in native units for plotting
        if axis_unit == "hz_log2":
            desc_before = 2.0 ** raw_descriptor[i]
            desc_after = 2.0 ** (centre_value + V1[i] * radius_value)
        else:
            desc_before = raw_descriptor[i]
            desc_after = centre_value + V1[i] * radius_value
        # orig time, descriptor before, field time, final rendered time,
        # descriptor after. Praat can show both the analytic field motion and
        # the audible post-collision placement.
        stats.set(
            f"vec_{j}",
            f"{starts[i]:.4f},{desc_before:.4f},{new_t[i]:.4f},"
            f"{final_event_times[i]:.4f},{desc_after:.4f}")

    # field arrow grid, same idea as fluid_vector_fields.py: sample the
    # velocity field directly on a coarse grid for the map background.
    nx, ny = 12, 9
    us = np.linspace(-2.5, 2.5, nx)
    vs = np.linspace(-2.5, 2.5, ny)
    UU, VV = np.meshgrid(us, vs, indexing="ij")
    DU, DV = field_velocity(UU, VV, field_type, direction_sign, strength, viscosity)
    stats.set("n_field_arrows", nx * ny)
    stats.set("field_grid_nx", nx)
    stats.set("field_grid_ny", ny)
    k = 0
    for a in range(nx):
        for bidx in range(ny):
            stats.set(f"arrowgrid_{k}",
                      f"{UU[a,bidx]:.3f},{VV[a,bidx]:.3f},{DU[a,bidx]:.4f},{DV[a,bidx]:.4f}")
            k += 1

    # instance placement summary (post-collision), downsampled
    n_inst = len(inst_t_resolved)
    idxs2 = np.linspace(0, n_inst - 1, min(MAX_VIZ_EVENTS, n_inst)).astype(int) if n_inst else np.array([], dtype=int)
    idxs2 = sorted(set(idxs2.tolist()))
    stats.set("n_instances_plotted", len(idxs2))
    for j, k2 in enumerate(idxs2):
        stats.set(f"inst_{j}", f"{starts[src_idx[k2]]:.4f},{inst_t_resolved[k2]:.4f},{int(gens[k2])}")


def cleanup_temp_files(args):
    for path in (args.input_wav, args.field_plan_csv):
        base = os.path.basename(path)
        if base.startswith("temp_fluidevt_") and os.path.isfile(path):
            try:
                os.remove(path)
            except OSError:
                pass


def write_failure_stats(path, stage, message):
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write("status=error\n")
            f.write(f"engine_version={ENGINE_VERSION}\n")
            f.write(f"stage={stage}\n")
            f.write(f"error_message={message}\n")
    except OSError:
        pass


def main():
    args = parse_args()
    try:
        return process(args)
    except EngineError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        write_failure_stats(args.stats_txt, "engine", str(e))
        if os.path.isfile(args.output_wav):
            try:
                os.remove(args.output_wav)
            except OSError:
                pass
        return 1
    except Exception as e:  # noqa: BLE001 -- top-level safety net
        print(f"UNEXPECTED ERROR: {e}", file=sys.stderr)
        traceback.print_exc()
        write_failure_stats(args.stats_txt, "unexpected", str(e))
        if os.path.isfile(args.output_wav):
            try:
                os.remove(args.output_wav)
            except OSError:
                pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
