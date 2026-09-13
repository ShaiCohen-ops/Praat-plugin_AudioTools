#!/usr/bin/env python3
# =============================================================================
# Hierarchical Neural Recomposition
# Author: Shai Cohen — Department of Music, Bar-Ilan University, Israel
# Version: 1.7 (2026)
# License: MIT
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.7:
#   - True event -> phrase -> section hierarchy: contiguous phrase groups are
#     aggregated into section embeddings before the bidirectional GRU planner.
#   - Descriptor-conditioned planning blends acoustic structure with the seeded
#     untrained neural prior, so source material influences the plan more strongly
#     than seed variation while keeping deterministic generative variation.
#   - Preset-specific mechanisms are now active (recursive memory, micro-event
#     litany, progressive collapsing refrain, sonata development/recapitulation,
#     and choir phase offsets).
#   - Planner cycles until the requested target duration is covered; render tails
#     are no longer silent merely because a single phrase pass ended early.
#   - Onset intervals longer than max event duration are fully chunked, preserving
#     all source material; local phase-cancellation protection is frame-adaptive.
#   - Effective preset parameters, section spans, true plan-row indices, and
#     content-end QC are exported for truthful Praat visualization.
#
# Changelog v1.4:
#   - Structural stereo spatialization for genuinely polyphonic presets only.
#     RecursiveSpeechChoir places its independent voices across a fixed
#     equal-power stereo field; braid operations occupy deterministic strands;
#     EchoArchitecture alternates successive echo generations left/right.
#   - Non-spatial presets keep the historical mono render path exactly.
#   - Process telemetry now includes per-operation pan plus output-channel and
#     spatialization QC so Praat can draw the audible stereo field.
#
# Changelog v1.3:
#   - Process visualization telemetry: stats now include actual event boundaries,
#     phrase spans, selected plan-slot means, and the render operations that were
#     actually scheduled in this run. This is diagnostic-only and does not alter
#     planning or audio rendering.
#   - Choir mode exposes the combined scheduled operations from all voices for
#     visualization while preserving the exact existing render path.
#
# Changelog v1.2:
#   - Phase-safe mono analysis/render source: multichannel input still uses the
#     ordinary channel mean when it is healthy, but if that mean collapses below
#     10% of the strongest channel RMS (anti-phase cancellation), the strongest
#     channel is used instead. Normal mono/stereo behaviour is unchanged.
#   - Documentation now states the actual neural mechanism: the PyTorch hierarchy
#     is seed-deterministic but randomly initialized on every run; no checkpoint
#     is loaded and no training happens in this script.
#   - Density and source_trace remain accepted as legacy positional arguments for
#     old Praat frontends, but are explicitly documented as inactive. Source trace
#     was deliberately removed earlier to avoid correlated comb-filter beating.
#
# Changelog v1.1:
#   - Numpy fallback is now reachable: the torch nn.Module subclasses are
#     rebased onto a BaseModule alias (object when torch is absent), so the
#     module imports without torch instead of NameError-ing at class
#     definition. (Previously the advertised fallback was dead code.)
#   - Fixed an IndexError in the surprise-swap path: rng.randint(0, len) is
#     inclusive and could index one past the list end (hit FormalBraiding,
#     surprise=0.35). Now uses len-1 and guards length >= 2.
#   - plan_event_ordering now takes the real sample rate instead of a
#     hardcoded 44100, so event placement geometry is correct for non-44.1k
#     input (previously planning seconds and render seconds disagreed).
#   - harmonicity_estimate uses an FFT autocorrelation (O(n log n)) instead
#     of np.correlate full (O(n^2)) — matters for long events.
#
# Description:
#   Multi-scale neural recomposition engine.
#   Segments an input sound into events → phrases and computes section descriptors
#   for diagnostics. A phrase-sequence hierarchy then builds seed-deterministic
#   embeddings via a randomly initialized PyTorch network (no training/checkpoint),
#   and generates a recomposition plan
#   (ordering, overlap, memory) and renders a new piece from the source material.
#
# Dependencies:
#   Required: numpy scipy soundfile
#   Optional: torch (seeded NumPy fallback is used when unavailable)
#
# Usage (from Praat via runSystem):
#   python hierarchical_recomposition.py \
#       input.wav output.wav stats.txt \
#       <target_dur> <density> <coherence> <contrast> \
#       <memory> <repetition> <fragmentation> <overlap> \
#       <source_trace> <surprise> <seed> \
#       <preset_name>
# =============================================================================

import sys
import os
import math
import json
import random
import numpy as np
import soundfile as sf
import scipy.signal as signal
import scipy.ndimage as ndimage

# ── Torch (required) ──────────────────────────────────────────────────────────
try:
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
    TORCH_OK = True
except ImportError:
    TORCH_OK = False
    print("[WARNING] PyTorch not found. Using fallback numpy model.", flush=True)

# Base class for the torch modules below. When torch is present this is the
# real nn.Module; when it is absent it is a plain object so the module can
# still IMPORT (the torch classes are only ever instantiated in the TORCH_OK
# branch of main(), so the stand-in is never actually used — it just keeps the
# `class X(nn.Module)` statements from raising NameError and lets the numpy
# fallback run).
BaseModule = nn.Module if TORCH_OK else object


# =============================================================================
# SECTION 1 — AUDIO UTILITIES
# =============================================================================

