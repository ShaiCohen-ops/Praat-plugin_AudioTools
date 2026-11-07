#!/usr/bin/env python3
# =============================================================================
# Hierarchical Neural Recomposition
# Author: Shai Cohen — Department of Music, Bar-Ilan University, Israel
# Version: 1.10 (2026)
# License: MIT
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.10 (response to the v1.9 engineering review):
#   - Endings. CollapsingRefrain gets a dedicated final window (last 18% of
#     the target) holding only refrain residues - shorter, quieter, darker,
#     sparser - the last ending on the final sample. HiddenSonata's duration
#     fill may only use theme-B material and belongs to the recapitulation;
#     the generic fill likewise uses the last part's pool when one is set.
#   - Phase vocoder timing: frames were trimmed at ratio*pad instead of
#     ratio*pad - (ratio-1)*n/2, shifting output by (ratio-1)*n/2 (-11.6 ms at
#     x2, +5.8 ms at x0.5). Corrected. Attacks are now spliced back unstretched
#     at their mapped position (2 ms before to 12 ms after each onset): an
#     impulse keeps peak 1.000 at its exact position at x0.5 and x2 (v1.9:
#     0.06-0.33, smeared). Level match runs before the splice.
#   - Latent Counterpoint: fragmentation = motivic disintegration that grows
#     through the piece; a voice answers with a slice of the event another
#     voice just played, in its own position.
#   - Minimum material: formal presets that the source cannot carry stop with
#     an explanation (exit 3, shown by Praat) instead of silently running the
#     generic planner.
#   - New Stretch amount (CLI arg 17, 0..1 = x1..x2 on every operation), so
#     the Stretch mode has material to act on in every preset.
#   - sonata_window_coverage: share of each window covered by its own
#     rendered material (an "existing" window with one tiny op shows as such).
#
# Changelog v1.9 (response to the v1.8 engineering review):
#   - HiddenSonata windows are now hard bounds: each window starts at its own
#     boundary and an event that would cross it is cut to end on it. v1.8 let
#     a long event carry the cursor past later windows (x0.2 gave 0 ops in
#     development and recapitulation). Verified over x0.1-x3.0, two seeds and
#     a long-event input: all five windows (expoA, expoB, dev, recapA, recapB)
#     always get rendered operations, none starts outside its window, 0 ms
#     overrun. New stats: sonata_windows, sonata_complete.
#   - Every editable control now changes the audio of every preset (A/B 0 vs 1
#     at base values and at each preset's own values; target 0.5 vs 2):
#     sonata memory = literalness of the recapitulation, contrast = overlay
#     rate, surprise = reversal rate, fragmentation = slice length; litany
#     memory = returning cells, surprise = mutation strength, contrast = cell
#     order; braiding contrast = strand width, memory = motif length,
#     repetition = restated events, fragmentation = grains; counterpoint
#     memory = imitation, repetition = restated phrases, surprise = rest
#     irregularity; memory spiral memory = depth and recall length; echo
#     contrast = echo width. Stretch mode stays conditional: it matters only
#     when an operation is stretched, so n_ops_stretched is reported.
#   - Phase vocoder: identity phase locking (bins follow their peak) fixes the
#     level loss (v1.8: -9.6 dB at x2 on 300 Hz, -16 dB on 1234 Hz; now within
#     0.06 dB before any correction, 0.00-0.09 dB envelope ripple), plus an
#     RMS match per event that also covers noise (-0.6 dB incoherent loss).
#   - Short input: the onset STFT shrinks its frame and hop with the input, so
#     <= 896-sample files no longer raise "noverlap must be less than
#     nperseg" (tested 64 samples to 1 s, all nine modes, both stretch modes).
#   - n_form_parts_empty reports declared parts that got no rendered operation.
#   - "Audible" is documented for what it is: the operation's peak within
#     -60 dB of the pre-limiter mix peak, not a perceptual measure.
#
# Changelog v1.8 (response to the v1.7 engineering review):
#   Formal planners
#   - HiddenSonata: exposition / development / recapitulation get a fixed time
#     budget (36/36/28 % of the target) before any material is placed, so the
#     recapitulation always exists. Theme A = first section, theme B = the
#     section most unlike it; each theme has its own window in exposition and
#     recapitulation (B returns slowed x1.08 and darkened). The development is
#     built only from slices of A and B, alternated and overlaid.
#   - FragmentedLitany: cells of 3-8 micro-slices (40-250 ms, from anywhere in
#     the event), repeated with cumulative order/length mutation. Cells come
#     from phrases spread across the whole source (v1.7 used the first third).
#   - FormalBraiding: real attack / sustain / noise families, three strands
#     with fixed pans, alternating braided and unravelled phases with a new
#     phase relationship on each re-formation.
#   - LatentCounterpoint: phrase clusters become persistent voices with their
#     own timeline and pan; onsets are staggered and prominence rotates.
#   - EchoArchitecture: echoes from every selected event on the phrase's own
#     inter-onset grid (v1.7: first event of each phrase, fixed delay).
#   - Sections: boundaries at novelty peaks (timbral change, wider-context
#     change, energy dip) instead of equal-size groups.
#   Plan -> sound
#   - All 16 slots now drive the scheduler: foreground -> level, density_up
#     -> layered entries, density_down -> thinning, call_response -> sequential
#     answer from a related phrase (contrast slot picks contrasting/agreeing),
#     restatement -> verbatim return of an earlier phrase, surprise -> a
#     reversed far-away event cutting in. surprise = 0 still turns it off.
#   - The plan blend is unchanged and documented: on the five control-mixed
#     slots neural 0.07 / descriptors 0.28 / controls 0.65. The network is
#     still untrained and seeded; it is a generative perturbation, not a
#     learned model of form.
#   Control and rendering
#   - CLI arg 15 "explicit": the values passed are final (Praat v1.8 sends
#     presets as editable values). Absent/"preset" keeps the old override.
#   - CLI arg 16 stretch mode: "resample" (default, pitch follows) or
#     "preserve" (phase vocoder; 300 Hz stays 300 Hz at x0.5 and x2).
#   - RecursiveSpeechChoir: voices are summed unnormalised and limited once,
#     so the per-voice gain steps survive.
#   - Slices carry an offset (no longer always the event head); the scheduler
#     refuses operations that would start after the end.
#   Telemetry
#   - planned / rendered / audible operation counts (audible = within -60 dB
#     of the pre-limiter mix peak); lane counts are rendered operations.
#   - Source map uses the slice actually read and runs backwards for reversed
#     material. Form parts (sonata parts, litany cells, braid phases) are
#     exported with spans and operation counts.
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
#   Multi-scale recomposition engine. Segments an input sound into events ->
#   phrases -> novelty-bounded sections. A 16-slot plan per phrase is built
#   mainly from acoustic descriptors, perturbed by a seeded, UNTRAINED
#   hierarchical network (no checkpoint, no learning), and biased by the user
#   controls. Each preset then runs its own formal planner (sonata, litany,
#   braid, counterpoint, or the generic phrase pass) and the result is
#   re-rendered from the source material.
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
#       <preset_name> [explicit|preset] [resample|preserve]
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
    # Shrink the frame for very short input so noverlap < nperseg always holds
    # (v1.8 crashed on <= 896 samples: SciPy shrank nperseg, noverlap stayed 896).
    n_fft = 1024
    while n_fft > 16 and n_fft > len(audio):
        n_fft //= 2
    hop = max(1, min(hop, n_fft // 4))
    if len(audio) < n_fft:
        audio = np.concatenate([audio, np.zeros(n_fft - len(audio), dtype=np.float32)])
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
        # No onset structure: split at the midpoint so the planners have two
        # units, and mark it so formal presets can tell it is not real structure.
        events = [
            {'start': 0,   'end': mid,        'audio': audio[:mid].copy(), 'forced_split': True},
            {'start': mid, 'end': len(audio), 'audio': audio[mid:].copy(), 'forced_split': True}
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

def phrase_boundary_novelty(phrases, events, features_list):
    """Structural novelty at each boundary between consecutive phrases.

    Boundary b sits between phrase b-1 and phrase b (b = 1..n-1). Three cues,
    each z-scored across the boundaries of this source:
      - local timbral change: cosine distance between the two phrase centroids;
      - wider-context change: distance between the mean of up to two phrases
        before and up to two after, so a single odd phrase scores lower than a
        real change of material;
      - pause: how far the energy at the junction dips below the source mean.
    Returns an array of length n-1 (empty for fewer than two phrases).
    """
    n = len(phrases)
    if n < 2:
        return np.zeros(0, dtype=np.float64)
    C = np.asarray([ph['centroid'] for ph in phrases], dtype=np.float64)

    def cdist(a, b):
        return 1.0 - float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))

    rms_all = np.asarray([f['rms'] for f in features_list], dtype=np.float64)
    rms_mean = float(np.mean(rms_all)) + 1e-12
    local, context, pause = [], [], []
    for b in range(1, n):
        local.append(cdist(C[b - 1], C[b]))
        context.append(cdist(C[max(0, b - 2):b].mean(axis=0), C[b:min(n, b + 2)].mean(axis=0)))
        e_last = phrases[b - 1]['event_indices'][-1]
        e_first = phrases[b]['event_indices'][0]
        junction = min(rms_all[e_last], rms_all[e_first])
        pause.append(float(np.clip(1.0 - junction / rms_mean, 0.0, 1.0)))

    def z(v):
        v = np.asarray(v, dtype=np.float64)
        sd = float(np.std(v))
        return (v - float(np.mean(v))) / sd if sd > 1e-9 else np.zeros_like(v)

    return 0.5 * z(local) + 0.3 * z(context) + 0.2 * z(pause)


def group_phrases_into_sections(phrases, events, features_list):
    """Group contiguous phrases into sections at the strongest structural boundaries.

    v1.8: boundaries are the local maxima of phrase_boundary_novelty() whose
    z-score exceeds 0.5, strongest first, capped at round(sqrt(n))+1 sections.
    A source of four or more phrases always gets at least one boundary (its
    strongest). Fewer than four phrases form a single section.
    Returns (sections, novelty).
    """
    n_ph = len(phrases)
    if n_ph == 0:
        return [], np.zeros(0)
    novelty = phrase_boundary_novelty(phrases, events, features_list)
    cuts = []
    if n_ph >= 4 and len(novelty):
        max_sections = max(2, min(8, int(round(math.sqrt(n_ph))) + 1))
        peaks = []
        for i in range(len(novelty)):
            left = novelty[i - 1] if i > 0 else -np.inf
            right = novelty[i + 1] if i + 1 < len(novelty) else -np.inf
            if novelty[i] >= left and novelty[i] >= right and novelty[i] > 0.5:
                peaks.append(i)
        peaks.sort(key=lambda i: -novelty[i])
        chosen = peaks[:max_sections - 1]
        if not chosen:
            chosen = [int(np.argmax(novelty))]
        cuts = sorted(i + 1 for i in chosen)       # boundary i sits before phrase i+1
    bounds = [0] + cuts + [n_ph]
    sections = []
    for si in range(len(bounds) - 1):
        p0, p1 = bounds[si], bounds[si + 1]
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
            'novelty_in': float(novelty[p0 - 1]) if p0 > 0 and len(novelty) else 0.0,
        })
    return sections, novelty


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
            'Placed events, selected by the overlap slot, generate up to three '
            'echoes that fall on the phrase\'s own inter-onset grid, decaying '
            'and alternating left/right. The result is a space-like '
            'architecture built from the source\'s own rhythm.'
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
            'Sonata-INSPIRED (themes are chosen by acoustic contrast, not by '
            'tonal or thematic relations). A three-part sonata outline is projected onto the '
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


