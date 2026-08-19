"""
semantic_timbre_retrieval.py — Semantic Timbre Retrieval  v1.1.1 (2026)

Part of Praat AudioTools plugin.
Author: Shai Cohen, Department of Music, Bar-Ilan University.
License: MIT.

Pipeline
--------
    corpus folder
      -> scan + manifest
      -> segment (RMS-gate, fallback = fixed windows)
      -> feature extraction (raw acoustic)
      -> derive 8 semantic dimensions in [0,1]
      -> rule-based tagging + template caption
      -> parse free-text prompt (target dims + tag boosts + exclusions)
      -> hybrid scoring + diversity penalty
      -> top-N ranking
      -> CSV export + optional preview montage WAV

Design notes
------------
* The 8 semantic dims are explainable heuristic retrieval proxies, not learned
  perceptual ground truth. Raw features inform the dims; the dims inform matching.
* Tagging is rule-based and explainable (see rules JSON). No external APIs.
* Captions are dominant-tag templates, musically meaningful.
* All outputs go where the caller asks (Praat passes temp paths).
* The Python side writes files and exits cleanly; the Praat side owns cleanup.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import sys
import time
import warnings
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

warnings.filterwarnings("ignore")


# ─────────────────────────────────────────────────────────────────────────────
# Dependency probe (matches the pattern used by the rest of the plugin)
# ─────────────────────────────────────────────────────────────────────────────

def check_dependencies() -> None:
    missing = []
    for pkg in ("numpy", "soundfile", "scipy", "librosa"):
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install: pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


check_dependencies()

import numpy as np
import soundfile as sf
import librosa


# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────

TARGET_SR = 44100
AUDIO_EXTS = (".wav", ".flac", ".aiff", ".aif", ".mp3", ".ogg")

SEMANTIC_DIMS = (
    "brightness",
    "noisiness",
    "tonalness",
    "stability",
    "impulsiveness",
    "sustain",
    "roughness",
    "spatiality",
)


# ─────────────────────────────────────────────────────────────────────────────
# Dataclasses for clarity
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class Segment:
    """A single analysis unit: either a whole file or a detected segment."""
    item_id: str
    file_id: str
    source_file: str
    start_sec: float
    end_sec: float
    duration_sec: float
    samplerate: int
    channels: int

    # Raw acoustic features (kept for debugging / future work)
    rms_mean: float = 0.0
    rms_std: float = 0.0
    zcr_mean: float = 0.0
    centroid_mean: float = 0.0
    bandwidth_mean: float = 0.0
    rolloff_mean: float = 0.0
    flatness_mean: float = 0.0
    contrast_mean: float = 0.0
    onset_strength_mean: float = 0.0
    attack_time: float = 0.0
    decay_time: float = 0.0
    pitch_confidence: float = 0.0
    f0_mean: float = 0.0
    f0_std: float = 0.0
    hnr_proxy: float = 0.0
    mfcc_mean: List[float] = field(default_factory=list)
    stereo_width: float = 0.0

    # Derived semantic dims in [0,1]
    brightness: float = 0.5
    noisiness: float = 0.5
    tonalness: float = 0.5
    stability: float = 0.5
    impulsiveness: float = 0.5
    sustain: float = 0.5
    roughness: float = 0.5
    spatiality: float = 0.5

    # Tagging
    tags: List[Tuple[str, float]] = field(default_factory=list)   # (tag, confidence)
    short_caption: str = ""

    def dim_vector(self) -> np.ndarray:
        return np.array([getattr(self, d) for d in SEMANTIC_DIMS], dtype=np.float32)

    def tag_set(self) -> set:
        return {t for t, _ in self.tags}


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Semantic Timbre Retrieval engine")
    p.add_argument("--corpus", required=True, help="Corpus folder (scanned recursively)")
    pg = p.add_mutually_exclusive_group(required=True)
    pg.add_argument("--prompt", default=None, help="Free-text timbre prompt")
    pg.add_argument("--prompt_file", default=None, help="UTF-8 file containing the prompt")
    p.add_argument("--mode", choices=("files", "segments"), default="segments")
    p.add_argument("--top_n", type=int, default=8)

    p.add_argument("--rules_json",   required=True)
    p.add_argument("--lexicon_json", required=True)

    p.add_argument("--out_retrieval_csv", required=True)
    p.add_argument("--out_segments_csv",  required=True)
    p.add_argument("--out_manifest_csv",  required=True)
    p.add_argument("--out_stats",         required=True)

    p.add_argument("--do_preview", action="store_true")
    p.add_argument("--out_preview_wav", default="")
    p.add_argument("--crossfade_ms", type=float, default=30.0)

    p.add_argument("--min_seg_sec", type=float, default=0.25)
    p.add_argument("--max_seg_sec", type=float, default=4.0)
    p.add_argument("--seg_gate_db", type=float, default=-35.0)

    p.add_argument("--w_semantic", type=float, default=1.0)
    p.add_argument("--w_tag",      type=float, default=0.5)
    p.add_argument("--w_keyword",  type=float, default=0.25)
    p.add_argument("--diversity_penalty", type=float, default=0.15)

    args = p.parse_args()

    args.top_n = min(100, max(1, args.top_n))
    args.crossfade_ms = max(0.0, args.crossfade_ms)
    args.min_seg_sec  = max(0.05, args.min_seg_sec)
    args.max_seg_sec  = max(args.min_seg_sec + 0.05, args.max_seg_sec)
    args.seg_gate_db  = max(-80.0, min(-3.0, args.seg_gate_db))
    args.w_semantic   = max(0.0, args.w_semantic)
    args.w_tag        = max(0.0, args.w_tag)
    args.w_keyword    = max(0.0, args.w_keyword)
    args.diversity_penalty = max(0.0, args.diversity_penalty)
    if args.w_semantic + args.w_tag + args.w_keyword <= 0:
        args.w_semantic = 1.0
    return args


# ─────────────────────────────────────────────────────────────────────────────
# Corpus scanning
# ─────────────────────────────────────────────────────────────────────────────

def scan_corpus(folder: str) -> List[Path]:
    """Recursively collect audio files, ignoring non-audio safely."""
    root = Path(folder)
    if not root.exists():
        raise FileNotFoundError(f"Corpus folder not found: {folder}")
    out: List[Path] = []
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in AUDIO_EXTS:
            out.append(p.resolve())
    # Stable ordering so a re-run of the same corpus is reproducible
    out.sort(key=lambda x: str(x).lower())
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Segmentation
# ─────────────────────────────────────────────────────────────────────────────

def energy_segment(
    y: np.ndarray,
    sr: int,
    min_sec: float,
    max_sec: float,
    gate_db: float,
) -> List[Tuple[float, float]]:
    """
    RMS-gate based segmentation.
    Returns a list of (start_sec, end_sec). Regions above the gate are kept
    and clipped to [min_sec, max_sec]; gaps below the gate split regions.
    Falls back to empty list if no usable region is found (caller will
    switch to fixed-window segmentation).
    """
    if len(y) < int(sr * min_sec):
        return []

    frame_len = 2048
    hop = 512
    rms = librosa.feature.rms(y=y, frame_length=frame_len, hop_length=hop, center=False)[0]
    if rms.size == 0:
        return []

    peak = float(np.max(rms))
    if peak <= 1e-8:
        return []

    thresh = peak * (10.0 ** (gate_db / 20.0))
    mask = rms >= thresh

    segs: List[Tuple[float, float]] = []
    i = 0
    N = len(mask)
    while i < N:
        if mask[i]:
            j = i
            while j < N and mask[j]:
                j += 1
            start_t = (i * hop) / sr
            end_t   = min(((j - 1) * hop + frame_len) / sr, len(y) / sr)
            # Split regions that exceed max_sec into consecutive chunks
            cur = start_t
            while end_t - cur > max_sec:
                segs.append((cur, cur + max_sec))
                cur += max_sec
            if end_t - cur >= min_sec:
                segs.append((cur, end_t))
            i = j
        else:
            i += 1
    return segs


def fixed_window_segment(
    y: np.ndarray,
    sr: int,
    min_sec: float,
    max_sec: float,
) -> List[Tuple[float, float]]:
    """Fallback: overlapping fixed chunks covering the whole file."""
    dur = len(y) / sr
    if dur < min_sec:
        return [(0.0, dur)] if dur > 0.05 else []

    win = float(np.clip((min_sec + max_sec) / 2.0, min_sec, max_sec))
    hop = win * 0.5
    out: List[Tuple[float, float]] = []
    t = 0.0
    while t < dur:
        out.append((t, min(t + win, dur)))
        t += hop
    # Drop trailing slivers
    out = [s for s in out if (s[1] - s[0]) >= min_sec * 0.8]
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Feature extraction
# ─────────────────────────────────────────────────────────────────────────────

def _safe_mean(x) -> float:
    try:
        v = float(np.nanmean(x))
        return 0.0 if not math.isfinite(v) else v
    except Exception:
        return 0.0


def _safe_std(x) -> float:
    try:
        v = float(np.nanstd(x))
        return 0.0 if not math.isfinite(v) else v
    except Exception:
        return 0.0


def _roughness_modulation(y: np.ndarray, sr: int) -> float:
    """Envelope-modulation proxy for perceptual/textural roughness.

    Measures the fraction of amplitude-envelope AC energy in 15..150 Hz.
    A steady sinusoid is near zero; rapid tremolo/noisy texture rises strongly.
    """
    from scipy.signal import hilbert
    y = np.asarray(y, dtype=np.float64)
    if y.size < 256:
        return 0.0
    rms = float(np.sqrt(np.mean(y * y)))
    if rms < 1e-8:
        return 0.0
    env = np.abs(hilbert(y))
    # Hilbert envelopes have finite-record edge transients even for a perfectly
    # steady sinusoid. Ignore a short boundary region so those artefacts do not
    # masquerade as 15..150 Hz amplitude modulation.
    edge = min(int(round(0.050 * sr)), len(env) // 10)
    if edge > 0 and len(env) > 2 * edge + 64:
        env = env[edge:-edge]
    factor = max(1, int(sr // 1000))
    n = (len(env) // factor) * factor
    if n < 64:
        return 0.0
    env_ds = env[:n].reshape(-1, factor).mean(axis=1)
    env_mean = float(np.mean(env_ds))
    env_std = float(np.std(env_ds))
    # A numerically tiny envelope ripple has no perceptual roughness; without a
    # relative floor its arbitrary FFT ratio can make a steady tone look rough.
    if env_mean <= 1e-12 or env_std / env_mean < 1e-5:
        return 0.0
    env_ds = env_ds - env_mean
    win = np.hanning(len(env_ds))
    power = np.abs(np.fft.rfft(env_ds * win)) ** 2
    freqs = np.fft.rfftfreq(len(env_ds), d=factor / float(sr))
    total = float(np.sum(power[(freqs >= 1.0) & (freqs <= 300.0)]))
    band  = float(np.sum(power[(freqs >= 15.0) & (freqs <= 150.0)]))
    if total <= 1e-20:
        return 0.0
    return float(np.sqrt(np.clip(band / total, 0.0, 1.0)))


def _multichannel_width(y_multi: Optional[np.ndarray]) -> float:
    """0..1 width proxy from inter-channel correlation and energy spread.

    Identical channels -> 0. Uncorrelated or anti-correlated equal-energy
    channels -> high width. Tiny side channels do not falsely imply width.
    """
    if y_multi is None:
        return 0.0
    x = np.asarray(y_multi, dtype=np.float64)
    if x.ndim == 1:
        x = x[np.newaxis, :]
    if x.ndim != 2 or x.shape[0] < 2 or x.shape[1] < 32:
        return 0.0
    rms = np.sqrt(np.mean(x * x, axis=1))
    active = np.where(rms > max(1e-8, float(np.max(rms)) * 1e-4))[0]
    if active.size < 2:
        return 0.0
    xa = x[active]
    ra = rms[active]
    corr_vals = []
    corr_w = []
    for i in range(len(active)):
        for j in range(i + 1, len(active)):
            a = xa[i] - float(np.mean(xa[i]))
            b = xa[j] - float(np.mean(xa[j]))
            den = float(np.sqrt(np.sum(a*a) * np.sum(b*b)))
            if den <= 1e-20:
                continue
            c = float(np.clip(np.sum(a*b) / den, -1.0, 1.0))
            corr_vals.append(c)
            corr_w.append(float(ra[i] * ra[j]))
    if not corr_vals:
        return 0.0
    w = np.asarray(corr_w, dtype=np.float64)
    c = np.asarray(corr_vals, dtype=np.float64)
    mean_corr = float(np.sum(w * c) / max(np.sum(w), 1e-20))
    decor = float(np.clip(1.0 - mean_corr, 0.0, 1.0))
    e = rms * rms
    frac_max = float(np.max(e) / max(np.sum(e), 1e-20))
    n_ch = len(e)
    spread = (1.0 - frac_max) / max(1.0 - 1.0 / n_ch, 1e-9)
    spread = float(np.clip(spread, 0.0, 1.0))
    return float(np.clip(decor * math.sqrt(spread), 0.0, 1.0))


def extract_features(
    y_mono: np.ndarray,
    y_multichannel: Optional[np.ndarray],
    sr: int,
) -> Dict:
    """Compute acoustic descriptors from one representative channel.

    Multichannel data is used only for the spatial-width descriptor. The
    representative timbral channel is selected upstream by highest RMS so
    anti-phase material cannot disappear through fold-down.
    """
    y_mono = np.asarray(y_mono, dtype=np.float32)
    out: Dict = {}
    global_rms = float(np.sqrt(np.mean(y_mono.astype(np.float64) ** 2))) if y_mono.size else 0.0
    if y_mono.size < 64 or global_rms < 1e-8:
        return {
            "rms_mean": 0.0, "rms_std": 0.0, "zcr_mean": 0.0,
            "centroid_mean": 0.0, "bandwidth_mean": 0.0, "rolloff_mean": 0.0,
            "flatness_mean": 0.0, "contrast_mean": 0.0,
            "onset_strength_mean": 0.0, "attack_time": 0.0, "decay_time": 0.0,
            "pitch_confidence": 0.0, "f0_mean": 0.0, "f0_std": 0.0,
            "hnr_proxy": 0.0, "mfcc_mean": [0.0] * 13,
            "stereo_width": _multichannel_width(y_multichannel),
            "_centroid_std": 0.0, "_contrast_std": 0.0, "_onset_std": 0.0,
            "_roughness_mod": 0.0,
        }

    n_fft = 2048 if len(y_mono) >= 2048 else max(256, 2 ** int(np.floor(np.log2(max(256, len(y_mono))))))
    n_fft = min(n_fft, len(y_mono))
    hop = max(64, n_fft // 4)

    rms = librosa.feature.rms(y=y_mono, frame_length=n_fft, hop_length=hop, center=False)[0]
    out["rms_mean"] = _safe_mean(rms)
    out["rms_std"]  = _safe_std(rms)

    if rms.size >= 3 and np.max(rms) > 1e-8:
        peak_frame = int(np.argmax(rms))
        peak_val = float(rms[peak_frame])
        t_frame = hop / sr
        atk_start = peak_frame
        for k in range(peak_frame - 1, -1, -1):
            atk_start = k
            if rms[k] <= 0.1 * peak_val:
                break
        out["attack_time"] = (peak_frame - atk_start) * t_frame
        dec_end = peak_frame
        for k in range(peak_frame + 1, len(rms)):
            dec_end = k
            if rms[k] <= 0.1 * peak_val:
                break
        out["decay_time"] = (dec_end - peak_frame) * t_frame
    else:
        out["attack_time"] = 0.0
        out["decay_time"] = 0.0

    zcr = librosa.feature.zero_crossing_rate(y=y_mono, frame_length=n_fft,
                                             hop_length=hop, center=False)[0]
    out["zcr_mean"] = _safe_mean(zcr)

    cent = librosa.feature.spectral_centroid(y=y_mono, sr=sr, n_fft=n_fft,
                                              hop_length=hop, center=False)[0]
    bw   = librosa.feature.spectral_bandwidth(y=y_mono, sr=sr, n_fft=n_fft,
                                               hop_length=hop, center=False)[0]
    roll = librosa.feature.spectral_rolloff(y=y_mono, sr=sr, n_fft=n_fft,
                                             hop_length=hop, center=False)[0]
    flat = librosa.feature.spectral_flatness(y=y_mono, n_fft=n_fft,
                                              hop_length=hop, center=False)[0]
    out["centroid_mean"]  = _safe_mean(cent)
    out["bandwidth_mean"] = _safe_mean(bw)
    out["rolloff_mean"]   = _safe_mean(roll)
    out["flatness_mean"]  = _safe_mean(flat)
    out["_centroid_std"] = _safe_std(cent)

    try:
        contrast = librosa.feature.spectral_contrast(y=y_mono, sr=sr, n_fft=n_fft,
                                                      hop_length=hop, center=False)
        out["contrast_mean"] = _safe_mean(contrast)
        out["_contrast_std"] = _safe_std(contrast)
    except Exception:
        out["contrast_mean"] = 0.0
        out["_contrast_std"] = 0.0

    try:
        onset_env = librosa.onset.onset_strength(y=y_mono, sr=sr, hop_length=hop,
                                                  center=False)
        out["onset_strength_mean"] = _safe_mean(onset_env)
        out["_onset_std"] = _safe_std(onset_env)
    except Exception:
        out["onset_strength_mean"] = 0.0
        out["_onset_std"] = 0.0

    # pYIN provides an actual voicing probability. The old YIN path treated
    # every positive F0 estimate as voiced, which makes noise/silence "tonal".
    try:
        fmin = 50.0
        fmax = min(2000.0, sr / 2 - 50.0)
        frame_pyin = max(1024, n_fft)
        if len(y_mono) >= frame_pyin and fmax > fmin:
            f0, voiced_flag, voiced_prob = librosa.pyin(
                y_mono, fmin=fmin, fmax=fmax, sr=sr,
                frame_length=frame_pyin, hop_length=hop, center=False,
                fill_na=np.nan, n_thresholds=32, resolution=0.2)
            vp = np.asarray(voiced_prob, dtype=np.float64)
            conf = float(np.clip(np.nanmean(vp), 0.0, 1.0)) if vp.size else 0.0
            vf = np.asarray(voiced_flag, dtype=bool) & np.isfinite(f0)
            f0v = np.asarray(f0)[vf]
            f0_mean = float(np.mean(f0v)) if f0v.size else 0.0
            f0_std  = float(np.std(f0v)) if f0v.size else 0.0
        else:
            conf = f0_mean = f0_std = 0.0
    except Exception:
        conf = f0_mean = f0_std = 0.0
    out["pitch_confidence"] = conf
    out["f0_mean"] = f0_mean
    out["f0_std"] = f0_std
    out["hnr_proxy"] = float(np.clip(conf * (1.0 - out["flatness_mean"]), 0.0, 1.0))

    try:
        mfcc = librosa.feature.mfcc(y=y_mono, sr=sr, n_mfcc=13, n_fft=n_fft,
                                    hop_length=hop)
        out["mfcc_mean"] = [float(v) for v in np.nanmean(mfcc, axis=1)]
    except Exception:
        out["mfcc_mean"] = [0.0] * 13

    out["_roughness_mod"] = _roughness_modulation(y_mono, sr)
    out["stereo_width"] = _multichannel_width(y_multichannel)
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Semantic dimension mapping
# ─────────────────────────────────────────────────────────────────────────────

def _sat(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    """Saturating clip, safe against NaN."""
    if not math.isfinite(x):
        return lo
    return float(min(max(x, lo), hi))


def _log_norm(x: float, x_lo: float, x_hi: float) -> float:
    """Log-space normalisation to [0,1] between x_lo and x_hi."""
    if x <= 0 or x_lo <= 0 or x_hi <= x_lo:
        return 0.0
    v = (math.log(x) - math.log(x_lo)) / (math.log(x_hi) - math.log(x_lo))
    return _sat(v)


def derive_semantic_dims(f: Dict, sr: int, duration: float) -> Dict[str, float]:
    """Collapse raw features into 8 explainable semantic proxies in [0,1]."""
    brightness = _log_norm(f["centroid_mean"], 200.0, sr / 4.0)

    noisiness = _sat(0.7 * f["flatness_mean"] + 0.3 * _sat(f["zcr_mean"] * 8.0))

    # pYIN confidence now contributes real voicing evidence instead of the old
    # always-positive YIN estimate.
    tonalness = _sat(0.65 * (1.0 - noisiness) + 0.35 * f["pitch_confidence"])

    cent_mean = max(f["centroid_mean"], 1.0)
    cent_var_norm = _sat(f.get("_centroid_std", 0.0) / (cent_mean + 1e-6) * 1.2)
    f0_var_norm = 0.0
    if f["f0_mean"] > 0 and f["pitch_confidence"] >= 0.15:
        f0_var_norm = _sat(f["f0_std"] / (f["f0_mean"] + 1e-6) * 2.0)
        stability = _sat(1.0 - 0.6 * cent_var_norm - 0.4 * f0_var_norm)
    else:
        stability = _sat(1.0 - cent_var_norm)

    atk = f["attack_time"]
    atk_norm = _sat(1.0 - atk / 0.15)
    onset_var = _sat(f.get("_onset_std", 0.0) / (f["onset_strength_mean"] + 1e-6))
    impulsiveness = _sat(0.6 * atk_norm + 0.4 * onset_var)

    dur_norm = _sat(duration / 3.0)
    dec_norm = _sat(f["decay_time"] / 1.0)
    sustain = _sat(0.5 * dur_norm + 0.5 * dec_norm)

    # Temporal envelope modulation is a more faithful roughness proxy than
    # spectral-contrast variance (which incorrectly rates pure tones as rough).
    rough_mod = _sat(f.get("_roughness_mod", 0.0))
    roughness = _sat(0.75 * rough_mod
                     + 0.15 * f["flatness_mean"]
                     + 0.10 * _sat(f["zcr_mean"] * 6.0))

    # Spatiality is primarily an inter-channel property. Spectral bandwidth is
    # kept only as a weak mono spaciousness proxy, not as 40% of the dimension.
    bw_norm = _log_norm(f["bandwidth_mean"], 200.0, sr / 4.0) if f["bandwidth_mean"] > 0 else 0.0
    spatiality = _sat(0.8 * f["stereo_width"] + 0.2 * bw_norm)

    return dict(
        brightness=brightness,
        noisiness=noisiness,
        tonalness=tonalness,
        stability=stability,
        impulsiveness=impulsiveness,
        sustain=sustain,
        roughness=roughness,
        spatiality=spatiality,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Rule-based tagging + captioning
# ─────────────────────────────────────────────────────────────────────────────

def _triangular_conf(x: float, lo: float, hi: float) -> float:
    """Confidence = 1 at band centre, fading linearly to 0 at band edges."""
    if not (lo <= x <= hi):
        return 0.0
    c = (lo + hi) * 0.5
    half = max(1e-6, (hi - lo) * 0.5)
    return float(max(0.0, 1.0 - abs(x - c) / half))


def tag_segment(dims: Dict[str, float], rules: Dict) -> List[Tuple[str, float]]:
    """
    Apply the rule JSON. Each family picks at most one tag per family based
    on the dim's band; compound rules add extra tags whose conditions match.
    """
    tagged: List[Tuple[str, float]] = []

    # Family bands
    for fam_name, bands in rules.get("rule_families", {}).items():
        best: Optional[Tuple[str, float]] = None
        for band in bands:
            dim = band["dim"]
            if dim not in dims:
                continue
            v = dims[dim]
            lo, hi = float(band["min"]), float(band["max"])
            if lo <= v < hi:
                conf = _triangular_conf(v, lo, hi)
                # fallback: centered bands can give 0 at edge, ensure >0
                conf = max(conf, 0.25)
                if best is None or conf > best[1]:
                    best = (band["tag"], conf)
        if best is not None:
            tagged.append(best)

    # Compound rules
    for rule in rules.get("compound_rules", []):
        cond = rule.get("conditions", {})
        ok = True
        score = 1.0
        for dim, (lo, hi) in cond.items():
            if dim not in dims:
                ok = False
                break
            v = dims[dim]
            if not (float(lo) <= v <= float(hi)):
                ok = False
                break
            # proximity to band gives more confidence
            score *= _triangular_conf(v, float(lo), float(hi)) * 0.5 + 0.5
        if ok:
            tagged.append((rule["tag"], float(rule.get("confidence", 0.7)) * score))

    return tagged


def make_caption(dims: Dict[str, float], tags: List[Tuple[str, float]]) -> str:
    """
    Template caption using the most salient tag from selected families.
    Shape: "<brightness> <envelope> <morphology> with <texture> edge"
    Falls back gracefully when a family is missing.
    """
    tag_lookup: Dict[str, str] = {}
    # Pick the highest-conf tag per family
    # (We infer family by a lookup against a fixed set below.)
    family_map = {
        "dark": "brightness", "warm": "brightness", "neutral": "brightness",
        "bright": "brightness", "piercing": "brightness",
        "noisy": "harmonicity", "airy": "harmonicity", "mixed": "harmonicity",
        "tonal": "harmonicity", "pure": "harmonicity",
        "impulsive": "envelope", "percussive": "envelope", "swelling": "envelope",
        "sustained": "envelope", "decaying": "envelope", "trembling": "envelope",
        "smooth": "texture", "rough": "texture", "grainy": "texture",
        "dense": "texture", "sparse": "texture",
        "burst": "morphology", "pulse": "morphology", "stream": "morphology",
        "cloud": "morphology", "drone": "morphology", "scrape": "morphology",
        "gesture": "morphology",
        "stable": "stability", "gliding": "stability",
        "unstable": "stability", "fluttering": "stability",
        "dry": "space", "narrow": "space", "wide": "space",
        "distant": "space", "reverberant": "space",
    }
    best_per_fam: Dict[str, Tuple[str, float]] = {}
    for t, c in tags:
        fam = family_map.get(t)
        if fam is None:
            continue
        prev = best_per_fam.get(fam)
        if prev is None or c > prev[1]:
            best_per_fam[fam] = (t, c)
    pick = {fam: v[0] for fam, v in best_per_fam.items()}

    brightness = pick.get("brightness", "neutral")
    harmonicity = pick.get("harmonicity", "mixed")
    envelope    = pick.get("envelope",    "sustained")
    morphology  = pick.get("morphology",  "gesture")
    texture     = pick.get("texture",     "")
    stability   = pick.get("stability",   "")
    space       = pick.get("space",       "")

    parts = [brightness]
    if harmonicity and harmonicity != brightness:
        parts.append(harmonicity)
    parts.append(envelope)
    parts.append(morphology)

    head = " ".join(parts)
    tail_bits = []
    if texture:
        tail_bits.append(f"{texture} edge")
    if stability and stability not in ("stable",):
        tail_bits.append(f"{stability} contour")
    if space and space not in ("narrow", "dry"):
        tail_bits.append(f"{space} field")

    if tail_bits:
        return head + " with " + " + ".join(tail_bits)
    return head


# ─────────────────────────────────────────────────────────────────────────────
# Prompt parsing
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class ParsedPrompt:
    target_dims: Dict[str, float]       # desired value per dim (0..1)
    dim_weights: Dict[str, float]       # how strongly to weight each dim
    tag_boosts: Dict[str, float]        # desired tags with boost weight
    exclusions: Dict[str, float]        # undesired tags with penalty weight
    keywords: List[str]                 # normalised tokens used
    raw: str


def parse_prompt(text: str, lexicon: Dict) -> ParsedPrompt:
    """Parse local free-text timbre language into weighted semantic targets.

    Intensity modifiers scale influence; they do not change the arithmetic
    definition of the target. "less X" reverses X softly, while explicit
    negations (not/no/without) reverse the dimension and penalize the tag.
    """
    raw = text
    lower = " " + text.lower().strip() + " "
    lower_nohy = re.sub(r"\s+", " ", lower.replace("-", " ").replace("_", " "))

    synonyms_raw = lexicon.get("synonyms", {})
    tokens_def = lexicon.get("tokens", {})
    intensity_raw = lexicon.get("intensity", {})

    def _norm_phrase(v: str) -> str:
        return re.sub(r"\s+", " ", str(v).lower().replace("-", " ").replace("_", " ")).strip()

    # Normalize lexicon keys as well as user input.  This makes vowel-like,
    # vowel_like and vowel like equivalent without changing canonical token IDs.
    token_key_by_norm = {_norm_phrase(k): k for k in tokens_def}
    synonyms = {_norm_phrase(k): v for k, v in synonyms_raw.items()}
    intensity = {_norm_phrase(k): float(v) for k, v in intensity_raw.items()}
    negations = {_norm_phrase(v) for v in lexicon.get("negation", [])}

    target_weighted_sum: Dict[str, float] = {d: 0.0 for d in SEMANTIC_DIMS}
    weight_sum: Dict[str, float] = {d: 0.0 for d in SEMANTIC_DIMS}
    tag_boosts: Dict[str, float] = {}
    exclusions: Dict[str, float] = {}
    used_keywords: List[str] = []

    words = re.findall(r"[a-zA-Z][a-zA-Z'-]*", lower_nohy)
    i = 0
    n = len(words)

    def _resolve_token(w: str) -> Optional[str]:
        nw = _norm_phrase(w)
        direct = token_key_by_norm.get(nw)
        if direct is not None:
            return direct
        if nw in synonyms:
            canon = synonyms[nw]
            if canon in tokens_def:
                return canon
            return token_key_by_norm.get(_norm_phrase(canon))
        return None

    while i < n:
        negate = False
        less = False
        mod = 1.0
        k = i
        qualifier_steps = 0
        while k < n and qualifier_steps < 3:
            w = words[k]
            if w in negations:
                negate = not negate
                k += 1; qualifier_steps += 1; continue
            two = (w + " " + words[k + 1]) if k + 1 < n else None
            if two and two in intensity:
                mod *= abs(float(intensity[two]))
                k += 2; qualifier_steps += 1; continue
            if w == "less":
                less = not less
                mod *= abs(float(intensity.get(w, 0.65)))
                k += 1; qualifier_steps += 1; continue
            if w == "more":
                mod *= abs(float(intensity.get(w, 1.25)))
                k += 1; qualifier_steps += 1; continue
            if w in intensity:
                mod *= abs(float(intensity[w]))
                k += 1; qualifier_steps += 1; continue
            break

        matched = None
        matched_len = 0
        for L in (3, 2, 1):
            if k + L > n:
                continue
            phrase = " ".join(words[k:k + L])
            canon = _resolve_token(phrase)
            if canon is not None:
                matched = canon
                matched_len = L
                break

        if matched is None:
            i = max(i + 1, k + 1)
            continue

        td = tokens_def[matched]
        if matched not in used_keywords:
            used_keywords.append(matched)

        reverse = bool(negate) ^ bool(less)
        for dim, delta in td.get("dims", {}).items():
            if dim not in SEMANTIC_DIMS:
                continue
            base = float(delta)
            d = (-base if reverse else base) * mod
            d = float(np.clip(d, -1.0, 1.0))
            target = 0.5 + 0.5 * d
            strength = max(abs(base) * mod, 1e-6)
            target_weighted_sum[dim] += target * strength
            weight_sum[dim] += strength

        for tag, boost in td.get("tag_boosts", {}).items():
            b = abs(float(boost)) * mod
            if reverse:
                exclusions[tag] = exclusions.get(tag, 0.0) + b
            else:
                tag_boosts[tag] = tag_boosts.get(tag, 0.0) + b

        i = k + matched_len

    target_dims: Dict[str, float] = {}
    dim_weights: Dict[str, float] = {}
    for d in SEMANTIC_DIMS:
        if weight_sum[d] > 1e-6:
            target_dims[d] = _sat(target_weighted_sum[d] / weight_sum[d])
            dim_weights[d] = float(min(weight_sum[d], 2.0))
        else:
            target_dims[d] = 0.5
            dim_weights[d] = 0.0

    return ParsedPrompt(target_dims, dim_weights, tag_boosts, exclusions,
                        used_keywords, raw)


# ─────────────────────────────────────────────────────────────────────────────
# Scoring
# ─────────────────────────────────────────────────────────────────────────────

def score_segment(seg: Segment, pp: ParsedPrompt, w_sem: float, w_tag: float, w_kw: float
                  ) -> Tuple[float, float, float, List[str], str]:
    """
    Returns (total, semantic_score, tag_score, matched_tags, explanation).
    Scores are in [0,1] approximately (can drift slightly due to caption match).
    """
    # Semantic score: 1 - weighted Euclidean distance (dim weights)
    weights = np.array([pp.dim_weights[d] for d in SEMANTIC_DIMS], dtype=np.float32)
    target  = np.array([pp.target_dims[d] for d in SEMANTIC_DIMS], dtype=np.float32)
    itemv   = seg.dim_vector()

    if float(np.sum(weights)) <= 1e-6:
        # Nothing in the prompt resolved to a dim → neutral semantic score
        semantic = 0.5
        per_dim_err = np.abs(itemv - target)
    else:
        diff = itemv - target
        per_dim_err = np.abs(diff)
        w = weights / (np.sum(weights) + 1e-9)
        # RMS distance, normalised: max possible ≈ 1.0
        dist = float(np.sqrt(np.sum(w * diff * diff)))
        semantic = _sat(1.0 - dist)

    # Tag score
    tag_set = seg.tag_set()
    matched: List[str] = []
    tag_total = 0.0
    tag_weight_sum = 0.0
    for tag, boost in pp.tag_boosts.items():
        tag_weight_sum += abs(boost)
        if tag in tag_set:
            # use the segment's confidence for that tag
            conf = next((c for t, c in seg.tags if t == tag), 0.7)
            tag_total += boost * conf
            matched.append(tag)
    for tag, pen in pp.exclusions.items():
        tag_weight_sum += abs(pen)
        if tag in tag_set:
            conf = next((c for t, c in seg.tags if t == tag), 0.7)
            tag_total -= pen * conf
    tag_score = 0.5 if tag_weight_sum <= 1e-6 else _sat(0.5 + 0.5 * tag_total / (tag_weight_sum + 1e-9))

    # Keyword score: tokens appearing in caption
    cap = seg.short_caption.lower()
    kw_hits = sum(1 for k in pp.keywords if k in cap)
    kw_score = 0.0 if not pp.keywords else _sat(kw_hits / len(pp.keywords))

    total = (w_sem * semantic + w_tag * tag_score + w_kw * kw_score) / max(w_sem + w_tag + w_kw, 1e-6)

    # Human-readable explanation
    dim_ranked = sorted(
        ((d, float(per_dim_err[i])) for i, d in enumerate(SEMANTIC_DIMS)
         if pp.dim_weights[d] > 1e-6),
        key=lambda x: x[1],
    )
    strong_bits = [d for d, e in dim_ranked[:2] if e < 0.2]
    weak_bits   = [d for d, e in dim_ranked[-2:] if e > 0.3]
    bits: List[str] = []
    if strong_bits:
        bits.append("strong on " + "+".join(strong_bits))
    if matched:
        bits.append("tags: " + "/".join(sorted(set(matched))))
    if weak_bits:
        bits.append("weak on " + "+".join(weak_bits))
    if not bits:
        bits.append("neutral profile match")
    explanation = " | ".join(bits)

    return float(total), float(semantic), float(tag_score), matched, explanation


# ─────────────────────────────────────────────────────────────────────────────
# Diversity-aware ranking
# ─────────────────────────────────────────────────────────────────────────────

def diversify_and_rank(scored: List[Tuple[Segment, float, float, float, List[str], str]],
                       top_n: int,
                       diversity_penalty: float,
                       ) -> List[Tuple[Segment, float, float, float, List[str], str]]:
    """
    Greedy diversity: repeatedly pick the highest-scoring candidate, then
    subtract `diversity_penalty` * k from any remaining candidate sharing its
    source file (where k is the number of already-picked siblings).

    Uses integer indexing into `scored` to avoid tuple-identity pitfalls.
    """
    remaining_idx = list(range(len(scored)))
    file_counts: Dict[str, int] = {}
    picked: List = []

    while remaining_idx and len(picked) < top_n:
        best_i: Optional[int] = None
        best_adj = -float("inf")
        for i in remaining_idx:
            seg, total, *_ = scored[i]
            k = file_counts.get(seg.source_file, 0)
            adj = total - diversity_penalty * k
            if adj > best_adj:
                best_adj = adj
                best_i = i
        if best_i is None:
            break
        picked.append(scored[best_i])
        src = scored[best_i][0].source_file
        file_counts[src] = file_counts.get(src, 0) + 1
        remaining_idx.remove(best_i)

    return picked


# ─────────────────────────────────────────────────────────────────────────────
# Preview montage
# ─────────────────────────────────────────────────────────────────────────────

def _preview_pair(y_multi: np.ndarray) -> np.ndarray:
    """Return channels x samples: mono unchanged, N-channel -> two strongest."""
    x = np.asarray(y_multi, dtype=np.float32)
    if x.ndim == 1:
        return x[np.newaxis, :]
    if x.shape[0] <= 2:
        return x
    rms = np.sqrt(np.mean(x.astype(np.float64) ** 2, axis=1))
    idx = np.argsort(rms)[-2:]
    idx = np.sort(idx)
    return x[idx]


def build_preview(
    segments: List[Segment],
    audio_cache: Dict[str, np.ndarray],
    sr: int,
    crossfade_ms: float,
) -> np.ndarray:
    """Preview montage preserving mono/stereo information when possible.

    If any selected source is stereo/multichannel, the preview is stereo.
    Mono chunks are duplicated; N-channel chunks use their two strongest
    channels. Crossfades are equal-power and level is not normalized upward.
    """
    if not segments:
        return np.zeros(int(sr * 0.1), dtype=np.float32)

    source_audio: List[Tuple[Segment, np.ndarray]] = []
    any_stereo = False
    for s in segments:
        y = audio_cache.get(s.source_file)
        if y is None:
            try:
                y, _ = librosa.load(s.source_file, sr=sr, mono=False)
                y = np.asarray(y, dtype=np.float32)
                if y.ndim == 1:
                    y = y[np.newaxis, :]
                audio_cache[s.source_file] = y
            except Exception:
                continue
        pair = _preview_pair(y)
        any_stereo = any_stereo or pair.shape[0] >= 2
        source_audio.append((s, pair))

    if not source_audio:
        return np.zeros(int(sr * 0.1), dtype=np.float32)

    out_ch = 2 if any_stereo else 1
    chunks: List[np.ndarray] = []
    for s, pair in source_audio:
        if out_ch == 2 and pair.shape[0] == 1:
            pair = np.repeat(pair, 2, axis=0)
        elif out_ch == 1:
            pair = pair[:1]
        i0 = max(0, min(int(round(s.start_sec * sr)), pair.shape[1]))
        i1 = max(i0 + 1, min(int(round(s.end_sec * sr)), pair.shape[1]))
        chunks.append(pair[:, i0:i1].astype(np.float32))

    if not chunks:
        return np.zeros(int(sr * 0.1), dtype=np.float32)

    cf_samples = int(round(sr * crossfade_ms / 1000.0))
    out = chunks[0].copy()
    for nxt in chunks[1:]:
        cf = min(cf_samples, out.shape[1], nxt.shape[1])
        if cf <= 1:
            out = np.concatenate([out, nxt], axis=1)
            continue
        t = np.linspace(0.0, 1.0, cf, dtype=np.float32)
        fade_out = np.cos(t * np.pi * 0.5)[np.newaxis, :]
        fade_in  = np.sin(t * np.pi * 0.5)[np.newaxis, :]
        tail = out[:, -cf:] * fade_out + nxt[:, :cf] * fade_in
        out = np.concatenate([out[:, :-cf], tail, nxt[:, cf:]], axis=1).astype(np.float32)

    if out_ch == 1:
        return out[0]
    return out.T  # soundfile convention: frames x channels


# ─────────────────────────────────────────────────────────────────────────────
# CSV helpers
# ─────────────────────────────────────────────────────────────────────────────

def _path_posix(p: str) -> str:
    """Normalise any filesystem path to forward-slash form.
    Praat's Table reader handles forward slashes cleanly on all platforms.
    """
    return str(p).replace("\\", "/")


def write_manifest_csv(path: str, manifest: List[Dict]) -> None:
    cols = ["file_id", "source_file", "duration_sec", "samplerate", "channels", "analysis_channel", "num_segments"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for row in manifest:
            vals = []
            for c in cols:
                v = row[c]
                if c == "source_file":
                    v = _path_posix(v)
                vals.append(v)
            w.writerow(vals)


def write_segments_csv(path: str, segs: List[Segment]) -> None:
    cols = [
        "segment_id", "source_file", "start_sec", "end_sec", "duration_sec",
        "brightness", "noisiness", "tonalness", "stability",
        "impulsiveness", "sustain", "roughness", "spatiality",
        "tags", "short_caption",
    ]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for s in segs:
            tag_str = "|".join(f"{t}:{c:.2f}" for t, c in s.tags)
            w.writerow([
                s.item_id, _path_posix(s.source_file),
                f"{s.start_sec:.3f}", f"{s.end_sec:.3f}", f"{s.duration_sec:.3f}",
                f"{s.brightness:.3f}", f"{s.noisiness:.3f}", f"{s.tonalness:.3f}",
                f"{s.stability:.3f}", f"{s.impulsiveness:.3f}", f"{s.sustain:.3f}",
                f"{s.roughness:.3f}", f"{s.spatiality:.3f}",
                tag_str, s.short_caption,
            ])


def write_retrieval_csv(path: str, picks) -> None:
    cols = ["rank", "item_id", "source_file", "start_sec", "end_sec",
            "score_total", "score_semantic", "score_tag",
            "matched_tags", "short_caption", "explanation"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for rank, (seg, total, sem, tg, matched, expl) in enumerate(picks, start=1):
            w.writerow([
                rank, seg.item_id, _path_posix(seg.source_file),
                f"{seg.start_sec:.3f}", f"{seg.end_sec:.3f}",
                f"{total:.4f}", f"{sem:.4f}", f"{tg:.4f}",
                "|".join(matched),
                seg.short_caption,
                expl,
            ])


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    t0 = time.time()
    args = parse_args()

    if args.prompt_file:
        try:
            prompt_text = Path(args.prompt_file).read_text(encoding="utf-8").strip()
        except Exception as e:
            print(f"ERROR: Cannot read prompt file {args.prompt_file}: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        prompt_text = (args.prompt or "").strip()
    if not prompt_text:
        print("ERROR: Prompt is empty.", file=sys.stderr)
        sys.exit(1)

    try:
        with open(args.rules_json, "r", encoding="utf-8") as f:
            rules = json.load(f)
    except Exception as e:
        print(f"ERROR: Cannot read rules JSON {args.rules_json}: {e}", file=sys.stderr)
        sys.exit(1)
    try:
        with open(args.lexicon_json, "r", encoding="utf-8") as f:
            lexicon = json.load(f)
    except Exception as e:
        print(f"ERROR: Cannot read lexicon JSON {args.lexicon_json}: {e}", file=sys.stderr)
        sys.exit(1)

    print("[1/5] Scanning corpus...")
    files = scan_corpus(args.corpus)
    if not files:
        print(f"ERROR: No audio files found in {args.corpus}", file=sys.stderr)
        sys.exit(1)
    print(f"    Found {len(files)} audio files")

    print("[2/5] Segmenting + extracting features...")
    all_segs: List[Segment] = []
    manifest: List[Dict] = []
    # Preview audio is loaded lazily only for selected Top-N results; do not
    # retain every corpus file in RAM during indexing.
    audio_cache: Dict[str, np.ndarray] = {}
    silent_skipped = 0

    for file_idx, fpath in enumerate(files):
        fstr = str(fpath)
        try:
            y_multi, _ = librosa.load(fstr, sr=TARGET_SR, mono=False)
            y_multi = np.asarray(y_multi, dtype=np.float32)
            if y_multi.ndim == 1:
                y_multi = y_multi[np.newaxis, :]
            if y_multi.ndim != 2 or y_multi.shape[1] < 1:
                raise ValueError("invalid audio shape")
            n_ch = int(y_multi.shape[0])
            ch_rms = np.sqrt(np.mean(y_multi.astype(np.float64) ** 2, axis=1))
            analysis_idx = int(np.argmax(ch_rms))
            y = y_multi[analysis_idx]
        except Exception as e:
            print(f"    SKIP: {fpath.name}: {e}", file=sys.stderr)
            continue

        dur = len(y) / TARGET_SR

        if args.mode == "files":
            bounds = [(0.0, dur)]
        else:
            bounds = energy_segment(y, TARGET_SR, args.min_seg_sec,
                                    args.max_seg_sec, args.seg_gate_db)
            # Fixed windows are a fallback only when the energy segmenter found
            # nothing, not when it found one perfectly valid event.
            if not bounds:
                bounds = fixed_window_segment(y, TARGET_SR, args.min_seg_sec,
                                              args.max_seg_sec)
            if not bounds and dur > 0.05:
                bounds = [(0.0, dur)]

        num_segs = 0
        for si, (a, b) in enumerate(bounds):
            ia = max(0, int(round(a * TARGET_SR)))
            ib = min(len(y), int(round(b * TARGET_SR)))
            y_seg = y[ia:ib]
            if len(y_seg) < int(TARGET_SR * 0.05):
                continue
            seg_rms = float(np.sqrt(np.mean(y_seg.astype(np.float64) ** 2)))
            if seg_rms < 1e-7:
                silent_skipped += 1
                continue
            y_seg_multi = y_multi[:, ia:ib] if n_ch > 1 else None
            feats = extract_features(y_seg, y_seg_multi, TARGET_SR)

            item_id = (f"file_{file_idx:05d}" if args.mode == "files"
                       else f"seg_{file_idx:05d}_{si:03d}")
            seg = Segment(
                item_id=item_id, file_id=f"file_{file_idx:05d}",
                source_file=fstr, start_sec=float(a), end_sec=float(b),
                duration_sec=float(b - a), samplerate=TARGET_SR, channels=n_ch,
                rms_mean=feats["rms_mean"], rms_std=feats["rms_std"],
                zcr_mean=feats["zcr_mean"], centroid_mean=feats["centroid_mean"],
                bandwidth_mean=feats["bandwidth_mean"], rolloff_mean=feats["rolloff_mean"],
                flatness_mean=feats["flatness_mean"], contrast_mean=feats["contrast_mean"],
                onset_strength_mean=feats["onset_strength_mean"],
                attack_time=feats["attack_time"], decay_time=feats["decay_time"],
                pitch_confidence=feats["pitch_confidence"], f0_mean=feats["f0_mean"],
                f0_std=feats["f0_std"], hnr_proxy=feats["hnr_proxy"],
                mfcc_mean=feats["mfcc_mean"], stereo_width=feats["stereo_width"],
            )
            dims = derive_semantic_dims(feats, TARGET_SR, seg.duration_sec)
            for d, v in dims.items():
                setattr(seg, d, v)
            seg.tags = tag_segment(dims, rules)
            seg.short_caption = make_caption(dims, seg.tags)
            all_segs.append(seg)
            num_segs += 1

        manifest.append(dict(
            file_id=f"file_{file_idx:05d}", source_file=fstr,
            duration_sec=round(dur, 3), samplerate=TARGET_SR, channels=n_ch,
            analysis_channel=analysis_idx + 1, num_segments=num_segs,
        ))

    if not all_segs:
        print("ERROR: No non-silent analysable segments extracted from corpus.", file=sys.stderr)
        sys.exit(1)
    print(f"    Analysed {len(all_segs)} items")

    print("[3/5] Parsing prompt...")
    pp = parse_prompt(prompt_text, lexicon)
    print(f"    Keywords resolved: {pp.keywords}")
    if not pp.keywords:
        print("ERROR: The prompt contains no terms recognized by the local semantic lexicon.", file=sys.stderr)
        print("Use one or more supported timbre descriptors or a built-in preset.", file=sys.stderr)
        sys.exit(1)

    print("[4/5] Scoring and ranking...")
    scored = []
    for seg in all_segs:
        total, sem, tg, matched, expl = score_segment(
            seg, pp, args.w_semantic, args.w_tag, args.w_keyword)
        scored.append((seg, total, sem, tg, matched, expl))
    picks = diversify_and_rank(scored, args.top_n, args.diversity_penalty)
    print(f"    Picked top {len(picks)}")

    print("[5/5] Writing outputs...")
    write_manifest_csv(args.out_manifest_csv, manifest)
    write_segments_csv(args.out_segments_csv, all_segs)
    write_retrieval_csv(args.out_retrieval_csv, picks)

    preview_channels = 0
    if args.do_preview and args.out_preview_wav:
        preview_segs = [p[0] for p in picks]
        preview_audio = build_preview(preview_segs, audio_cache, TARGET_SR,
                                      args.crossfade_ms)
        peak = float(np.max(np.abs(preview_audio))) if preview_audio.size else 0.0
        if peak > 0.95:
            preview_audio = (preview_audio * (0.95 / peak)).astype(np.float32)
        preview_channels = 1 if preview_audio.ndim == 1 else int(preview_audio.shape[1])
        sf.write(args.out_preview_wav, preview_audio, TARGET_SR, subtype="FLOAT")

    elapsed = time.time() - t0
    unique_files = len({s.source_file for s in all_segs})
    with open(args.out_stats, "w", encoding="utf-8") as f:
        f.write(f"Corpus files scanned: {len(files)}\n")
        f.write(f"Files analysed: {unique_files}\n")
        f.write(f"Items indexed: {len(all_segs)}\n")
        f.write(f"Silent items skipped: {silent_skipped}\n")
        f.write(f"Retrieval mode: {args.mode}\n")
        f.write(f"Prompt tokens resolved: {len(pp.keywords)}\n")
        for d in SEMANTIC_DIMS:
            f.write(f"Prompt target {d}: {pp.target_dims[d]:.6f}\n")
            f.write(f"Prompt weight {d}: {pp.dim_weights[d]:.6f}\n")
        f.write(f"Top N requested: {args.top_n}\n")
        f.write(f"Top N returned: {len(picks)}\n")
        f.write(f"Preview channels: {preview_channels}\n")
        f.write(f"Render time: {elapsed:.2f}s\n")

    print("[Py] Success. Exiting cleanly.")


if __name__ == "__main__":
    main()