def load_audio(path):
    """Load audio and return a phase-safe mono working signal.

    Ordinary multichannel material uses the arithmetic mean.  If the whole-file
    mean nearly cancels, the strongest channel is used globally.  Otherwise a
    short-time OLA pass replaces only locally near-cancelling frames with their
    strongest channel, so a brief anti-phase passage is not erased from analysis
    while healthy stereo material retains the historical channel mean.

    Returns (mono, sr, strategy).
    """
    audio, sr = sf.read(path, dtype='float32', always_2d=True)
    if audio.shape[1] == 1:
        return audio[:, 0].copy(), sr, "mono"

    mono = audio.mean(axis=1).astype(np.float32)
    ch_rms = np.sqrt(np.mean(audio.astype(np.float64) ** 2, axis=0) + 1e-20)
    strong_idx = int(np.argmax(ch_rms))
    strong_rms = float(ch_rms[strong_idx])
    mean_rms = float(np.sqrt(np.mean(mono.astype(np.float64) ** 2) + 1e-20))

    if strong_rms > 1e-9 and mean_rms < 0.10 * strong_rms:
        return audio[:, strong_idx].copy(), sr, f"channel_{strong_idx + 1}_phase_safe"

    # Local cancellation protection.  Only frames whose channel mean collapses
    # below 10% of the strongest local channel are substituted.
    frame = max(64, int(round(0.040 * sr)))
    hop = max(32, frame // 2)
    win = np.hanning(frame).astype(np.float64)
    if not np.any(win):
        win = np.ones(frame, dtype=np.float64)
    acc = np.zeros(len(mono) + frame, dtype=np.float64)
    wacc = np.zeros(len(mono) + frame, dtype=np.float64)
    n_fallback = 0

    for start in range(0, len(mono), hop):
        end = min(len(mono), start + frame)
        n = end - start
        if n <= 0:
            continue
        block = audio[start:end].astype(np.float64)
        mean_block = block.mean(axis=1)
        local_ch_rms = np.sqrt(np.mean(block ** 2, axis=0) + 1e-20)
        local_strong = int(np.argmax(local_ch_rms))
        local_max = float(local_ch_rms[local_strong])
        local_mean = float(np.sqrt(np.mean(mean_block ** 2) + 1e-20))
        if local_max > 1e-9 and local_mean < 0.10 * local_max:
            chosen = block[:, local_strong]
            n_fallback += 1
        else:
            chosen = mean_block
        w = win[:n]
        # Hann is zero at an endpoint; keep a tiny floor so file edges are covered.
        w = np.maximum(w, 1e-4)
        acc[start:end] += chosen * w
        wacc[start:end] += w

    local = (acc[:len(mono)] / np.maximum(wacc[:len(mono)], 1e-12)).astype(np.float32)
    if n_fallback:
        return local, sr, f"adaptive_phase_safe_{n_fallback}_frames"
    return mono, sr, "channel_mean"


def save_audio(path, audio, sr):
    """Save float32 audio, clipping to [-1, 1]."""
    out = np.clip(audio, -1.0, 1.0).astype(np.float32)
    sf.write(path, out, sr, subtype='FLOAT')


def rms(x):
    return float(np.sqrt(np.mean(x ** 2) + 1e-12))


def crossfade(a, b, fade_samples):
    """Overlap-add crossfade between two buffers."""
    if fade_samples <= 0:
        return np.concatenate([a, b])
    fade_samples = min(fade_samples, len(a), len(b))
    fade_out = np.linspace(1.0, 0.0, fade_samples)
    fade_in  = np.linspace(0.0, 1.0, fade_samples)
    result   = np.concatenate([a[:-fade_samples],
                                a[-fade_samples:] * fade_out + b[:fade_samples] * fade_in,
                                b[fade_samples:]])
    return result


# =============================================================================
# SECTION 2 — SEGMENTATION  (Event Level)
# =============================================================================

def compute_onset_strength(audio, sr, hop=128):
    """
    Onset strength curve via half-wave rectified spectral flux.
    Returns (strength_curve, hop_size).
    """
    from scipy.signal import stft as scipy_stft
    n_fft = 1024
    _, _, Zxx = scipy_stft(audio, fs=sr, window="hann",
                           nperseg=n_fft, noverlap=n_fft - hop,
                           nfft=n_fft, boundary="zeros", padded=True)
    mag = np.abs(Zxx)  # (freq_bins, n_frames)
    flux = np.diff(mag, axis=1)
    flux = np.maximum(flux, 0).sum(axis=0)  # half-wave rectify + sum across freq
    flux = np.concatenate([[0.0], flux])
    return flux, hop


def pick_onsets(strength, sr, hop, min_gap_s=0.08, threshold_ratio=0.35):
    """
    Peak-pick the onset strength curve.
    Returns list of onset sample positions.
    """
    from scipy.signal import find_peaks as _find_peaks
    min_gap_frames = max(1, int(min_gap_s * sr / hop))
    mu    = strength.mean()
    sigma = strength.std()
    thr   = mu + threshold_ratio * sigma
    peak_idx, _ = _find_peaks(strength, height=thr, distance=min_gap_frames)
    peaks = sorted(set([0] + peak_idx.tolist()))
    return [p * hop for p in peaks]


def segment_events(audio, sr, min_dur_s=0.05, max_dur_s=4.0):
    """Segment audio by onsets while preserving the complete source timeline.

    Long onset intervals are divided into contiguous <= max_dur_s chunks instead
    of discarding everything after the first chunk.  A short trailing remainder
    is merged into the previous contiguous chunk when possible.
    """
    strength, hop = compute_onset_strength(audio, sr)
    onsets = pick_onsets(strength, sr, hop)
    onsets = sorted(set(max(0, min(len(audio), int(x))) for x in onsets))
    if not onsets or onsets[0] != 0:
        onsets = [0] + onsets
    if onsets[-1] != len(audio):
        onsets.append(len(audio))

    min_samples = max(1, int(min_dur_s * sr))
    max_samples = max(min_samples, int(max_dur_s * sr))

    spans = []
    for i in range(len(onsets) - 1):
        s0 = onsets[i]
        e0 = onsets[i + 1]
        if e0 <= s0:
            continue
        s = s0
        while s < e0:
            e = min(e0, s + max_samples)
            remain = e0 - e
            if 0 < remain < min_samples and (e - s) + remain <= max_samples + min_samples:
                e = e0
            spans.append([s, e])
            s = e

    # Merge tiny spans rather than dropping them, preserving source coverage.
    merged = []
    for s0, e0 in spans:
        if e0 - s0 >= min_samples or not merged:
            merged.append([s0, e0])
        elif merged[-1][1] == s0:
            merged[-1][1] = e0
        else:
            merged.append([s0, e0])

    if merged and merged[0][0] > 0:
        merged[0][0] = 0
    if merged and merged[-1][1] < len(audio):
        merged[-1][1] = len(audio)

    events = [
        {'start': int(s0), 'end': int(e0), 'audio': audio[int(s0):int(e0)].copy()}
        for s0, e0 in merged if e0 > s0
    ]

    if len(events) < 2:
        mid = len(audio) // 2
        events = [
            {'start': 0,   'end': mid,        'audio': audio[:mid].copy()},
            {'start': mid, 'end': len(audio), 'audio': audio[mid:].copy()}
        ]
    return events


# =============================================================================
# SECTION 3 — FEATURE EXTRACTION  (Event Level)
# =============================================================================

def spectral_centroid(audio, sr):
    spec = np.abs(np.fft.rfft(audio * np.hanning(len(audio)) if len(audio) >= 8 else audio))
    freqs = np.fft.rfftfreq(len(audio), 1.0/sr)
    total = spec.sum() + 1e-12
    return float((freqs * spec).sum() / total) / (sr / 2.0)   # normalised 0-1


def spectral_flatness(audio):
    spec = np.abs(np.fft.rfft(audio * np.hanning(len(audio)) if len(audio) >= 8 else audio)) + 1e-12
    geometric = np.exp(np.mean(np.log(spec)))
    arithmetic = spec.mean()
    return float(geometric / (arithmetic + 1e-12))


def harmonicity_estimate(audio, sr):
    """
    Estimate HNR via autocorrelation peak ratio in the 60-800 Hz range.
    Returns 0 (noisy) to 1 (harmonic).
    Uses an FFT autocorrelation: O(n log n) instead of np.correlate's O(n^2),
    which mattered for long (up to ~4 s) events.
    """
    n = len(audio)
    if n < 64:
        return 0.0
    # Linear autocorrelation via FFT (zero-pad to >= 2n-1 to avoid wrap-around)
    nfft = 1 << ((2 * n - 1).bit_length())
    spec = np.fft.rfft(audio, nfft)
    ac   = np.fft.irfft(spec * np.conj(spec), nfft)[:n]
    ac   = ac / (ac[0] + 1e-12)
    # Look for peak in 60-800 Hz range
    min_lag = max(1, int(sr / 800))
    max_lag = min(len(ac) - 1, int(sr / 60))
    if min_lag >= max_lag:
        return 0.0
    peak = ac[min_lag:max_lag].max()
    return float(np.clip(peak, 0.0, 1.0))


def onset_sharpness(audio, sr, pre_samples=64):
    """Ratio of RMS in first pre_samples vs full RMS."""
    pre = min(pre_samples, len(audio) // 4)
    return float(rms(audio[:pre]) / (rms(audio) + 1e-12))


def extract_event_features(ev, sr):
    """Return a feature dict for one event."""
    a = ev['audio']
    dur = len(a) / sr
    return {
        'duration':         dur,
        'rms':              rms(a),
        'centroid':         spectral_centroid(a, sr),
        'flatness':         spectral_flatness(a),
        'harmonicity':      harmonicity_estimate(a, sr),
        'onset_sharpness':  onset_sharpness(a, sr),
        'log_rms':          float(np.log(rms(a) + 1e-6)),
    }


def features_to_vector(f):
    """Convert feature dict to numpy vector (7-dim)."""
    return np.array([
        np.clip(f['duration'] / 4.0, 0, 1),
        np.clip(f['rms'] * 4.0, 0, 1),
        f['centroid'],
        f['flatness'],
        f['harmonicity'],
        f['onset_sharpness'],
        np.clip((f['log_rms'] + 12) / 12.0, 0, 1),
    ], dtype=np.float32)


# =============================================================================
# SECTION 4 — PHRASE GROUPING
# =============================================================================

def cosine_sim(a, b):
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))


def group_into_phrases(events, features_vecs, coherence=0.5, min_events=2, max_events=8):
    """
    Greedily group consecutive events into phrases
    based on feature similarity + coherence parameter.

    coherence: 0 = large heterogeneous phrases, 1 = tight homogeneous phrases
    Returns list of phrase dicts: {event_indices, centroid_vec}.
    """
    if len(events) == 0:
        return []

    # Similarity threshold derived from coherence
    threshold = 0.5 + 0.45 * coherence   # 0.5 – 0.95

    phrases  = []
    current  = [0]
    cur_vec  = features_vecs[0].copy()

    for i in range(1, len(events)):
        sim = cosine_sim(cur_vec, features_vecs[i])
        group_too_large = len(current) >= max_events
        group_ok_size   = len(current) >= min_events

        if (sim < threshold and group_ok_size) or group_too_large:
            centroid = np.mean([features_vecs[j] for j in current], axis=0)
            phrases.append({'event_indices': current, 'centroid': centroid})
            current = [i]
            cur_vec = features_vecs[i].copy()
        else:
            current.append(i)
            cur_vec = (cur_vec * (len(current)-1) + features_vecs[i]) / len(current)

    if current:
        centroid = np.mean([features_vecs[j] for j in current], axis=0)
        phrases.append({'event_indices': current, 'centroid': centroid})

    return phrases


def rebalance_phrases(events, features_vecs, n_phrases):
    """Create contiguous balanced phrase groups when a formal preset needs a
    minimum number of structural units that similarity grouping did not produce.
    This never invents audio; it only repartitions the existing event sequence.
    """
    n_ev = len(events)
    n_phrases = max(1, min(int(n_phrases), n_ev))
    bounds = np.linspace(0, n_ev, n_phrases + 1).astype(int)
    out = []
    for i in range(n_phrases):
        a, b = int(bounds[i]), int(bounds[i + 1])
        if b <= a:
            continue
        inds = list(range(a, b))
        centroid = np.mean(features_vecs[inds], axis=0)
        out.append({'event_indices': inds, 'centroid': centroid})
    return out


# =============================================================================
# SECTION 5 — SECTION DESCRIPTORS
# =============================================================================

def group_phrases_into_sections(phrases, events, n_sections=4):
    """Group contiguous phrases into real structural sections.

    Returns a list of dicts with phrase_indices, event_range and source span.
    """
    n_ph = len(phrases)
    if n_ph == 0:
        return []
    n_sections = max(1, min(int(n_sections), n_ph))
    bounds = np.linspace(0, n_ph, n_sections + 1).astype(int)
    sections = []
    for si in range(n_sections):
        p0, p1 = int(bounds[si]), int(bounds[si + 1])
        if p1 <= p0:
            continue
        pidx = list(range(p0, p1))
        evs = [ei for pi in pidx for ei in phrases[pi]['event_indices']]
        if not evs:
            continue
        e0, e1 = min(evs), max(evs)
        sections.append({
            'phrase_indices': pidx,
            'event_range': (e0, e1 + 1),
            'start': events[e0]['start'],
            'end': events[e1]['end'],
        })
    return sections


def compute_section_descriptors(events, features_list, sr, sections):
    """Compute descriptors for the actual phrase-derived sections."""
    out = []
    for sec in sections:
        idx_s, idx_e = sec['event_range']
        sel = features_list[idx_s:idx_e]
        if not sel:
            continue
        span = max(1e-6, (sec['end'] - sec['start']) / sr)
        out.append({
            'event_range': (idx_s, idx_e),
            'phrase_indices': list(sec['phrase_indices']),
            'start': sec['start'], 'end': sec['end'],
            'density': len(sel) / span,
            'brightness': float(np.mean([f['centroid'] for f in sel])),
            'harmonicity': float(np.mean([f['harmonicity'] for f in sel])),
            'flatness': float(np.mean([f['flatness'] for f in sel])),
            'mean_rms': float(np.mean([f['rms'] for f in sel])),
            'onset_sharpness': float(np.mean([f['onset_sharpness'] for f in sel])),
            'total_dur': float(sum(f['duration'] for f in sel)),
        })
    return out


def _norm01(values):
    x = np.asarray(values, dtype=np.float64)
    if x.size == 0:
        return x
    lo, hi = float(np.min(x)), float(np.max(x))
    if hi - lo < 1e-9:
        return np.full_like(x, 0.5, dtype=np.float64)
    return (x - lo) / (hi - lo)


