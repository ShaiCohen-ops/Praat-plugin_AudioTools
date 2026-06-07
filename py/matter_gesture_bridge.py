#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - matter_gesture_bridge.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Matter Gesture Bridge — Stochastic Timbral Plastic
#   Python rendering engine. Called by MatterGestureBridge.praat.
#
#   Core technique:
#     1. Slice the Matter Sound into spectral patches (real STFT frames).
#     2. For each output frame, select the best-matching Matter patch
#        using gesture-driven target descriptors (intensity, brightness).
#     3. Apply stochastic modulation: intensity roughness, pitch noise
#        spectral warp, formant resonance injection, liminal freeze.
#     4. Griffin-Lim ISTFT → audio.
#     5. Apply gesture amplitude envelope in the time domain.
#
# Dependencies:
#   pip install numpy soundfile
#   Optional: pip install librosa, scipy (multithreaded FFT)
#
# Changelog v1.2:
#   - Vectorized the per-frame Python loops (the bottleneck) with identical
#     results, preserving exact RNG-stream consumption so output is reproducible:
#       * select_matter_frames : broadcast L1 distance + single argmin; jitter
#         drawn (n_frames, M) then transposed to keep the original draw order.
#       * apply_pitch_noise_schedule : one normal per active frame (same stream),
#         per-column circular shift done as a single gather.
#       * inject_formant_vectors : strided column updates vectorized.
#       * build_matter_library : batched STFT (sliding-window + one FFT).
#   - Griffin-Lim rewritten frame-major so every FFT runs on the contiguous
#     axis; overlap-add via R block-shifted adds; window normalization computed
#     once; optional scipy.fft (workers=-1) multithreads the batched FFTs.
#   - GL phasor projection (mag * S/|S|) replaces angle()->exp() per iteration
#     (the single largest cost). Differs from the original by <= 1 LSB at 16-bit;
#     set config "gl_phasor": 0 for byte-identical (slower) output.
# ============================================================

import argparse
import hashlib
import json
import os
import pickle
import sys

import numpy as np
import soundfile as sf

try:
    import librosa
    HAS_LIBROSA = True
except ImportError:
    HAS_LIBROSA = False

# Batched FFT helpers. scipy.fft can multithread across frames (workers=-1),
# which matters once everything is vectorized to operate on all frames at once;
# at float64 it is numerically identical to numpy.fft. Fall back to numpy.
try:
    import scipy.fft as _spfft
    def _rfft(x, axis=-1):
        return _spfft.rfft(x, axis=axis, workers=-1)
    def _irfft(x, n, axis=-1):
        return _spfft.irfft(x, n=n, axis=axis, workers=-1)
except ImportError:
    def _rfft(x, axis=-1):
        return np.fft.rfft(x, axis=axis)
    def _irfft(x, n, axis=-1):
        return np.fft.irfft(x, n=n, axis=axis)


# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

