#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - ai_conductor_mix.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Title: AI Conductor Mix
# Version: 3.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   AI Conductor Mix is an offline algorithmic ensemble conductor for Praat
#   AudioTools. It analyzes two or more recorded Sounds and generates a
#   continuous stereo mix through context-sensitive role assignment,
#   interpretive memory, and coordinated gain and spatial decisions.
#   Version 3.3 introduces Responsive and Complementary conducting
#   behaviors, phrase-aware interpretation, and optional fixed chamber
#   positioning while preserving the original v3.2 processing mode.
#
#   "AI" is the instrument's name. v3.3 contains no trained or neural
#   model: every decision is a deterministic, inspectable heuristic.
#
# Input (called by AI_Conductor_Mix.praat):
#   manifest (index, name, WAV path, ...), Praat macro descriptors,
#   output paths, and the conducting parameters as CLI options.
#
# Output:
#   1. Stereo float32 WAV rendered at sample level from the uncut sources
#   2. Tab-delimited mix plan CSV (v3.2 columns; contextual modes append
#      diagnostic columns after them)
#   3. Optional visualisation table (--viz_file): rendered gain envelopes,
#      phrase context and per-voice foreground exposure on a 50 Hz grid
#
# Dependencies:
#   pip install numpy soundfile
#   Optional: pip install librosa  (better onset detection)
#   Optional: pip install scipy    (better resampling)
#
# Musical concept:
#   Roles: leader, shadow, resonance, noise_fringe, pulse_carrier,
#          interruption, sustain_bed, contrast_voice, memory_trace, silence
#   States: sparse, balanced, agitated, saturated, suspended, released
#   Behaviors:
#     original      - v3.2 conducting, reproduced exactly
#     responsive    - emphasizes significant gestures, in context
#     complementary - makes room for gestures by adjusting the other voices
#
# Usage:
#   python3 ai_conductor_mix.py manifest descriptors plan.csv done.txt
#       --result_wav out.wav --behavior complementary --imem_tau 4
#       --ctx_strength 0.5 --phrase 1 --spatial chamber
#
# Changelog v3.3:
#   - Added Interpretive Memory (time-based, per voice, from committed gains)
#   - Added Responsive Conductor
#   - Added Complementary Conductor
#   - Added phrase-aware contextual decisions (bounded 1.5 s source lookahead)
#   - Added optional fixed chamber positioning
#   - Polyphony counted as distinct active sources in contextual modes
#   - Added neutral-intervention ("preserve") decisions
#   - Extended visualisation table and plan diagnostics
#   - Original Conductor (v3.2) path unchanged; default CLI = v3.2 output
#   - Fix: joint decision groups no longer hide segment starts; plan rows
#     are cut at every segment boundary, with an exact-sample coverage
#     check logged on every contextual run
#   - Role column stays the analytic role. Two separate indicators:
#     gain_emphasized (committed offsets put the voice clearly ahead) and
#     level_foreground (source RMS + applied gain >= 3 dB above the rest;
#     an estimate, not a perceptual loudness model)
#   - Overlap search is exact for any segment overlap; an unintended
#     coverage gap is now an error and no result is written
#
# ============================================================

import argparse
import csv
import math
import os
import sys
import traceback
from collections import Counter

import numpy as np
import soundfile as sf

# ── Optional librosa for onset detection ──────────────────────────────────────
try:
    import librosa
    HAS_LIBROSA = True
except ImportError:
    HAS_LIBROSA = False

# Optional SciPy: preferred high-quality resampling.
try:
    from scipy import signal as scipy_signal
    HAS_SCIPY = True
except ImportError:
    scipy_signal = None
    HAS_SCIPY = False

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS / LABELS
# ─────────────────────────────────────────────────────────────────────────────

ROLES = [
    "leader", "shadow", "resonance", "noise_fringe",
    "pulse_carrier", "interruption", "sustain_bed",
    "contrast_voice", "memory_trace", "silence"
]

STATES = ["sparse", "balanced", "agitated", "saturated", "suspended", "released"]

N_ROLES  = len(ROLES)
N_STATES = len(STATES)

DESC_DIM = 10


# ─────────────────────────────────────────────────────────────────────────────
# AUDIO ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────

def _analysis_mono(audio_2d):
    """Mono analysis signal with anti-phase cancellation protection.

    A straight channel mean is normally appropriate, but a stereo pair can be
    nearly anti-phase. In that case the mean can approach silence and corrupt
    every descriptor, so use the strongest individual channel instead.
    """
    audio_2d = np.asarray(audio_2d, dtype=np.float64)
    if audio_2d.shape[1] == 1:
        return audio_2d[:, 0].astype(np.float32), "mono"
    mean = audio_2d.mean(axis=1)
    ch_rms = np.sqrt(np.mean(audio_2d ** 2, axis=0) + 1e-20)
    mean_rms = float(np.sqrt(np.mean(mean ** 2) + 1e-20))
    strongest = int(np.argmax(ch_rms))
    if ch_rms[strongest] > 1e-9 and mean_rms < 0.20 * float(ch_rms[strongest]):
        return audio_2d[:, strongest].astype(np.float32), f"channel_{strongest+1}_anti_phase_safe"
    return mean.astype(np.float32), "mean"


def load_audio_mono(path: str) -> tuple:
    audio, sr = sf.read(path, always_2d=True)
    mono, mix_mode = _analysis_mono(audio)
    return mono, sr, mix_mode