def build_phrase_descriptor_plan(phrases, features_list):
    """Build a source-conditioned 16-slot plan from phrase acoustics.

    This is intentionally deterministic and musically interpretable.  It is
    blended with the seeded untrained neural prior, rather than claiming the
    random network has learned an acoustic representation.
    """
    rows = []
    raw = []
    for ph in phrases:
        fs = [features_list[i] for i in ph['event_indices']]
        if not fs:
            raw.append([0.5] * 8)
            continue
        raw.append([
            np.mean([f['rms'] for f in fs]),
            np.mean([f['centroid'] for f in fs]),
            np.mean([f['flatness'] for f in fs]),
            np.mean([f['harmonicity'] for f in fs]),
            np.mean([f['onset_sharpness'] for f in fs]),
            np.mean([f['duration'] for f in fs]),
            np.std([f['centroid'] for f in fs]),
            len(fs),
        ])
    A = np.asarray(raw, dtype=np.float64)
    rel = [_norm01(A[:, i]) for i in range(A.shape[1])]
    # Blend corpus-relative contrast with absolute normalized descriptors.  This
    # matters when the source collapses to a single phrase: relative normalization
    # alone would make every descriptor exactly 0.5 and erase source identity.
    abs_cols = [
        np.clip(A[:, 0] * 4.0, 0, 1),          # RMS
        np.clip(A[:, 1], 0, 1),                # spectral centroid already 0..1
        np.clip(A[:, 2], 0, 1),                # flatness
        np.clip(A[:, 3], 0, 1),                # harmonicity
        np.clip(A[:, 4] / 3.0, 0, 1),          # onset sharpness
        np.clip(A[:, 5] / 4.0, 0, 1),          # duration
        np.clip(A[:, 6] * 4.0, 0, 1),          # centroid variation
        np.clip(A[:, 7] / 8.0, 0, 1),          # event count
    ]
    cols = [0.40 * r + 0.60 * a for r, a in zip(rel, abs_cols)]
    rms_n, bright, flat, harm, sharp, dur, var, count = cols
    global_b = float(np.mean(bright)) if len(bright) else 0.5
    contrast = np.clip(np.abs(bright - global_b) * 1.6 + 0.45 * var + 0.25 * flat, 0, 1)
    pos = np.linspace(0, 1, len(phrases)) if phrases else np.array([])
    arc = np.sin(np.pi * pos) ** 2 if len(pos) else pos

    for i in range(len(phrases)):
        row = np.zeros(PLAN_DIM, dtype=np.float32)
        row[PLAN_SLOTS['repetition']] = np.clip(0.50 * harm[i] + 0.30 * (1-var[i]) + 0.20 * (1-count[i]), 0, 1)
        row[PLAN_SLOTS['fragmentation']] = np.clip(0.45 * sharp[i] + 0.30 * flat[i] + 0.25 * count[i], 0, 1)
        row[PLAN_SLOTS['overlap']] = np.clip(0.45 * harm[i] + 0.35 * dur[i] + 0.20 * (1-sharp[i]), 0, 1)
        row[PLAN_SLOTS['stretch']] = np.clip(0.55 * dur[i] + 0.30 * harm[i] + 0.15 * (1-count[i]), 0, 1)
        row[PLAN_SLOTS['foreground']] = np.clip(0.75 * rms_n[i] + 0.25 * sharp[i], 0, 1)
        row[PLAN_SLOTS['memory']] = np.clip(0.50 * harm[i] + 0.30 * (1-var[i]) + 0.20 * dur[i], 0, 1)
        row[PLAN_SLOTS['contrast']] = contrast[i]
        row[PLAN_SLOTS['inversion']] = np.clip(0.40 * flat[i] + 0.35 * contrast[i] + 0.25 * (1-harm[i]), 0, 1)
        row[PLAN_SLOTS['density_up']] = np.clip(0.55 * count[i] + 0.45 * sharp[i], 0, 1)
        row[PLAN_SLOTS['density_down']] = np.clip(1.0 - row[PLAN_SLOTS['density_up']], 0, 1)
        row[PLAN_SLOTS['braid']] = np.clip(0.55 * contrast[i] + 0.30 * count[i] + 0.15 * flat[i], 0, 1)
        row[PLAN_SLOTS['call_response']] = np.clip(0.65 * contrast[i] + 0.35 * sharp[i], 0, 1)
        row[PLAN_SLOTS['collapse']] = np.clip(0.45 * flat[i] + 0.35 * (1-rms_n[i]) + 0.20 * contrast[i], 0, 1)
        row[PLAN_SLOTS['restatement']] = np.clip(0.55 * harm[i] + 0.45 * (1-flat[i]), 0, 1)
        row[PLAN_SLOTS['surprise']] = np.clip(0.55 * contrast[i] + 0.45 * flat[i], 0, 1)
        row[PLAN_SLOTS['formal_weight']] = np.clip(0.55 * arc[i] + 0.30 * rms_n[i] + 0.15 * contrast[i], 0, 1)
        rows.append(row)
    return np.asarray(rows, dtype=np.float32)


def expand_section_plan_to_phrases(section_plan, sections, n_phrases):
    out = np.zeros((n_phrases, PLAN_DIM), dtype=np.float32)
    for si, sec in enumerate(sections):
        src = section_plan[min(si, len(section_plan)-1)]
        for pi in sec['phrase_indices']:
            if 0 <= pi < n_phrases:
                out[pi] = src
    return out


# =============================================================================
# SECTION 6 — PYTORCH HIERARCHICAL MODEL
# =============================================================================

EVENT_DIM   = 7
PHRASE_DIM  = 32
SECTION_DIM = 64
PLAN_DIM    = 16


class EventEncoder(BaseModule):
    """
    Projects raw event feature vectors into a latent event embedding.
    """
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(EVENT_DIM, 32),
            nn.LayerNorm(32),
            nn.GELU(),
            nn.Linear(32, 64),
            nn.LayerNorm(64),
            nn.GELU(),
            nn.Linear(64, PHRASE_DIM),
        )

    def forward(self, x):
        return self.net(x)


class PhraseEncoder(BaseModule):
    """
    Encodes a variable-length sequence of event embeddings into
    a single phrase embedding using a small transformer.
    """
    def __init__(self, max_events=8):
        super().__init__()
        self.pos_enc = nn.Embedding(max_events + 1, PHRASE_DIM)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=PHRASE_DIM, nhead=4, dim_feedforward=64,
            dropout=0.0, batch_first=True
        )
        self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=2)
        self.pool = nn.Linear(PHRASE_DIM, SECTION_DIM)

    def forward(self, event_embeddings):
        # event_embeddings: (seq_len, PHRASE_DIM)
        seq = event_embeddings.unsqueeze(0)   # (1, seq_len, PHRASE_DIM)
        T   = seq.size(1)
        pos = torch.arange(T, device=seq.device)
        seq = seq + self.pos_enc(pos).unsqueeze(0)
        out = self.transformer(seq)            # (1, seq_len, PHRASE_DIM)
        pooled = out.mean(dim=1)              # (1, PHRASE_DIM)
        return self.pool(pooled).squeeze(0)   # (SECTION_DIM,)


class SectionPlanner(BaseModule):
    """
    Takes section-level phrase embeddings and produces
    a recomposition plan vector per phrase.

    Uses a bidirectional GRU so each section is informed
    by both past and future context — enabling formal memory
    and anticipation.
    """
    def __init__(self, n_sections=4):
        super().__init__()
        self.gru = nn.GRU(
            input_size=SECTION_DIM, hidden_size=SECTION_DIM,
            num_layers=2, batch_first=True, bidirectional=True
        )
        self.plan_head = nn.Sequential(
            nn.Linear(SECTION_DIM * 2, SECTION_DIM),
            nn.GELU(),
            nn.Linear(SECTION_DIM, PLAN_DIM),
            nn.Sigmoid(),   # plan values in [0,1]
        )

    def forward(self, section_embeddings):
        # section_embeddings: (n_sections, SECTION_DIM)
        x   = section_embeddings.unsqueeze(0)      # (1, n_sections, SECTION_DIM)
        out, _ = self.gru(x)                       # (1, n_sections, SECTION_DIM*2)
        return self.plan_head(out.squeeze(0))      # (n_sections, PLAN_DIM)


class HierarchicalRecompositionModel(BaseModule):
    """
    Full three-level hierarchical model:
      raw features → event embeddings → phrase embeddings → section plan
    """
    def __init__(self):
        super().__init__()
        self.event_encoder   = EventEncoder()
        self.phrase_encoder  = PhraseEncoder()
        self.section_planner = SectionPlanner()

    def forward(self, phrase_event_tensors):
        """
        phrase_event_tensors: list of (n_events, EVENT_DIM) tensors, one per phrase.
        Returns:
          event_embs  : list of (n_events, PHRASE_DIM)
          phrase_embs : (n_phrases, SECTION_DIM)
          section_plan: (n_sections, PLAN_DIM)  — here n_sections = n_phrases
        """
        event_emb_list  = []
        phrase_emb_list = []

        for phrase_tensor in phrase_event_tensors:
            ev_embs = self.event_encoder(phrase_tensor)     # (n_ev, PHRASE_DIM)
            ph_emb  = self.phrase_encoder(ev_embs)          # (SECTION_DIM,)
            event_emb_list.append(ev_embs)
            phrase_emb_list.append(ph_emb)

        phrase_embs  = torch.stack(phrase_emb_list, dim=0)  # (n_phrases, SECTION_DIM)
        section_plan = self.section_planner(phrase_embs)    # (n_phrases, PLAN_DIM)

        return event_emb_list, phrase_embs, section_plan


# =============================================================================
# SECTION 7 — NUMPY FALLBACK MODEL (when PyTorch unavailable)
# =============================================================================

class NumpyFallbackModel:
    """
    Simple numpy approximation of the hierarchical model.
    Uses PCA-like projection and simple softmax attention.
    """
    def __init__(self, seed=42):
        rng = np.random.RandomState(seed)
        self.W_event   = rng.randn(EVENT_DIM, PHRASE_DIM).astype(np.float32) * 0.3
        self.W_phrase  = rng.randn(PHRASE_DIM, SECTION_DIM).astype(np.float32) * 0.3
        self.W_section = rng.randn(SECTION_DIM, PLAN_DIM).astype(np.float32) * 0.3

    def encode_events(self, x):
        h = np.tanh(x @ self.W_event)
        return h

    def encode_phrase(self, ev_embs):
        return np.tanh(ev_embs.mean(axis=0) @ self.W_phrase)

    def plan_sections(self, phrase_embs):
        plans = []
        for i, pe in enumerate(phrase_embs):
            # Simple context: self + weighted neighbours
            weights = np.array([np.exp(-abs(i-j)*0.5) for j in range(len(phrase_embs))])
            weights /= weights.sum() + 1e-8
            ctx = (np.array(phrase_embs) * weights[:, None]).sum(axis=0)
            plan = 1.0 / (1.0 + np.exp(-ctx @ self.W_section))   # sigmoid
            plans.append(plan.astype(np.float32))
        return np.array(plans)

    def forward(self, phrase_event_arrays):
        event_emb_list  = []
        phrase_emb_list = []
        for arr in phrase_event_arrays:
            ev  = self.encode_events(arr)
            ph  = self.encode_phrase(ev)
            event_emb_list.append(ev)
            phrase_emb_list.append(ph)
        section_plan = self.plan_sections(phrase_emb_list)
        return event_emb_list, np.array(phrase_emb_list), section_plan