def check_dependencies() -> None:
    missing = []
    for pkg in ["numpy", "soundfile"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print(f"ERROR: Missing required packages: {', '.join(missing)}", flush=True)
        print("Install: pip install numpy soundfile", flush=True)
        sys.exit(1)
    if not HAS_LIBROSA:
        print("INFO: librosa not found - using built-in resampler.", flush=True)


# =============================================================================
# DONE / LOGGING
# =============================================================================

def write_done(done_file: str, status: str = "ok") -> None:
    try:
        with open(done_file, "w", encoding="utf-8") as f:
            f.write(status + "\n")
    except Exception:
        pass


def log(msg: str, log_file: str = "") -> None:
    print(msg, flush=True)
    if log_file:
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(msg + "\n")
        except Exception:
            pass


# =============================================================================
# AUDIO I/O
# =============================================================================

def _resample(audio: np.ndarray, sr_in: int, sr_out: int) -> np.ndarray:
    if sr_in == sr_out:
        return audio
    if HAS_LIBROSA:
        return librosa.resample(audio.astype(np.float32), orig_sr=sr_in, target_sr=sr_out)
    ratio   = sr_out / sr_in
    new_len = max(1, int(len(audio) * ratio))
    idx     = np.linspace(0, len(audio) - 1, new_len)
    idx_lo  = np.clip(idx.astype(int), 0, len(audio) - 1)
    idx_hi  = np.clip(idx_lo + 1,      0, len(audio) - 1)
    frac    = (idx - idx_lo).astype(np.float32)
    return (audio[idx_lo] * (1.0 - frac) + audio[idx_hi] * frac).astype(np.float32)


def load_audio(path: str, target_sr: int) -> tuple:
    """Load audio → (mono float32, sr)."""
    audio, sr = sf.read(path, always_2d=True)
    mono = audio.mean(axis=1).astype(np.float32)
    mono = _resample(mono, sr, target_sr)
    return mono, target_sr


def load_matter_file(path: str, target_sr: int, train_limit_sec: float,
                     log_file: str = "") -> np.ndarray:
    log(f"  Loading Matter Sound: {os.path.basename(path)}", log_file)
    audio, _ = load_audio(path, target_sr)
    limit     = int(train_limit_sec * target_sr)
    if len(audio) > limit:
        audio = audio[:limit]
        log(f"  Truncated to {train_limit_sec:.0f}s", log_file)
    log(f"  Matter: {len(audio)/target_sr:.2f}s @ {target_sr}Hz", log_file)
    return audio


def load_gesture_file(path: str, target_sr: int, log_file: str = "") -> np.ndarray:
    log(f"  Loading Gesture Sound: {os.path.basename(path)}", log_file)
    audio, _ = load_audio(path, target_sr)
    log(f"  Gesture: {len(audio)/target_sr:.2f}s @ {target_sr}Hz", log_file)
    return audio


# =============================================================================
# DESCRIPTOR LOADING
# =============================================================================

def _read_tsv_column(path: str, col: int) -> np.ndarray:
    values = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        for line in lines[1:]:          # skip header
            parts = line.strip().split("\t")
            if col < len(parts):
                try:
                    values.append(float(parts[col]))
                except ValueError:
                    pass
    except Exception:
        pass
    return np.array(values, dtype=np.float32) if values else np.array([0.0], dtype=np.float32)


def extract_internal_gesture_controls(cfg: dict, gesture: np.ndarray,
                                      target_sr: int, log_file: str = "") -> dict:
    intensity_path = cfg.get("intensity_txt", "")
    pitch_path     = cfg.get("pitch_txt", "")
    formant_path   = cfg.get("formant_txt", "")

    # Intensity
    if intensity_path and os.path.isfile(intensity_path):
        intensity_db = _read_tsv_column(intensity_path, col=1)
    else:
        hop = max(1, target_sr // 100)
        n   = max(1, len(gesture) // hop)
        frames = gesture[:n * hop].reshape(n, hop)
        rms    = np.sqrt(np.mean(frames ** 2, axis=1) + 1e-12)
        intensity_db = 20.0 * np.log10(rms + 1e-12)

    # Pitch
    if pitch_path and os.path.isfile(pitch_path):
        pitch_hz = _read_tsv_column(pitch_path, col=1)
    else:
        pitch_hz = np.zeros(len(intensity_db), dtype=np.float32)

    # Formants
    formants = {}
    defaults = {"f1": 500.0, "f2": 1500.0, "f3": 2500.0, "f4": 3500.0}
    if formant_path and os.path.isfile(formant_path):
        for fi, fname in enumerate(["f1", "f2", "f3", "f4"], start=1):
            col = _read_tsv_column(formant_path, col=fi)
            formants[fname] = col if len(col) > 1 else np.full(len(intensity_db), defaults[fname])
    else:
        n = len(intensity_db)
        for k, v in defaults.items():
            formants[k] = np.full(n, v, dtype=np.float32)

    log(f"  Gesture controls: intensity={len(intensity_db)} pts, "
        f"pitch={len(pitch_hz)} pts", log_file)

    return {
        "intensity_db": intensity_db,
        "pitch_hz":     pitch_hz,
        "formants":     formants,
        "brightness":   float(cfg.get("gesture_brightness", 2000.0)),
        "mean_pitch":   float(cfg.get("gesture_mean_pitch", 0.0)),
        "pitch_range":  float(cfg.get("gesture_pitch_range", 0.0)),
        "int_mean":     float(cfg.get("gesture_int_mean", 60.0)),
        "int_range":    float(cfg.get("gesture_int_range", 20.0)),
    }


def interpolate_controls(curve: np.ndarray, n_out: int) -> np.ndarray:
    if len(curve) == n_out:
        return curve.astype(np.float32)
    if len(curve) == 1:
        return np.full(n_out, curve[0], dtype=np.float32)
    x_in  = np.linspace(0.0, 1.0, len(curve))
    x_out = np.linspace(0.0, 1.0, n_out)
    return np.interp(x_out, x_in, curve).astype(np.float32)


# =============================================================================
# MATTER PATCH LIBRARY  (real STFT frames anchored to Matter amplitude)
# =============================================================================

N_FFT = 2048
HOP   = N_FFT // 4


def matter_hash(matter_path: str, train_limit_sec: float,
                patch_sec: float, target_sr: int) -> str:
    key = f"{matter_path}|{train_limit_sec}|{patch_sec}|{target_sr}"
    return hashlib.md5(key.encode()).hexdigest()[:16]


def build_matter_library(matter: np.ndarray, target_sr: int,
                         log_file: str = "") -> dict:
    """
    Compute the full STFT of the Matter Sound and derive per-frame
    descriptors (RMS, spectral centroid) for patch selection.
    Returns a dict with keys: mag (n_freq, n_frames), rms, centroid.
    """
    win    = np.hanning(N_FFT).astype(np.float32)
    n_freq = N_FFT // 2 + 1

    n_fr = (len(matter) - N_FFT) // HOP + 1
    if n_fr >= 1:
        # Batched STFT: one strided sliding-window view + a single FFT call,
        # replacing the per-frame Python loop. The complex64 cast matches the
        # original element-for-element.
        sw       = np.lib.stride_tricks.sliding_window_view(matter, N_FFT)[::HOP][:n_fr]
        spec     = np.fft.rfft(sw * win[None, :], n=N_FFT, axis=1).astype(np.complex64)
        # C-contiguous (n_freq, n_fr), matching the original np.stack layout so
        # the axis=0 reductions (rms, centroid) sum in the same order -> identical.
        mag_full = np.ascontiguousarray(np.abs(spec).T)    # (n_freq, n_fr)
    else:
        log("  WARNING: Matter too short for STFT - padding.", log_file)
        chunk    = np.pad(matter, (0, N_FFT - len(matter))) * win
        spec     = np.fft.rfft(chunk, n=N_FFT).astype(np.complex64)
        mag_full = np.abs(spec)[:, None]                   # (n_freq, 1)
    eps      = 1e-8
    freqs    = np.fft.rfftfreq(N_FFT, d=1.0 / target_sr).astype(np.float32)

    rms      = np.sqrt(np.mean(mag_full ** 2, axis=0)) + eps   # (n_frames,)
    spec_sum = mag_full.sum(axis=0) + eps
    centroid = (freqs[:, None] * mag_full).sum(axis=0) / spec_sum  # (n_frames,)

    log(f"  Matter library: {mag_full.shape[1]} frames, "
        f"RMS range [{rms.min():.4f}, {rms.max():.4f}]", log_file)

    return {
        "mag":      mag_full,       # (n_freq, n_frames)  linear magnitude
        "rms":      rms,            # (n_frames,)
        "centroid": centroid,       # (n_frames,)  Hz
        "freqs":    freqs,          # (n_freq,)
        "mean_rms": float(rms.mean()),
        "mean_cen": float(centroid.mean()),
    }


def load_or_build_library(matter: np.ndarray, cfg: dict,
                           cache_dir: str, log_file: str = "") -> dict:
    target_sr   = int(cfg.get("target_sr", 44100))
    patch_sec   = float(cfg.get("patch_sec", 1.5))
    reuse       = int(cfg.get("reuse_cache", 0))

    h          = matter_hash(cfg.get("matter_wav", ""),
                             float(cfg.get("train_limit_sec", 420)),
                             patch_sec, target_sr)
    cache_path = os.path.join(cache_dir, f"mgb_lib_{h}.pkl")

    if reuse and os.path.isfile(cache_path):
        log(f"  Loading cached library: {cache_path}", log_file)
        try:
            with open(cache_path, "rb") as f:
                lib = pickle.load(f)
            log("  Cached library loaded.", log_file)
            lib["cache_hit"] = True
            return lib
        except Exception as e:
            log(f"  Cache load failed ({e}), rebuilding.", log_file)

    lib = build_matter_library(matter, target_sr, log_file)
    lib["cache_hit"] = False

    try:
        os.makedirs(cache_dir, exist_ok=True)
        with open(cache_path, "wb") as f:
            pickle.dump(lib, f)
        log(f"  Library cached: {cache_path}", log_file)
    except Exception as e:
        log(f"  Could not cache library: {e}", log_file)

    return lib


# =============================================================================
# GESTURE CONDITIONING
# =============================================================================

def build_gesture_conditioning(controls: dict, n_frames: int, cfg: dict) -> dict:
    gesture_amount = float(cfg.get("gesture_amount", 0.65))

    int_db  = interpolate_controls(controls["intensity_db"], n_frames)
    pitch   = interpolate_controls(controls["pitch_hz"],     n_frames)
    f1      = interpolate_controls(controls["formants"]["f1"], n_frames)
    f2      = interpolate_controls(controls["formants"]["f2"], n_frames)
    f3      = interpolate_controls(controls["formants"]["f3"], n_frames)
    f4      = interpolate_controls(controls["formants"]["f4"], n_frames)

    # Normalise intensity to [0,1]
    i_min, i_max = int_db.min(), int_db.max()
    if i_max > i_min:
        int_norm = (int_db - i_min) / (i_max - i_min)
    else:
        int_norm = np.full(n_frames, 0.5, dtype=np.float32)

    int_norm = np.clip(0.5 + (int_norm - 0.5) * gesture_amount, 0.0, 1.0)

    # Amplitude envelope from intensity dB (linear scale, smoothed)
    amp_env = 10.0 ** ((int_db - int_db.max()) / 20.0)
    amp_env = np.clip(amp_env, 0.02, 1.0).astype(np.float32)

    return {
        "intensity_norm": int_norm,
        "amp_env":        amp_env,
        "pitch_hz":       pitch,
        "f1": f1, "f2": f2, "f3": f3, "f4": f4,
    }


# =============================================================================
# PATCH SELECTION  (gesture-driven frame matching in the Matter library)
# =============================================================================

def select_matter_frames(lib: dict, cond: dict, cfg: dict,
                          n_frames: int, rng: np.random.Generator,
                          log_file: str = "") -> np.ndarray:
    """
    For each output frame select the best-matching Matter STFT frame
    based on the gesture's intensity (→ RMS target) and brightness
    (→ centroid target).  A small stochastic jitter avoids repetition.

    Returns selected_mag: (n_freq, n_frames) linear magnitude.
    """
    chaos        = float(cfg.get("chaos", 0.50))
    gesture_amt  = float(cfg.get("gesture_amount", 0.65))

    matter_rms = lib["rms"]         # (M,)
    matter_cen = lib["centroid"]    # (M,)
    matter_mag = lib["mag"]         # (n_freq, M)
    M          = matter_mag.shape[1]

    int_norm   = cond["intensity_norm"]  # (n_frames,) in [0,1]
    pitch_hz   = cond["pitch_hz"]        # (n_frames,)

    # Map gesture intensity [0,1] → target RMS in Matter's range
    rms_min, rms_max = matter_rms.min(), matter_rms.max()
    target_rms = rms_min + int_norm * (rms_max - rms_min)

    # Map gesture pitch (where voiced) → centroid target
    cen_min, cen_max = matter_cen.min(), matter_cen.max()
    voiced    = pitch_hz > 50.0
    # Normalize pitch within its own range
    p_min, p_max = float(pitch_hz.max()), float(pitch_hz.min())
    if p_max > p_min:
        pitch_norm = np.clip((pitch_hz - p_min) / (p_max - p_min + 1e-8), 0.0, 1.0)
    else:
        pitch_norm = np.full(n_frames, 0.5, dtype=np.float32)

    target_cen = np.where(voiced,
                          cen_min + pitch_norm * (cen_max - cen_min),
                          np.full(n_frames, lib["mean_cen"])).astype(np.float32)

    # Normalise cost components
    rms_range = rms_max - rms_min + 1e-8
    cen_range = cen_max - cen_min + 1e-8
    norm_rms  = (matter_rms - rms_min) / rms_range   # (M,)
    norm_cen  = (matter_cen - cen_min) / cen_range   # (M,)

    # Vectorized over all output frames at once.
    tr = (target_rms - rms_min) / rms_range          # (n_frames,)
    tc = (target_cen - cen_min) / cen_range          # (n_frames,)

    w_rms = gesture_amt
    w_cen = gesture_amt * 0.5

    # Weighted L1 distance for every (Matter frame m, output frame t): (M, n_frames)
    dist = (w_rms * np.abs(norm_rms[:, None] - tr[None, :])
            + w_cen * np.abs(norm_cen[:, None] - tc[None, :])).astype(np.float32)

    # Stochastic jitter. Drawn as (n_frames, M) then transposed so the random
    # stream is consumed in the exact same order as the original per-frame loop
    # (frame 0's M draws, then frame 1's, ...), keeping output reproducible.
    jitter = rng.uniform(0.0, chaos * 0.3, size=(n_frames, M)).astype(np.float32).T
    dist += jitter

    best = np.argmin(dist, axis=0)                   # (n_frames,)
    selected = matter_mag[:, best].astype(np.float32)

    log(f"  Frame selection complete: {n_frames} frames from {M} Matter frames", log_file)
    return selected


# =============================================================================
# MODULATION PASSES  (all in linear magnitude space)
# =============================================================================

def _smooth(x: np.ndarray, w: int = 5) -> np.ndarray:
    if len(x) <= w or w < 2:
        return x
    kernel = np.ones(w, dtype=np.float32) / w
    return np.convolve(x, kernel, mode="same")


def apply_intensity_roughness(mag: np.ndarray, cond: dict, cfg: dict,
                               rng: np.random.Generator) -> np.ndarray:
    """
    High gesture intensity → rougher (multiplicative spectral noise).
    Low intensity → smoother / crystallized.
    Operates in linear magnitude space.
    """
    roughness  = float(cfg.get("intensity_roughness", 0.75))
    int_norm   = interpolate_controls(cond["intensity_norm"], mag.shape[1])

    # Multiplicative noise: scale factor drawn from log-normal
    noise_std  = roughness * int_norm * 0.4            # per-frame noise strength
    noise      = np.exp(rng.standard_normal(mag.shape).astype(np.float32)
                        * noise_std[None, :])           # (n_freq, n_frames)
    return mag * noise


def apply_pitch_noise_schedule(mag: np.ndarray, cond: dict, cfg: dict,
                                target_sr: int,
                                rng: np.random.Generator) -> np.ndarray:
    """
    Pitch change rate → spectral bin shift (timbral fracture).
    """
    pitch_noise = float(cfg.get("pitch_noise", 0.55))
    pitch_hz    = interpolate_controls(cond["pitch_hz"], mag.shape[1])
    n_freq      = mag.shape[0]

    diff  = np.diff(pitch_hz, prepend=pitch_hz[0])
    vel   = _smooth(np.abs(diff) / (np.abs(pitch_hz).mean() + 1e-6), w=5)
    vel   = np.clip(vel * pitch_noise, 0.0, 1.0)

    # Vectorized. Draw exactly one normal per active frame, in frame order, so
    # the random stream is consumed identically to the original loop (this keeps
    # every downstream RNG-dependent pass reproducible).
    n_frames = mag.shape[1]
    active   = vel >= 0.01
    n_active = int(active.sum())
    shifts   = np.zeros(n_frames, dtype=np.int64)
    if n_active > 0:
        draws = rng.standard_normal(n_active)
        shifts[active] = np.round(draws * vel[active] * n_freq * 0.04).astype(np.int64)

    # Per-column circular shift as one gather:
    # np.roll(col, s)[i] == col[(i - s) % n_freq]
    rows = (np.arange(n_freq)[:, None] - shifts[None, :]) % n_freq
    mag  = mag[rows, np.arange(n_frames)[None, :]]
    return mag


def inject_formant_vectors(mag: np.ndarray, cond: dict, cfg: dict,
                            target_sr: int) -> np.ndarray:
    """
    Boost energy at F1-F4 positions using Gaussian resonance shapes.
    """
    formant_inj = float(cfg.get("formant_injection", 0.45))
    if formant_inj < 1e-4:
        return mag

    n_freq, n_frames = mag.shape
    freqs = np.fft.rfftfreq(N_FFT, d=1.0 / target_sr).astype(np.float32)
    bws   = {"f1": 120.0, "f2": 200.0, "f3": 300.0, "f4": 400.0}

    step = max(1, n_frames // 200)
    cols = np.arange(0, n_frames, step)                   # strided columns to update
    for fname, bw in bws.items():
        # col_mean recomputed per formant so later formants see earlier
        # injections, matching the original outer-formant / inner-frame ordering.
        col_mean = mag[:, cols].mean(axis=0)              # (n_cols,)
        f_curve  = interpolate_controls(cond[fname], n_frames)[cols]   # (n_cols,)
        valid    = f_curve >= 50.0
        boost    = np.exp(-0.5 * ((freqs[:, None] - f_curve[None, :]) / bw) ** 2).astype(np.float32)
        boost   *= valid[None, :]                         # zero columns with f_hz < 50
        mag[:, cols] += formant_inj * boost * col_mean[None, :]

    return mag


def apply_liminal_freeze(mag: np.ndarray, lib: dict, cfg: dict,
                          rng: np.random.Generator) -> np.ndarray:
    """
    freeze_t=0.0  → crystallized  (blend toward Matter mean spectrum)
    freeze_t=0.55 → liminal cloud (partial blend + spectral smear)
    freeze_t=0.95 → ghost matter  (high noise, barely structured)
    """
    freeze_t = float(cfg.get("freeze_t", 0.45))
    chaos    = float(cfg.get("chaos",    0.50))

    mean_spec = lib["mag"].mean(axis=1)                       # (n_freq,)
    crystal   = np.tile(mean_spec[:, None], (1, mag.shape[1])).astype(np.float32)

    if freeze_t < 0.05:
        return crystal * 0.9 + mag * 0.1

    # Ghost noise: log-normal multiplicative
    ghost_noise = np.exp(rng.standard_normal(mag.shape).astype(np.float32)
                         * freeze_t * chaos * 0.8)

    w = freeze_t
    out = crystal * (1.0 - w) + mag * ghost_noise * w
    return np.clip(out, 0.0, None)


# =============================================================================
# AMPLITUDE ENVELOPE  (applied in time domain after ISTFT)
# =============================================================================

def apply_amplitude_envelope(audio: np.ndarray, cond: dict,
                              cfg: dict, target_sr: int) -> np.ndarray:
    """
    Impose the gesture's amplitude envelope on the rendered audio.
    This is what makes it sound like the Matter is being animated
    by the Gesture — silence where the gesture is silent, loud where loud.

    Gate: the raw amp_env (before the gesture_amount blend) is used as a
    hard gate so that truly silent passages in the gesture produce silence
    in the output.  Without this, the blend floor (1 - gesture_amount) keeps
    a residual signal alive even when the gesture is completely quiet.
    """
    gesture_amt = float(cfg.get("gesture_amount", 0.65))
    gate_thresh = float(cfg.get("gate_threshold", 0.02))   # matches amp_env clip floor
    amp_env     = interpolate_controls(cond["amp_env"], len(audio))
    amp_env     = _smooth(amp_env, w=max(3, target_sr // 200))

    # Hard gate: zero out samples where the gesture envelope is at or below
    # the clip floor (amp_env ≤ gate_threshold means the gesture is silent).
    gate = (amp_env > gate_thresh).astype(np.float32)
    # Short fade on gate edges (5 ms) to avoid clicks at open/close transitions.
    fade_smp = max(2, int(target_sr * 0.005))
    fade     = np.hanning(fade_smp * 2).astype(np.float32)
    # Convolve gate with a small smoothing kernel to round the edges.
    gate = np.convolve(gate, fade / fade.sum(), mode="same")
    gate = np.clip(gate, 0.0, 1.0)

    # Blend: full gesture envelope × gesture_amount + unity × (1 - gesture_amount)
    env = amp_env * gesture_amt + (1.0 - gesture_amt)
    return (audio * env * gate).astype(np.float32)


# =============================================================================
# GRIFFIN-LIM ISTFT
# =============================================================================

def griffin_lim(mag: np.ndarray, n_iter: int, seed: int,
                log_file: str = "", use_phasor: bool = True) -> np.ndarray:
    """
    Phase reconstruction from linear magnitude spectrogram.
    mag: (n_freq, n_frames) — must be in LINEAR amplitude (not log).
    Returns time-domain float32 audio.
    """
    n_freq, n_frames = mag.shape
    win     = np.hanning(N_FFT).astype(np.float64)
    out_len = (n_frames - 1) * HOP + N_FFT

    rng   = np.random.default_rng(seed + 99)
    # Random phase, drawn in the original (n_freq, n_frames) order for identical
    # results, then stored FRAME-MAJOR so every FFT runs along the contiguous
    # last axis (numpy's FFT is far faster contiguous than strided).
    phase = np.ascontiguousarray(
        rng.uniform(-np.pi, np.pi, (n_freq, n_frames)).T)      # (n_frames, n_freq)
    mag_t = np.ascontiguousarray(mag.astype(np.float64).T)     # (n_frames, n_freq)

    log(f"  Griffin-Lim ISTFT ({n_iter} iters, {n_frames} frames)...", log_file)

    # Overlap-add by block decomposition. Because HOP divides N_FFT exactly
    # (R = N_FFT // HOP), each frame splits into R blocks of HOP samples and
    # output block p receives block b of frame (p - b). The OLA is then R
    # block-shifted adds (R = 4 here, independent of frame count) - far faster
    # than a per-frame Python loop and with no large scatter. The window-power
    # normalization is precomputed ONCE (the original recomputed it each iter).
    R        = N_FFT // HOP
    n_blocks = n_frames + R - 1                                # out_len == n_blocks * HOP
    winsq_b  = (win ** 2).reshape(R, HOP)
    w_blocks = np.zeros((n_blocks, HOP), dtype=np.float64)
    for b in range(R):
        w_blocks[b: b + n_frames] += winsq_b[b][None, :]
    w_norm   = w_blocks.reshape(-1)[:out_len]
    w_norm   = np.where(w_norm > 1e-10, w_norm, 1.0)

    def _istft(stft):
        # stft: (n_frames, n_freq). Batched inverse FFT along the contiguous
        # last axis, windowed, then overlap-added via R block-shifted adds.
        td   = _irfft(stft, n=N_FFT, axis=1) * win[None, :]    # (n_frames, N_FFT)
        td_b = td.reshape(n_frames, R, HOP)
        y_blocks = np.zeros((n_blocks, HOP), dtype=np.float64)
        for b in range(R):
            y_blocks[b: b + n_frames] += td_b[:, b, :]
        return y_blocks.reshape(-1)[:out_len] / w_norm

    # Carry the unit-magnitude complex spectrum (phasor) instead of recomputing
    # angle() -> exp(1j*phase) every iteration. mag * S/|S| is the standard
    # Griffin-Lim magnitude projection and avoids two transcendental passes over
    # the whole spectrogram each iter (the dominant cost at scale).
    phasor = np.exp(1j * phase)                               # (n_frames, n_freq)

    for it in range(n_iter):
        stft  = mag_t * phasor                                # (n_frames, n_freq)
        y_ola = _istft(stft)
        # Re-STFT: one window per hop (strided sliding view), batched FFT.
        frames = np.lib.stride_tricks.sliding_window_view(y_ola, N_FFT)[::HOP]  # (n_frames, N_FFT)
        spec   = _rfft(frames * win[None, :], axis=1)          # (n_frames, n_freq)
        if use_phasor:
            phasor = spec / (np.abs(spec) + 1e-12)            # fast magnitude projection
        else:
            phasor = np.exp(1j * np.angle(spec))              # byte-identical to original

    stft_final = mag_t * phasor
    audio = _istft(stft_final).astype(np.float32)

    # Boundary fade: the first and last N_FFT samples of the OLA output sit
    # in a region where w_norm is effectively 0 (only one Hann window
    # contributes there), so the clamped normalisation leaves them at raw
    # un-averaged amplitude — audible as a click at the very start and end
    # even when the interior is correctly synthesised.  A Hann fade over the
    # first/last N_FFT samples masks this completely without touching any
    # other part of the signal.
    fade_len = min(N_FFT, len(audio) // 2)
    if len(audio) > 2 * fade_len:
        fade = np.hanning(2 * fade_len).astype(np.float32)
        audio[:fade_len]  *= fade[:fade_len]
        audio[-fade_len:] *= fade[fade_len:]

    return audio


# =============================================================================
# NORMALIZATION
# =============================================================================

def safe_normalize(audio: np.ndarray, target_peak: float = 0.92) -> np.ndarray:
    peak = np.max(np.abs(audio))
    if peak > 1e-8:
        audio = audio * (target_peak / peak)
    return audio.astype(np.float32)


# =============================================================================
# MAIN
# =============================================================================

def main() -> None:
    check_dependencies()

    ap = argparse.ArgumentParser(description="Matter Gesture Bridge v1.2")
    ap.add_argument("config_json", type=str)
    args = ap.parse_args()

    if not os.path.isfile(args.config_json):
        print(f"ERROR: Config JSON not found: {args.config_json}", flush=True)
        sys.exit(1)

    with open(args.config_json, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    matter_wav  = cfg.get("matter_wav", "")
    gesture_wav = cfg.get("gesture_wav", "")
    result_wav  = cfg.get("result_wav", "")
    log_file    = cfg.get("log_file", "")
    done_file   = cfg.get("done_file", "")
    stats_file  = cfg.get("stats_file", "")
    target_sr   = int(cfg.get("target_sr", 44100))
    seed        = int(cfg.get("seed", 1234))

    if log_file:
        try:
            open(log_file, "w").close()
        except Exception:
            pass

    log("=== Matter Gesture Bridge v1.2 ===", log_file)
    log(f"Matter:  {os.path.basename(matter_wav)}", log_file)
    log(f"Gesture: {os.path.basename(gesture_wav)}", log_file)
    log(f"freeze_t={cfg.get('freeze_t',0.45)}  chaos={cfg.get('chaos',0.50)}  "
        f"gesture_amount={cfg.get('gesture_amount',0.65)}", log_file)

    np.random.seed(seed)
    rng = np.random.default_rng(seed)

    # Validate
    for label, path in [("Matter", matter_wav), ("Gesture", gesture_wav)]:
        if not path or not os.path.isfile(path):
            log(f"ERROR: {label} file not found: {path}", log_file)
            write_done(done_file, "error"); sys.exit(1)

    # [1] Load audio
    log("[1/7] Loading audio...", log_file)
    try:
        matter  = load_matter_file(matter_wav,  target_sr,
                                   float(cfg.get("train_limit_sec", 420)), log_file)
        gesture = load_gesture_file(gesture_wav, target_sr, log_file)
    except Exception as e:
        log(f"ERROR loading audio: {e}", log_file)
        write_done(done_file, "error"); sys.exit(1)

    # [2] Extract gesture controls
    log("[2/7] Extracting gesture controls...", log_file)
    controls = extract_internal_gesture_controls(cfg, gesture, target_sr, log_file)

    # [3] Build / load Matter library
    log("[3/7] Building Matter library...", log_file)
    cache_dir = os.path.dirname(log_file) if log_file else os.path.dirname(result_wav)
    lib = load_or_build_library(matter, cfg, cache_dir, log_file)

    # [4] Determine output frame count from gesture duration
    gesture_samples = len(gesture)
    n_frames = max(4, (gesture_samples - N_FFT) // HOP + 1)
    log(f"  Output: {n_frames} frames -> {gesture_samples/target_sr:.3f}s", log_file)

    # [5] Build gesture conditioning
    cond = build_gesture_conditioning(controls, n_frames, cfg)

    # [6] Select Matter frames driven by gesture
    log("[5/7] Gesture-driven patch selection...", log_file)
    mag = select_matter_frames(lib, cond, cfg, n_frames, rng, log_file)

    # [7] Modulation passes (all in linear magnitude space)
    log("[6/7] Applying modulation...", log_file)
    mag = apply_intensity_roughness(mag,    cond, cfg, rng)
    mag = apply_pitch_noise_schedule(mag,   cond, cfg, target_sr, rng)
    mag = inject_formant_vectors(mag,       cond, cfg, target_sr)
    mag = apply_liminal_freeze(mag,         lib,  cfg, rng)
    mag = np.clip(mag, 0.0, None)          # ensure non-negative magnitude

    # [8] ISTFT → audio
    log("[7/7] Rendering...", log_file)
    try:
        n_iter_gl  = int(cfg.get("diffusion_steps", 64))
        use_phasor = bool(int(cfg.get("gl_phasor", 1)))
        audio = griffin_lim(mag, n_iter=n_iter_gl, seed=seed,
                            log_file=log_file, use_phasor=use_phasor)
    except Exception as e:
        log(f"ERROR during Griffin-Lim: {e}", log_file)
        write_done(done_file, "error"); sys.exit(1)

    # Trim / pad to gesture duration
    if len(audio) > gesture_samples:
        audio = audio[:gesture_samples]
    elif len(audio) < gesture_samples:
        audio = np.pad(audio, (0, gesture_samples - len(audio)))

    # Apply gesture amplitude envelope
    audio = apply_amplitude_envelope(audio, cond, cfg, target_sr)

    # Normalize
    audio = safe_normalize(audio, target_peak=0.92)

    log(f"  Peak: {np.max(np.abs(audio)):.4f}  RMS: {np.sqrt(np.mean(audio**2)):.4f}", log_file)

    # Write result
    try:
        sf.write(result_wav, audio, target_sr, subtype="PCM_16")
        log(f"  Written: {result_wav}  ({len(audio)/target_sr:.3f}s)", log_file)
    except Exception as e:
        log(f"ERROR writing result WAV: {e}", log_file)
        write_done(done_file, "error"); sys.exit(1)

    # Write stats file for Praat visualization
    if stats_file:
        try:
            peak_val   = float(np.max(np.abs(audio)))
            rms_val    = float(np.sqrt(np.mean(audio**2)))
            cache_hit  = lib.get("cache_hit", False)
            int_ctrl   = controls.get("intensity_db", np.array([60.0]))
            pitch_ctrl = controls.get("pitch_hz",     np.array([0.0]))
            with open(stats_file, "w", encoding="utf-8") as sf_out:
                sf_out.write(f"gesture_dur={len(gesture)/target_sr:.4f}\n")
                sf_out.write(f"result_dur={len(audio)/target_sr:.4f}\n")
                sf_out.write(f"n_frames={n_frames}\n")
                sf_out.write(f"peak={peak_val:.4f}\n")
                sf_out.write(f"rms_out={rms_val:.4f}\n")
                sf_out.write(f"freeze_t={cfg.get('freeze_t', 0.45):.4f}\n")
                sf_out.write(f"chaos={cfg.get('chaos', 0.50):.4f}\n")
                sf_out.write(f"gesture_amount={cfg.get('gesture_amount', 0.65):.4f}\n")
                sf_out.write(f"seed={seed}\n")
                sf_out.write(f"gl_iters={n_iter_gl}\n")
                sf_out.write(f"matter_file={os.path.basename(matter_wav)}\n")
                sf_out.write(f"cache_hit={'yes' if cache_hit else 'no'}\n")
                sf_out.write(f"int_mean={float(int_ctrl.mean()):.2f}\n")
                sf_out.write(f"int_range={float(int_ctrl.max() - int_ctrl.min()):.2f}\n")
                voiced = pitch_ctrl[pitch_ctrl > 10.0]
                sf_out.write(f"pitch_mean={float(voiced.mean()) if len(voiced) else 0.0:.2f}\n")
                sf_out.write(f"pitch_range={float(voiced.max() - voiced.min()) if len(voiced) > 1 else 0.0:.2f}\n")
                sf_out.write(f"brightness={float(cfg.get('gesture_brightness', 2000.0)):.1f}\n")
        except Exception as e:
            log(f"  Warning: could not write stats file: {e}", log_file)

    write_done(done_file, "ok")
    log("=== Matter Gesture Bridge complete ===", log_file)


if __name__ == "__main__":
    main()