def _resample_channel(x, sr, target_sr):
    if sr == target_sr or len(x) == 0:
        return np.asarray(x, dtype=np.float64)
    if HAS_SCIPY:
        g = math.gcd(int(sr), int(target_sr))
        return scipy_signal.resample_poly(x, target_sr // g, sr // g).astype(np.float64)
    if HAS_LIBROSA:
        return librosa.resample(np.asarray(x, dtype=np.float64),
                                orig_sr=sr, target_sr=target_sr).astype(np.float64)
    # Last-resort dependency-free interpolation.
    new_len = max(1, int(round(len(x) * target_sr / sr)))
    old_pos = np.arange(len(x), dtype=np.float64)
    new_pos = np.linspace(0.0, max(len(x) - 1, 0), new_len)
    return np.interp(new_pos, old_pos, x).astype(np.float64)


def load_audio_stereo(path: str, target_sr: int) -> tuple:
    """Load all source channels and fold to stereo at target_sr.

    Mono is duplicated; stereo is preserved; >2 channels are folded by
    alternating channels so no channel is silently discarded.
    """
    audio, sr = sf.read(path, always_2d=True)
    audio = audio.astype(np.float64)
    n_ch = audio.shape[1]
    if n_ch == 1:
        left = right = audio[:, 0]
    elif n_ch == 2:
        left, right = audio[:, 0], audio[:, 1]
    else:
        left_group = audio[:, 0::2]
        right_group = audio[:, 1::2]
        left = left_group.mean(axis=1)
        right = right_group.mean(axis=1) if right_group.shape[1] else left.copy()
    return _resample_channel(left, sr, target_sr), _resample_channel(right, sr, target_sr)


def segment_fixed(audio, sr, frame_ms, hop_ms):
    frame_n = max(2, int(round(sr * frame_ms / 1000)))
    hop_n   = max(1, int(round(sr * hop_ms  / 1000)))
    n = len(audio)
    if n < 2:
        return []
    segs, t, idx = [], 0, 0
    while t < n:
        end = min(t + frame_n, n)
        if end - t >= 2:
            segs.append({"start_samp": t, "end_samp": end,
                         "start_sec": t / sr, "dur_sec": (end-t) / sr, "idx": idx})
            idx += 1
        if end >= n:
            break
        t += hop_n
    return segs


def segment_onset(audio, sr, min_gap_ms):
    n = len(audio)
    if n < 2:
        return []
    if HAS_LIBROSA and n >= 2048:
        onsets = librosa.onset.onset_detect(
            y=audio, sr=sr, units="samples", backtrack=True, delta=0.1)
    else:
        hop = max(8, min(int(sr * 0.01), max(8, n // 4)))
        n_frames = n // hop
        if n_frames < 2:
            onsets = np.array([], dtype=int)
        else:
            usable = n_frames * hop
            frames = audio[:usable].reshape(n_frames, hop)
            energy = np.sum(frames ** 2, axis=1)
            diff   = np.diff(energy, prepend=energy[0])
            thresh = diff.mean() + diff.std() * 1.5
            onsets = (np.where(diff > thresh)[0] * hop).astype(int)

    min_gap_samp = max(1, int(sr * min_gap_ms / 1000))
    # Always cover the beginning of the source: onset detectors need not return 0.
    filtered, last = [0], 0
    for o in np.asarray(onsets, dtype=int):
        o = int(np.clip(o, 0, n - 1))
        if o > 0 and o - last >= min_gap_samp:
            filtered.append(o); last = o

    segs = []
    for i, seg_start in enumerate(filtered):
        seg_end = filtered[i + 1] if i + 1 < len(filtered) else n
        if seg_end - seg_start >= 2:
            segs.append({"start_samp": seg_start, "end_samp": seg_end,
                         "start_sec": seg_start / sr,
                         "dur_sec": (seg_end-seg_start) / sr, "idx": i})
    return segs

def segment_hybrid(audio, sr, frame_ms, hop_ms, min_gap_ms):
    onset_segs = segment_onset(audio, sr, min_gap_ms)
    fixed_segs = segment_fixed(audio, sr, frame_ms, hop_ms)
    hybrid, idx = [], 0
    for os_seg in onset_segs:
        if os_seg["dur_sec"] > frame_ms / 1000 * 3:
            sub = segment_fixed(
                audio[os_seg["start_samp"]:os_seg["end_samp"]], sr,
                frame_ms, hop_ms)
            for s in sub:
                s["start_samp"] += os_seg["start_samp"]
                s["end_samp"]   += os_seg["start_samp"]
                s["start_sec"]   = s["start_samp"] / sr
                s["idx"] = idx; hybrid.append(s); idx += 1
        else:
            os_seg["idx"] = idx; hybrid.append(os_seg); idx += 1
    return hybrid if hybrid else fixed_segs


def extract_descriptors(audio, sr, segs):
    """Extract comparable segment descriptors on a fixed spectral grid.

    Onset segments can differ greatly in duration. Using each segment's native
    FFT size makes spectral flux and cepstral measures incomparable, and very
    long segments can allocate huge autocorrelation FFTs. We therefore average
    a few 4096-sample views on one fixed grid and cap the pitch-analysis view.
    """
    descs = np.zeros((len(segs), DESC_DIM), dtype=np.float32)
    eps = 1e-12; prev_mag = None
    spec_n = 4096
    freqs = np.fft.rfftfreq(spec_n, d=1.0 / sr)

    for i, seg in enumerate(segs):
        chunk = np.asarray(audio[seg["start_samp"]:seg["end_samp"]], dtype=np.float64)
        if len(chunk) < 2:
            continue
        n = len(chunk)

        view_n = min(spec_n, n)
        n_views = min(8, max(1, int(math.ceil(n / max(view_n, 1)))))
        starts = np.linspace(0, max(0, n-view_n), n_views).astype(int)
        specs = []
        for st in starts:
            view = chunk[st:st+view_n]
            win = view * np.hanning(len(view))
            specs.append(np.abs(np.fft.rfft(win, n=spec_n)))
        spec = np.mean(specs, axis=0)

        rms = float(np.sqrt(np.mean(chunk ** 2)))
        zcr = float(np.mean(np.abs(np.diff(np.signbit(chunk))).astype(float)))
        spec_sum = spec.sum() + eps
        centroid = float(np.sum(freqs * spec) / spec_sum)
        bandwidth = float(np.sqrt(np.sum(((freqs - centroid)**2) * spec) / spec_sum))

        norm_spec = spec / spec_sum
        if prev_mag is None:
            flux = 0.0
        else:
            flux = float(np.sum(np.maximum(norm_spec - prev_mag, 0.0)))
        prev_mag = norm_spec.copy()

        roughness = float(spec[freqs > 3000].sum() / spec_sum)

        pitch_cap = min(n, max(256, int(sr * 2.0)))
        if n > pitch_cap:
            # Use the highest-RMS of a few candidate windows rather than the attack only.
            cand_starts = np.linspace(0, n-pitch_cap, min(7, max(2, n//pitch_cap+1))).astype(int)
            st = max(cand_starts, key=lambda q: float(np.mean(chunk[q:q+pitch_cap]**2)))
            pitch_view = chunk[st:st+pitch_cap]
        else:
            pitch_view = chunk
        pn = len(pitch_view)
        n_fft = 1 << max(1, (2 * pn - 1).bit_length())
        X = np.fft.rfft(pitch_view, n=n_fft)
        acorr = np.fft.irfft(X * np.conj(X))[:pn]
        lo_lag, hi_lag = max(1, sr // 500), min(pn - 1, sr // 50)
        pitch_salience = float(acorr[lo_lag:hi_lag].max() / acorr[0]) \
            if hi_lag > lo_lag and acorr[0] > eps else 0.0

        log_spec = np.log(spec + eps)
        ceps = np.abs(np.fft.irfft(log_spec, n=spec_n))
        q_lo, q_hi = max(1, int(sr / 500)), min(len(ceps) - 1, int(sr / 50))
        hnr_proxy = float(ceps[q_lo:q_hi].max() / (np.abs(ceps).mean() + eps)) \
            if q_hi > q_lo and len(ceps) > 10 else 0.0

        attack_n = max(2, min(n-1, n // 5))
        tail = chunk[attack_n:] if attack_n < n else chunk[-1:]
        attack_slope = float(
            np.sqrt(np.mean(chunk[:attack_n]**2) + eps) /
            (np.sqrt(np.mean(tail**2) + eps) + eps) - 1.0)

        blk = 32
        if n >= blk * 2:
            n_blks = n // blk
            frame_e = np.mean(chunk[:n_blks*blk].reshape(n_blks, blk)**2, axis=1)
            stab = 1.0 - min(1.0, float(frame_e.std() / (frame_e.mean() + eps))) \
                if frame_e.mean() > eps else 1.0
        else:
            stab = 1.0

        descs[i] = [rms, zcr, centroid, bandwidth, flux, roughness,
                    pitch_salience, hnr_proxy, attack_slope, stab]
    return descs



def read_macro_descriptors(path):
    """Read the Praat-side per-file descriptors. Returns index->dict."""
    out = {}
    if not path or not os.path.isfile(path):
        return out
    try:
        with open(path, "r", encoding="utf-8") as f:
            r = csv.DictReader(f, delimiter="\t")
            for row in r:
                try:
                    idx = int(row.get("file_index", 0))
                except (TypeError, ValueError):
                    continue
                vals = {}
                for k in ("rms", "mean_pitch_hz", "pitch_range", "mean_intensity_db",
                          "intensity_range_db", "spectral_centroid_est", "harmonicity_hnr"):
                    try:
                        vals[k] = float(row.get(k, "nan"))
                    except (TypeError, ValueError):
                        vals[k] = float("nan")
                out[idx] = vals
    except OSError:
        return {}
    return out


def _normalise_macro(macro_descs, key, default=0.5):
    vals = np.array([d.get(key, np.nan) if d else np.nan for d in macro_descs], dtype=float)
    valid = np.isfinite(vals)
    out = np.full(len(vals), default, dtype=float)
    if valid.any():
        lo, hi = float(np.min(vals[valid])), float(np.max(vals[valid]))
        if hi - lo > 1e-9:
            out[valid] = (vals[valid] - lo) / (hi - lo)
        else:
            out[valid] = 0.5
    return out

# ─────────────────────────────────────────────────────────────────────────────
# CONDUCTOR LOGIC
# ─────────────────────────────────────────────────────────────────────────────

def conduct(file_audios, file_srs, file_names, seg_mode, frame_ms, hop_ms,
            onset_gap_ms, style, memory_weight, tension_sens,
            allow_silence, nonlinear, macro_descs=None,
            behavior="original", imem_tau=4.0, ctx_strength=0.5,
            phrase_aware=True, spatial="role"):
    n_files = len(file_audios)
    memory_weight = float(np.clip(memory_weight, 0.0, 1.0))
    tension_sens = float(np.clip(tension_sens, 0.0, 2.0))

    # ── 1. Segmentation ──────────────────────────────────────────────────────
    print("  Segmenting ensemble...", flush=True)
    all_segs, all_descs = [], []
    for fi, (audio, sr) in enumerate(zip(file_audios, file_srs)):
        if seg_mode == "fixed":
            segs = segment_fixed(audio, sr, frame_ms, hop_ms)
        elif seg_mode == "onset":
            segs = segment_onset(audio, sr, onset_gap_ms)
        else:
            segs = segment_hybrid(audio, sr, frame_ms, hop_ms, onset_gap_ms)
        descs = extract_descriptors(audio, sr, segs)
        all_segs.extend([(fi, s) for s in segs])
        all_descs.append(descs)
        print(f"    File {fi+1} ({file_names[fi]}): {len(segs)} segments", flush=True)

    n_total = len(all_segs)
    if n_total == 0:
        raise RuntimeError("No analysable segments were produced from the ensemble.")
    flat_descs = np.vstack(all_descs)
    max_dur = max(a.shape[0] / sr for a, sr in zip(file_audios, file_srs))

    # ── 2. Normalise ─────────────────────────────────────────────────────────
    col_min = flat_descs.min(axis=0)
    col_range = flat_descs.max(axis=0) - col_min + 1e-12
    flat_norm = (flat_descs - col_min) / col_range

    rms, flux, centroid = flat_norm[:, 0], flat_norm[:, 4], flat_norm[:, 2]
    rough, pitch_s, hnr = flat_norm[:, 5], flat_norm[:, 6], flat_norm[:, 7]
    attack_arr, stab = flat_norm[:, 8], flat_norm[:, 9]

    # Praat-side macro descriptors are deliberately a light prior (15-20%):
    # local segment behaviour remains dominant, but the expensive Pitch/HNR/
    # Spectrum analysis performed by Praat now genuinely informs the conductor.
    macro_descs = macro_descs or [None] * n_files
    if len(macro_descs) < n_files:
        macro_descs = list(macro_descs) + [None] * (n_files-len(macro_descs))
    seg_file_ids = np.array([fi for fi, _ in all_segs], dtype=int)
    m_rms = _normalise_macro(macro_descs, "rms")
    m_int = _normalise_macro(macro_descs, "mean_intensity_db")
    m_cent = _normalise_macro(macro_descs, "spectral_centroid_est")
    m_hnr = _normalise_macro(macro_descs, "harmonicity_hnr")
    m_prange = _normalise_macro(macro_descs, "pitch_range")
    m_irange = _normalise_macro(macro_descs, "intensity_range_db")
    m_pitch_present = np.array([1.0 if d and np.isfinite(d.get("mean_pitch_hz", np.nan))
                                and d.get("mean_pitch_hz", 0.0) > 0 else 0.0
                                for d in macro_descs])

    macro_energy = 0.55*m_rms + 0.45*m_int
    energy_local = np.clip(rms * 0.6 + flux * 0.4, 0, 1)
    energy = np.clip(0.85*energy_local + 0.15*macro_energy[seg_file_ids], 0, 1)
    pitch_s = np.clip(0.85*pitch_s + 0.15*m_pitch_present[seg_file_ids], 0, 1)
    hnr = np.clip(0.82*hnr + 0.18*m_hnr[seg_file_ids], 0, 1)
    noisiness = np.clip((rough + (1 - pitch_s) + (1 - hnr)) / 3, 0, 1)
    bright = np.clip(0.85*centroid + 0.15*m_cent[seg_file_ids], 0, 1)
    macro_var = 0.5*m_prange + 0.5*m_irange
    sharpness = np.clip(0.90*np.clip(attack_arr, 0, 1) + 0.10*macro_var[seg_file_ids], 0, 1)
    stabil = stab

    print(f"    energy: {energy.min():.3f}–{energy.max():.3f} "
          f"| bright: {bright.min():.3f}–{bright.max():.3f} "
          f"| noise: {noisiness.min():.3f}–{noisiness.max():.3f}", flush=True)

    # ── 3. Tension curve ─────────────────────────────────────────────────────
    n_tc = 100; t_ax = np.linspace(0, 1, n_tc)
    if style == "dramatic":
        tension_curve = (0.6 * np.sin(t_ax * np.pi) ** 1.5
                         + 0.25 * np.sin(t_ax * 3 * np.pi)
                         + 0.15 * np.clip(np.sin((t_ax - 0.8) * 5 * np.pi), 0, 1))
    elif style == "minimal":
        tension_curve = 0.2 + 0.3 * np.sin(t_ax * np.pi)
    elif style == "dense":
        tension_curve = 0.7 + 0.25 * np.sin(t_ax * 4 * np.pi)
    else:
        tension_curve = 0.4 + 0.2 * np.sin(t_ax * np.pi)
    tension_curve = np.clip(tension_curve, 0, 1)

    def get_tension(t_norm):
        return float(tension_curve[int(np.clip(t_norm * (n_tc-1), 0, n_tc-1))])

    # ── 4. Role scoring ──────────────────────────────────────────────────────
    print("  Assigning roles...", flush=True)
    def rank_norm(arr):
        """Tie-aware percentile rank. Equal descriptors must remain equal.

        The old argsort-based ranking assigned 0..1 by segment order even when
        every value was identical, inventing musical distinctions from ties.
        """
        x = np.asarray(arr, dtype=float)
        n = len(x)
        if n == 0:
            return np.zeros(0, dtype=float)
        if n == 1:
            return np.full(1, 0.5, dtype=float)
        vals, inv, counts = np.unique(x, return_inverse=True, return_counts=True)
        if len(vals) == 1:
            return np.full(n, 0.5, dtype=float)
        starts = np.cumsum(np.r_[0, counts[:-1]])
        avg_rank = starts + (counts - 1) / 2.0
        return avg_rank[inv] / (n - 1)

    rn = {k: rank_norm(v) for k, v in [
        ("energy", energy), ("bright", bright), ("noise", noisiness),
        ("stab", stabil), ("attack", sharpness), ("hnr", hnr),
        ("flux", flux), ("pitch", pitch_s)]}

    STYLE_W = {
        "neutral":  [1.0, 0.8, 0.9, 0.7, 0.9, 0.7, 0.9, 0.9, 0.8, 0.4],
        "dramatic": [1.4, 0.8, 0.9, 0.6, 0.9, 0.9, 0.8, 1.0, 0.7, 0.3],
        "minimal":  [0.8, 0.7, 1.1, 0.5, 0.6, 0.4, 1.2, 0.8, 1.1, 0.8],
        "dense":    [1.0, 0.8, 1.1, 1.0, 1.2, 0.9, 1.0, 1.1, 0.6, 0.1],
    }
    sw = np.array(STYLE_W.get(style, STYLE_W["neutral"]))

    scores = np.column_stack([
        rn["energy"]*0.7 + rn["bright"]*0.3,
        (1-rn["energy"])*0.4 + rn["stab"]*0.6,
        rn["hnr"]*0.5 + rn["stab"]*0.3 + (1-rn["noise"])*0.2,
        rn["noise"]*0.6 + (1-rn["pitch"])*0.4,
        rn["attack"]*0.5 + rn["energy"]*0.3 + rn["stab"]*0.2,
        rn["energy"]*0.5 + rn["flux"]*0.3 + rn["attack"]*0.2,
        rn["stab"]*0.5 + (1-rn["energy"])*0.3 + (1-rn["flux"])*0.2,
        rn["bright"]*0.5 + rn["pitch"]*0.3 + (1-rn["noise"])*0.2,
        (1-rn["energy"])*0.5 + rn["stab"]*0.3 + (1-rn["flux"])*0.2,
        (1-rn["energy"])*0.8 + (1-rn["flux"])*0.2,
    ]) * sw

    if not allow_silence:
        scores[:, ROLES.index("silence")] = -1.0

    role_ids  = scores.argmax(axis=1).astype(int)
    # v3.3: snapshot of the baseline role decision (read only by the
    # contextual modes; the legacy path never uses it).
    role_base = role_ids.copy()
    past_e_vals = np.zeros(n_total, dtype=float)
    state_ids = np.zeros(n_total, dtype=int)
    prom_vals = np.zeros(n_total, dtype=float)
    tension_vals = np.zeros(n_total, dtype=float)

    # ── 5. Temporal post-pass ────────────────────────────────────────────────
    sorted_gi = sorted(range(n_total), key=lambda i: all_segs[i][1]["start_sec"])
    last_leader_end, last_file_leader = -999.0, -1
    memory_energy = float(np.mean(energy))
    e_med = float(np.median(energy))

    for gi in sorted_gi:
        fi, seg = all_segs[gi]
        t_norm  = seg["start_sec"] / (max_dur + 1e-9)
        base_tension = get_tension(t_norm)
        e, s    = float(energy[gi]), float(stabil[gi])
        seg_start, seg_end = seg["start_sec"], seg["start_sec"] + seg["dur_sec"]

        # React to contrast against PAST energy, then update memory afterwards.
        # v3.0 updated memory first and never used tension_sens at all.
        past_energy = memory_energy
        past_e_vals[gi] = past_energy
        contrast = abs(e - past_energy)
        sens = float(np.clip(tension_sens, 0.0, 2.0))
        tension = float(np.clip(base_tension + 0.55 * sens * contrast, 0.0, 1.0))
        prom = float(np.clip(rn["energy"][gi] * (0.4 + 0.6*tension) + rn["stab"][gi]*0.2, 0, 1))
        prom_vals[gi] = prom
        tension_vals[gi] = tension

        if tension > 0.75:
            st = STATES.index("agitated") if e > e_med else STATES.index("saturated")
        elif tension > 0.5:
            st = STATES.index("balanced") if s > 0.5 else STATES.index("saturated")
        elif tension > 0.25:
            st = STATES.index("sparse") if e < e_med else STATES.index("balanced")
        else:
            st = STATES.index("suspended") if s > 0.5 else STATES.index("released")
        state_ids[gi] = st

        if ROLES[role_ids[gi]] == "leader":
            gap_needed = 2.0 / (tension + 0.2)
            if seg_start < last_leader_end + gap_needed or fi == last_file_leader:
                row = scores[gi].copy(); row[ROLES.index("leader")] = -1.0
                role_ids[gi] = int(row.argmax())
            else:
                last_leader_end, last_file_leader = seg_end, fi

        if (nonlinear and float(rn["energy"][gi]) > 0.90
                and past_energy < float(np.percentile(energy, 20))
                and tension > 0.6
                and ROLES[role_ids[gi]] not in ["leader", "interruption"]):
            role_ids[gi] = ROLES.index("interruption")

        memory_energy = past_energy * (1 - memory_weight) + e * memory_weight

    # ── v3.3 branch: contextual behaviours leave here. Everything below this
    #    point is the untouched v3.2 decision chain (Original Conductor).
    if behavior in ("responsive", "complementary"):
        base_pans = ({fi: -1.0 + 2.0*fi/(n_files-1) for fi in range(n_files)}
                     if n_files > 1 else {0: 0.0})
        return conduct_contextual(dict(
            behavior=behavior, imem_tau=float(imem_tau),
            ctx_strength=float(np.clip(ctx_strength, 0.0, 1.0)),
            phrase_aware=bool(phrase_aware), spatial=spatial, style=style,
            n_files=n_files, file_audios=file_audios, file_srs=file_srs,
            file_names=file_names, all_segs=all_segs, sorted_gi=sorted_gi,
            max_dur=max_dur, energy=energy, stabil=stabil, centroid=centroid,
            rms_raw=flat_descs[:, 0].astype(float), rn=rn, scores=scores,
            cent_hz=flat_descs[:, 2].astype(float),
            role_base=role_base, allow_silence=bool(allow_silence),
            nonlinear=bool(nonlinear), past_e_vals=past_e_vals,
            tension_vals=tension_vals, prom_vals=prom_vals, e_med=e_med,
            energy_all=energy, base_pans=base_pans))

    # ── 6a. Foreground guarantee ─────────────────────────────────────────────
    FOREGROUND = {"leader", "contrast_voice", "interruption", "pulse_carrier"}
    for fi in range(n_files):
        file_gis = [gi for gi in sorted_gi if all_segs[gi][0] == fi]
        if file_gis and not any(ROLES[role_ids[gi]] in FOREGROUND for gi in file_gis):
            best = max(file_gis, key=lambda g: float(energy[g]))
            role_ids[best] = ROLES.index("leader")
            prom_vals[best] = max(prom_vals[best], 0.65)

    # ── 6b. Masking awareness ────────────────────────────────────────────────
    seg_intervals = [(all_segs[gi][1]["start_sec"],
                      all_segs[gi][1]["start_sec"] + all_segs[gi][1]["dur_sec"], gi)
                     for gi in sorted_gi]
    for idx_a, (st_a, en_a, gi_a) in enumerate(seg_intervals):
        if ROLES[role_ids[gi_a]] in ["silence", "leader", "interruption"]:
            continue
        fi_a = all_segs[gi_a][0]
        for idx_b in range(idx_a + 1, len(seg_intervals)):
            st_b, en_b, gi_b = seg_intervals[idx_b]
            if st_b >= en_a: break
            if all_segs[gi_b][0] == fi_a: continue
            if min(en_a, en_b) - max(st_a, st_b) > 0.05:
                cd = abs(centroid[gi_a] - centroid[gi_b])
                mr = float(np.exp(-cd*4) * (rms[gi_a] + rms[gi_b]))
                if mr > 0.55 and prom_vals[gi_a] < prom_vals[gi_b]:
                    if ROLES[role_ids[gi_a]] not in ["sustain_bed", "shadow", "memory_trace"]:
                        role_ids[gi_a] = ROLES.index("shadow")
                        prom_vals[gi_a] *= 0.65

    # ── 6c. Role diversity cap ───────────────────────────────────────────────
    max_per_role = max(2, int(n_total * 0.35))
    rc = np.bincount(role_ids, minlength=N_ROLES)
    for rid in range(N_ROLES):
        if ROLES[rid] == "silence": continue
        while rc[rid] > max_per_role:
            cands = [gi for gi in sorted_gi if role_ids[gi] == rid]
            if not cands: break
            w = min(cands, key=lambda g: prom_vals[g])
            row = scores[w].copy(); row[rid] = -1.0
            if not allow_silence: row[ROLES.index("silence")] = -1.0
            nr = int(row.argmax()); role_ids[w] = nr; rc[rid] -= 1; rc[nr] += 1

    print(f"    Roles: {dict(Counter(ROLES[r] for r in role_ids))}", flush=True)

    # ── 7. Gain / Pan / Polyphony ────────────────────────────────────────────
    ROLE_GAIN = {"leader": 0.90, "shadow": 0.45, "resonance": 0.60,
                 "noise_fringe": 0.35, "pulse_carrier": 0.70,
                 "interruption": 0.88, "sustain_bed": 0.40,
                 "contrast_voice": 0.75, "memory_trace": 0.30, "silence": 0.0}
    base_pans = ({fi: -1.0 + 2.0*fi/(n_files-1) for fi in range(n_files)}
                 if n_files > 1 else {0: 0.0})
    ROLE_PAN = {"leader": 0.3, "shadow": 1.0, "resonance": 0.8,
                "noise_fringe": 1.2, "pulse_carrier": 0.6,
                "interruption": 0.1, "sustain_bed": 0.9,
                "contrast_voice": 1.1, "memory_trace": 0.7, "silence": 0.0}

    active_gi = [gi for gi in sorted_gi if ROLES[role_ids[gi]] != "silence"]
    intervals = [(all_segs[gi][1]["start_sec"],
                  all_segs[gi][1]["start_sec"]+all_segs[gi][1]["dur_sec"], gi)
                 for gi in active_gi]
    poly_count = {}
    for ia, (sa, ea, ga) in enumerate(intervals):
        mid_a = (sa + ea) * 0.5
        count = sum(1 for (sb, eb, _) in intervals if sb <= mid_a < eb)
        poly_count[ga] = max(1, count)
    max_poly = max(poly_count.values()) if poly_count else 1
    print(f"    Peak polyphony: {max_poly}", flush=True)

    # ── 8. Build plan ────────────────────────────────────────────────────────
    print("  Assembling mix plan...", flush=True)
    plan_rows = []
    for gi in sorted_gi:
        fi, seg = all_segs[gi]
        rl = ROLES[role_ids[gi]]
        if rl == "silence": continue

        gain = ROLE_GAIN[rl] * (0.5 + 0.5 * float(prom_vals[gi]))
        nv = poly_count.get(gi, 1)
        if nv > 2:
            ps = 2.0 / nv
            if rl in ("leader", "interruption"): ps = min(1.0, ps * 1.5)
            gain *= ps
        gain = round(float(np.clip(gain, 0.05, 1.0)), 4)

        pv = round(float(base_pans[fi] * ROLE_PAN.get(rl, 1.0)), 4)
        pv = max(-1.0, min(1.0, pv))

        fade = max(0.003, min(0.008, seg["dur_sec"] * 0.10))

        plan_rows.append({
            "time": round(seg["start_sec"], 4),
            "file_index": fi + 1, "file_index0": fi,
            "file_name": file_names[fi], "seg_index": seg["idx"],
            "src_start": round(seg["start_sec"], 4),
            "src_dur": round(seg["dur_sec"], 4),
            # Exact sample positions for click-free rendering
            "src_start_samp": seg["start_samp"],
            "src_end_samp":   seg["end_samp"],
            "src_sr":         file_srs[fi],
            "gain": gain, "role": rl,
            "layer_group": 0 if rl in ["leader","interruption","contrast_voice"]
                           else 1 if rl in ["pulse_carrier","resonance","shadow"]
                           else 2,
            "entry_time": round(seg["start_sec"], 4),
            "exit_time": round(seg["start_sec"]+seg["dur_sec"], 4),
            "transform": round(float(1.0-prom_vals[gi])*0.4, 3),
            "state": STATES[state_ids[gi]],
            "density": round(gain/0.9, 3),
            "priority": round(float(prom_vals[gi]), 4),
            "pan": pv, "fade": round(fade, 6),
            "tension": round(float(tension_vals[gi]), 4),
            "polyphony": int(nv),
        })

    plan_rows.sort(key=lambda r: (r["entry_time"], -r["priority"]))
    if spatial == "chamber":
        cpos = chamber_positions(n_files)
        for r in plan_rows:
            r["pan"] = cpos[r["file_index0"]]
        print("    Spatial: fixed chamber positions", flush=True)
    print(f"  Plan: {len(plan_rows)} events", flush=True)
    return plan_rows, max_dur


# ─────────────────────────────────────────────────────────────────────────────
# v3.3 CONTEXTUAL CONDUCTING (Responsive / Complementary)
#
# Pipeline:  baseline role scores (shared with v3.2) → phrase context
#   (source-only, bounded lookahead) → decision groups on a common time grid
#   → per group: evaluate every active voice against ONE memory snapshot →
#   coordinated gain offsets → commit → update Interpretive Memory from the
#   committed gains → non-overlapping per-voice plan rows → v3.2 renderer.
#
# Because each group's gains are final when committed (no later foreground,
# masking or diversity post-pass rewrites them), the memory is always fed by
# decisions that actually reach the renderer.
# ─────────────────────────────────────────────────────────────────────────────

PHRASE_LABELS = ["continuing", "building", "contrasting", "releasing"]
DECISIONS = ["preserve", "emphasize", "withdraw"]

# State → small parameter set inside the shared mechanism (Sec. 8).
#   contrast: scales the size of offsets      slew: scales dB/s rate limit
#   relax:    seconds for offsets to relax    comp: penalty on secondary boosts
STATE_PARAMS = {
    "sparse":    dict(contrast=0.85, slew=1.0, relax=3.0, comp=1.4),
    "balanced":  dict(contrast=0.90, slew=1.0, relax=3.0, comp=1.0),
    "agitated":  dict(contrast=1.25, slew=1.4, relax=2.5, comp=0.9),
    "saturated": dict(contrast=0.75, slew=1.0, relax=2.0, comp=1.8),
    "suspended": dict(contrast=0.70, slew=0.5, relax=4.0, comp=1.0),
    "released":  dict(contrast=0.60, slew=0.8, relax=1.2, comp=1.0),
}
# Phrase context → response strength, leadership persistence, relax factor.
PHRASE_PARAMS = {
    "continuing":  dict(resp=0.85, persist=0.12, relax=1.0),
    "building":    dict(resp=1.00, persist=0.10, relax=1.0),
    "contrasting": dict(resp=1.20, persist=0.04, relax=0.8),
    "releasing":   dict(resp=0.70, persist=0.08, relax=0.6),
}
PHRASE_OFF = dict(resp=1.0, persist=0.08, relax=1.0)
STYLE_SCALE = {"dramatic": 1.2, "minimal": 0.75, "dense": 0.9, "neutral": 1.0}

BEHAVIOR_PARAMS = {
    # slew dB/s, max boost/cut dB, memory weight in priority (direction),
    # memory modulation of emphasis size (how much history scales a response)
    "responsive":    dict(slew=14.0, boost=3.5, cut=5.0, mem_w=0.15, mem_mod=0.45),
    "complementary": dict(slew=7.0,  boost=1.0, cut=4.5, mem_w=0.10, mem_mod=0.35),
}

CTX_G0 = 0.70          # neutral reference gain (offset 0 dB)
EV_DECAY_S = 0.6       # how long an onset keeps counting as a live gesture
GROUP_WIN_S = 0.04     # onsets closer than this are decided jointly
TICK_S = 0.5           # longest interval between decisions
LOOKAHEAD_S = 1.5      # bounded source-analysis lookahead
PHRASE_HOP = 0.05


def chamber_positions(n_files):
    """Stable, restrained stereo layout (independent of roles and gain)."""
    if n_files <= 1:
        return {0: 0.0}
    width = 0.5 if n_files == 2 else (0.6 if n_files == 3 else 0.7)
    return {fi: round(-width + 2.0 * width * fi / (n_files - 1), 4)
            for fi in range(n_files)}


def polyphony_distinct(active_files):
    """Contextual polyphony: one voice per source file, however its
    segmentation windows overlap."""
    return max(1, len(set(active_files)))


class InterpretiveMemory:
    """Per-voice record of what the conductor actually did.

    All quantities decay with elapsed TIME (not segment count):
        m(t+Δ) = a·m(t) + (1-a)·u,   a = exp(-Δ/τ)
    exposure    recent foreground exposure (u from committed gain + level)
    avg_gain    recent average realised (commanded) gain
    atten       recent fraction of time held > 3 dB under the ensemble
    since_fg    seconds since the voice last held the foreground
    trans       decaying count of foreground/background flips
    offset_db   current committed offset (continuity state)
    """

    def __init__(self, n_files, tau):
        self.n = n_files
        self.tau = max(0.25, float(tau))
        self.exposure = np.zeros(n_files)
        self.avg_gain = np.zeros(n_files)
        self.atten = np.zeros(n_files)
        self.since_fg = np.full(n_files, 1e3)
        self.trans = np.zeros(n_files)
        self.was_fg = np.zeros(n_files, dtype=bool)
        self.offset_db = np.zeros(n_files)
        self.prev_fg_count = 0

    def snapshot(self):
        return dict(exposure=self.exposure.copy(), since_fg=self.since_fg.copy(),
                    trans_rate=self.trans / self.tau, offset_db=self.offset_db.copy(),
                    atten=self.atten.copy(), avg_gain=self.avg_gain.copy(),
                    prev_fg_count=self.prev_fg_count)


def update_interpretive_memory(mem, dt, gains, levels_db, active):
    """Commit one group's decisions into memory. gains/levels per file;
    active: bool array (voice sounding with gain > 0 in this group)."""
    dt = max(0.0, float(dt))
    a = math.exp(-dt / mem.tau)
    idx = np.where(active)[0]
    u = np.zeros(mem.n)
    below = np.zeros(mem.n)
    if len(idx) == 1:
        u[idx] = 0.75                         # a solo voice is the foreground
    elif len(idx) >= 2:
        gdb = 20.0 * np.log10(np.maximum(gains[idx], 1e-6))
        lv = levels_db[idx]
        rel_g = gdb - gdb.mean()
        rel_l = lv - lv.mean()
        u[idx] = np.clip(0.5 + 0.6 * rel_g / 6.0 + 0.4 * rel_l / 12.0, 0.0, 1.0)
        below[idx] = (rel_g < -3.0).astype(float)
    mem.exposure = a * mem.exposure + (1 - a) * u
    mem.avg_gain = a * mem.avg_gain + (1 - a) * np.where(active, gains, 0.0)
    mem.atten = a * mem.atten + (1 - a) * below
    fg = u > 0.65
    flips = (fg != mem.was_fg).astype(float)
    mem.trans = a * mem.trans + flips
    mem.since_fg = np.where(fg, 0.0, mem.since_fg + dt)
    mem.was_fg = fg
    mem.prev_fg_count = int(fg.sum())


def _segment_onset_strength(all_segs, rn, energy, stabil, file_audios, file_srs):
    """Source-only significance of each segment's onset (0..1).

    Dominated by the local level jump at the onset, measured on the audio
    (100 ms after vs 200 ms before). Segment-averaged descriptors cannot see
    this: a segment holding a pluck plus its decay has the same mean energy
    as the next one. Helped by attack/flux and by a calm preceding segment
    (a strong onset interrupting a stable texture). Damped when the same
    voice has re-triggered within the last 0.5 s: a voice whose detector
    fires every 100 ms (vibrato, tremolo, dense runs) is continuing, not
    introducing a new gesture each time."""
    n = len(all_segs)
    os_ = np.zeros(n)
    post_db = np.full(n, -180.0)
    by_file = {}
    for gi, (fi, seg) in enumerate(all_segs):
        by_file.setdefault(fi, []).append(gi)
    for fi, gis in by_file.items():
        gis = sorted(gis, key=lambda g: (all_segs[g][1]["start_samp"], g))
        prev = None
        for g in gis:
            a = file_audios[fi]; sr = file_srs[fi]
            st = all_segs[g][1]["start_samp"]
            pre = np.asarray(a[max(0, st - int(0.2 * sr)):st], dtype=np.float64)
            post = np.asarray(a[st:st + int(0.1 * sr)], dtype=np.float64)
            pre_rms = float(np.sqrt(np.mean(pre ** 2))) if len(pre) else 0.0
            post_rms = float(np.sqrt(np.mean(post ** 2))) if len(post) else 0.0
            jump_db = 20.0 * math.log10((post_rms + 1e-5) / (pre_rms + 1e-5))
            rise = float(np.clip((jump_db - 3.0) / 15.0, 0, 1))
            if prev is None:
                calm, gap = 0.0, 1.0
            else:
                calm = float(stabil[prev])
                gap = all_segs[g][1]["start_sec"] - all_segs[prev][1]["start_sec"]
            raw = (0.15 * rn["attack"][g] + 0.10 * rn["flux"][g]
                   + 0.75 * rise + 0.10 * calm * rise)
            density = float(np.clip(gap / 0.5, 0.25, 1.0))
            os_[g] = float(np.clip(raw * density, 0, 1))
            post_db[g] = 20.0 * math.log10(post_rms + 1e-9)
            prev = g
    return os_, post_db


def estimate_phrase_context(file_audios, file_srs, all_segs, onset_str, max_dur,
                            hop=PHRASE_HOP):
    """Lightweight phrase awareness from source analysis only.

    Returns grid times, context code per grid point, boundary list
    [(time, weight, kind)] and a confidence in [0,1]. Boundaries are
    estimates; with no reliable evidence every point is 'continuing' and
    confidence is low, so the context collapses to neutral parameters.
    """
    n_grid = max(2, int(math.ceil(max_dur / hop)) + 1)
    t_grid = np.arange(n_grid) * hop
    n_files = len(file_audios)
    pow_mat = np.zeros((n_files, n_grid))
    for fi, (a, sr) in enumerate(zip(file_audios, file_srs)):
        win = max(2, int(0.1 * sr)); hp = hop * sr
        for k in range(n_grid):
            c = int(round(k * hp)); lo = max(0, c - win // 2); hi = min(len(a), c + win // 2)
            if hi > lo:
                pow_mat[fi, k] = float(np.mean(np.asarray(a[lo:hi], dtype=np.float64) ** 2))
    ens_db = 10 * np.log10(pow_mat.mean(axis=0) + 1e-12)
    ref = np.percentile(ens_db, 95)
    ens_db = ens_db - ref
    file_db = 10 * np.log10(pow_mat + 1e-12)
    file_ref = np.percentile(file_db, 95, axis=1, keepdims=True)
    active = file_db > (file_ref - 30.0)
    n_active = active.sum(axis=0)

    # onset density per second (all voices) in ±1.5 s windows
    on_times = np.array([seg["start_sec"] for _, seg in all_segs])
    on_strong = np.array(onset_str)
    def dens(lo, hi):
        m = (on_times >= lo) & (on_times < hi)
        return m.sum() / max(hi - lo, 1e-6)
    mean_dens = len(on_times) / max(max_dur, 1e-6)

    cands = []
    # (a) significant pauses: ensemble < -30 dB for >= 0.25 s
    quiet = ens_db < -30.0
    k = 0
    pauses = []
    while k < n_grid:
        if quiet[k]:
            j = k
            while j + 1 < n_grid and quiet[j + 1]:
                j += 1
            if (j - k + 1) * hop >= 0.25 and k * hop > 0.5:
                pauses.append((k * hop, j * hop))
                if (j + 1) * hop < max_dur - 0.5:
                    cands.append(((j + 1) * hop, 1.0, "pause"))
            k = j + 1
        else:
            k += 1
    # (b) simultaneous drop in activity (half or more of the voices stop)
    if n_files >= 2:
        need = max(1, int(math.ceil(n_files / 2)))
        L = int(round(0.3 / hop))
        for k in range(L, n_grid - L):
            if ((n_active[k - L:k].min() - n_active[k:k + L].max()) >= need
                    and n_active[k + L:].max(initial=0) >= need):   # something follows
                cands.append((k * hop, 0.6, "drop"))
    # (c) density change and (d) strong event after a stable passage
    for t0, s in zip(on_times, on_strong):
        if t0 < 1.0 or t0 > max_dur - 0.5:
            continue
        d_before, d_after = dens(t0 - 1.5, t0), dens(t0, t0 + 1.5)
        if abs(d_after - d_before) > max(2.0, 0.8 * mean_dens):
            cands.append((t0, 0.55, "density"))
        if s >= 0.75 and d_before < 0.5 * max(mean_dens, 1e-6):
            cands.append((t0, 0.8, "contrast"))

    # merge within 1 s (keep the strongest, earliest on ties), min 1.5 s apart
    cands.sort(key=lambda c: (c[0], -c[1]))
    merged = []
    for c in cands:
        if merged and c[0] - merged[-1][0] < 1.0:
            if c[1] > merged[-1][1]:
                merged[-1] = c
        else:
            merged.append(c)
    bounds = []
    for c in merged:
        if c[1] >= 0.55 and (not bounds or c[0] - bounds[-1][0] >= 1.5):
            bounds.append(c)

    confidence = 0.0 if (max_dur < 3.0 or not bounds) else \
        min(1.0, 0.3 + 0.2 * len(bounds)) * float(np.clip(max_dur / 10.0, 0.3, 1.0))

    # level trajectory: smoothed, slope over ±0.75 s (0.75 s lookahead, source only)
    sm_n = max(1, int(round(1.0 / hop)))
    ker = np.hanning(2 * sm_n + 1); ker /= ker.sum()
    es = np.convolve(np.pad(ens_db, sm_n, mode="edge"), ker, mode="valid")
    L = max(1, int(round(0.75 / hop)))
    slope = np.zeros(n_grid)
    for k in range(n_grid):
        lo, hi = max(0, k - L), min(n_grid - 1, k + L)
        if hi > lo:
            slope[k] = (es[hi] - es[lo]) / ((hi - lo) * hop)

    ctx = np.zeros(n_grid, dtype=int)          # 0 continuing
    btimes = np.array([b[0] for b in bounds])
    pstarts = np.array([p[0] for p in pauses])
    for k in range(n_grid):
        t = t_grid[k]
        if len(btimes) and np.any((t >= btimes) & (t < btimes + 1.0)):
            ctx[k] = 2
        elif slope[k] > 4.0:
            ctx[k] = 1
        elif slope[k] < -4.0 or (len(pstarts) and np.any((pstarts > t) & (pstarts <= t + 1.0))):
            ctx[k] = 3
    # mode filter (0.5 s) so labels do not flicker
    M = max(1, int(round(0.25 / hop)))
    filt = ctx.copy()
    for k in range(n_grid):
        w = ctx[max(0, k - M):k + M + 1]
        filt[k] = int(np.bincount(w, minlength=4).argmax()) if ctx[k] != 2 else 2
    if confidence == 0.0:
        filt[:] = np.where(np.abs(slope) > 6.0, filt, 0)   # uncertain: stay near-neutral
    return t_grid, filt, bounds, confidence


def _decision_times(all_segs, max_dur):
    """Decision points as (t_start, t_eval) pairs.

    Onsets within GROUP_WIN_S of a group's first onset are decided JOINTLY:
    every voice is evaluated at t_eval (the group's last onset), so a voice
    whose new segment starts a few ms into the group is judged on that new
    material. The group only shares a decision; it never hides a segment
    boundary — plan pieces are still cut at every boundary (see
    _tile_voice), so no onset inside a group can leave a coverage gap."""
    starts = sorted(set(round(seg["start_sec"], 9) for _, seg in all_segs))
    groups = []
    for t in starts:
        if not groups or t - groups[-1][0] > GROUP_WIN_S:
            groups.append([t, t])
        else:
            groups[-1][1] = t
    # regular ticks so memory, phrase and relaxation evolve inside long notes
    out = []
    for i, (t, te) in enumerate(groups):
        out.append((t, te))
        nxt = groups[i + 1][0] if i + 1 < len(groups) else max_dur
        tt = t + TICK_S
        while tt < nxt - 0.5 * TICK_S:
            out.append((round(tt, 9), round(tt, 9))); tt += TICK_S
    return out


def verify_contextual_coverage(plan_rows, all_segs, role_ids, n_files, file_srs):
    """Every span covered by a non-silent segment must be covered by a plan
    row (silence-role spans are intentional mutes). Returns {file: seconds
    missing}; exact sample arithmetic, independent of CSV rounding."""
    missing = {}
    for fi in range(n_files):
        req, got = [], []
        for gi, (f, seg) in enumerate(all_segs):
            if f == fi and ROLES[role_ids[gi]] != "silence":
                req.append((seg["start_samp"], seg["end_samp"]))
        for r in plan_rows:
            if r["file_index0"] == fi:
                got.append((r["src_start_samp"], r["src_end_samp"]))
        def union(iv):
            iv = sorted(iv); out = []
            for a, b in iv:
                if out and a <= out[-1][1]:
                    out[-1][1] = max(out[-1][1], b)
                else:
                    out.append([a, b])
            return out
        R, G = union(req), union(got)
        miss = 0; j = 0
        for a, b in R:
            cur = a
            while cur < b:
                while j < len(G) and G[j][1] <= cur:
                    j += 1
                if j < len(G) and G[j][0] <= cur:
                    cur = min(b, G[j][1])
                else:
                    nxt = G[j][0] if j < len(G) else b
                    miss += min(b, nxt) - cur
                    cur = min(b, nxt)
        missing[fi] = miss / float(file_srs[fi])
    return missing


def compute_contextual_priorities(V, segs_now, t, A, mem_snap, ev, sal, anticip,
                                  role_now, prev_leader, phr, bp):
    """Priority of each active voice: acoustic salience + live gesture +
    interpretive history + lookahead + small role bias + leadership
    persistence. Symmetric in the voices: file order never matters."""
    m = mem_snap["exposure"]
    mean_m = float(np.mean([m[i] for i in V]))
    ROLE_BIAS = {"leader": 0.10, "interruption": 0.10, "contrast_voice": 0.05,
                 "pulse_carrier": 0.05, "shadow": -0.05, "memory_trace": -0.05,
                 "noise_fringe": -0.05}
    p = {}
    for i in V:
        mb = -(m[i] - mean_m) + 0.25 * float(np.clip((mem_snap["since_fg"][i] - 3.0) / 6.0, 0, 1))
        pr = (0.45 * sal[i] + 0.9 * phr["resp"] * ev[i] + bp["mem_w"] * mb
              + 0.25 * anticip[i] + ROLE_BIAS.get(role_now[i], 0.0))
        if prev_leader is not None and i == prev_leader:
            pr += phr["persist"] * (1.0 + float(mem_snap["trans_rate"][i]))
        p[i] = float(np.clip(pr, 0.0, 1.5))
    return p


def memory_modulation(i, V, mem_snap, ev_i, bp):
    """How history scales the size of a response for voice i (0.4..1.8).
    Recently over-exposed relative to the other active voices → smaller;
    long in the background → larger. A particularly significant event
    (ev > 0.8) pulls the factor back toward 1 (it overrides memory)."""
    m = mem_snap["exposure"]
    others = [m[j] for j in V if j != i]
    rel = float(m[i] - np.mean(others)) if others else 0.0
    bg = float(np.clip((mem_snap["since_fg"][i] - 3.0) / 6.0, 0, 1))
    mod = 1.0 - bp["mem_mod"] * float(np.clip(rel / 0.25, -1.5, 1.5)) + 0.15 * bg
    override = float(np.clip((ev_i - 0.8) / 0.2, 0, 1))
    mod = mod + (1.0 - mod) * 0.6 * override
    return float(np.clip(mod, 0.4, 1.8))


def apply_responsive_behavior(V, p, ev, anticip, mem_snap, sp, phr, bp, C, style_k, dt):
    """Emphasis as a LEVEL, not an increment: a continuing gesture holds its
    level instead of stacking; secondary boosts and the total boost are
    limited so emphasis never becomes excessive."""
    d_prev = mem_snap["offset_db"]
    relax = math.exp(-dt / max(0.2, sp["relax"] * phr["relax"]))
    gesture = max(max(ev[i] for i in V), max(anticip[i] for i in V)) if V else 0.0
    if len(V) < 2 or gesture < 0.25:
        # no live gesture: static differences alone do not justify
        # intervention → hold and relax the current balance
        return {i: d_prev[i] * relax for i in V}, 0.0, "preserve"
    vals = np.array([p[i] for i in V])
    top = int(np.argmax(vals))
    spread = float(vals.max() - np.delete(vals, top).mean())   # value only; order-free
    need = float(np.clip((spread - 0.15) / 0.35, 0, 1))
    if need < 0.2:
        return {i: d_prev[i] * relax for i in V}, need, "preserve"
    pmax = float(vals.max())
    tgt = {}
    for i in V:
        dev = float(np.clip((p[i] - vals.mean()) / max(spread, 0.15), -1, 1))
        raw = dev * (bp["boost"] if dev > 0 else bp["cut"])
        k = C * style_k * sp["contrast"] * need
        if dev > 0:
            raw *= (p[i] / max(pmax, 1e-9)) ** (4.0 * sp["comp"])   # secondary boosts shrink
        tgt[i] = raw * k
    pos = sum(v for v in tgt.values() if v > 0)
    budget = bp["boost"] * C * style_k
    if pos > budget > 0:
        for i in V:
            if tgt[i] > 0:
                tgt[i] *= budget / pos
    # history scales the emphasis AFTER the budget, so a saturated response
    # still differs with what the conductor has recently done
    for i in V:
        if tgt[i] > 0:
            tgt[i] = min(1.5 * budget, tgt[i] * memory_modulation(i, V, mem_snap, ev[i], bp))
    return tgt, need, "emphasize"


def apply_complementary_behavior(V, p, ev, L_on, L_now, cent_hz, role_now, stab_now,
                                 mem_snap, prev_featured, sp, phr, phr_label,
                                 bp, C, style_k, dt):
    """Make room for significant gestures by adjusting the OTHER voices.
    No intervention when the gesture is already prominent or nothing
    competes with it; supporting voices and complementary gestures kept."""
    d_prev = mem_snap["offset_db"]
    relax = math.exp(-dt / max(0.2, sp["relax"] * phr["relax"]))
    keep = {i: d_prev[i] * relax for i in V}
    if len(V) < 2:
        return keep, 0.0, "preserve", set()
    evmax = max(ev[i] for i in V)
    F = {i for i in V if ev[i] >= 0.3 and ev[i] >= 0.6 * evmax}
    if not F:
        return keep, 0.0, "preserve", set()
    m = mem_snap["exposure"]; mean_m = float(np.mean([m[i] for i in V]))
    room = {}
    for f in F:
        # already prominent? onset level vs the loudest other voice, in dB
        others = [L_now[j] for j in V if j != f]
        prominence = float(np.clip((L_on[f] - max(others) - 3.0) / 9.0, 0, 1)) if others else 1.0
        room[f] = min(1.0, ev[f] * (1.0 - prominence))
    need = max(room.values())
    # history scales how much room is made (a recently dominant voice gets
    # less help, a long-background voice more); applied after the clip
    room_eff = {f: room[f] * memory_modulation(f, V, mem_snap, ev[f], bp) for f in F}
    if need < 0.15:
        return keep, need, "preserve", F
    tgt = dict(keep)
    k = bp["cut"] * C * style_k * sp["contrast"] * phr["resp"]
    any_cut = 0.0
    for j in V:
        pressure = 0.0
        for f in F:
            if f == j:
                continue
            # competition: register proximity (log-frequency of the spectral
            # centroids, ~0.37 at one octave) x level relation (a quieter
            # voice still competes, a louder one competes fully)
            prox = math.exp(-abs(math.log2(max(cent_hz[j], 20.0) / max(cent_hz[f], 20.0))))
            comp = prox * float(np.clip(0.6 + (L_now[j] - L_on[f]) / 12.0, 0.15, 1.0))
            if j in F:
                comp *= 0.5 if comp > 0.6 else 0.0   # complementary gestures coexist
            pressure = max(pressure, room_eff[f] * comp)
        if pressure <= 0:
            continue
        support = 0.5 if (role_now[j] in ("sustain_bed", "resonance") and stab_now[j] > 0.5) else 1.0
        if phr_label == "continuing" and support < 1.0:
            support *= 0.8
        yield_ = 0.6 + 0.4 * float(np.clip(0.5 + (m[j] - mean_m), 0, 1))
        delay = 0.5 if (j in prev_featured and ev[j] >= 0.25 and phr_label == "continuing") else 1.0
        cut = k * pressure * support * yield_ * delay * (1.0 - 0.5 * ev[j])
        if cut > 0.2:
            tgt[j] = -cut
            any_cut = max(any_cut, cut)
    # only when nothing could make room: a small lift of the gesture itself
    for f in F:
        if any_cut < 0.3 and room[f] > 0.3:
            tgt[f] = max(tgt[f], bp["boost"] * C * style_k * room_eff[f])
    dec = "withdraw" if any_cut >= 0.3 else ("emphasize" if any(tgt[f] > 0.3 for f in F) else "preserve")
    return tgt, need, dec, F


def _ensemble_state(V, segs_now, A, mem_snap):
    """Ensemble state from information available before the decision:
    pre-decision tension/energy of the active segments, plus the previous
    group's committed foreground count (decision feedback)."""
    tv = A["tension_vals"]; en = A["energy"]; stb = A["stabil"]
    T = float(np.mean([tv[segs_now[i]] for i in V]))
    Em = float(np.mean([en[segs_now[i]] for i in V]))
    S = float(np.mean([stb[segs_now[i]] for i in V]))
    many = mem_snap["prev_fg_count"] >= 2
    if T > 0.75:
        return "saturated" if many else "agitated"
    if T > 0.5:
        return "saturated" if many else "balanced"
    if T > 0.25:
        return "sparse" if Em < A["e_med"] else "balanced"
    return "suspended" if S > 0.5 else "released"


def conduct_contextual(A):
    beh = A["behavior"]; bp = BEHAVIOR_PARAMS[beh]
    n_files = A["n_files"]; all_segs = A["all_segs"]; rn = A["rn"]
    C = A["ctx_strength"]; style_k = STYLE_SCALE.get(A["style"], 1.0)
    energy, stabil, cent = A["energy"], A["stabil"], A["centroid"]
    print(f"  Contextual conductor: {beh} | tau={A['imem_tau']:.2f}s | "
          f"strength={C:.2f} | phrase={'on' if A['phrase_aware'] else 'off'}", flush=True)

    # baseline roles (+ the source-based nonlinear interruption reaction)
    role_base = A["role_base"].copy()
    p20 = float(np.percentile(A["energy_all"], 20))
    if A["nonlinear"]:
        for gi in range(len(all_segs)):
            if (rn["energy"][gi] > 0.90 and A["past_e_vals"][gi] < p20
                    and A["tension_vals"][gi] > 0.6
                    and ROLES[role_base[gi]] not in ("leader", "interruption")):
                role_base[gi] = ROLES.index("interruption")

    onset_str, onset_db = _segment_onset_strength(all_segs, rn, energy, stabil,
                                                  A["file_audios"], A["file_srs"])
    sal = np.clip(0.30 * rn["energy"] + 0.20 * rn["flux"] + 0.15 * rn["attack"]
                  + 0.15 * rn["pitch"] + 0.10 * rn["hnr"] + 0.10 * rn["bright"], 0, 1)

    if A["phrase_aware"]:
        t_grid, ctx_codes, bounds, conf = estimate_phrase_context(
            A["file_audios"], A["file_srs"], all_segs, onset_str, A["max_dur"])
    else:
        t_grid = np.array([0.0, A["max_dur"]]); ctx_codes = np.zeros(2, dtype=int)
        bounds, conf = [], 0.0
    print(f"    Phrase boundaries: {len(bounds)} (confidence {conf:.2f})", flush=True)

    # per-file segment lists for fast lookup
    file_segs = {fi: [] for fi in range(n_files)}
    for gi, (fi, seg) in enumerate(all_segs):
        file_segs[fi].append(gi)
    for fi in file_segs:
        file_segs[fi].sort(key=lambda g: (all_segs[g][1]["start_samp"], g))
    file_starts = {fi: np.array([all_segs[g][1]["start_sec"] for g in file_segs[fi]])
                   for fi in file_segs}
    # running maximum of segment ends (segments sorted by start): if the
    # max end of segments 0..k is <= t, NO earlier segment covers t. This
    # makes the backward search exact for any amount of overlap.
    file_cummax_end = {fi: (np.maximum.accumulate(
        np.array([all_segs[g][1]["start_sec"] + all_segs[g][1]["dur_sec"] for g in file_segs[fi]]))
        if file_segs[fi] else np.zeros(0)) for fi in file_segs}

    def covering_segs(fi, t):
        """All segments of voice fi covering time t, latest start first.
        Exact: walks back until no earlier segment can still be sounding."""
        st = file_starts[fi]
        out = []
        k = int(np.searchsorted(st, t + 1e-9, side="right")) - 1
        cme = file_cummax_end[fi]
        while k >= 0 and cme[k] > t + 1e-9:
            g = file_segs[fi][k]; s_ = all_segs[g][1]
            if s_["start_sec"] + s_["dur_sec"] > t + 1e-9:
                out.append(g)
            k -= 1
        return out

    def current_seg(fi, t):
        # latest-starting covering segment = the voice's current material
        # (one physical voice even when fixed/hybrid windows overlap)
        cov = covering_segs(fi, t)
        return cov[0] if cov else None

    def tile_voice(fi, t0, t1):
        """Cut [t0, t1) at EVERY segment boundary of this voice. Each piece is
        carried by the latest-starting covering non-silent segment (one
        physical voice even with overlapping windows); spans covered only by
        silence-role segments are intentional mutes and get no piece."""
        st = file_starts[fi]; out = []; cur = t0
        if len(st) == 0:
            return out
        while cur < t1 - 1e-9:
            k = int(np.searchsorted(st, cur + 1e-9, side="right")) - 1
            cover = covering_segs(fi, cur)
            nk = k + 1
            next_start = st[nk] if nk < len(st) else math.inf
            live = [g for g in cover if ROLES[role_base[g]] != "silence"]
            if live:
                g = live[0]          # latest start first (search runs backwards)
                s_ = all_segs[g][1]
                end = min(t1, s_["start_sec"] + s_["dur_sec"], next_start)
                out.append((g, cur, end))
            else:
                ends = [all_segs[g][1]["start_sec"] + all_segs[g][1]["dur_sec"] for g in cover]
                end = min([t1, next_start] + ends)     # finite: t1 is finite
            if end <= cur + 1e-12:                     # cannot advance (defensive)
                break
            cur = end
        return out

    def anticipation(fi, t):
        st = file_starts[fi]
        lo = int(np.searchsorted(st, t + 1e-9, side="right"))
        hi = int(np.searchsorted(st, t + LOOKAHEAD_S, side="right"))
        best = 0.0
        for k in range(lo, hi):
            g = file_segs[fi][k]
            if onset_str[g] >= 0.6:
                best = max(best, onset_str[g] * (1.0 - (st[k] - t) / LOOKAHEAD_S))
        return min(best, 0.4)          # never larger than the gesture itself

    times = _decision_times(all_segs, A["max_dur"])
    mem = InterpretiveMemory(n_files, A["imem_tau"])
    level_db_seg = 20.0 * np.log10(np.maximum(A["rms_raw"], 1e-9))
    cpos = chamber_positions(n_files) if A["spatial"] == "chamber" else None
    ROLE_PAN = {"leader": 0.3, "shadow": 1.0, "resonance": 0.8,
                "noise_fringe": 1.2, "pulse_carrier": 0.6,
                "interruption": 0.1, "sustain_bed": 0.9,
                "contrast_voice": 1.1, "memory_trace": 0.7, "silence": 0.0}

    pieces = []          # per file, non-overlapping commanded pieces
    viz_ctx = []         # per group: time, phrase code, decision code, exposures
    prev_featured = set()
    state_count = Counter(); dec_count = Counter(); phr_count = Counter()
    max_poly = 1

    for gk, (t, t_eval) in enumerate(times):
        t_next = times[gk + 1][0] if gk + 1 < len(times) else A["max_dur"]
        dt = max(1e-6, t_next - t)
        snap = mem.snapshot()
        segs_now, V, silent = {}, [], []
        for fi in range(n_files):
            g = current_seg(fi, t_eval)        # joint decision on the group's material
            if g is None:
                continue
            segs_now[fi] = g
            if ROLES[role_base[g]] == "silence":
                silent.append(fi)
            else:
                V.append(fi)
        kph = int(np.clip(round(t / PHRASE_HOP), 0, len(ctx_codes) - 1)) if A["phrase_aware"] else 0
        phr_label = PHRASE_LABELS[int(ctx_codes[kph])] if A["phrase_aware"] else "continuing"
        phr = PHRASE_PARAMS[phr_label] if A["phrase_aware"] else PHRASE_OFF
        if A["phrase_aware"] and conf < 0.5:          # uncertain structure → closer to neutral
            w = 0.5 + conf
            phr = {k2: PHRASE_OFF[k2] + w * (phr[k2] - PHRASE_OFF[k2]) for k2 in phr}

        gains = np.zeros(n_files); offs = mem.offset_db.copy()
        decision, need, state, p = "preserve", 0.0, "balanced", {}
        if V:
            state = _ensemble_state(V, segs_now, A, snap)
            sp = STATE_PARAMS[state]
            ev = {i: float(onset_str[segs_now[i]] *
                           math.exp(-max(0.0, t_eval - all_segs[segs_now[i]][1]["start_sec"]) / EV_DECAY_S)) for i in V}
            sal_now = {i: float(sal[segs_now[i]]) for i in V}
            anticip = {i: (anticipation(i, t) if A["phrase_aware"] else 0.0) for i in V}
            role_now = {i: ROLES[role_base[segs_now[i]]] for i in V}
            # previous leader from committed offsets (history only; exact ties → none)
            prev_leader = None
            od = snap["offset_db"]
            if len(V) >= 2:
                srt = sorted((od[i] for i in V), reverse=True)
                if srt[0] > 1.0 and srt[0] - srt[1] > 0.75:
                    prev_leader = [i for i in V if od[i] == srt[0]][0]
            p = compute_contextual_priorities(V, segs_now, t, A, snap, ev, sal_now,
                                              anticip, role_now, prev_leader, phr, bp)
            if beh == "responsive":
                tgt, need, decision = apply_responsive_behavior(
                    V, p, ev, anticip, snap, sp, phr, bp, C, style_k, dt)
            else:
                L_on = {i: float(onset_db[segs_now[i]]) for i in V}
                L_now = {i: float(level_db_seg[segs_now[i]]) for i in V}
                cent_now = {i: float(A["cent_hz"][segs_now[i]]) for i in V}
                stab_now = {i: float(stabil[segs_now[i]]) for i in V}
                tgt, need, decision, prev_featured = apply_complementary_behavior(
                    V, p, ev, L_on, L_now, cent_now, role_now, stab_now, snap,
                    prev_featured, sp, phr, phr_label, bp, C, style_k, dt)
            # coordinated rate limit (state-dependent) → committed offsets
            slew = bp["slew"] * sp["slew"] * dt
            for i in V:
                d0 = snap["offset_db"][i]
                offs[i] = d0 + float(np.clip(tgt[i] - d0, -slew, slew))
            n_poly = polyphony_distinct(V)
            max_poly = max(max_poly, n_poly)
            ps = math.sqrt(2.0 / n_poly) if n_poly > 2 else 1.0
            for i in V:
                gains[i] = float(np.clip(CTX_G0 * ps * 10 ** (offs[i] / 20.0), 0.05, 1.0))
        # voices not sounding relax toward neutral
        relax_idle = math.exp(-dt / 3.0)
        for fi in range(n_files):
            if fi not in V:
                offs[fi] *= relax_idle

        # Two indicators, both separate from the analytic role column:
        # gain_emphasized - the voice the committed gain OFFSETS put clearly
        #                   ahead (a statement about the conducting commands)
        # level_foreground - the voice whose SOURCE LEVEL + APPLIED GAIN over
        #                   this interval is >= 3 dB above every other voice
        #                   (an RMS estimate, not a perceptual loudness model;
        #                   it also catches voices that come forward because
        #                   the others were withdrawn)
        top = None
        if len(V) >= 2:
            srt = sorted((offs[i] for i in V), reverse=True)
            if srt[0] > 0.75 and srt[0] - srt[1] > 0.5:
                top = [i for i in V if offs[i] == srt[0]][0]
        eff = {}
        for i in V:
            a_ = A["file_audios"][i]; sr_ = A["file_srs"][i]
            x = np.asarray(a_[int(t * sr_):max(int(t * sr_) + 1, int(t_next * sr_))], dtype=np.float64)
            rms_i = float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0
            if rms_i > 1e-3 and gains[i] > 0:          # audible (> -60 dBFS)
                eff[i] = 20.0 * math.log10(rms_i) + 20.0 * math.log10(gains[i])
        lvl_top = None
        if len(eff) == 1:
            lvl_top = next(iter(eff))
        elif len(eff) >= 2:
            srt = sorted(eff.values(), reverse=True)
            if srt[0] - srt[1] >= 3.0:
                lvl_top = [i for i in eff if eff[i] == srt[0]][0]
        n_poly_now = polyphony_distinct(V) if V else 1
        ps_now = math.sqrt(2.0 / n_poly_now) if n_poly_now > 2 else 1.0

        for i in range(n_files):
            # a voice outside this decision (e.g. its group material is a
            # silence-role segment but earlier material still sounds) keeps
            # its current, relaxed offset rather than dropping out
            g_i = float(gains[i]) if i in V else float(
                np.clip(CTX_G0 * ps_now * 10 ** (offs[i] / 20.0), 0.05, 1.0))
            for g, a, b in tile_voice(i, t, t_next):
                rl = ROLES[role_base[g]]
                pan = cpos[i] if cpos is not None else max(-1.0, min(1.0, round(
                    float(A["base_pans"][i] * ROLE_PAN.get(rl, 1.0)), 4)))
                pieces.append(dict(fi=i, g=g, t0=a, t1=b, role=rl,
                                   gain=round(g_i, 4), pan=pan,
                                   state=state, phrase=phr_label, decision=decision,
                                   prio=round(float(min(1.0, p.get(i, 0.0))), 4),
                                   mem=round(float(snap["exposure"][i]), 4),
                                   off=round(float(offs[i]), 3), poly=len(V),
                                   fg=1 if i == top else 0,
                                   lfg=1 if i == lvl_top else 0))
        state_count[state] += 1; dec_count[decision] += 1; phr_count[phr_label] += 1
        viz_ctx.append((t, int(ctx_codes[kph]) if A["phrase_aware"] else -1,
                        DECISIONS.index(decision), snap["exposure"].copy()))

        # commit → memory
        act = np.zeros(n_files, dtype=bool)
        lv = np.full(n_files, -120.0)
        for i in V:
            act[i] = gains[i] > 0
            lv[i] = level_db_seg[segs_now[i]]
        update_interpretive_memory(mem, dt, gains, lv, act)
        mem.offset_db = offs

    # ── merge identical consecutive pieces and build v3.2-compatible rows ──
    plan_rows = []
    for fi in range(n_files):
        fp = [pc for pc in pieces if pc["fi"] == fi]
        merged = []
        for pc in fp:
            if (merged and merged[-1]["g"] == pc["g"] and merged[-1]["role"] == pc["role"]
                    and merged[-1]["gain"] == pc["gain"] and merged[-1]["pan"] == pc["pan"]
                    and merged[-1]["fg"] == pc["fg"] and merged[-1]["lfg"] == pc["lfg"]
                    and abs(merged[-1]["t1"] - pc["t0"]) < 1e-9):
                merged[-1]["t1"] = pc["t1"]
            else:
                merged.append(dict(pc))
        sr = A["file_srs"][fi]
        for pc in merged:
            g = pc["g"]; seg = all_segs[g][1]
            # exact sample boundaries: segment starts/ends keep their own
            # samples; group/tick times are rounded identically on both sides
            ss = int(round(pc["t0"] * sr)); se = int(round(pc["t1"] * sr))
            if abs(pc["t0"] - seg["start_sec"]) < 1e-9:
                ss = seg["start_samp"]
            if abs(pc["t1"] - (seg["start_sec"] + seg["dur_sec"])) < 1e-9:
                se = seg["end_samp"]
            if se <= ss:
                continue
            rl = pc["role"]
            plan_rows.append({
                "time": round(pc["t0"], 4), "file_index": fi + 1, "file_index0": fi,
                "file_name": A["file_names"][fi], "seg_index": seg["idx"],
                "src_start": round(pc["t0"], 4), "src_dur": round(pc["t1"] - pc["t0"], 4),
                "src_start_samp": ss, "src_end_samp": se, "src_sr": sr,
                "gain": pc["gain"], "role": rl,
                "layer_group": 0 if rl in ["leader", "interruption", "contrast_voice"]
                               else 1 if rl in ["pulse_carrier", "resonance", "shadow"] else 2,
                "entry_time": round(pc["t0"], 4), "exit_time": round(pc["t1"], 4),
                "transform": round(float(1.0 - A["prom_vals"][g]) * 0.4, 3),
                "state": pc["state"], "density": round(pc["gain"] / 0.9, 3),
                "priority": pc["prio"], "pan": pc["pan"],
                "fade": round(max(0.003, min(0.008, (pc["t1"] - pc["t0"]) * 0.10)), 6),
                "tension": round(float(A["tension_vals"][g]), 4), "polyphony": int(pc["poly"]),
                # appended diagnostics (contextual modes only)
                "behavior": beh, "fg_memory": pc["mem"], "ctx_priority": pc["prio"],
                "phrase_ctx": pc["phrase"], "ctx_gain_db": pc["off"],
                "decision": pc["decision"], "gain_emphasized": pc["fg"],
                "level_foreground": pc["lfg"],
            })
    plan_rows.sort(key=lambda r: (r["entry_time"], -r["priority"], r["file_index0"]))
    miss = verify_contextual_coverage(plan_rows, all_segs, role_base, n_files, A["file_srs"])
    if max(miss.values()) > 0:
        # an UNINTENDED gap would silence real material in the renderer:
        # refuse to produce a result (Praat reports the error, nothing saved)
        raise RuntimeError("Contextual plan coverage gap (s): " + ", ".join(
            f"{A['file_names'][f]}={v:.4f}" for f, v in miss.items() if v > 0)
            + " - non-silent material without a plan row; result not written.")
    else:
        print("    Coverage check: every non-silent segment span has a plan row", flush=True)
    print(f"    Roles: {dict(Counter(r['role'] for r in plan_rows))}", flush=True)
    print(f"    Decisions: {dict(dec_count)} | States: {dict(state_count)}", flush=True)
    print(f"    Phrase contexts: {dict(phr_count)} | Peak polyphony (distinct voices): {max_poly}", flush=True)
    print(f"  Plan: {len(plan_rows)} events ({len(times)} decision points)", flush=True)
    conduct_contextual.last_viz = dict(groups=viz_ctx, bounds=bounds, confidence=conf)
    return plan_rows, A["max_dur"]


conduct_contextual.last_viz = None


def write_viz_table(path, n_files, max_dur, env_out, env_rate, ctx_viz):
    """50 Hz table for the Praat picture: rendered gain per voice (the actual
    smoothed renderer envelope), phrase context, boundary flag, decision and
    per-voice foreground exposure (contextual modes; -1 otherwise)."""
    hop = 0.02
    n = max(2, int(math.ceil(max_dur / hop)) + 1)
    tg = np.arange(n) * hop
    cols = ["time", "phrase", "boundary", "decision"] + \
           [f"g{i+1}" for i in range(n_files)] + [f"e{i+1}" for i in range(n_files)]
    G = np.zeros((n, n_files))
    for fi in range(n_files):
        env = env_out.get(fi)
        if env is not None and len(env):
            idx = np.clip(np.round(tg * env_rate).astype(int), 0, len(env) - 1)
            G[:, fi] = env[idx]
            G[tg * env_rate > len(env) - 1, fi] = 0.0
    phr = np.full(n, -1); dec = np.full(n, -1); E = np.full((n, n_files), -1.0)
    bnd = np.zeros(n, dtype=int)
    if ctx_viz:
        gt = np.array([g[0] for g in ctx_viz["groups"]])
        if len(gt):
            k = np.clip(np.searchsorted(gt, tg, side="right") - 1, 0, len(gt) - 1)
            phr = np.array([ctx_viz["groups"][j][1] for j in k])
            dec = np.array([ctx_viz["groups"][j][2] for j in k])
            E = np.array([ctx_viz["groups"][j][3] for j in k])
        for b in ctx_viz["bounds"]:
            j = int(round(b[0] / hop))
            if 0 <= j < n:
                bnd[j] = 1
    with open(path, "w", encoding="utf-8") as f:
        f.write("\t".join(cols) + "\n")
        for r in range(n):
            vals = [f"{tg[r]:.3f}", str(int(phr[r])), str(int(bnd[r])), str(int(dec[r]))]
            vals += [f"{G[r, i]:.4f}" for i in range(n_files)]
            vals += [f"{E[r, i]:.4f}" for i in range(n_files)]
            f.write("\t".join(vals) + "\n")


# ─────────────────────────────────────────────────────────────────────────────
# SAMPLE-LEVEL RENDERER — continuous gain envelope (no segment chopping)
# ─────────────────────────────────────────────────────────────────────────────

def render_mix(plan_rows, file_paths, target_sr, max_dur, result_path,
               env_out=None, env_rate=100):
    """
    Renders the conductor plan into a stereo WAV.

    Instead of extracting and reassembling individual segments (which
    creates boundary artifacts), this renderer:
      1. Loads each source file as a continuous stereo stream.
      2. Builds a smooth per-sample gain envelope from the role/gain plan.
      3. Builds a smooth per-sample pan envelope.
      4. Multiplies the uncut audio by the envelopes.
      5. Accumulates into stereo output buffers.

    Zero segment boundaries = zero clicks.
    """
    print("  Rendering stereo mix (continuous envelope)...", flush=True)

    SMOOTH_MS = 150.0   # envelope smoothing window in ms
    smooth_n  = max(1, int(round(SMOOTH_MS / 1000.0 * target_sr)))

    # --- FAST FFT CONVOLUTION HELPER ---
    # Kernel spectra are cached because gain, pan numerator and pan support use
    # the same smoothing window for a given source length.
    smooth_kernel_cache = {}

    def fast_smooth(arr, kernel):
        n = len(arr)
        k = len(kernel)
        if n == 0 or k == 0:
            return arr
        n_fft = 1 << (n + k - 1).bit_length()
        key = (n_fft, k)
        ker_f = smooth_kernel_cache.get(key)
        if ker_f is None:
            ker_f = np.fft.rfft(kernel, n=n_fft)
            smooth_kernel_cache[key] = ker_f
        arr_f = np.fft.rfft(arr, n=n_fft)
        res = np.fft.irfft(arr_f * ker_f, n=n_fft)
        shift = (k - 1) // 2
        return res[shift : shift + n][:n]
    # -----------------------------------

    n_out = int(math.ceil(max_dur * target_sr)) + target_sr
    buf_L = np.zeros(n_out, dtype=np.float64)
    buf_R = np.zeros(n_out, dtype=np.float64)

    # ── Group plan rows by file ──────────────────────────────────────────
    file_rows = {}
    for row in plan_rows:
        fi = row["file_index0"]
        file_rows.setdefault(fi, []).append(row)

    # ── Process each file as a continuous stream ─────────────────────────
    all_fis = sorted(set(row["file_index0"] for row in plan_rows))

    for fi in all_fis:
        # Load full file as stereo at target_sr
        src_L, src_R = load_audio_stereo(file_paths[fi], target_sr)
        n_src = len(src_L)
        print(f"    File [{fi+1}] {n_src} samples", flush=True)

        # Build COUPLED gain + pan targets. In v3.0 overlapping fixed/hybrid
        # segments took the maximum gain but "last writer wins" pan, so the pan
        # could belong to a different event than the gain actually being heard.
        gain_target = np.zeros(n_src, dtype=np.float64)
        pan_target = np.zeros(n_src, dtype=np.float64)

        rows = file_rows.get(fi, [])
        for row in rows:
            src_sr = row["src_sr"]
            if src_sr == target_sr:
                ss, se = row["src_start_samp"], row["src_end_samp"]
            else:
                ratio = target_sr / src_sr
                ss = int(round(row["src_start_samp"] * ratio))
                se = int(round(row["src_end_samp"] * ratio))
            ss = max(0, min(ss, n_src)); se = max(ss, min(se, n_src))
            if se <= ss:
                continue
            g = float(row["gain"]); p = float(row["pan"])
            cur = gain_target[ss:se]
            choose = g > cur + 1e-12
            # On equal gain, higher-priority later plan row may define the colour.
            if np.any(choose):
                cur[choose] = g
                pan_slice = pan_target[ss:se]
                pan_slice[choose] = p

        active_target = (gain_target > 0).astype(np.float64)
        gain_env = gain_target.copy()
        pan_env = pan_target.copy()
        if smooth_n > 1 and n_src > smooth_n * 2:
            kernel = np.hanning(smooth_n * 2 + 1)
            kernel /= kernel.sum()
            gain_env = fast_smooth(gain_target, kernel)
            # Smooth pan only over active support, so zeros outside events do not
            # pull pan toward the centre and create an unintended second fade.
            pan_num = fast_smooth(pan_target * active_target, kernel)
            pan_den = fast_smooth(active_target, kernel)
            pan_env = np.divide(pan_num, np.maximum(pan_den, 1e-12),
                                out=np.zeros_like(pan_num), where=pan_den > 1e-9)

        pan_env = np.clip(pan_env, -1.0, 1.0)
        pan_angle = (pan_env + 1.0) * (math.pi / 4.0)
        pan_l_env = np.cos(pan_angle)
        pan_r_env = np.sin(pan_angle)

        # ── Apply envelopes to full file and accumulate ONCE ─────────
        scaled_L = src_L.astype(np.float64) * gain_env * pan_l_env
        scaled_R = src_R.astype(np.float64) * gain_env * pan_r_env

        # Place into output buffer (source position = output position)
        out_len = min(n_src, n_out)
        buf_L[:out_len] += scaled_L[:out_len]
        buf_R[:out_len] += scaled_R[:out_len]

        if env_out is not None:   # v3.3: read-only copy for the picture
            step = max(1, int(round(target_sr / env_rate)))
            env_out[fi] = gain_env[::step].astype(np.float32)

        print(f"      gain range: {gain_env.min():.4f}–{gain_env.max():.4f}  "
              f"active: {np.count_nonzero(gain_env)}/{n_src} samples",
              flush=True)

    # ── Diagnostics ──────────────────────────────────────────────────────
    # Windowed RMS, not a single sample: a legitimate waveform zero crossing
    # at a segment boundary must not be reported as a renderer dropout.
    check_r = max(4, int(0.004 * target_sr))
    centre_r = max(2, int(0.001 * target_sr))
    all_starts = sorted(set(
        row["src_start_samp"] if row["src_sr"] == target_sr
        else int(round(row["src_start_samp"] * target_sr / row["src_sr"]))
        for row in plan_rows
    ))
    dbg_dips = 0

    def stereo_rms(lo, hi):
        lo = max(0, lo); hi = min(len(buf_L), hi)
        if hi <= lo:
            return 0.0
        return float(np.sqrt(np.mean(buf_L[lo:hi]**2 + buf_R[lo:hi]**2) + 1e-20))

    for bp in all_starts:
        if bp < check_r or bp + check_r >= len(buf_L):
            continue
        centre = stereo_rms(bp-centre_r, bp+centre_r)
        before = stereo_rms(bp-check_r, bp-centre_r)
        after = stereo_rms(bp+centre_r, bp+check_r)
        surround = 0.5 * (before + after)
        if surround > 1e-5 and centre < surround * 0.30:
            dbg_dips += 1
            if dbg_dips <= 5:
                print(f"    RMS dip near {bp/target_sr:.4f}s: "
                      f"centre={centre:.6f} vs surround={surround:.6f}", flush=True)
    if dbg_dips > 5:
        print(f"    ... and {dbg_dips - 5} more RMS dips", flush=True)
    if dbg_dips == 0:
        print("    No boundary RMS dips detected", flush=True)

    # ── Trim / normalize / write ─────────────────────────────────────────
    trim = n_out
    while trim > 0 and abs(buf_L[trim-1]) < 1e-6 and abs(buf_R[trim-1]) < 1e-6:
        trim -= 1
    trim = max(trim, target_sr // 10)
    buf_L, buf_R = buf_L[:trim], buf_R[:trim]

    peak = max(np.max(np.abs(buf_L)), np.max(np.abs(buf_R)), 1e-12)
    rms_l = float(np.sqrt(np.mean(buf_L ** 2)))
    rms_r = float(np.sqrt(np.mean(buf_R ** 2)))
    print(f"    Pre-norm: peak={peak:.4f}  RMS L={rms_l:.4f} R={rms_r:.4f}",
          flush=True)

    if peak > 0.95:
        s = 0.95 / peak
        buf_L *= s; buf_R *= s
        print(f"    Scaled peak {peak:.3f} → 0.95", flush=True)

    actual_dur = trim / target_sr
    print(f"    Output: {actual_dur:.2f}s stereo @ {target_sr}Hz", flush=True)

    stereo = np.column_stack([buf_L.astype(np.float32),
                              buf_R.astype(np.float32)])
    sf.write(result_path, stereo, target_sr, subtype="FLOAT")
    print(f"    Written: {result_path}", flush=True)
    return actual_dur


# ─────────────────────────────────────────────────────────────────────────────
# I/O HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def read_manifest(path):
    entries = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            parts = line.split("\t")
            if len(parts) < 3: continue
            entries.append({
                "index": int(parts[0]), "name": parts[1],
                "wav_path": parts[2],
                "duration": float(parts[3]) if len(parts) > 3 else None,
                "sr": int(parts[4]) if len(parts) > 4 else None,
                "channels": int(parts[5]) if len(parts) > 5 else None,
            })
    return entries


def write_plan_csv(path, rows, max_dur=0.0, diagnostics=False):
    if not rows: return
    fld = ["time","file_index","file_name","seg_index","src_start","src_dur",
           "gain","role","layer_group","entry_time","exit_time","transform",
           "state","density","priority","pan","tension","polyphony"]
    if diagnostics:   # v3.3 contextual modes: appended AFTER the v3.2 columns
        fld += ["behavior","fg_memory","ctx_priority","phrase_ctx",
                "ctx_gain_db","decision","gain_emphasized","level_foreground"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        f.write(f"#max_dur={round(max_dur,6)}\n")
        w = csv.DictWriter(f, fieldnames=fld, delimiter="\t", extrasaction="ignore")
        w.writeheader(); w.writerows(rows)


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="AI Conductor Mix v3.3")
    ap.add_argument("manifest_file", type=str)
    ap.add_argument("descriptor_file", type=str)
    ap.add_argument("mix_plan_file", type=str)
    ap.add_argument("done_file", type=str)
    ap.add_argument("--result_wav", type=str, default="")
    ap.add_argument("--style", type=str, default="dramatic")
    ap.add_argument("--seg_mode", type=str, default="onset")
    ap.add_argument("--frame_ms", type=float, default=80.0)
    ap.add_argument("--hop_ms", type=float, default=40.0)
    ap.add_argument("--onset_gap_ms", type=float, default=50.0)
    ap.add_argument("--memory", type=float, default=0.4)
    ap.add_argument("--tension", type=float, default=0.6)
    ap.add_argument("--allow_silence", type=int, default=1)
    ap.add_argument("--nonlinear", type=int, default=1)
    # v3.3 (defaults reproduce v3.2 exactly)
    ap.add_argument("--behavior", type=str, default="original",
                    choices=["original", "responsive", "complementary"])
    ap.add_argument("--imem_tau", type=float, default=4.0,
                    help="Interpretive memory duration in seconds")
    ap.add_argument("--ctx_strength", type=float, default=0.5)
    ap.add_argument("--phrase", type=int, default=1)
    ap.add_argument("--spatial", type=str, default="role", choices=["role", "chamber"])
    ap.add_argument("--viz_file", type=str, default="")
    args = ap.parse_args()

    print("=== AI Conductor Mix v3.3 ===", flush=True)
    print(f"Style: {args.style} | Seg: {args.seg_mode} | "
          f"Mem: {args.memory:.2f} | Tens: {args.tension:.2f}", flush=True)
    print(f"Behaviour: {args.behavior} | Interp. memory: {args.imem_tau:.2f}s | "
          f"Ctx strength: {args.ctx_strength:.2f} | Phrase: {args.phrase} | "
          f"Spatial: {args.spatial}", flush=True)

    manifest = read_manifest(args.manifest_file)
    macro_by_index = read_macro_descriptors(args.descriptor_file)
    print(f"Ensemble: {len(manifest)} files | Praat macro descriptors: {len(macro_by_index)}", flush=True)

    print("Loading audio...", flush=True)
    file_audios, file_srs, file_names, file_paths, macro_descs = [], [], [], [], []
    for entry in manifest:
        if not os.path.isfile(entry["wav_path"]):
            raise FileNotFoundError(f"Input WAV missing: {entry['wav_path']}")
        audio, sr, mix_mode = load_audio_mono(entry["wav_path"])
        file_audios.append(audio); file_srs.append(sr)
        file_names.append(entry["name"]); file_paths.append(entry["wav_path"])
        macro_descs.append(macro_by_index.get(entry["index"]))
        print(f"  [{entry['index']}] {entry['name']} | {len(audio)/sr:.2f}s @ {sr}Hz | analysis={mix_mode}", flush=True)

    if len(file_audios) < 2:
        print("ERROR: Need >=2 audio files.", flush=True)
        with open(args.done_file, "w") as f: f.write("error\n")
        sys.exit(1)

    plan, _max_dur = conduct(
        file_audios, file_srs, file_names, args.seg_mode,
        args.frame_ms, args.hop_ms, args.onset_gap_ms,
        args.style, args.memory, args.tension,
        bool(args.allow_silence), bool(args.nonlinear), macro_descs=macro_descs,
        behavior=args.behavior, imem_tau=args.imem_tau,
        ctx_strength=args.ctx_strength, phrase_aware=bool(args.phrase),
        spatial=args.spatial)

    contextual = args.behavior != "original"
    write_plan_csv(args.mix_plan_file, plan, max_dur=_max_dur, diagnostics=contextual)
    print(f"Plan CSV: {args.mix_plan_file} ({len(plan)} events)", flush=True)

    target_sr = max(file_srs)
    result_wav = args.result_wav or args.mix_plan_file.replace(".csv", "_mix.wav")

    env_out = {} if args.viz_file else None
    actual_dur = render_mix(plan, file_paths, target_sr, _max_dur, result_wav,
                            env_out=env_out)
    if args.viz_file:
        write_viz_table(args.viz_file, len(file_paths), _max_dur, env_out, 100,
                        conduct_contextual.last_viz if contextual else None)
        print(f"Viz table: {args.viz_file}", flush=True)

    rc = Counter(r["role"] for r in plan)
    sc = Counter(r["state"] for r in plan)
    print(f"Roles: {dict(rc)}", flush=True)
    print(f"States: {dict(sc)}", flush=True)
    print(f"Duration: {actual_dur:.2f}s", flush=True)

    with open(args.done_file, "w") as f: f.write("ok\n")
    print("OK: conductor done", flush=True)


if __name__ == "__main__":
    # Praat polls done_file. On a Python exception, always release the poller
    # immediately instead of making the user wait for the 10-minute timeout.
    done_path = sys.argv[4] if len(sys.argv) > 4 else None
    try:
        main()
    except Exception:
        tb = traceback.format_exc()
        print(tb, file=sys.stderr, flush=True)
        if done_path:
            try:
                with open(done_path, "w") as f:
                    f.write("error\n")
            except OSError:
                pass
        sys.exit(1)