# =============================================================================
# SECTION 8 — PLAN INTERPRETATION
# =============================================================================

# Plan vector slot assignments (indices into PLAN_DIM=16 vector)
PLAN_SLOTS = {
    'repetition':    0,   # tendency to repeat this phrase
    'fragmentation': 1,   # break phrase into sub-events
    'overlap':       2,   # overlap with next phrase
    'stretch':       3,   # time-stretch amount
    'foreground':    4,   # prominence / loudness weight
    'memory':        5,   # connect back to earlier material
    'contrast':      6,   # seek dissimilar phrase for juxtaposition
    'inversion':     7,   # time-reverse the phrase
    'density_up':    8,   # increase local event density
    'density_down':  9,   # decrease local event density
    'braid':         10,  # interleave with another phrase
    'call_response': 11,  # set up a call (odd) / response (even) pair
    'collapse':      12,  # sudden density drop → silence
    'restatement':   13,  # verbatim recall of an earlier phrase
    'surprise':      14,  # random structural disruption
    'formal_weight': 15,  # weight in final formal arc
}


def apply_compositional_params(section_plan_np, params):
    """Apply user controls as strong monotonic biases while preserving plan detail."""
    plan = np.asarray(section_plan_np, dtype=np.float32).copy()

    def mix_slot(name, control):
        col = PLAN_SLOTS[name]
        c = float(np.clip(control, 0.0, 1.0))
        plan[:, col] = np.clip(0.35 * plan[:, col] + 0.65 * c, 0, 1)

    mix_slot('repetition', params['repetition'])
    mix_slot('fragmentation', params['fragmentation'])
    mix_slot('overlap', params['overlap'])
    mix_slot('memory', params['memory'])
    mix_slot('contrast', params['contrast'])
    # Surprise should be able to turn completely off.
    plan[:, PLAN_SLOTS['surprise']] = np.clip(
        plan[:, PLAN_SLOTS['surprise']] * float(np.clip(params['surprise'], 0, 1)), 0, 1)
    return plan


# =============================================================================
# SECTION 9 — PRESET DEFINITIONS
# =============================================================================

PRESETS = {

    'LatentCounterpoint': {
        'description': (
            'Two or more phrase classes are extracted and braided into a '
            'polyphonic texture. Each phrase forms an independent voice '
            'defined by its timbral identity. Voices interweave, creating '
            'a multi-strand counterpoint from a single monophonic source.'
        ),
        'params': {
            'target_duration': 1.2, 'coherence': 0.7,
            'contrast': 0.8, 'memory': 0.3, 'repetition': 0.4,
            'fragmentation': 0.3, 'overlap': 0.6,
            'surprise': 0.2,
        },
        'ops': {'braid': True, 'polyphony': 2},
    },

    'MemorySpiral': {
        'description': (
            'Material accumulates in spiralling layers of recall. '
            'Earlier events return at increasing distances, folded '
            'into later phrases. The form curves back on itself '
            'while continuously elongating — a spiral, not a loop.'
        ),
        'params': {
            'target_duration': 1.5, 'coherence': 0.6,
            'contrast': 0.4, 'memory': 0.95, 'repetition': 0.7,
            'fragmentation': 0.2, 'overlap': 0.4,
            'surprise': 0.15,
        },
        'ops': {'memory_depth': 4, 'recurrence': True},
    },

    'FragmentedLitany': {
        'description': (
            'Short micro-events are actively sliced from source events and arranged into a slow, '
            'incantatory repetition. Each litany cycle slightly mutates '
            'the ordering or duration of its fragments. The form accumulates '
            'ritual weight through obsessive variation.'
        ),
        'params': {
            'target_duration': 1.3, 'coherence': 0.9,
            'contrast': 0.2, 'memory': 0.8, 'repetition': 0.9,
            'fragmentation': 0.95, 'overlap': 0.1,
            'surprise': 0.05,
        },
        'ops': {'litany_cycles': 3, 'micro_events': True},
    },

    'FormalBraiding': {
        'description': (
            'Three phrase classes — attack-heavy, sustained, and noisy — '
            'are braided into a single continuous strand. The braid '
            'periodically unravels and re-forms with different phase '
            'relationships, producing a dynamic formal weave.'
        ),
        'params': {
            'target_duration': 1.1, 'coherence': 0.5,
            'contrast': 0.75, 'memory': 0.5, 'repetition': 0.5,
            'fragmentation': 0.4, 'overlap': 0.7,
            'surprise': 0.35,
        },
        'ops': {'braid': True, 'n_strands': 3},
    },

    'CollapsingRefrain': {
        'description': (
            'A strong opening phrase acts as a refrain. It returns repeatedly, '
            'each return more fragmented, quieter, and spectrally eroded. '
            'The final statement collapses into isolated residual events. '
            'Form is built entirely by progressive dissolution.'
        ),
        'params': {
            'target_duration': 1.4, 'coherence': 0.6,
            'contrast': 0.5, 'memory': 0.85, 'repetition': 0.8,
            'fragmentation': 0.8, 'overlap': 0.2,
            'surprise': 0.1,
        },
        'ops': {'refrain': True, 'collapse_rate': 0.4},
    },

    'EchoArchitecture': {
        'description': (
            'Each event generates one or more echoes — slightly delayed '
            'and reduced in amplitude. Phrases are constructed by the '
            'layering of events with their echo trails. The result is '
            'a space-like architecture built from the source\'s own resonance.'
        ),
        'params': {
            'target_duration': 1.6, 'coherence': 0.55,
            'contrast': 0.3, 'memory': 0.6, 'repetition': 0.6,
            'fragmentation': 0.15, 'overlap': 0.8,
            'surprise': 0.2,
        },
        'ops': {'echo_depth': 3, 'echo_decay': 0.55},
    },

    'RecursiveSpeechChoir': {
        'description': (
            'The source is treated as a single utterance. Events '
            'corresponding to syllable-like onsets are extracted and '
            'redistributed into a multi-voice "choir" — the same material '
            'sung back to itself from multiple temporal positions simultaneously.'
        ),
        'params': {
            'target_duration': 1.0, 'coherence': 0.75,
            'contrast': 0.4, 'memory': 0.7, 'repetition': 0.65,
            'fragmentation': 0.2, 'overlap': 0.9,
            'surprise': 0.1,
        },
        'ops': {'choir_voices': 4, 'phase_offset': True},
    },

    'HiddenSonata': {
        'description': (
            'A classical three-part sonata form is projected onto the '
            'event/phrase structure: an exposition introduces two contrasting '
            'phrase groups, a development section fragments and combines them, '
            'and a recapitulation restates the opening material with a controlled transformation. '
            'The hidden sonata is latent inside the source.'
        ),
        'params': {
            'target_duration': 1.8, 'coherence': 0.65,
            'contrast': 0.7, 'memory': 0.9, 'repetition': 0.7,
            'fragmentation': 0.5, 'overlap': 0.35,
            'surprise': 0.25,
        },
        'ops': {'sonata_form': True, 'recapitulation': True},
    },
}


def get_preset(name, fallback_params):
    """Return preset params merged with fallback, or fallback if unknown."""
    if name in PRESETS:
        p = dict(fallback_params)
        p.update(PRESETS[name]['params'])
        return p, PRESETS[name].get('ops', {})
    return fallback_params, {}


# =============================================================================
# SECTION 10 — RECOMPOSITION PLAN EXECUTION
# =============================================================================

def build_event_similarity_matrix(feat_vecs):
    """
    Compute pairwise cosine similarity matrix for all events.
    Returns (N, N) numpy array.
    """
    X = np.array(feat_vecs, dtype=np.float32)
    norms = np.linalg.norm(X, axis=1, keepdims=True) + 1e-12
    X_n = X / norms
    return (X_n @ X_n.T).astype(np.float32)