def get_preset(name, fallback_params, explicit=False):
    """Return (params, ops). With explicit=True the caller's values are final
    and the preset contributes only its mechanisms (ops); otherwise the
    preset's parameter table overrides them (pre-v1.8 behaviour)."""
    if name in PRESETS and explicit:
        return dict(fallback_params), PRESETS[name].get('ops', {})
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


class Scheduler:
    """Shared scheduling state for every planner.

    All operations pass through add(), which refuses anything starting at or
    after the target duration (those could never sound) and stamps the current
    form part. Parts are named time windows a planner declares (sonata
    sections, litany cells, braid phases) and are exported as telemetry.
    """

    def __init__(self, events, feat_vecs, features_list, phrases, sections,
                 plan, params, ops, rng, sr):
        self.events = events
        self.fv = feat_vecs
        self.fl = features_list
        self.phrases = phrases
        self.sections = sections
        self.plan = plan
        self.params = params
        self.ops = ops
        self.rng = rng
        self.sr = sr
        self.dur = [len(e['audio']) / sr for e in events]
        self.src_dur = float(sum(self.dur))
        self.target = float(params.get('target_duration', 1.0)) * self.src_dur
        self.sim = build_event_similarity_matrix(feat_vecs)
        self.ev_phrase = np.zeros(len(events), dtype=int)
        for pi, ph in enumerate(phrases):
            for ei in ph['event_indices']:
                self.ev_phrase[ei] = pi
        self.ops_list = []
        self.parts = []
        self.part_idx = -1
        self.memory_bank = []
        self.refrain_returns = 0
        self.n_refused = 0
        # Stretch amount (v1.10): a global factor on every operation, so the
        # Stretch mode always has something to act on when amount > 0.
        self.stretch_amount = float(np.clip(params.get('stretch_amount', 0.0), 0.0, 1.0))
        # Material the end-of-piece duration fill may use (None = any event).
        self.fill_pool = None
        # Layer contrast (v1.10, generic planner): the contrast control also
        # sets the level of the secondary layers (repeat, recall, braid, echo)
        # against the main statement: x1.2 at contrast 0, x1.0 at 0.5, x0.8 at 1.
        self.layer_contrast = False

    # -- bookkeeping ---------------------------------------------------------
    def row(self, pi):
        return self.plan[min(int(pi), len(self.plan) - 1)]

    def begin_part(self, name, t0):
        self.parts.append([str(name), float(t0), float(t0)])
        self.part_idx = len(self.parts) - 1

    def end_part(self, t1):
        if self.part_idx >= 0:
            self.parts[self.part_idx][2] = float(min(t1, self.target))

    def add(self, op):
        if self.layer_contrast and op.get('type') in ('repeat', 'recall', 'braid', 'echo'):
            c = float(np.clip(self.params.get('contrast', 0.5), 0, 1))
            op['gain'] = float(op.get('gain', 1.0)) * (1.0 + 0.4 * (0.5 - c))
        if self.stretch_amount > 0 and 'stretch' not in op:
            op['stretch'] = 1.0 + self.stretch_amount
        if float(op['start_time']) >= self.target:
            self.n_refused += 1
            return False
        if self.part_idx >= 0:
            op.setdefault('part', self.part_idx)
        self.ops_list.append(op)
        return True

    # -- per-event values read from the plan row -----------------------------
    def stretch_for(self, row):
        s = 1.0
        if row[PLAN_SLOTS['stretch']] > 0.55:
            s = 1.0 + (row[PLAN_SLOTS['stretch']] - 0.5) * self.params.get('fragmentation', 0.3)
        return float(np.clip(s * (1.0 + self.stretch_amount), 0.5, 3.0))

    def fg_gain(self, row):
        """foreground slot -> level of the phrase's main statement (0.70..1.00)."""
        return 0.70 + 0.30 * float(np.clip(row[PLAN_SLOTS['foreground']], 0, 1))

    def xfade_ms(self, row):
        return int(20 + float(row[PLAN_SLOTS['overlap']]) * 80)

    # -- primitive operations ------------------------------------------------
    def place(self, ei, cursor, row, typ='place', gain=None, stretch=None,
              label='', **extra):
        """Schedule a whole event; return the cursor after it (minus overlap)."""
        ei = int(ei)
        if stretch is None:
            stretch = self.stretch_for(row)
        if gain is None:
            gain = self.fg_gain(row)
        xf = self.xfade_ms(row)
        op = {'type': typ, 'event_idx': ei, 'start_time': float(cursor),
              'gain': float(gain), 'crossfade_ms': xf, 'stretch': float(stretch),
              'label': label}
        op.update(extra)
        self.add(op)
        gap = self.dur[ei] * stretch
        return cursor + max(gap * 0.1, gap - min(xf / 1000.0, gap * 0.15))

    def fragment(self, ei, cursor, ratio, offset_ratio=0.0, gain=0.82, label='',
                 advance=0.9, typ='fragment', **extra):
        """Schedule a slice of an event taken from offset_ratio of its length."""
        ei = int(ei)
        n = len(self.events[ei]['audio'])
        off = int(np.clip(offset_ratio, 0.0, 0.98) * n)
        nf = max(1, min(n - off, int(n * ratio)))
        op = {'type': typ, 'event_idx': ei, 'start_time': float(cursor),
              'gain': float(gain), 'crossfade_ms': 10,
              'slice_ratio': nf / max(1, n), 'slice_offset': off, 'label': label}
        op.update(extra)
        self.add(op)
        return cursor + nf / self.sr * float(op.get('stretch', 1.0)) * advance

    def phrase_similarity(self, i, j):
        ev_i = self.phrases[i]['event_indices']
        ev_j = self.phrases[j]['event_indices']
        return float(np.mean(self.sim[np.ix_(ev_i, ev_j)])) if ev_i and ev_j else 0.5

    def related_phrase(self, phrase_idx, want_contrast=True):
        """Most dissimilar (or most similar) other phrase."""
        n = len(self.phrases)
        if n < 2:
            return None
        cand = [j for j in range(n) if j != int(phrase_idx)]
        sims = [self.phrase_similarity(int(phrase_idx), j) for j in cand]
        k = int(np.argmin(sims)) if want_contrast else int(np.argmax(sims))
        return cand[k]

    def far_event(self, ev_indices):
        """An event from the far side of the source relative to this phrase."""
        centre = float(np.mean([self.events[e]['start'] for e in ev_indices]))
        dist = np.asarray([abs(e['start'] - centre) for e in self.events], dtype=np.float64)
        order = np.argsort(-dist)
        pool = order[:max(1, len(order) // 4)]
        return int(self.rng.choice(list(pool)))

    # -- source-time geometry, shared with the duration fill ------------------
    def op_audio(self, op):
        a = np.asarray(self.events[int(op['event_idx'])]['audio'])
        if 'slice_ratio' in op or op.get('type') == 'fragment':
            off = int(op.get('slice_offset', 0))
            n = max(1, int(len(a) * float(op.get('slice_ratio', 0.3))))
            a = a[off:off + n]
        if op.get('type') == 'invert' or op.get('reverse'):
            a = a[::-1]
        return a

    def sched_end(self, op):
        ei = int(op.get('event_idx', -1))
        if ei < 0 or ei >= len(self.events):
            return 0.0
        a = self.op_audio(op)
        active = np.flatnonzero(np.abs(a) > 1e-5) if len(a) else np.zeros(0, dtype=int)
        if len(active) == 0:
            return float(op.get('start_time', 0.0))
        return float(op.get('start_time', 0.0)) + (active[-1] + 1) * float(op.get('stretch', 1.0)) / self.sr

    def finalize(self):
        """Guarantee audible coverage to the target boundary."""
        audible_end = max((self.sched_end(op) for op in self.ops_list), default=0.0)
        gap = self.target - audible_end
        if gap <= 0.010 or not self.events:
            return
        # The fill belongs to the last declared part and, when the planner set a
        # pool (sonata: theme B; refrain: the refrain), uses only that material.
        pool = list(self.fill_pool) if self.fill_pool else list(range(len(self.events)))
        edge_scores, edge_reverse = [], []
        for ei_ in pool:
            ev = self.events[ei_]
            a = ev['audio']
            q = max(16, len(a) // 4)
            head = rms(a[:q]) if len(a) else 0.0
            tail = rms(a[-q:]) if len(a) else 0.0
            edge_scores.append(max(head, tail))
            edge_reverse.append(head > tail)
        k_best = int(np.argmax(edge_scores))
        fill_ei = int(pool[k_best])
        edge_reverse = {fill_ei: edge_reverse[k_best]}
        fill_dur = self.dur[fill_ei]
        if self.ops.get('micro_events'):
            # A litany ends on one of its own slices, not on a whole event.
            sdur = float(np.clip(min(gap, 0.25), 0.04, fill_dur))
            ratio = sdur / max(1e-9, fill_dur)
            self.fragment(fill_ei, max(0.0, self.target - sdur), ratio, 0.0, 0.72,
                          'duration_fill', advance=0.0, reverse=bool(edge_reverse[fill_ei]))
            return
        self.add({'type': 'invert' if edge_reverse[fill_ei] else 'place',
                  'event_idx': fill_ei, 'start_time': max(0.0, self.target - fill_dur),
                  'gain': 0.72, 'crossfade_ms': 35, 'stretch': 1.0,
                  'label': 'duration_fill'})

    # -- the generic per-phrase pass (Custom, MemorySpiral, CollapsingRefrain,
    #    EchoArchitecture, RecursiveSpeechChoir) -------------------------------
    def play_phrase(self, phrase_pos, phrase_idx, cursor, cycle):
        S = PLAN_SLOTS
        ops, rng, sr = self.ops, self.rng, self.sr
        T = self.target
        phrase_idx = int(phrase_idx)
        row = self.row(phrase_idx)
        ev_indices = list(self.phrases[phrase_idx]['event_indices'])
        if not ev_indices:
            return cursor, False
        progressed = False

        # memory: MemorySpiral recalls deterministically at growing lookback;
        # elsewhere the memory slot sets the chance of a free recall.
        if self.memory_bank:
            recall_entry = None
            mem = float(np.clip(self.params.get('memory', 0.5), 0, 1))
            if ops.get('recurrence'):
                # memory control: how far back the spiral reaches (v1.9)
                depth = max(1, int(round(ops.get('memory_depth', 4) * (0.5 + mem))))
                lookback = min(len(self.memory_bank), 1 + ((phrase_pos + cycle) % depth))
                recall_entry = self.memory_bank[-lookback]
            elif row[S['memory']] > 0.55 and rng.random() < row[S['memory']]:
                recall_entry = rng.choice(self.memory_bank)
            if recall_entry is not None:
                rp = int(recall_entry[0])
                n_rec = 1 + int(round(3 * mem)) if ops.get('recurrence') else 2
                for ei in self.phrases[min(rp, len(self.phrases) - 1)]['event_indices'][:n_rec]:
                    if cursor >= T:
                        break
                    self.add({'type': 'recall', 'event_idx': ei, 'start_time': cursor,
                              'gain': 0.58 if ops.get('recurrence') else 0.65,
                              'crossfade_ms': 30, 'label': f'memory_recall(p{rp})'})
                    cursor += min(self.dur[ei] * 0.42, max(0.0, T - cursor))
        if cursor >= T:
            return cursor, progressed

        # restatement: a verbatim return of a whole earlier phrase.
        r = float(row[S['restatement']])
        if self.memory_bank and r > 0.70 and rng.random() < (r - 0.70) * 0.8:
            past = sorted({int(p) for p, _ in self.memory_bank if int(p) != phrase_idx})
            if past:
                rp = rng.choice(past)
                for ei in self.phrases[rp]['event_indices']:
                    if cursor >= T:
                        break
                    cursor = self.place(ei, cursor, row, typ='recall', stretch=1.0,
                                        gain=0.80 * self.fg_gain(row),
                                        label=f'restatement(p{rp},e{ei})')
                progressed = True

        # fragmentation slot: a slice of one of the phrase's events.
        frag = float(row[S['fragmentation']])
        if frag > 0.6 and rng.random() < frag:
            sub_ev = int(rng.choice(ev_indices))
            ratio = rng.uniform(0.15, 0.45)
            cursor = self.fragment(sub_ev, cursor, ratio, rng.uniform(0.0, 1.0 - ratio), 0.82,
                                   f'fragment(p{phrase_idx},e{sub_ev})', advance=0.9)

        # CollapsingRefrain: each return of phrase 0 is shorter, quieter, eroded.
        collapse_amount = 0.0
        if ops.get('refrain') and phrase_idx == 0:
            self.refrain_returns += 1
            collapse_amount = float(np.clip((self.refrain_returns - 1) * float(ops.get('collapse_rate', 0.0)), 0.0, 0.88))

        placed = []
        for pos, ei in enumerate(ev_indices):
            if cursor >= T:
                break
            ev_dur = self.dur[ei]
            # density_down thins the phrase (never its first event).
            dd = float(row[S['density_down']])
            if pos > 0 and dd > 0.6 and rng.random() < (dd - 0.6) * 1.25:
                continue
            if row[S['repetition']] > 0.5 and rng.random() < row[S['repetition']] * 0.4:
                self.add({'type': 'repeat', 'event_idx': ei,
                          'start_time': max(0.0, cursor - ev_dur * rng.uniform(0.0, 0.3)),
                          'gain': 0.7, 'crossfade_ms': 20,
                          'label': f'repeat(p{phrase_idx},e{ei})'})
            op_start = cursor
            if collapse_amount > 0:
                if pos > 0 and rng.random() < collapse_amount * 0.75:
                    continue
                ratio = max(0.10, 1.0 - collapse_amount)
                self.fragment(ei, cursor, ratio, 0.0, max(0.20, 1.0 - 0.65 * collapse_amount),
                              f'collapsing_refrain(r{self.refrain_returns},e{ei})', advance=0.0,
                              crossfade_ms=12, erosion=collapse_amount)
                gap = ev_dur * ratio
                xf = min(self.xfade_ms(row) / 1000.0, gap * 0.15)
                cursor += max(gap * 0.1, gap - xf)
            else:
                cursor = self.place(ei, cursor, row, label=f'place(p{phrase_idx},e{ei})')
                placed.append((ei, op_start))
            # density_up layers a second, quieter entry of the same event.
            du = float(row[S['density_up']])
            if du > 0.6 and rng.random() < (du - 0.6) * 1.25:
                self.add({'type': 'repeat', 'event_idx': ei,
                          'start_time': op_start + ev_dur * rng.uniform(0.25, 0.5),
                          'gain': 0.5 * self.fg_gain(row), 'crossfade_ms': 20,
                          'label': f'density_layer(p{phrase_idx},e{ei})'})
            progressed = True

        # call_response: an answer from a related phrase after a short breath.
        # The contrast slot decides whether the answer contrasts or agrees.
        cr = float(row[S['call_response']])
        if cr > 0.6 and cursor < T and rng.random() < (cr - 0.6) * 1.5:
            resp = self.related_phrase(phrase_idx, want_contrast=row[S['contrast']] >= 0.5)
            if resp is not None:
                cursor += rng.uniform(0.05, 0.15) * (1.0 - 0.5 * float(row[S['overlap']]))
                for ei in self.phrases[resp]['event_indices'][:2]:
                    if cursor >= T:
                        break
                    cursor = self.place(ei, cursor, row, gain=0.85 * self.fg_gain(row),
                                        label=f'response(p{phrase_idx}-p{resp},e{ei})')

        # braid slot: a contrasting phrase interleaved on top (mono).
        b = float(row[S['braid']])
        if b > 0.6 and cursor < T and rng.random() < (b - 0.6) * 1.0:
            ci = self.related_phrase(phrase_idx, want_contrast=True)
            if ci is not None:
                bc = max(0.0, cursor - sum(self.dur[e] for e in ev_indices) * 0.5)
                for bei in self.phrases[ci]['event_indices'][:3]:
                    self.add({'type': 'braid', 'event_idx': bei, 'start_time': bc,
                              'gain': 0.6, 'crossfade_ms': 25,
                              'label': f'braid(p{phrase_idx}+p{ci},e{bei})'})
                    bc += self.dur[bei] * 0.7

        if row[S['collapse']] > 0.7 and not ops.get('refrain') and rng.random() < 0.3:
            cursor += min(rng.uniform(0.2, 0.6), max(0.0, T - cursor))

        # EchoArchitecture: echoes on the phrase's own inter-onset grid, from
        # every placed event the overlap slot selects (not only the first).
        if ops.get('echo_depth') and placed:
            depth = int(ops.get('echo_depth', 2))
            decay = float(ops.get('echo_decay', 0.5))
            src_on = [self.events[e]['start'] / sr for e in ev_indices]
            iois = np.diff(src_on) if len(src_on) > 1 else np.asarray([self.dur[ev_indices[0]] * 0.6])
            iois = np.maximum(iois, 0.05)
            p_echo = 0.30 + 0.50 * float(row[S['overlap']])
            for j, (ei, t0) in enumerate(placed):
                if rng.random() >= p_echo:
                    continue
                delay = 0.0
                for ech in range(1, depth + 1):
                    delay += float(iois[(j + ech - 1) % len(iois)])
                    spread = min(0.85, 0.28 + 0.18 * ech) * (0.4 + 0.6 * float(np.clip(self.params.get('contrast', 0.5), 0, 1)))
                    if not self.add({'type': 'echo', 'event_idx': ei, 'start_time': t0 + delay,
                                     'gain': decay ** ech, 'crossfade_ms': 15,
                                     'pan': float(-spread if ech % 2 else spread),
                                     'label': f'echo{ech}(p{phrase_idx},e{ei})'}):
                        break

        if row[S['inversion']] > 0.65 and rng.random() < 0.3:
            for ei in ev_indices[:2]:
                if cursor >= T:
                    break
                self.add({'type': 'invert', 'event_idx': ei, 'start_time': cursor,
                          'gain': 0.75, 'crossfade_ms': 15,
                          'label': f'invert(p{phrase_idx},e{ei})'})
                cursor += self.dur[ei] * 0.8

        # surprise slot: a reversed event from the far side of the source cuts in.
        sp = float(row[S['surprise']])
        if sp > 0.35 and cursor < T and rng.random() < sp * 0.35:
            far = self.far_event(ev_indices)
            self.add({'type': 'invert', 'event_idx': far, 'start_time': cursor,
                      'gain': 0.8, 'crossfade_ms': 3,
                      'label': f'surprise(p{phrase_idx},e{far})'})
            cursor += self.dur[far] * 0.6

        self.memory_bank.append((phrase_idx, cursor))
        depth = max(4, int(ops.get('memory_depth', 8)))
        if len(self.memory_bank) > depth * 3:
            self.memory_bank = self.memory_bank[-depth * 3:]
        return cursor, progressed

    # -- window filler used by the sonata ------------------------------------
    def fill_window(self, phrase_list, t_start, t_end, label, stretch_mul=1.0,
                    erosion=0.0):
        """Play phrase_list in order, cycling, strictly inside [t_start, t_end).

        v1.9: the cursor starts at t_start whatever the previous window did, and
        an event that would run past t_end is cut to the time left (a head
        slice ending on the boundary), so no window can swallow the next one.
        A window always receives at least one operation unless it is shorter
        than 20 ms. Returns the cursor (never beyond t_end).
        """
        t_end = min(t_end, self.target)
        cursor = float(t_start)
        S = PLAN_SLOTS
        guard = 0
        while cursor < t_end - 0.02 and guard < 10000:
            guard += 1
            progressed = False
            for pi in phrase_list:
                row = self.row(pi)
                for ei in self.phrases[pi]['event_indices']:
                    left = t_end - cursor
                    if left <= 0.02:
                        break
                    if row[S['repetition']] > 0.5 and self.rng.random() < row[S['repetition']] * 0.25:
                        rd = min(self.dur[ei], left)
                        self.add({'type': 'repeat', 'event_idx': ei,
                                  'start_time': max(t_start, cursor - rd * self.rng.uniform(0.0, 0.3)),
                                  'gain': 0.6, 'crossfade_ms': 20,
                                  'slice_ratio': rd / max(1e-9, self.dur[ei]), 'slice_offset': 0,
                                  'label': f'{label}_repeat(p{pi},e{ei})'})
                    extra = {'erosion': erosion} if erosion > 0 else {}
                    st = self.stretch_for(row) * stretch_mul
                    span = self.dur[ei] * st
                    if span > left:
                        extra['slice_ratio'] = left / span
                        extra['slice_offset'] = 0
                        self.place(ei, cursor, row, stretch=st,
                                   label=f'{label}(p{pi},e{ei},cut)', **extra)
                        cursor = t_end
                    else:
                        cursor = self.place(ei, cursor, row, stretch=st,
                                            label=f'{label}(p{pi},e{ei})', **extra)
                    progressed = True
                if cursor >= t_end - 0.02:
                    break
            if not progressed:
                break
        return min(cursor, t_end)


# =============================================================================
# Planners
# =============================================================================

def _phrase_dur(S, pi):
    return sum(S.dur[e] for e in S.phrases[pi]['event_indices'])


def plan_generic(S, phrase_order):
    S.layer_contrast = True
    if not phrase_order:
        return 0.0
    cursor, cycle = 0.0, 0
    max_cycles = max(2, int(math.ceil(S.target / max(0.05, S.src_dur))) + 4)
    while cursor < S.target and cycle < max_cycles:
        progressed = False
        for pos, pi in enumerate(phrase_order):
            if cursor >= S.target:
                break
            cursor, p = S.play_phrase(pos, pi, cursor, cycle)
            progressed = progressed or p
        if not progressed:
            break
        cycle += 1
        if cursor < S.target and S.params.get('surprise', 0.0) > 0 and len(phrase_order) > 1:
            shift = 1 + (cycle % len(phrase_order))
            phrase_order = phrase_order[shift:] + phrase_order[:shift]
    return cursor


def plan_refrain(S, phrase_order):
    """CollapsingRefrain: the refrain form, then a dedicated final collapse.

    The phrase cycle (refrain returning between body phrases, each return
    more eroded) runs in the first 82% of the target. The remaining window
    holds only residues of the refrain: slices that get shorter, quieter,
    darker and sparser, the last one ending exactly on the final sample, so
    the piece always ends in the dissolving refrain (v1.9 could end on an
    ordinary body event).
    """
    T, rng = S.target, S.rng
    rate = float(S.ops.get('collapse_rate', 0.4))
    S.begin_part('refrain form', 0.0)
    S.target = 0.82 * T
    cursor = plan_generic(S, phrase_order)
    S.target = T
    c0 = float(np.clip(cursor, 0.80 * T, max(0.80 * T, T - 0.25)))
    S.end_part(c0)
    S.begin_part('final collapse', c0)
    evs = list(S.phrases[0]['event_indices'])
    S.fill_pool = evs
    c_start = float(np.clip(S.refrain_returns * rate, 0.35, 0.88))
    cur, j = c0, 0
    while cur < T - 0.005:
        c = c_start + (0.97 - c_start) * (cur - c0) / max(1e-6, T - c0)
        ei = evs[j % len(evs)]
        j += 1
        d_ev = S.dur[ei]
        sd = float(np.clip(d_ev * max(0.03, 1.0 - c), 0.02, d_ev))
        gain = max(0.08, 1.0 - 0.85 * c)
        last = cur + sd >= T - 0.005
        start = T - sd if last else cur
        S.fragment(ei, max(c0, start), sd / d_ev, 0.0, gain,
                   f'collapse_residue({c:.2f},e{ei})', advance=0.0,
                   erosion=c, crossfade_ms=12)
        if last:
            break
        cur = start + sd * (1.0 + 4.0 * c)          # residues thin out
        if cur >= T - 0.005:
            # the next gap would overshoot: end on one more residue at the end
            ei = evs[j % len(evs)]
            sd = float(np.clip(S.dur[ei] * 0.03, 0.02, S.dur[ei]))
            S.fragment(ei, T - sd, sd / S.dur[ei], 0.0, 0.08,
                       f'collapse_residue(0.97,e{ei})', advance=0.0,
                       erosion=0.97, crossfade_ms=12)
            break
    S.end_part(T)


def sonata_themes(S):
    """Theme A = the first section; theme B = the section most unlike it.
    With a single section, the phrases are split at the strongest boundary."""
    n = len(S.phrases)
    C = np.asarray([ph['centroid'] for ph in S.phrases], dtype=np.float64)

    def cdist(a, b):
        return 1.0 - float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))

    secs = [s for s in S.sections if s['phrase_indices']]
    if len(secs) >= 2:
        A = list(secs[0]['phrase_indices'])
        ca = C[A].mean(axis=0)
        best = max(secs[1:], key=lambda s: cdist(ca, C[s['phrase_indices']].mean(axis=0)))
        return A, list(best['phrase_indices'])
    split = max(1, n // 2)
    if n >= 3:
        nov = phrase_boundary_novelty(S.phrases, S.events, S.fl)
        if len(nov):
            split = int(np.argmax(nov)) + 1
    return list(range(split)), list(range(split, n)) or [n - 1]


def plan_sonata(S):
    """Sonata-inspired form: exposition / development / recapitulation.

    Themes are chosen by acoustic contrast between sections, not by tonal or
    thematic relations, so this is a sonata-INSPIRED recomposition.
    The time budget (36% / 36% / 28% of the target) is fixed first, and every
    window is realised strictly inside its own bounds (fill_window cuts the
    last event at the boundary), so each part and each theme window always
    gets material. Controls read here:
      memory     how literally the recapitulation restates the exposition
                 (low memory = darker, slower, more transformed return);
      contrast   how often the development overlays the other theme;
      surprise   how often development slices are reversed;
      fragmentation  how short the development slices are;
      repetition / overlap / fragmentation through the plan slots.
    """
    T, rng = S.target, S.rng
    P = S.params
    mem = float(np.clip(P.get('memory', 0.9), 0, 1))
    con = float(np.clip(P.get('contrast', 0.7), 0, 1))
    sur = float(np.clip(P.get('surprise', 0.25), 0, 1))
    frg = float(np.clip(P.get('fragmentation', 0.5), 0, 1))
    A, B = sonata_themes(S)
    b1, b2 = 0.36 * T, 0.72 * T

    S.begin_part('exposition', 0.0)
    S.fill_window(A, 0.0, 0.5 * b1, 'expoA')
    S.fill_window(B, 0.5 * b1, b1, 'expoB')
    S.end_part(b1)

    S.begin_part('development', b1)
    cursor, k = b1, 0
    while cursor < b2 - 0.02:
        th, other = (A, B) if k % 2 == 0 else (B, A)
        k += 1
        pi = int(rng.choice(th))
        row = S.row(pi)
        ei = int(rng.choice(S.phrases[pi]['event_indices']))
        st = S.stretch_for(row)
        # fragmentation control: high = shorter development slices (v1.9)
        ratio = rng.uniform(0.10, 0.22) + 0.25 * (1.0 - frg)
        ratio = min(ratio, (b2 - cursor) / max(1e-9, S.dur[ei] * st))
        progress = (cursor - b1) / max(1e-6, b2 - b1)
        start = cursor
        cursor = S.fragment(ei, cursor, ratio, rng.uniform(0.0, 1.0 - ratio),
                            0.82 * S.fg_gain(row), f'dev(p{pi},e{ei})',
                            advance=0.95 - 0.40 * progress,
                            reverse=bool(rng.random() < 0.10 + 0.50 * sur),
                            stretch=st)
        p_comb = (0.15 + 0.55 * con) * (0.6 + 0.4 * float(row[PLAN_SLOTS['braid']]))
        if rng.random() < p_comb:
            pj = int(rng.choice(other))
            ej = int(rng.choice(S.phrases[pj]['event_indices']))
            t_c = start + (cursor - start) * 0.4
            r2 = min(rng.uniform(0.15, 0.30), max(0.0, b2 - t_c) / max(1e-9, S.dur[ej]))
            if r2 * S.dur[ej] > 0.01:
                S.fragment(ej, t_c, r2, rng.uniform(0.0, 1.0 - r2),
                           0.55, f'dev_combine(p{pi}+p{pj},e{ej})', advance=0.0, typ='braid')
        if cursor <= start:
            cursor = start + 0.02
    S.end_part(b2)

    S.begin_part('recapitulation', b2)
    loose = 1.0 - mem
    S.fill_window(A, b2, b2 + 0.55 * (T - b2), 'recapA',
                  stretch_mul=1.0 + 0.10 * loose, erosion=0.30 * loose)
    S.fill_window(B, b2 + 0.55 * (T - b2), T, 'recapB',
                  stretch_mul=1.08 + 0.20 * loose, erosion=0.12 + 0.40 * loose)
    S.end_part(T)
    S.fill_pool = [e for pi in B for e in S.phrases[pi]['event_indices']]


def plan_litany(S):
    """FragmentedLitany: cells of micro-slices, repeated with slow mutation.

    Each phrase yields one cell of 3-8 slices of 40-250 ms taken from anywhere
    inside its events. A cell is repeated `cycles` times; each repeat swaps one
    adjacent pair and jitters slice lengths by +/-15%, cumulatively. Rests are
    as long as the slices or longer. When the target cannot hold one cell per
    phrase, the cells are drawn from phrases spread evenly across the whole
    source (first and last included) instead of from its opening only.
    Controls read here (v1.9): repetition = cycles per cell; memory = chance
    that an earlier cell (in its mutated state) returns for one cycle after a
    new one; surprise = mutation strength; contrast = cell order (high: each
    next cell is the most unlike the last one; low: source order); overlap =
    rest length; fragmentation = slices per cell.
    """
    T, rng = S.target, S.rng
    S_ = PLAN_SLOTS
    overlap = float(np.clip(S.params.get('overlap', 0.1), 0, 1))
    rest_k = 0.35 + 0.90 * (1.0 - overlap)
    breath = 0.12 + 0.25 * (1.0 - overlap)
    cycles = max(2, int(round(S.ops.get('litany_cycles', 3) * (0.5 + 0.6 * S.params.get('repetition', 0.9)))))
    mem = float(np.clip(S.params.get('memory', 0.8), 0, 1))
    sur = float(np.clip(S.params.get('surprise', 0.05), 0, 1))
    con = float(np.clip(S.params.get('contrast', 0.2), 0, 1))
    p_swap = 0.35 + 0.60 * sur
    jit = 0.08 + 0.30 * sur
    n = len(S.phrases)

    def make_cell(pi):
        row = S.row(pi)
        evs = S.phrases[pi]['event_indices']
        k = int(np.clip(round(3 + 5 * float(row[S_['fragmentation']])), 3, 8))
        cell = []
        for j in range(k):
            ei = int(evs[j]) if j < len(evs) else int(rng.choice(evs))
            d = S.dur[ei]
            sdur = min(d, float(np.clip(d * rng.uniform(0.06, 0.22), 0.04, 0.25)))
            ratio = sdur / max(1e-9, d)
            cell.append([ei, ratio, rng.uniform(0.0, max(0.0, 1.0 - ratio))])
        return cell

    def cell_seconds(cell):
        return cycles * (sum(S.dur[ei] * r for ei, r, _ in cell) * (1.0 + rest_k) + breath)

    cells = [make_cell(pi) for pi in range(n)]
    est = [cell_seconds(c) for c in cells]
    order = list(range(n))
    if n > 1 and sum(est) > T:
        m = n
        while m > 1:
            pick = sorted(set(int(round(x)) for x in np.linspace(0, n - 1, m)))
            if sum(est[i] for i in pick) <= T * 1.05:
                break
            m -= 1
        order = pick if m > 1 else [0, n - 1]
    if con > 0.5 and len(order) > 2:
        # greedy contrast ordering: each next cell is the phrase least like the last
        rest_o = list(order[1:])
        seq = [order[0]]
        while rest_o:
            nxt = min(rest_o, key=lambda j: S.phrase_similarity(seq[-1], j))
            seq.append(nxt)
            rest_o.remove(nxt)
        order = seq

    def sing(pi, n_cycles, tag, cursor):
        row = S.row(pi)
        origin = [list(x) for x in cells[pi]]
        cell = [list(x) for x in origin]
        for c in range(n_cycles):
            if c > 0 and rng.random() >= mem:
                # memory control: a low-memory cycle forgets the accumulated
                # mutations and varies the cell as it was first stated
                cell = [list(x) for x in origin]
            if c > 0 or tag == 'return':
                if len(cell) > 1 and rng.random() < p_swap:
                    i = rng.randint(0, len(cell) - 2)
                    cell[i], cell[i + 1] = cell[i + 1], cell[i]
                for x in cell:
                    x[1] = float(np.clip(x[1] * rng.uniform(1.0 - jit, 1.0 + jit), 0.01, 1.0 - x[2]))
            for jj, (ei, ratio, off) in enumerate(cell):
                if cursor >= T:
                    break
                sd = S.dur[ei] * ratio
                st = S.stretch_for(row)
                # contrast control: accent on the first slice of each statement
                accent = (1.0 + 0.5 * con) if jj == 0 else (1.0 - 0.25 * con)
                S.fragment(ei, cursor, ratio, off, 0.85 * S.fg_gain(row) * accent,
                           f'litany_{tag}(p{pi + 1}.{c + 1},e{ei})', advance=0.0, stretch=st)
                cursor += sd * st * (1.0 + rest_k)
            cursor += breath
        cells[pi] = cell          # a returning cell keeps its mutations
        return cursor

    cursor, cell_no, guard = 0.0, 0, 0
    heard = []
    while cursor < T and guard < 1000:
        guard += 1
        for pi in order:
            if cursor >= T:
                break
            cell_no += 1
            S.begin_part(f'cell {cell_no} (p{pi + 1})', cursor)
            cursor = sing(pi, cycles, 'cell', cursor)
            S.end_part(cursor)
            if heard and cursor < T and rng.random() < 0.9 * mem:
                back = heard[int(rng.randint(0, len(heard) - 1))]
                S.begin_part(f'return (p{back + 1})', cursor)
                cursor = sing(back, 1, 'return', cursor)
                S.end_part(cursor)
            heard.append(pi)


def classify_material_families(S):
    """Attack / sustain / noise family per event, from z-scored descriptors.
    A family nobody falls into borrows the events that score highest for it."""
    fl = S.fl
    n = len(fl)

    def z(v):
        v = np.asarray(v, dtype=np.float64)
        sd = float(np.std(v))
        return (v - float(np.mean(v))) / sd if sd > 1e-9 else np.zeros_like(v)

    sharp = z([f['onset_sharpness'] for f in fl])
    dur = z([math.log(max(1e-3, f['duration'])) for f in fl])
    flat = z([f['flatness'] for f in fl])
    harm = z([f['harmonicity'] for f in fl])
    scores = np.stack([sharp - 0.5 * dur, harm + 0.5 * dur - 0.5 * flat, flat - harm], axis=1)
    fam = np.argmax(scores, axis=1)
    # Near-silent events (pauses) score as "noise" because silence is flat;
    # they are kept out of every strand so a strand never plays a gap.
    lvl = np.asarray([f['rms'] for f in fl], dtype=np.float64)
    voiced = lvl >= 0.1 * float(np.median(lvl))
    if not np.any(voiced):
        voiced[:] = True
    members = []
    for k in range(3):
        m = [int(i) for i in np.flatnonzero((fam == k) & voiced)]
        if not m:
            ranked = [int(i) for i in np.argsort(-scores[:, k]) if voiced[i]]
            m = sorted(ranked[:max(1, n // 6)])
        members.append(m)
    return members


def plan_braiding(S):
    """FormalBraiding: three strands (attack, sustain, noise), each a fixed
    family with its own stereo position, alternating between braided phases
    (all strands at once, a new phase offset each time) and unravelled phases
    (the strands take solo turns in a new order)."""
    T, rng = S.target, S.rng
    fams = classify_material_families(S)
    names = ['attack', 'sustain', 'noise']
    overlap = float(np.clip(S.params.get('overlap', 0.7), 0, 1))
    surprise = float(np.clip(S.params.get('surprise', 0.35), 0, 1))
    # v1.9 controls: contrast = width between strands; memory = how short a
    # motif each strand cycles (high memory = ostinato on its first events);
    # repetition = chance a strand restates the event it just played.
    contrast = float(np.clip(S.params.get('contrast', 0.75), 0, 1))
    memory = float(np.clip(S.params.get('memory', 0.5), 0, 1))
    repetition = float(np.clip(S.params.get('repetition', 0.5), 0, 1))
    fragmentation = float(np.clip(S.params.get('fragmentation', 0.4), 0, 1))
    width = 0.25 + 0.65 * contrast
    pans = [-width, 0.0, width]
    ptr = [0, 0, 0]
    motif = [max(1, int(math.ceil(len(f) * (1.0 - 0.85 * memory)))) for f in fams]
    mean_ph = float(np.mean([_phrase_dur(S, i) for i in range(len(S.phrases))])) if S.phrases else 1.0
    P = float(np.clip(2.0 * mean_ph, 1.5, 6.0))

    def strand_step(s, cur, tag):
        ei = fams[s][ptr[s] % motif[s]]
        if not (repetition > 0 and rng.random() < 0.5 * repetition):
            ptr[s] += 1
        row = S.row(S.ev_phrase[ei])
        if rng.random() < 0.6 * fragmentation:
            # fragmentation control: the strand plays a grain of the event
            ratio = rng.uniform(0.15, 0.45)
            st = S.stretch_for(row)
            S.fragment(ei, cur, ratio, rng.uniform(0.0, 1.0 - ratio), 0.8 * S.fg_gain(row),
                       f'{names[s]}:{tag}_grain(e{ei})', advance=0.0, typ='braid',
                       pan=pans[s], voice=s + 1, stretch=st)
            cur2 = cur + S.dur[ei] * ratio * st
        else:
            cur2 = S.place(ei, cur, row, typ='braid', gain=0.8 * S.fg_gain(row),
                           pan=pans[s], voice=s + 1, label=f'{names[s]}:{tag}(e{ei})')
        rest_scale = 0.6 if s == 0 else 0.25        # the attack strand breathes most
        return cur2 + S.dur[ei] * rng.uniform(0.1, 1.0) * rest_scale * (1.0 - overlap)

    t, k = 0.0, 0
    while t < T:
        Pk = P * (1.0 + surprise * rng.uniform(-0.5, 0.5))
        t1 = min(T, t + Pk)
        if k % 2 == 0:
            S.begin_part(f'braid {k // 2 + 1}', t)
            offsets = [rng.uniform(0.0, Pk / 3.0) for _ in range(3)]
            offsets[rng.randint(0, 2)] = 0.0
            for s in range(3):
                cur = t + offsets[s]
                while cur < t1:
                    cur = strand_step(s, cur, 'braid')
        else:
            S.begin_part(f'unravel {k // 2 + 1}', t)
            order = rng.sample(range(3), 3)
            seg = (t1 - t) / 3.0
            for j, s in enumerate(order):
                cur = t + j * seg
                while cur < t + (j + 1) * seg:
                    cur = strand_step(s, cur, 'solo')
        S.end_part(t1)
        t, k = t1, k + 1


def cluster_phrases(S, k):
    """k-means (farthest-point initialisation, deterministic) on phrase centroids."""
    n = len(S.phrases)
    if n < k:
        return [[j % n] for j in range(k)]
    X = np.asarray([ph['centroid'] for ph in S.phrases], dtype=np.float64)
    cent = [X[0]]
    for _ in range(1, k):
        d = np.min([np.linalg.norm(X - c, axis=1) for c in cent], axis=0)
        cent.append(X[int(np.argmax(d))])
    cent = np.asarray(cent)
    lab = np.zeros(n, dtype=int)
    for _ in range(25):
        lab = np.argmin(np.stack([np.linalg.norm(X - c, axis=1) for c in cent], axis=1), axis=1)
        for j in range(k):
            if np.any(lab == j):
                cent[j] = X[lab == j].mean(axis=0)
    voices = [[int(i) for i in np.flatnonzero(lab == j)] for j in range(k)]
    for j in range(k):
        if not voices[j]:
            big = max(range(k), key=lambda q: len(voices[q]))
            voices[j] = [voices[big].pop()]
    return voices


def plan_counterpoint(S):
    """LatentCounterpoint: phrase classes become persistent voices.

    Each voice owns one cluster of phrases (its timbral identity), one stereo
    position, and its own timeline. Relations between voices are planned:
    onsets are staggered so no two voices attack together, and prominence
    rotates between the voices on a slow cosine cycle."""
    T, rng = S.target, S.rng
    k = max(2, int(S.ops.get('polyphony', 2)))
    voices = cluster_phrases(S, k)
    # v1.9 controls: memory = imitation (a voice answers with the phrase the
    # other voice just finished, keeping its own pan); repetition = a voice
    # restates its own phrase before moving on; surprise = rest irregularity.
    memory = float(np.clip(S.params.get('memory', 0.3), 0, 1))
    repetition = float(np.clip(S.params.get('repetition', 0.4), 0, 1))
    surprise = float(np.clip(S.params.get('surprise', 0.2), 0, 1))
    # fragmentation (v1.10): motivic disintegration passed between voices. As
    # the piece advances, a voice increasingly answers with a slice of the
    # event another voice has just played, in its own register (pan) - the
    # motifs break up and migrate. 0 = whole events only.
    fragmentation = float(np.clip(S.params.get('fragmentation', 0.3), 0, 1))
    last_ev = [None] * k
    last_done = [None] * k
    current = [None] * k
    pans = np.linspace(-0.6, 0.6, k)
    overlap = float(np.clip(S.params.get('overlap', 0.6), 0, 1))
    contrast = float(np.clip(S.params.get('contrast', 0.8), 0, 1))
    mean_ph = float(np.mean([_phrase_dur(S, i) for i in range(len(S.phrases))])) if S.phrases else 1.0
    cursors = [j * mean_ph * 0.5 for j in range(k)]
    ptr_ph, ptr_ev = [0] * k, [0] * k
    last_on = [-1e9] * k
    min_sep = 0.04 + 0.08 * contrast
    Pe = float(np.clip(4.0 * mean_ph, 3.0, 12.0))
    S.begin_part('counterpoint', 0.0)
    guard = 0
    while min(cursors) < T and guard < 200000:
        guard += 1
        v = int(np.argmin(cursors))
        if current[v] is None:
            current[v] = voices[v][ptr_ph[v] % len(voices[v])]
            others = [last_done[u] for u in range(k) if u != v and last_done[u] is not None]
            if others and rng.random() < 0.6 * memory:
                current[v] = others[0]                     # imitation
        pi = current[v]
        evs = S.phrases[pi]['event_indices']
        ei = evs[ptr_ev[v] % len(evs)]
        start = cursors[v]
        for u in range(k):
            if u != v and abs(start - last_on[u]) < min_sep:
                start = last_on[u] + min_sep
        emph = 0.65 + 0.35 * math.cos(2 * math.pi * start / Pe + v * 2 * math.pi / k)
        row = S.row(pi)
        imit = pi not in voices[v]
        others_ev = [last_ev[u] for u in range(k) if u != v and last_ev[u] is not None]
        if others_ev and rng.random() < fragmentation * min(1.0, start / max(1e-6, T)) * 1.2:
            fe = int(others_ev[0])
            ratio = rng.uniform(0.12, 0.40)
            S.fragment(fe, start, ratio, rng.uniform(0.0, 1.0 - ratio),
                       S.fg_gain(row) * emph, f'voice{v + 1}_motif_fragment(e{fe})',
                       advance=0.0, pan=float(pans[v]), voice=v + 1,
                       stretch=S.stretch_for(row))
            last_on[v] = start
            cursors[v] = start + S.dur[fe] * ratio * S.stretch_for(row) * (1.15 + 0.5 * (1.0 - overlap))
            continue
        end = S.place(ei, start, row, gain=S.fg_gain(row) * emph, pan=float(pans[v]),
                      voice=v + 1, label=f'voice{v + 1}{"_imitation" if imit else ""}(p{pi},e{ei})')
        last_ev[v] = ei
        last_on[v] = start
        ptr_ev[v] += 1
        if ptr_ev[v] >= len(evs):
            ptr_ev[v] = 0
            last_done[v] = pi
            if imit or not (rng.random() < 0.5 * repetition):
                if not imit:
                    ptr_ph[v] += 1
                current[v] = None
            rest_f = 0.45 + surprise * rng.uniform(-0.35, 0.35)
            end += _phrase_dur(S, pi) * rest_f * (1.0 - 0.6 * overlap)
        cursors[v] = max(end, start + 0.01)
    S.end_part(T)


def plan_event_ordering(events, feat_vecs, features_list, phrases, sections,
                        plan, params, ops, rng, sr):
    """Dispatch to the preset's planner; returns the Scheduler (ops + parts)."""
    S = Scheduler(events, feat_vecs, features_list, phrases, sections,
                  plan, params, ops, rng, sr)
    if ops.get('sonata_form') and len(phrases) >= 2:
        plan_sonata(S)
    elif ops.get('micro_events'):
        plan_litany(S)
    elif ops.get('n_strands', 0) >= 3:
        plan_braiding(S)
    elif ops.get('polyphony'):
        plan_counterpoint(S)
    elif ops.get('refrain') and len(phrases) >= 2:
        plan_refrain(S, _plan_phrase_order(phrases, plan, params, ops, rng))
    else:
        plan_generic(S, _plan_phrase_order(phrases, plan, params, ops, rng))
    S.finalize()
    return S


def _plan_phrase_order(phrases, section_plan_np, params, ops, rng):
    """Phrase order for the generic planner: refrain form, or formal_weight
    order with repetitions and surprise swaps."""
    n = len(phrases)
    indices = list(range(n))

    if ops.get('refrain') and n >= 2:
        body = [i for i in indices if i != 0]
        # contrast control (v1.10): the body phrases between refrain returns
        # are ordered by distance from the refrain - most unlike first when
        # contrast >= 0.5, most alike first below it.
        if len(body) > 1:
            c0 = np.asarray(phrases[0]['centroid'], dtype=np.float64)
            def _dist(i):
                c = np.asarray(phrases[i]['centroid'], dtype=np.float64)
                return 1.0 - float(np.dot(c0, c) / (np.linalg.norm(c0) * np.linalg.norm(c) + 1e-12))
            sign = -1.0 if float(params.get('contrast', 0.5)) >= 0.5 else 1.0
            body = sorted(body, key=lambda i: sign * _dist(i))
        order = []
        for i, b in enumerate(body):
            order.append(b)
            if (i + 1) % 2 == 0:
                order.append(0)
        order.append(0)
        return order

    formal_weights = [
        float(section_plan_np[min(i, len(section_plan_np)-1), PLAN_SLOTS['formal_weight']])
        for i in indices
    ]
    order = sorted(indices, key=lambda i: formal_weights[i])

    rep_thresh = params.get('repetition', 0.5)
    final_order = []
    for idx in order:
        final_order.append(idx)
        if rng.random() < rep_thresh * 0.4:
            final_order.append(idx)

    surprise = params.get('surprise', 0.2)
    if surprise > 0.3 and len(final_order) >= 2:
        n_swaps = int(len(final_order) * surprise * 0.5)
        hi = len(final_order) - 1   # randint is INCLUSIVE; must not exceed last index
        for _ in range(n_swaps):
            i, j = rng.randint(0, hi), rng.randint(0, hi)
            final_order[i], final_order[j] = final_order[j], final_order[i]

    return final_order


# =============================================================================
# SECTION 11 — AUDIO RENDERING
# =============================================================================

def time_stretch_naive(audio, ratio):
    """Resampling stretch: duration and pitch change together (tape-speed).
    ratio 2.0 = twice as long and an octave lower."""
    if abs(ratio - 1.0) < 0.01:
        return audio
    n_out = max(1, int(len(audio) * ratio))
    indices = np.linspace(0, len(audio) - 1, n_out)
    return np.interp(indices, np.arange(len(audio)), audio).astype(np.float32)


def time_stretch_pv(audio, ratio, n_fft=1024, hop=256):
    """Pitch-preserving stretch: phase vocoder with identity phase locking.

    Analysis frames are read every hop/ratio samples and resynthesised every
    hop samples. Peak bins advance by their measured instantaneous frequency;
    every other bin is locked to its nearest peak (Laroche & Dolson identity
    locking), which keeps the bins of one partial coherent. Without it the
    zero-padded onset frames left each bin with its own arbitrary phase
    offset, and partials partly cancelled (v1.8: -9.6 dB on a 300 Hz sine and
    -16 dB at 1234 Hz for x2). Finally the stretched event is matched to the
    input RMS, so level does not depend on the ratio or on how coherent the
    material is (noise lost ~3 dB in incoherent overlap-add).
    Output length is int(len * ratio). Events under 64 samples resample.
    """
    if abs(ratio - 1.0) < 0.01:
        return audio
    x = np.asarray(audio, dtype=np.float64).reshape(-1)
    n_out = max(1, int(len(x) * ratio))
    if len(x) < 64:
        return time_stretch_naive(audio, ratio)
    while n_fft > 64 and n_fft > len(x):
        n_fft //= 2
    hop = max(1, n_fft // 4)
    win = np.hanning(n_fft)
    pad = n_fft
    xp = np.concatenate([np.zeros(pad), x, np.zeros(pad + n_fft)])
    Ha = hop / float(ratio)
    n_frames = int((len(xp) - n_fft) / Ha) + 1
    y = np.zeros(n_frames * hop + n_fft)
    wsum = np.zeros_like(y)
    nb = n_fft // 2 + 1
    omega = 2.0 * np.pi * np.arange(nb) / n_fft
    bins = np.arange(nb)
    prev_ph = None
    prev_pos = 0
    acc = None
    for k in range(n_frames):
        pos = int(round(k * Ha))
        if pos + n_fft > len(xp):
            break
        X = np.fft.rfft(xp[pos:pos + n_fft] * win)
        mag, ph = np.abs(X), np.angle(X)
        if acc is None:
            out_ph = ph.copy()
        else:
            dpos = max(1, pos - prev_pos)
            dphi = ph - prev_ph - omega * dpos
            dphi = (dphi + np.pi) % (2.0 * np.pi) - np.pi
            adv = acc + (omega + dphi / dpos) * hop
            # identity phase locking: every bin follows its region's peak
            m = mag
            is_pk = np.zeros(nb, dtype=bool)
            is_pk[1:-1] = (m[1:-1] > m[:-2]) & (m[1:-1] >= m[2:])
            pk = np.flatnonzero(is_pk)
            if len(pk):
                mids = (pk[:-1] + pk[1:]) // 2
                owner = pk[np.searchsorted(mids, bins, side='left')]
                out_ph = adv[owner] + (ph - ph[owner])
            else:
                out_ph = adv
        acc = out_ph
        prev_ph, prev_pos = ph, pos
        o = k * hop
        y[o:o + n_fft] += np.fft.irfft(mag * np.exp(1j * out_ph), n_fft) * win
        wsum[o:o + n_fft] += win ** 2
    y = np.where(wsum > 1e-3, y / np.maximum(wsum, 1e-3), 0.0)
    # Time alignment (v1.10): analysis frame k is centred on padded input
    # sample k*Ha + n/2 and resynthesised centred on k*hop + n/2, so padded
    # input sample t lands at ratio*t - (ratio-1)*n/2. v1.9 trimmed at
    # ratio*pad, which shifted everything by (ratio-1)*n/2 (-11.6 ms at x2).
    s0 = int(round(pad * ratio - (ratio - 1.0) * n_fft / 2.0))
    if s0 < 0:
        y = np.concatenate([np.zeros(-s0), y])
        s0 = 0
    y = y[s0:s0 + n_out]
    if len(y) < n_out:
        y = np.concatenate([y, np.zeros(n_out - len(y))])
    r_in = float(np.sqrt(np.mean(x ** 2)))
    r_out = float(np.sqrt(np.mean(y ** 2)))
    if r_in > 1e-9 and r_out > 1e-9:
        y *= float(np.clip(r_in / r_out, 0.25, 4.0))      # match level, at most +/-12 dB
    # attacks are spliced in after the level match, at their original level
    y = _transient_splice(x, y, ratio)
    return y.astype(np.float32)


def _transient_splice(x, y, ratio, sr_guess=44100):
    """Copy each sharp attack of x, unstretched, into the stretched y.

    A phase vocoder spreads an attack over its analysis window (an impulse
    lost ~94% of its peak at x2 in v1.9). Attacks are found as >= 9 dB jumps
    of 1 ms short-term energy that also reach -40 dB of the event's loudest
    millisecond; for each, 2 ms before to 12 ms after the onset is copied from
    the source to the mapped position (onset * ratio), with 1 ms raised-cosine
    joins. A loud first millisecond counts as an attack.
    """
    n = len(x)
    fr = max(8, int(0.001 * sr_guess))
    if n < 4 * fr:
        return y
    nf = n // fr
    e = np.sqrt(np.mean(x[:nf * fr].reshape(nf, fr) ** 2, axis=1)) + 1e-12
    top = float(e.max())
    pre, post, xf = 2 * fr, 12 * fr, max(4, fr)
    out = y.copy()
    last = -10 ** 9
    for i in range(0, nf):
        # frame 0 counts as an attack when the event starts loud (events are
        # cut at onsets, so this is the usual case)
        rise = e[i] / max(e[i - 1], 1e-12) if i > 0 else e[0] / (top * 0.005)
        if rise < 2.8 or e[i] < top * 0.01:
            continue
        n0 = i * fr
        if n0 - last < post:
            continue
        last = n0
        # refine to the first sample above half of this frame's peak
        seg = np.abs(x[n0:n0 + fr])
        n0 += int(np.argmax(seg >= 0.5 * seg.max())) if seg.max() > 0 else 0
        a0, a1 = max(0, n0 - pre), min(n, n0 + post)
        m0 = int(round(n0 * ratio)) - (n0 - a0)
        if m0 < 0:                       # compressed start: drop part of the pre-roll
            a0 -= m0
            m0 = 0
        a1 = min(a1, a0 + (len(out) - m0))
        L = a1 - a0
        if a0 > n0 or L <= 2 * xf:
            continue
        w = np.ones(L)
        xin = max(1, min(xf, n0 - a0))          # fade-in must end before the onset
        w[:xin] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, xin))
        w[-xf:] = (0.5 - 0.5 * np.cos(np.linspace(0, np.pi, xf)))[::-1]
        out[m0:m0 + L] = out[m0:m0 + L] * (1.0 - w) + x[a0:a1] * w
    return out


def apply_stretch(audio, ratio, mode='resample'):
    if mode == 'preserve':
        return time_stretch_pv(audio, ratio)
    return time_stretch_naive(audio, ratio)


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


def soft_limit(output):
    """Static tanh squash, then normalise to 0.92 peak (memoryless, no pumping)."""
    peak = float(np.abs(output).max()) if output.size else 0.0
    if peak > 0.01:
        drive = min(0.9 / peak, 4.0)
        output = np.tanh(output * drive).astype(np.float32)
        post_peak = float(np.abs(output).max())
        if post_peak > 0.01:
            output = output / post_peak * 0.92
    return output.astype(np.float32)


def render_ops(ops_list, events, sr, target_dur_s, overlap_default_ms=20,
               stretch_mode='resample', force_mono=False, normalize=True, meta=None):
    """
    Render a sequence of operation dicts to an audio buffer.

    - Crossfades only where two events genuinely overlap; otherwise 5 ms
      de-click fades. No weight-division normalisation; amplitude is set by
      per-op gain and one soft limiter at the end.
    - Any op carrying slice_ratio is cut from slice_offset in source time
      first; 'invert' ops and ops with reverse=True are then reversed.
    - normalize=False returns the raw sum (used per choir voice, so the voice
      gains survive into the final mix). force_mono ignores per-op pan.
    - Each op dict is annotated in place: _rendered (any sample inside the
      target duration) and _peak (peak of the part that was written).
      meta['pre_peak'] receives the mix peak before limiting.
    """
    if not ops_list:
        return np.zeros(int(sr * 1.0), dtype=np.float32)

    valid_ops = [op for op in ops_list if 0 <= op['event_idx'] < len(events)]
    if not valid_ops:
        return np.zeros(int(sr * max(target_dur_s, 1.0)), dtype=np.float32)
    valid_ops = sorted(valid_ops, key=lambda o: o['start_time'])

    max_time = max(
        max(0.0, op['start_time']) + len(events[op['event_idx']]['audio']) / sr
        for op in valid_ops
    )
    total_samples = int(max(max_time, target_dur_s) * sr) + sr
    tgt = int(target_dur_s * sr)
    spatial = (not force_mono) and any(abs(float(op.get('pan', 0.0))) > 1e-9 for op in valid_ops)
    output = np.zeros((total_samples, 2) if spatial else total_samples, dtype=np.float32)

    placements = []
    declick_samples = max(1, int(0.005 * sr))

    for idx, op in enumerate(valid_ops):
        op['_rendered'] = False
        op['_peak'] = 0.0
        ei = op['event_idx']
        raw = events[ei]['audio'].copy()
        gain = float(op.get('gain', 1.0))

        if 'slice_ratio' in op or op['type'] == 'fragment':
            off = int(op.get('slice_offset', 0))
            n = max(1, int(len(raw) * float(op.get('slice_ratio', 0.3))))
            raw = raw[off:off + n].copy()
        if op['type'] == 'invert' or op.get('reverse'):
            raw = raw[::-1].copy()

        erosion = float(np.clip(op.get('erosion', 0.0), 0.0, 1.0))
        if erosion > 1e-6 and len(raw) > 16:
            cutoff = max(180.0, (0.48 - 0.40 * erosion) * sr)
            cutoff = min(cutoff, sr * 0.49)
            try:
                sos = signal.butter(2, cutoff, btype='lowpass', fs=sr, output='sos')
                raw = signal.sosfilt(sos, raw).astype(np.float32)
            except Exception:
                pass

        stretch = float(op.get('stretch', 1.0))
        if abs(stretch - 1.0) > 0.02:
            raw = apply_stretch(raw, stretch, stretch_mode)

        if len(raw) == 0:
            continue
        raw = raw * gain

        skip = max(0, -int(op['start_time'] * sr))
        if skip >= len(raw):
            continue
        raw = raw[skip:]
        start_samp = max(0, int(op['start_time'] * sr))
        end_samp = start_samp + len(raw)

        xfade_samples = 0
        for prev_start, prev_end in reversed(placements):
            if prev_end > start_samp:
                max_xfade_s = int(op.get('crossfade_ms', overlap_default_ms) * sr / 1000.0)
                xfade_samples = min(max_xfade_s, prev_end - start_samp, len(raw) // 2)
                break
        fade_in_len = min(max(declick_samples, xfade_samples), len(raw) // 2)
        if fade_in_len > 0:
            raw[:fade_in_len] *= np.linspace(0.0, 1.0, fade_in_len, dtype=np.float32)

        fade_out_len = declick_samples
        for nxt_op in valid_ops[idx+1:idx+6]:
            nxt_start = max(0, int(nxt_op['start_time'] * sr))
            if nxt_start < end_samp:
                max_xfade_s = int(nxt_op.get('crossfade_ms', overlap_default_ms) * sr / 1000.0)
                fade_out_len = min(max_xfade_s, end_samp - nxt_start, len(raw) // 2)
                break
        fade_out_len = min(max(declick_samples, fade_out_len), len(raw) // 2)
        if fade_out_len > 0:
            raw[-fade_out_len:] *= np.linspace(1.0, 0.0, fade_out_len, dtype=np.float32)

        if end_samp > len(output):
            pad = end_samp - len(output)
            padding = np.zeros((pad, 2) if spatial else pad, dtype=np.float32)
            output = np.concatenate([output, padding], axis=0)

        if spatial:
            gl, gr = equal_power_pan_gains(op.get('pan', 0.0))
            output[start_samp:end_samp, 0] += raw * gl
            output[start_samp:end_samp, 1] += raw * gr
        else:
            output[start_samp:end_samp] += raw
        placements.append((start_samp, end_samp))

        if start_samp < tgt:
            seen = raw[:tgt - start_samp]
            op['_rendered'] = True
            op['_peak'] = float(np.abs(seen).max()) if len(seen) else 0.0

    if len(output) > tgt:
        output = output[:tgt]
    elif len(output) < tgt:
        pad = tgt - len(output)
        output = np.concatenate([output, np.zeros((pad, 2) if spatial else pad, dtype=np.float32)], axis=0)

    if meta is not None:
        meta['pre_peak'] = float(np.abs(output).max()) if output.size else 0.0
    if normalize:
        output = soft_limit(output)
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
      [15] param_mode             "explicit" = the values above are final
                                  (v1.8 Praat front-end: presets arrive as
                                  pre-filled, user-editable values);
                                  "preset" (default, older front-ends) =
                                  the preset's table overrides them
      [16] stretch_mode           "resample" (default; pitch follows the
                                  stretch) or "preserve" (phase vocoder)
      [17] stretch_amount         0..1 (default 0): every operation is
                                  stretched by 1 + amount (x1 .. x2) on top
                                  of the plan's own stretch
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
        'param_mode': s(15, 'preset').strip().lower(),
        'stretch_mode': 'preserve' if s(16, 'resample').strip().lower().startswith('pres') else 'resample',
        'stretch_amount': float(np.clip(f(17, 0.0), 0.0, 1.0)),
    }


def main():
    if len(sys.argv) < 3:
        print("Usage: hierarchical_recomposition.py input.wav output.wav stats.txt [params...] [preset]")
        sys.exit(1)

    cfg    = parse_args(sys.argv[1:])
    params = cfg['params']
    preset_name = cfg['preset']

    # Apply preset overrides
    explicit = cfg['param_mode'] == 'explicit'
    stretch_mode = cfg['stretch_mode']
    params, ops = get_preset(preset_name, params, explicit=explicit)
    params['stretch_amount'] = cfg['stretch_amount']

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
    if len(phrases) < min_form_phrases and len(events) >= 2:
        phrases = rebalance_phrases(events, feat_vecs, min(min_form_phrases, len(events)))
    # Minimum material for the formal presets (v1.10). If the source cannot
    # carry the requested form, stop with an explanation instead of silently
    # rendering a different planner.
    need = None
    n_natural = 1 if events and events[0].get('forced_split') else len(events)
    if (ops.get('sonata_form') or ops.get('refrain') or ops.get('polyphony')) and n_natural < 2:
        need = (f'{preset_name} needs at least two onset-separated events; the source has no '
                'detectable onset structure (it was only split at its midpoint)')
    elif ops.get('sonata_form') and len(phrases) < 2:
        need = 'Hidden Sonata needs two contrasting phrase groups (themes A and B)'
    elif ops.get('refrain') and len(phrases) < 2:
        need = 'Collapsing Refrain needs a refrain phrase plus at least one other phrase'
    elif ops.get('polyphony') and len(phrases) < 2:
        need = 'Latent Counterpoint needs at least two phrases to form two voices'
    elif ops.get('n_strands', 0) >= 3 and n_natural < 3:
        need = 'Formal Braiding needs at least three events for its three strands'
    form_warning = ''
    if not need and min_form_phrases > 1 and n_natural < min_form_phrases:
        form_warning = (f'thin material: {n_natural} event(s) for a form that wants '
                        f'{min_form_phrases} phrases; phrases were split from them')
    if need:
        sys.stderr.write(
            f"INSUFFICIENT MATERIAL: {need}.\n"
            f"The source gave {n_natural} onset-separated event(s).\n"
            "Try a longer or more varied source, a higher Phrase coherence, "
            "or a non-formal preset (Custom, Memory Spiral, Echo Architecture).\n")
        sys.exit(3)
    n_ph = len(phrases)
    print(f"      {n_ph} phrases found.", flush=True)

    # ── Stage 4: Real phrase-derived sections ────────────────────────────
    print("[4/6] Building sections + descriptors...", flush=True)
    phrase_sections, boundary_novelty = group_phrases_into_sections(phrases, events, features_list)
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
    sched_main = None
    if n_voices > 1:
        # Each voice is rendered unnormalised and in mono, then panned and
        # summed; ONE limiter runs on the sum. v1.7 normalised every voice
        # separately, which erased the planned per-voice gain steps.
        voice_sum = None
        voice_pans = np.linspace(-0.85, 0.85, n_voices)
        for v in range(n_voices):
            v_seed = seed + v * 137
            v_rng  = random.Random(v_seed)
            v_np   = np.random.RandomState(v_seed)
            v_plan = np.clip(section_plan_np + v_np.randn(*section_plan_np.shape) * 0.05, 0, 1)
            v_sched = plan_event_ordering(
                events, feat_vecs, features_list, phrases, phrase_sections,
                v_plan, params, ops, v_rng, sr)
            if sched_main is None:
                sched_main = v_sched
            v_ops = v_sched.ops_list
            offset = (v * dur_in / n_voices * 0.3) if ops.get('phase_offset', False) else 0.0
            voice_pan = float(voice_pans[v])
            for op in v_ops:
                op['start_time'] += offset
                op['gain']       *= (1.0 - v * 0.18)
                op['pan']         = voice_pan
                op['voice']       = v + 1
            visual_ops.extend(v_ops)
            buf = render_ops(v_ops, events, sr, target_dur, stretch_mode=stretch_mode,
                             force_mono=True, normalize=False)
            pbuf = pan_mono_buffer(buf, voice_pan) / n_voices
            pk_scale = max(equal_power_pan_gains(voice_pan)) / n_voices
            for op in v_ops:
                op['_peak'] = float(op.get('_peak', 0.0)) * pk_scale
            if voice_sum is None:
                voice_sum = pbuf
            else:
                n = max(len(voice_sum), len(pbuf))
                acc = np.zeros((n, 2), dtype=np.float32)
                acc[:len(voice_sum)] += voice_sum
                acc[:len(pbuf)] += pbuf
                voice_sum = acc
        mix_pre_peak = float(np.abs(voice_sum).max())
        output_audio = soft_limit(voice_sum)
        spatial_mode = f"choir_{n_voices}_voices"
    else:
        sched_main = plan_event_ordering(
            events, feat_vecs, features_list, phrases, phrase_sections,
            section_plan_np, params, ops, rng, sr)
        visual_ops = sched_main.ops_list
        rmeta = {}
        output_audio = render_ops(visual_ops, events, sr, target_dur,
                                  stretch_mode=stretch_mode, meta=rmeta)
        mix_pre_peak = rmeta.get('pre_peak', 0.0)
        if output_audio.ndim == 2:
            if ops.get('echo_depth'):
                spatial_mode = "echo_alternating"
            elif ops.get('n_strands', 0) >= 3:
                spatial_mode = "braid_strands"
            elif ops.get('polyphony'):
                spatial_mode = "counterpoint_voices"
            else:
                spatial_mode = "operation_pan"

    # Source trace stays removed: mixing a stretched copy of the original back
    # in produced comb filtering / beating against the correlated events.
    # Rendering already ends in a single soft limiter at 0.92 peak.

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
        'param_mode': 'explicit' if explicit else 'preset_table',
        'stretch_mode': stretch_mode,
        'stretch_amount': f'{cfg["stretch_amount"]:.3f}',
        'form_warning': form_warning,
        # Fixed blend weights of the plan (not a measured audible contribution):
        # on the five control-mixed slots neural 0.07 / descriptors 0.28 /
        # controls 0.65; on the other slots neural 0.20 / descriptors 0.80.
        'plan_mix': 'neural 0.20 + descriptors 0.80, then 0.35 plan + 0.65 control on 5 slots',
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

    # Actual section spans and phrase membership (boundaries = novelty peaks).
    stats['n_section_viz'] = len(phrase_sections)
    stats['section_method'] = 'novelty_peaks'
    stats['boundary_novelty'] = ','.join(f'{float(v):.3f}' for v in boundary_novelty)
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
    # planned  = accepted by the scheduler (starts before the target end)
    # rendered = at least one sample written inside the output
    # audible  = rendered and its peak within -60 dB of the mix peak (pre-limiter)
    def _op_duration_seconds(op):
        ei = int(op.get('event_idx', -1))
        if ei < 0 or ei >= len(events):
            return 0.0
        n = len(events[ei]['audio'])
        if 'slice_ratio' in op or op.get('type') == 'fragment':
            off = int(op.get('slice_offset', 0))
            n = min(n - off, max(1, int(n * float(op.get('slice_ratio', 0.3)))))
        stretch = float(op.get('stretch', 1.0))
        if abs(stretch - 1.0) > 0.02:
            n = max(1, int(n * stretch))
        return max(1, n) / sr

    def _op_source_span(op):
        """Source-time span actually read, oriented in playback direction."""
        ei = int(op.get('event_idx', -1))
        ev = events[ei]
        s0, s1 = ev['start'], ev['end']
        if 'slice_ratio' in op or op.get('type') == 'fragment':
            n = ev['end'] - ev['start']
            off = int(op.get('slice_offset', 0))
            s0 = ev['start'] + off
            s1 = min(ev['end'], s0 + max(1, int(n * float(op.get('slice_ratio', 0.3)))))
        if op.get('type') == 'invert' or op.get('reverse'):
            s0, s1 = s1, s0
        return s0 / sr, s1 / sr

    aud_floor = 1e-3 * max(mix_pre_peak, 1e-9)
    for op in visual_ops:
        op['_audible'] = bool(op.get('_rendered')) and float(op.get('_peak', 0.0)) >= aud_floor

    ops_sorted = sorted(visual_ops, key=lambda o: float(o.get('start_time', 0.0)))
    stats['n_ops_planned'] = len(ops_sorted)
    stats['n_ops_rendered'] = sum(1 for o in ops_sorted if o.get('_rendered'))
    stats['n_ops_audible'] = sum(1 for o in ops_sorted if o.get('_audible'))
    stats['n_ops_refused_beyond_target'] = int(sched_main.n_refused) if sched_main else 0
    stats['n_ops_stretched'] = sum(1 for o in ops_sorted if o.get('_rendered')
                                   and abs(float(o.get('stretch', 1.0)) - 1.0) > 0.02)
    stats['n_ops_total'] = stats['n_ops_rendered']
    rendered_ops = [o for o in ops_sorted if o.get('_rendered')]
    pan_values = np.array([float(op.get('pan', 0.0)) for op in rendered_ops], dtype=float) \
        if rendered_ops else np.array([0.0])
    stats['pan_min'] = f'{float(np.min(pan_values)):.4f}'
    stats['pan_max'] = f'{float(np.max(pan_values)):.4f}'
    stats['n_spatial_ops'] = int(np.count_nonzero(np.abs(pan_values) > 1e-9))
    for typ in ('place', 'repeat', 'fragment', 'recall', 'braid', 'echo', 'invert'):
        stats[f'n_op_{typ}'] = sum(1 for o in rendered_ops if o.get('type') == typ)
        stats[f'n_op_{typ}_planned'] = sum(1 for o in ops_sorted if o.get('type') == typ)
    for key, lab in (('restatement', 'restatement'), ('response', 'response'),
                     ('surprise', 'surprise'), ('density_layer', 'density_layer')):
        stats[f'n_mech_{key}'] = sum(1 for o in rendered_ops if str(o.get('label', '')).startswith(lab))

    # Sonata: rendered operations per theme window, so a missing theme shows.
    if ops.get('sonata_form'):
        win_counts = {}
        for o in rendered_ops:
            if int(o.get('voice', 1)) > 1:
                continue
            lab = str(o.get('label', '')).split('(')[0].replace('_repeat', '')
            win_counts[lab] = win_counts.get(lab, 0) + 1
        stats['sonata_windows'] = ','.join(
            f'{w}:{win_counts.get(w, 0)}' for w in ('expoA', 'expoB', 'dev', 'recapA', 'recapB'))
        stats['sonata_complete'] = int(all(win_counts.get(w, 0) > 0 for w in ('expoA', 'expoB', 'dev', 'recapA', 'recapB')))
        # Share of each window's duration actually covered by its own
        # rendered material (union of op spans). 1 op can still cover 100%.
        T_ = target_dur
        b1_, b2_ = 0.36 * T_, 0.72 * T_
        wins = {'expoA': (0, 0.5 * b1_), 'expoB': (0.5 * b1_, b1_), 'dev': (b1_, b2_),
                'recapA': (b2_, b2_ + 0.55 * (T_ - b2_)), 'recapB': (b2_ + 0.55 * (T_ - b2_), T_)}
        cover = []
        for w, (w0, w1) in wins.items():
            spans = []
            for o in rendered_ops:
                lab = str(o.get('label', '')).split('(')[0].replace('_repeat', '')
                if lab == w or (w == 'dev' and lab == 'dev_combine'):
                    st_ = float(o['start_time'])
                    spans.append((max(w0, st_), min(w1, st_ + _op_duration_seconds(o))))
            spans.sort()
            tot, ce = 0.0, w0
            for a_, b_ in spans:
                a_ = max(a_, ce)
                if b_ > a_:
                    tot += b_ - a_
                    ce = b_
            cover.append(f'{w}:{tot / max(1e-9, w1 - w0):.2f}')
        stats['sonata_window_coverage'] = ','.join(cover)

    # Form parts declared by the planner (voice 1 in choir mode).
    parts = sched_main.parts if sched_main else []
    max_parts = 64
    stats['n_form_parts'] = min(len(parts), max_parts)
    stats['n_form_parts_all'] = len(parts)
    n_empty = 0
    for pi_, (pname, t0p, t1p) in enumerate(parts[:max_parts]):
        n_in = sum(1 for o in rendered_ops if o.get('part') == pi_ and int(o.get('voice', 1)) <= 1)
        stats[f'form_part_{pi_}'] = f'{t0p:.6f},{t1p:.6f},{n_in},{pname}'
    for pi_ in range(len(parts)):
        if not any(o.get('part') == pi_ for o in rendered_ops):
            n_empty += 1
    stats['n_form_parts_empty'] = n_empty

    max_op_viz = 240
    audible_ops = []
    for op in rendered_ops:
        start = float(op.get('start_time', 0.0))
        end = start + _op_duration_seconds(op)
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
        ei = int(op.get('event_idx', -1))
        if 0 <= ei < len(events):
            sa, sb = _op_source_span(op)
            stats[f'opsrc_{j}'] = f'{sa:.6f},{sb:.6f}'
        else:
            stats[f'opsrc_{j}'] = '-1.000000,-1.000000'

    write_stats(cfg['stats'], stats)
    print("[HNR] Done.", flush=True)


if __name__ == '__main__':
    main()