def plan_event_ordering(events, feat_vecs, phrases, section_plan_np, params, ops, rng, sr):
    """Generate scheduled operations and keep cycling until target duration is covered."""
    sim_matrix = build_event_similarity_matrix(feat_vecs)
    ops_list = []
    cursor = 0.0
    target_dur = params.get('target_duration', 1.0) * sum(len(e['audio']) for e in events) / sr
    phrase_order = _plan_phrase_order(phrases, section_plan_np, params, ops, rng)
    if not phrase_order:
        return ops_list

    memory_bank = []
    refrain_returns = 0
    n_ph = len(phrases)
    sonata_exp = n_ph // 2 if ops.get('sonata_form') and n_ph >= 4 else 0
    sonata_dev = n_ph if sonata_exp else 0
    max_cycles = max(2, int(math.ceil(target_dur / max(0.05, sum(len(e['audio']) for e in events) / sr))) + 4)
    cycle = 0

    def slot(name):
        return PLAN_SLOTS[name]

    while cursor < target_dur and cycle < max_cycles:
        progressed = False
        for phrase_pos, phrase_idx in enumerate(phrase_order):
            if cursor >= target_dur:
                break
            phrase = phrases[int(phrase_idx)]
            plan_row = section_plan_np[min(int(phrase_idx), len(section_plan_np)-1)]
            ev_indices = list(phrase['event_indices'])
            if not ev_indices:
                continue

            # Sonata phase is explicit in the first formal pass and mutates gently
            # on later cycles used only to fill a longer requested duration.
            sonata_phase = 'none'
            if sonata_exp:
                if phrase_pos < sonata_exp:
                    sonata_phase = 'exposition'
                elif phrase_pos < sonata_exp + sonata_dev:
                    sonata_phase = 'development'
                else:
                    sonata_phase = 'recapitulation'

            # MemorySpiral: deterministic recursive recalls with increasing lookback.
            if memory_bank:
                do_recall = False
                recall_entry = None
                if ops.get('recurrence'):
                    depth = max(1, int(ops.get('memory_depth', 4)))
                    lookback = min(len(memory_bank), 1 + ((phrase_pos + cycle) % depth))
                    recall_entry = memory_bank[-lookback]
                    do_recall = True
                elif plan_row[slot('memory')] > 0.55 and rng.random() < plan_row[slot('memory')]:
                    recall_entry = rng.choice(memory_bank)
                    do_recall = True
                if do_recall and recall_entry is not None:
                    recall_phrase_idx, _ = recall_entry
                    recall_phrase = phrases[min(int(recall_phrase_idx), len(phrases)-1)]
                    for ei in recall_phrase['event_indices'][:2]:
                        dur_s = len(events[ei]['audio']) / sr
                        ops_list.append({
                            'type':'recall','event_idx':ei,'start_time':cursor,
                            'gain':0.58 if ops.get('recurrence') else 0.65,
                            'crossfade_ms':30,
                            'label':f'memory_recall(p{recall_phrase_idx})'})
                        cursor += min(dur_s * 0.42, max(0.0, target_dur-cursor))
                        if cursor >= target_dur:
                            break

            if cursor >= target_dur:
                break

            # Preset-level development forces real fragmentation/combination.
            force_fragment = sonata_phase == 'development'
            micro = bool(ops.get('micro_events'))
            if force_fragment or (plan_row[slot('fragmentation')] > 0.6 and rng.random() < plan_row[slot('fragmentation')]):
                sub_ev = int(rng.choice(ev_indices))
                if micro:
                    slice_ratio = rng.uniform(0.06, 0.22)
                elif force_fragment:
                    slice_ratio = rng.uniform(0.18, 0.38)
                else:
                    slice_ratio = rng.uniform(0.15, 0.45)
                ops_list.append({
                    'type':'fragment','event_idx':sub_ev,'start_time':cursor,
                    'gain':0.82,'crossfade_ms':10,'slice_ratio':slice_ratio,
                    'label':f'fragment(p{phrase_idx},e{sub_ev})'})
                dur_s = len(events[sub_ev]['audio']) / sr
                cursor += dur_s * slice_ratio * (0.65 if micro else 0.9)

            # Collapsing refrain: each return is shorter, quieter and more eroded.
            collapse_refrain = bool(ops.get('refrain')) and int(phrase_idx) == 0
            collapse_rate = float(ops.get('collapse_rate', 0.0))
            if collapse_refrain:
                refrain_returns += 1
            collapse_amount = np.clip((refrain_returns - 1) * collapse_rate, 0.0, 0.88) if collapse_refrain else 0.0

            for pos_in_phrase, ei in enumerate(ev_indices):
                if cursor >= target_dur:
                    break
                ev_dur_s = len(events[ei]['audio']) / sr

                if plan_row[slot('repetition')] > 0.5 and rng.random() < plan_row[slot('repetition')] * 0.4:
                    ops_list.append({
                        'type':'repeat','event_idx':ei,
                        'start_time':max(0.0, cursor-ev_dur_s*rng.uniform(0.0,0.3)),
                        'gain':0.7,'crossfade_ms':20,
                        'label':f'repeat(p{phrase_idx},e{ei})'})

                stretch = 1.0
                if plan_row[slot('stretch')] > 0.55:
                    stretch = 1.0 + (plan_row[slot('stretch')] - 0.5) * params.get('fragmentation',0.3)
                    stretch = float(np.clip(stretch,0.5,3.0))
                if sonata_phase == 'recapitulation' and ops.get('recapitulation'):
                    stretch *= 1.08

                if collapse_amount > 0:
                    # Later refrain statements progressively reduce to residual fragments.
                    if pos_in_phrase > 0 and rng.random() < collapse_amount * 0.75:
                        continue
                    slice_ratio = max(0.10, 1.0 - collapse_amount)
                    ops_list.append({
                        'type':'fragment','event_idx':ei,'start_time':cursor,
                        'gain':max(0.20, 1.0 - 0.65*collapse_amount),
                        'crossfade_ms':12,'slice_ratio':slice_ratio,
                        'erosion':collapse_amount,
                        'label':f'collapsing_refrain(r{refrain_returns},e{ei})'})
                    gap = ev_dur_s * slice_ratio
                else:
                    op = {
                        'type':'place','event_idx':ei,'start_time':cursor,'gain':1.0,
                        'crossfade_ms':int(20+plan_row[slot('overlap')]*80),
                        'stretch':stretch,'label':f'place(p{phrase_idx},e{ei})'}
                    if sonata_phase == 'recapitulation' and ops.get('recapitulation') and pos_in_phrase == 0:
                        op['erosion'] = 0.12
                    ops_list.append(op)
                    gap = ev_dur_s * stretch

                xfade_s = int(20 + plan_row[slot('overlap')] * 80) / 1000.0
                xfade_s = min(xfade_s, gap * 0.15)
                cursor += max(gap * 0.1, gap - xfade_s)
                progressed = True

            # Braid, and guaranteed combination during sonata development.
            do_braid = (ops.get('braid') and plan_row[slot('braid')] > 0.45) or force_fragment
            if do_braid and cursor < target_dur:
                contrast_idx = _find_contrast_phrase(int(phrase_idx), phrases, sim_matrix, feat_vecs, rng)
                if contrast_idx is not None:
                    braid_evs = phrases[contrast_idx]['event_indices']
                    braid_cursor = max(0.0, cursor - sum(len(events[ei]['audio'])/sr for ei in ev_indices)*0.5)
                    n_strands = max(2, int(ops.get('n_strands', ops.get('polyphony', 2))))
                    strand_pans = np.linspace(-0.78,0.78,n_strands)
                    for braid_i, bei in enumerate(braid_evs[:3]):
                        bop = {
                            'type':'braid','event_idx':bei,'start_time':braid_cursor,
                            'gain':0.55 if force_fragment else 0.6,'crossfade_ms':25,
                            'label':f'braid(p{phrase_idx}+p{contrast_idx},e{bei})'}
                        if ops.get('braid'):
                            bop['pan'] = float(strand_pans[braid_i % n_strands])
                        ops_list.append(bop)
                        braid_cursor += len(events[bei]['audio'])/sr * 0.7

            if plan_row[slot('collapse')] > 0.7 and not ops.get('refrain') and rng.random() < 0.3:
                cursor += min(rng.uniform(0.2,0.6), max(0.0,target_dur-cursor))

            if ops.get('echo_depth') and ev_indices:
                echo_decay = ops.get('echo_decay',0.5)
                echo_depth = int(ops.get('echo_depth',2))
                src_ev = ev_indices[0]
                ev_dur_s = len(events[src_ev]['audio'])/sr
                for ech in range(1,echo_depth+1):
                    echo_spread = min(0.85,0.28+0.18*ech)
                    echo_pan = -echo_spread if ech % 2 else echo_spread
                    ops_list.append({
                        'type':'echo','event_idx':src_ev,
                        'start_time':cursor+ev_dur_s*ech*0.6,
                        'gain':echo_decay**ech,'crossfade_ms':15,
                        'pan':float(echo_pan),
                        'label':f'echo{ech}(p{phrase_idx},e{src_ev})'})

            if plan_row[slot('inversion')] > 0.65 and rng.random() < 0.3:
                for ei in ev_indices[:2]:
                    if cursor >= target_dur:
                        break
                    ops_list.append({
                        'type':'invert','event_idx':ei,'start_time':cursor,
                        'gain':0.75,'crossfade_ms':15,
                        'label':f'invert(p{phrase_idx},e{ei})'})
                    cursor += len(events[ei]['audio'])/sr * 0.8

            memory_bank.append((int(phrase_idx), cursor))
            depth = max(4, int(ops.get('memory_depth', 8)))
            if len(memory_bank) > depth * 3:
                memory_bank = memory_bank[-depth*3:]

        if not progressed:
            break
        cycle += 1
        if cycle > 0 and cursor < target_dur:
            # Mutate subsequent fill cycles without changing determinism.
            if params.get('surprise',0.0) > 0:
                phrase_order = phrase_order[:]
                if len(phrase_order) > 1:
                    shift = 1 + (cycle % len(phrase_order))
                    phrase_order = phrase_order[shift:] + phrase_order[:shift]

    # Guarantee audible coverage to the target boundary.  Cursor can reach the
    # target via overlap/gap arithmetic before the last scheduled waveform does.
    def _sched_end(op):
        ei = int(op.get('event_idx', -1))
        if ei < 0 or ei >= len(events):
            return 0.0
        a = np.asarray(events[ei]['audio'])
        if op.get('type') == 'invert':
            a = a[::-1]
        if op.get('type') == 'fragment':
            nfrag = max(1, int(len(a) * float(op.get('slice_ratio', 0.3))))
            a = a[:nfrag]
        if len(a) == 0:
            return float(op.get('start_time', 0.0))
        active = np.flatnonzero(np.abs(a) > 1e-5)
        if len(active) == 0:
            return float(op.get('start_time', 0.0))
        active_len = int(active[-1] + 1)
        stretch = float(op.get('stretch', 1.0))
        return float(op.get('start_time', 0.0)) + active_len * stretch / sr

    audible_end = max((_sched_end(op) for op in ops_list), default=0.0)
    if target_dur - audible_end > 0.010 and events:
        # Choose a source event with energy at one edge.  If its attack is
        # stronger than its tail, reverse it so the target boundary is reached
        # by audible material rather than by a silent source tail.
        edge_scores = []
        edge_reverse = []
        for ev in events:
            a = ev['audio']
            q = max(16, len(a) // 4)
            head = rms(a[:q]) if len(a) else 0.0
            tail = rms(a[-q:]) if len(a) else 0.0
            edge_scores.append(max(head, tail))
            edge_reverse.append(head > tail)
        fill_ei = int(np.argmax(edge_scores))
        fill_dur = len(events[fill_ei]['audio']) / sr
        fill_start = max(0.0, target_dur - fill_dur)
        ops_list.append({
            'type':'invert' if edge_reverse[fill_ei] else 'place',
            'event_idx':fill_ei,'start_time':fill_start,
            'gain':0.72,'crossfade_ms':35,'stretch':1.0,
            'label':'duration_fill'})

    return ops_list


def _plan_phrase_order(phrases, section_plan_np, params, ops, rng):
    """
    Decide the order in which phrases appear in the output.
    Implements sonata-like structure if ops['sonata_form'] is True.
    Otherwise uses formal arc from plan weights.
    """
    n = len(phrases)
    indices = list(range(n))

    if ops.get('sonata_form') and n >= 4:
        # Exposition: first half | Development: fragmented | Recapitulation: first
        mid = n // 2
        exposition    = indices[:mid]
        development   = sorted(indices, key=lambda i: -section_plan_np[min(i, len(section_plan_np)-1), PLAN_SLOTS['contrast']])
        recapitulation = indices[:max(2, mid//2)]
        return exposition + development + recapitulation

    if ops.get('refrain') and n >= 2:
        refrain_idx = 0
        body = [i for i in indices if i != refrain_idx]
        order = []
        for i, b in enumerate(body):
            order.append(b)
            if (i + 1) % 2 == 0:
                order.append(refrain_idx)  # insert refrain periodically
        order.append(refrain_idx)
        return order

    if ops.get('litany_cycles'):
        cycles = ops['litany_cycles']
        block  = indices[:max(1, n // 3)]
        order  = []
        for c in range(cycles):
            shuffled = block[:]
            rng.shuffle(shuffled)
            order += shuffled
        return order

    # Default: sort by formal_weight, inject repeats and contrasts
    formal_weights = [
        float(section_plan_np[min(i, len(section_plan_np)-1), PLAN_SLOTS['formal_weight']])
        for i in indices
    ]
    order = sorted(indices, key=lambda i: formal_weights[i])

    # Sprinkle repetitions
    rep_thresh = params.get('repetition', 0.5)
    final_order = []
    for idx in order:
        final_order.append(idx)
        if rng.random() < rep_thresh * 0.4:
            final_order.append(idx)

    # Surprise: random transpositions
    surprise = params.get('surprise', 0.2)
    if surprise > 0.3 and len(final_order) >= 2:
        n_swaps = int(len(final_order) * surprise * 0.5)
        hi = len(final_order) - 1   # randint is INCLUSIVE; must not exceed last index
        for _ in range(n_swaps):
            i, j = rng.randint(0, hi), rng.randint(0, hi)
            final_order[i], final_order[j] = final_order[j], final_order[i]

    return final_order


def _find_contrast_phrase(phrase_idx, phrases, sim_matrix, feat_vecs, rng):
    """Find the phrase most dissimilar to phrase_idx."""
    n = len(phrases)
    if n < 2:
        return None
    # Average sim across events
    ev_i = phrases[phrase_idx]['event_indices']
    scores = []
    for j in range(n):
        if j == phrase_idx:
            scores.append(1.0)
            continue
        ev_j = phrases[j]['event_indices']
        pairs = [(a, b) for a in ev_i for b in ev_j]
        avg_sim = np.mean([sim_matrix[a, b] for a, b in pairs]) if pairs else 0.5
        scores.append(avg_sim)
    return int(np.argmin(scores))


# =============================================================================
# SECTION 11 — AUDIO RENDERING
# =============================================================================

def time_stretch_naive(audio, ratio):
    """
    Very simple time stretch via resampling (pitch changes).
    For a true pitch-preserving stretch, replace with phase vocoder.
    """
    if abs(ratio - 1.0) < 0.01:
        return audio
    n_out = max(1, int(len(audio) * ratio))
    indices = np.linspace(0, len(audio) - 1, n_out)
    return np.interp(indices, np.arange(len(audio)), audio).astype(np.float32)


def equal_power_pan_gains(pan):
    """Return equal-power (left, right) gains for pan in [-1, +1]."""
    p = float(np.clip(pan, -1.0, 1.0))
    theta = (p + 1.0) * (math.pi / 4.0)
    return float(math.cos(theta)), float(math.sin(theta))


def pan_mono_buffer(audio, pan):
    """Place an already-rendered mono buffer in stereo without changing it first."""
    audio = np.asarray(audio, dtype=np.float32).reshape(-1)
    gl, gr = equal_power_pan_gains(pan)
    return np.column_stack((audio * gl, audio * gr)).astype(np.float32)


def render_ops(ops_list, events, sr, target_dur_s, overlap_default_ms=20):
    """
    Render a sequence of operation dicts to an audio buffer.

    Design decisions to avoid tremolo / amplitude flutter:
    - Crossfade envelopes are applied ONLY at junctions where two events
      genuinely overlap (determined by whether the next op starts before
      the current one ends).  Non-overlapping events get short 5 ms de-click fades at both edges;
      longer fades are applied only where overlaps genuinely occur.
    - The weight-division normalisation is REMOVED.  Amplitude is
      controlled solely by per-event gain.  Polyphonic passages that
      overlap will naturally sum; a single soft-limiter at the end
      prevents clipping without modulating the envelope.
    - 'place' ops always use gain = 1.0 (set at call site). Secondary
      ops (repeat, recall, braid, echo) keep their lower gain so they
      blend without competing.
    """
    if not ops_list:
        return np.zeros(int(sr * 1.0), dtype=np.float32)

    # ── Filter and sort by start_time ────────────────────────────────────
    valid_ops = [op for op in ops_list if 0 <= op['event_idx'] < len(events)]
    if not valid_ops:
        return np.zeros(int(sr * max(target_dur_s, 1.0)), dtype=np.float32)

    valid_ops = sorted(valid_ops, key=lambda o: o['start_time'])

    # ── Size output buffer ───────────────────────────────────────────────
    max_time = max(
        max(0.0, op['start_time']) + len(events[op['event_idx']]['audio']) / sr
        for op in valid_ops
    )
    total_samples = int(max(max_time, target_dur_s) * sr) + sr
    spatial = any(abs(float(op.get('pan', 0.0))) > 1e-9 for op in valid_ops)
    if spatial:
        output = np.zeros((total_samples, 2), dtype=np.float32)
    else:
        # Preserve the exact historical mono code path for non-spatial presets.
        output = np.zeros(total_samples, dtype=np.float32)

    # Build a list of (start_samp, end_samp) for overlap detection
    placements = []   # filled per-op below, used to decide crossfade length

    declick_samples = max(1, int(0.005 * sr))   # 5 ms de-click fade-in only

    for idx, op in enumerate(valid_ops):
        ei   = op['event_idx']
        raw  = events[ei]['audio'].copy()
        gain = float(op.get('gain', 1.0))

        # ── Audio transforms ─────────────────────────────────────────────
        if op['type'] == 'invert':
            raw = raw[::-1].copy()

        if op['type'] == 'fragment':
            ratio = float(op.get('slice_ratio', 0.3))
            raw   = raw[:max(1, int(len(raw) * ratio))]

        erosion = float(np.clip(op.get('erosion', 0.0), 0.0, 1.0))
        if erosion > 1e-6 and len(raw) > 16:
            # Progressive spectral erosion for collapsing/recap transformations.
            cutoff = max(180.0, (0.48 - 0.40 * erosion) * sr)
            cutoff = min(cutoff, sr * 0.49)
            try:
                sos = signal.butter(2, cutoff, btype='lowpass', fs=sr, output='sos')
                raw = signal.sosfilt(sos, raw).astype(np.float32)
            except Exception:
                pass

        if op['type'] in ('place', 'recall', 'repeat', 'braid', 'echo', 'invert', 'fragment'):
            stretch = float(op.get('stretch', 1.0))
            if abs(stretch - 1.0) > 0.02:
                raw = time_stretch_naive(raw, stretch)

        if len(raw) == 0:
            continue

        raw = raw * gain

        # ── Placement ────────────────────────────────────────────────────
        skip = max(0, -int(op['start_time'] * sr))
        if skip >= len(raw):
            continue
        raw = raw[skip:]

        start_samp = max(0, int(op['start_time'] * sr))
        end_samp   = start_samp + len(raw)

        if len(raw) == 0:
            continue

        # ── Crossfade only where this event overlaps the PREVIOUS placed event ──
        # Find the most recent placement that overlaps our start
        xfade_samples = 0
        for prev_start, prev_end in reversed(placements):
            if prev_end > start_samp:
                # Overlap: fade for the overlapping region, capped at crossfade_ms
                max_xfade_ms = op.get('crossfade_ms', overlap_default_ms)
                max_xfade_s  = int(max_xfade_ms * sr / 1000.0)
                xfade_samples = min(max_xfade_s, prev_end - start_samp, len(raw) // 2)
                break

        # Apply fade-in at the junction (de-click or crossfade)
        fade_in_len = max(declick_samples, xfade_samples)
        fade_in_len = min(fade_in_len, len(raw) // 2)
        if fade_in_len > 0:
            raw[:fade_in_len] *= np.linspace(0.0, 1.0, fade_in_len, dtype=np.float32)

        # Apply fade-out ONLY if this event overlaps the NEXT placed event
        # (look-ahead: check if any later op starts before our end_samp)
        fade_out_len = declick_samples  # always a tiny de-click at tail
        for nxt_op in valid_ops[idx+1:idx+6]:   # check next 5 ops only
            nxt_start = max(0, int(nxt_op['start_time'] * sr))
            if nxt_start < end_samp:
                max_xfade_ms = nxt_op.get('crossfade_ms', overlap_default_ms)
                max_xfade_s  = int(max_xfade_ms * sr / 1000.0)
                fade_out_len = min(max_xfade_s, end_samp - nxt_start, len(raw) // 2)
                break
        fade_out_len = max(declick_samples, fade_out_len)
        fade_out_len = min(fade_out_len, len(raw) // 2)
        if fade_out_len > 0:
            raw[-fade_out_len:] *= np.linspace(1.0, 0.0, fade_out_len, dtype=np.float32)

        # ── Write into buffer ─────────────────────────────────────────────
        if end_samp > len(output):
            pad = end_samp - len(output)
            if spatial:
                output = np.concatenate(
                    [output, np.zeros((pad, 2), dtype=np.float32)], axis=0)
            else:
                output = np.concatenate([output, np.zeros(pad, dtype=np.float32)])

        if spatial:
            gl, gr = equal_power_pan_gains(op.get('pan', 0.0))
            output[start_samp:end_samp, 0] += raw * gl
            output[start_samp:end_samp, 1] += raw * gr
        else:
            output[start_samp:end_samp] += raw
        placements.append((start_samp, end_samp))

    # ── Trim to target duration ──────────────────────────────────────────
    tgt = int(target_dur_s * sr)
    if len(output) > tgt:
        output = output[:tgt]
    elif len(output) < tgt:
        pad = tgt - len(output)
        if spatial:
            output = np.concatenate(
                [output, np.zeros((pad, 2), dtype=np.float32)], axis=0)
        else:
            output = np.concatenate([output, np.zeros(pad, dtype=np.float32)])

    # ── Soft-limiter: smooth tanh squash, then normalise to -1 dBFS ─────
    # This does NOT create amplitude modulation — it is a static memoryless
    # function applied sample-by-sample.
    peak = float(np.abs(output).max())
    if peak > 0.01:
        # Scale so loudest moment enters tanh at ~0.9 (gentle knee)
        drive  = min(0.9 / peak, 4.0)
        output = np.tanh(output * drive).astype(np.float32)
        # Final normalise to 0.92 peak
        post_peak = float(np.abs(output).max())
        if post_peak > 0.01:
            output = output / post_peak * 0.92

    return output.astype(np.float32)


# =============================================================================
# SECTION 12 — STATS FILE OUTPUT
# =============================================================================

def write_stats(path, stats):
    lines = [f"{k}={v}" for k, v in stats.items()]
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')


# =============================================================================
# SECTION 13 — MAIN ENTRY POINT
# =============================================================================

def parse_args(argv):
    """
    argv order (matching Praat runSystem call):
      [0] input_wav
      [1] output_wav
      [2] stats_txt
      [3] target_duration_ratio   (0.5 – 3.0)
      [4] density                 LEGACY / currently inactive
      [5] coherence               (0.0 – 1.0)
      [6] contrast                (0.0 – 1.0)
      [7] memory                  (0.0 – 1.0)
      [8] repetition              (0.0 – 1.0)
      [9] fragmentation           (0.0 – 1.0)
      [10] overlap                (0.0 – 1.0)
      [11] source_trace           LEGACY / currently inactive
      [12] surprise               (0.0 – 1.0)
      [13] seed                   (integer)
      [14] preset_name            (string or "Custom")
    """
    def f(i, default):
        try:
            return float(argv[i])
        except (IndexError, ValueError):
            return default

    def s(i, default):
        try:
            return argv[i]
        except IndexError:
            return default

    return {
        'input':     argv[0],
        'output':    argv[1],
        'stats':     argv[2],
        'params': {
            'target_duration': f(3, 1.0),
            'density':         f(4, 0.5),
            'coherence':       f(5, 0.5),
            'contrast':        f(6, 0.5),
            'memory':          f(7, 0.5),
            'repetition':      f(8, 0.5),
            'fragmentation':   f(9, 0.3),
            'overlap':         f(10, 0.3),
            'source_trace':    f(11, 0.85),
            'surprise':        f(12, 0.2),
        },
        'seed':   int(f(13, 42)),
        'preset': s(14, 'Custom'),
    }


def main():
    if len(sys.argv) < 3:
        print("Usage: hierarchical_recomposition.py input.wav output.wav stats.txt [params...] [preset]")
        sys.exit(1)

    cfg    = parse_args(sys.argv[1:])
    params = cfg['params']
    preset_name = cfg['preset']

    # Apply preset overrides
    params, ops = get_preset(preset_name, params)

    # Legacy controls kept only for positional CLI compatibility. They are not
    # part of the current renderer/planner (source_trace was deliberately removed).

    seed = cfg['seed']
    rng  = random.Random(seed)
    np_rng = np.random.RandomState(seed)
    # Reseed numpy random for the run
    np.random.seed(seed)

    print(f"[HNR] Preset: {preset_name} | Seed: {seed}", flush=True)
    print(f"[HNR] Loading audio: {cfg['input']}", flush=True)

    audio, sr, mono_strategy = load_audio(cfg['input'])
    dur_in    = len(audio) / sr
    print(f"[HNR] Duration: {dur_in:.2f}s | SR: {sr}Hz | mono={mono_strategy}", flush=True)

    # ── Stage 1: Segmentation ────────────────────────────────────────────
    print("[1/6] Segmenting events...", flush=True)
    min_dur = max(0.03, 0.04 * (1.0 - params['fragmentation']))
    max_dur = 1.0 if ops.get('micro_events') else 4.0
    events  = segment_events(audio, sr, min_dur_s=min_dur, max_dur_s=max_dur)
    n_ev    = len(events)
    print(f"      {n_ev} events found.", flush=True)

    # ── Stage 2: Feature extraction ──────────────────────────────────────
    print("[2/6] Extracting features...", flush=True)
    features_list = [extract_event_features(ev, sr) for ev in events]
    feat_vecs     = np.array([features_to_vector(f) for f in features_list])

    # ── Stage 3: Phrase grouping ─────────────────────────────────────────
    print("[3/6] Grouping phrases...", flush=True)
    phrases = group_into_phrases(events, feat_vecs,
                                  coherence=params['coherence'])
    # Formal presets require enough structural units for their defining mechanism.
    min_form_phrases = 1
    if ops.get('sonata_form'):
        min_form_phrases = 4
    elif ops.get('n_strands', 0) >= 3:
        min_form_phrases = 3
    elif ops.get('braid'):
        min_form_phrases = 2
    elif ops.get('refrain'):
        min_form_phrases = 2
    if len(phrases) < min_form_phrases and len(events) >= min_form_phrases:
        phrases = rebalance_phrases(events, feat_vecs, min_form_phrases)
    n_ph = len(phrases)
    print(f"      {n_ph} phrases found.", flush=True)

    # ── Stage 4: Real phrase-derived sections ────────────────────────────
    print("[4/6] Building sections + descriptors...", flush=True)
    n_sections_target = max(1, min(8, int(round(math.sqrt(max(1, n_ph))))))
    phrase_sections = group_phrases_into_sections(phrases, events, n_sections_target)
    sections = compute_section_descriptors(events, features_list, sr, phrase_sections)
    print(f"      {len(sections)} sections found.", flush=True)

    # ── Stage 5: Hierarchical model ──────────────────────────────────────
    print("[5/6] Running descriptor-conditioned hierarchical model...", flush=True)
    if TORCH_OK:
        torch.manual_seed(seed)
    np.random.seed(seed)

    phrase_arrays = [feat_vecs[ph['event_indices']] for ph in phrases]

    if TORCH_OK:
        model = HierarchicalRecompositionModel()
        model.eval()
        with torch.no_grad():
            phrase_tensors = [torch.from_numpy(arr) for arr in phrase_arrays]
            event_embs = []
            phrase_emb_list = []
            for pt in phrase_tensors:
                ee = model.event_encoder(pt)
                pe = model.phrase_encoder(ee)
                event_embs.append(ee)
                phrase_emb_list.append(pe)
            phrase_embs = torch.stack(phrase_emb_list, dim=0)
            section_emb_list = []
            for sec in phrase_sections:
                idx = torch.tensor(sec['phrase_indices'], dtype=torch.long)
                section_emb_list.append(phrase_embs.index_select(0, idx).mean(dim=0))
            section_embs = torch.stack(section_emb_list, dim=0)
            section_plan_t = model.section_planner(section_embs)
        neural_section_plan = section_plan_t.numpy()
        phrase_embs_np = phrase_embs.numpy()
    else:
        fb_model = NumpyFallbackModel(seed=seed)
        event_embs = []
        phrase_embs_list = []
        for arr in phrase_arrays:
            ee = fb_model.encode_events(arr)
            pe = fb_model.encode_phrase(ee)
            event_embs.append(ee)
            phrase_embs_list.append(pe)
        phrase_embs_np = np.asarray(phrase_embs_list, dtype=np.float32)
        section_embs_np = np.asarray([
            phrase_embs_np[sec['phrase_indices']].mean(axis=0)
            for sec in phrase_sections], dtype=np.float32)
        neural_section_plan = fb_model.plan_sections(section_embs_np)

    neural_phrase_plan = expand_section_plan_to_phrases(
        neural_section_plan, phrase_sections, n_ph)
    descriptor_phrase_plan = build_phrase_descriptor_plan(phrases, features_list)
    # Acoustic descriptors dominate; the seeded untrained network contributes
    # contextual/formal variation without overwhelming source conditioning.
    section_plan_np = np.clip(
        0.20 * neural_phrase_plan + 0.80 * descriptor_phrase_plan, 0, 1).astype(np.float32)

    # Apply user/preset controls after source conditioning.
    section_plan_np = apply_compositional_params(section_plan_np, params)

    # ── Stage 6: Recomposition & rendering ───────────────────────────────
    print("[6/6] Building recomposition plan & rendering...", flush=True)

    # ── Choir mode: multiple offset copies ───────────────────────────────
    n_voices   = ops.get('choir_voices', 1)
    target_dur = dur_in * params['target_duration']

    visual_ops = []
    spatial_mode = "mono"
    if n_voices > 1:
        # Render each voice through the historical mono renderer first, then
        # distribute the completed voices with equal-power panning. This keeps
        # each voice's internal sound identical and changes only its location.
        voice_buffers = []
        voice_pans = np.linspace(-0.85, 0.85, n_voices)
        for v in range(n_voices):
            v_seed = seed + v * 137
            v_rng  = random.Random(v_seed)
            v_np   = np.random.RandomState(v_seed)
            v_plan = section_plan_np.copy()
            v_plan = v_plan + v_np.randn(*v_plan.shape) * 0.05
            v_plan = np.clip(v_plan, 0, 1)
            v_ops  = plan_event_ordering(
                events, feat_vecs, phrases, v_plan, params, ops, v_rng, sr)
            offset = (v * dur_in / n_voices * 0.3) if ops.get('phase_offset', False) else 0.0
            voice_pan = float(voice_pans[v])
            for op in v_ops:
                op['start_time'] += offset
                op['gain']       *= (1.0 - v * 0.18)
                op['pan']         = voice_pan
                op['voice']       = v + 1
            visual_ops.extend(v_ops)
            # Deliberately remove pan only for the per-voice render so the
            # pre-pan voice buffer is sample-identical to v1.3.
            mono_ops = [dict(op, pan=0.0) for op in v_ops]
            buf = render_ops(mono_ops, events, sr, target_dur)
            voice_buffers.append(pan_mono_buffer(buf, voice_pan))

        max_len = max(len(b) for b in voice_buffers)
        output_audio = np.zeros((max_len, 2), dtype=np.float32)
        for buf in voice_buffers:
            output_audio[:len(buf), :] += buf / n_voices
        spatial_mode = f"choir_{n_voices}_voices"
    else:
        plan_ops = plan_event_ordering(
            events, feat_vecs, phrases, section_plan_np, params, ops, rng, sr)
        visual_ops = plan_ops
        output_audio = render_ops(plan_ops, events, sr, target_dur)
        if output_audio.ndim == 2:
            if ops.get('echo_depth'):
                spatial_mode = "echo_alternating"
            elif ops.get('braid'):
                spatial_mode = "braid_strands"
            else:
                spatial_mode = "operation_pan"

    # ── Source trace: removed ────────────────────────────────────────────
    # The review noted this layer is unnecessary: the recomposition already
    # preserves source identity structurally. More importantly, mixing a
    # time-stretched copy of the original back into the output at any ratio
    # creates comb filtering and amplitude beating (tremolo) because the
    # stretched signal is partially correlated with the summed events at
    # unpredictable phase relationships. Removed entirely.

    # Final normalise (single-pass, no modulation)
    peak = float(np.abs(output_audio).max())
    if peak > 0.01:
        output_audio = (output_audio / peak * 0.92).astype(np.float32)

    save_audio(cfg['output'], output_audio, sr)
    print(f"[HNR] Output written: {cfg['output']}", flush=True)
    print(f"[HNR] Output duration: {len(output_audio)/sr:.2f}s", flush=True)

    # ── Write stats + process-visualization telemetry ────────────────────
    if output_audio.ndim == 2:
        activity = np.max(np.abs(output_audio), axis=1)
    else:
        activity = np.abs(output_audio)
    nz = np.flatnonzero(activity > 1e-5)
    content_end_s = (float(nz[-1] + 1) / sr) if len(nz) else 0.0

    stats = {
        'n_events':       n_ev,
        'n_phrases':      n_ph,
        'n_sections':     len(sections),
        'input_duration': f'{dur_in:.3f}',
        'output_duration':f'{len(output_audio)/sr:.3f}',
        'preset':         preset_name,
        'seed':           seed,
        'torch_used':     int(TORCH_OK),
        'neural_model':   'descriptor_conditioned_seeded_untrained' if TORCH_OK else 'descriptor_conditioned_numpy_fallback',
        'mono_strategy':  mono_strategy,
        'spatial_mode':   spatial_mode,
        'output_channels': (output_audio.shape[1] if output_audio.ndim == 2 else 1),
        'mean_density':   f'{np.mean([s["density"] for s in sections]):.3f}' if sections else '0',
        'mean_brightness':f'{np.mean([s["brightness"] for s in sections]):.3f}' if sections else '0',
        'plan_rows':      len(section_plan_np),
        'target_duration_s': f'{target_dur:.4f}',
        'content_end_s': f'{content_end_s:.4f}',
        'trailing_silence_s': f'{max(0.0, target_dur-content_end_s):.4f}',
        'n_voices':       n_voices,
        'used_target_duration': f'{params["target_duration"]:.4f}',
        'used_coherence': f'{params["coherence"]:.4f}',
        'used_contrast': f'{params["contrast"]:.4f}',
        'used_memory': f'{params["memory"]:.4f}',
        'used_repetition': f'{params["repetition"]:.4f}',
        'used_fragmentation': f'{params["fragmentation"]:.4f}',
        'used_overlap': f'{params["overlap"]:.4f}',
        'used_surprise': f'{params["surprise"]:.4f}',
    }

    # Actual plan values used by the scheduler (after user-parameter modulation).
    for key in ('repetition', 'fragmentation', 'overlap', 'stretch',
                'memory', 'braid', 'inversion', 'collapse'):
        col = PLAN_SLOTS[key]
        stats[f'plan_{key}_mean'] = f'{float(np.mean(section_plan_np[:, col])):.4f}'

    # The generated plan itself, one row per phrase and one column per slot.
    # Only eight column means were reported before, which is not enough to see
    # whether the planner actually differentiated the phrases.
    n_plan_rows_all = len(section_plan_np)
    stats['n_plan_cols'] = section_plan_np.shape[1] if n_plan_rows_all else 0
    for name, col in PLAN_SLOTS.items():
        stats[f'plan_col_{col}'] = name
    max_plan_viz = 40
    if n_plan_rows_all <= max_plan_viz:
        plan_viz_idx = np.arange(n_plan_rows_all, dtype=int)
    else:
        plan_viz_idx = np.unique(
            np.linspace(0, n_plan_rows_all - 1, max_plan_viz).astype(int))
    stats['n_plan_viz'] = len(plan_viz_idx)
    stats['plan_rows_all'] = n_plan_rows_all
    # How much the planner actually differentiated the phrases: the mean, over
    # slots, of the spread across plan rows. Near zero means every phrase got
    # essentially the same plan, which a heatmap alone can look like either way.
    if n_plan_rows_all > 1:
        stats['plan_row_spread'] = '%.4f' % float(np.mean(np.std(section_plan_np, axis=0)))
    else:
        stats['plan_row_spread'] = '0.0000'
    for j, pi in enumerate(plan_viz_idx):
        stats[f'plan_row_index_{j}'] = int(pi)
        stats[f'plan_row_{j}'] = ','.join(
            f'{float(v):.4f}' for v in section_plan_np[int(pi)])

    # Actual section spans and phrase membership.
    stats['n_section_viz'] = len(phrase_sections)
    for si, sec in enumerate(phrase_sections):
        p0 = sec['phrase_indices'][0] if sec['phrase_indices'] else -1
        p1 = sec['phrase_indices'][-1] if sec['phrase_indices'] else -1
        stats[f'section_{si}'] = (
            f'{sec["start"]/sr:.6f},{sec["end"]/sr:.6f},{p0},{p1}')

    # Map source events to their actual phrase membership.
    event_phrase = np.full(n_ev, -1, dtype=int)
    for pi, ph in enumerate(phrases):
        for ei in ph['event_indices']:
            if 0 <= ei < n_ev:
                event_phrase[ei] = pi

    # Source-event telemetry. Downsample only for drawing; phrase spans are
    # reported separately so the hierarchy remains truthful on dense material.
    max_event_viz = 120
    if n_ev <= max_event_viz:
        event_viz_idx = np.arange(n_ev, dtype=int)
    else:
        event_viz_idx = np.unique(
            np.linspace(0, n_ev - 1, max_event_viz).astype(int))
    stats['n_event_viz'] = len(event_viz_idx)
    for j, ei in enumerate(event_viz_idx):
        ev = events[int(ei)]
        stats[f'event_{j}'] = (
            f'{ev["start"]/sr:.6f},{ev["end"]/sr:.6f},'
            f'{int(event_phrase[int(ei)])},{int(ei)}')

    max_phrase_viz = 48
    if n_ph <= max_phrase_viz:
        phrase_viz_idx = np.arange(n_ph, dtype=int)
    else:
        phrase_viz_idx = np.unique(
            np.linspace(0, n_ph - 1, max_phrase_viz).astype(int))
    stats['n_phrase_viz'] = len(phrase_viz_idx)
    for j, pi in enumerate(phrase_viz_idx):
        ph = phrases[int(pi)]
        inds = ph['event_indices']
        if inds:
            t0p = events[inds[0]]['start'] / sr
            t1p = events[inds[-1]]['end'] / sr
        else:
            t0p = t1p = 0.0
        stats[f'phrase_{j}'] = (
            f'{t0p:.6f},{t1p:.6f},{len(inds)},{int(pi)}')

    # Actual scheduled operations, including all voices in choir mode.
    def _op_duration_seconds(op):
        ei = int(op.get('event_idx', -1))
        if ei < 0 or ei >= len(events):
            return 0.0
        n = len(events[ei]['audio'])
        if op.get('type') == 'fragment':
            n = max(1, int(n * float(op.get('slice_ratio', 0.3))))
        stretch = float(op.get('stretch', 1.0))
        if abs(stretch - 1.0) > 0.02:
            n = max(1, int(n * stretch))
        return n / sr

    ops_sorted = sorted(visual_ops, key=lambda o: float(o.get('start_time', 0.0)))
    op_counts = {}
    for op in ops_sorted:
        typ = str(op.get('type', 'other'))
        op_counts[typ] = op_counts.get(typ, 0) + 1
    stats['n_ops_total'] = len(ops_sorted)
    pan_values = np.array([float(op.get('pan', 0.0)) for op in ops_sorted], dtype=float) \
        if ops_sorted else np.array([0.0])
    stats['pan_min'] = f'{float(np.min(pan_values)):.4f}'
    stats['pan_max'] = f'{float(np.max(pan_values)):.4f}'
    stats['n_spatial_ops'] = int(np.count_nonzero(np.abs(pan_values) > 1e-9))
    for typ in ('place', 'repeat', 'fragment', 'recall', 'braid', 'echo', 'invert'):
        stats[f'n_op_{typ}'] = op_counts.get(typ, 0)

    max_op_viz = 240
    audible_ops = []
    for op in ops_sorted:
        start = float(op.get('start_time', 0.0))
        dur_op = _op_duration_seconds(op)
        end = start + dur_op
        if end > 0.0 and start < target_dur:
            audible_ops.append((op, max(0.0, start), min(target_dur, end)))
    if len(audible_ops) <= max_op_viz:
        op_viz = audible_ops
    else:
        keep = np.unique(np.linspace(0, len(audible_ops) - 1, max_op_viz).astype(int))
        op_viz = [audible_ops[int(i)] for i in keep]
    stats['n_op_viz'] = len(op_viz)
    for j, (op, t0o, t1o) in enumerate(op_viz):
        stats[f'op_{j}'] = (
            f'{op.get("type", "other")},{t0o:.6f},{t1o:.6f},'
            f'{int(op.get("event_idx", -1))},{float(op.get("gain", 1.0)):.4f},'
            f'{float(op.get("pan", 0.0)):.4f},{int(op.get("voice", 0))}')
        # Where in the SOURCE this operation's material came from. Separate key
        # so a front-end that parses the fixed op_ layout is unaffected.
        ei = int(op.get('event_idx', -1))
        if 0 <= ei < len(events):
            stats[f'opsrc_{j}'] = (
                f'{events[ei]["start"]/sr:.6f},{events[ei]["end"]/sr:.6f}')
        else:
            stats[f'opsrc_{j}'] = '-1.000000,-1.000000'

    write_stats(cfg['stats'], stats)
    print("[HNR] Done.", flush=True)


if __name__ == '__main__':
    main()
