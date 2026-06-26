#!/usr/bin/env python3
# =============================================================================
# Hierarchical Neural Recomposition
# Author: Shai Cohen — Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026)
# License: MIT
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
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
#   Segments an input sound into events → phrases → sections,
#   builds hierarchical embeddings via PyTorch, then generates
#   a recomposition plan (ordering, overlap, density, memory)
#   and renders a new piece from the original source material.
#
# Dependencies:
#   pip install numpy scipy soundfile torch
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
    """Load audio, convert to mono float32."""
    audio, sr = sf.read(path, dtype='float32', always_2d=True)
    mono = audio.mean(axis=1)
    return mono, sr


def save_audio(path, audio, sr):
    """Save float32 audio, clipping to [-1, 1]."""
    out = np.clip(audio, -1.0, 1.0).astype(np.float32)
    sf.write(path, out, sr)


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
    """
    Segment audio into events using onset detection.
    Returns list of dicts: {start, end, audio}.
    """
    strength, hop = compute_onset_strength(audio, sr)
    onsets = pick_onsets(strength, sr, hop)
    onsets.append(len(audio))

    min_samples = int(min_dur_s * sr)
    max_samples = int(max_dur_s * sr)

    events = []
    for i in range(len(onsets) - 1):
        s = onsets[i]
        e = min(onsets[i + 1], s + max_samples)
        if (e - s) < min_samples:
            continue
        events.append({'start': s, 'end': e, 'audio': audio[s:e].copy()})

    # Safety: at least 2 events
    if len(events) < 2:
        mid = len(audio) // 2
        events = [
            {'start': 0,   'end': mid,         'audio': audio[:mid].copy()},
            {'start': mid, 'end': len(audio),  'audio': audio[mid:].copy()}
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


# =============================================================================
# SECTION 5 — SECTION DESCRIPTORS
# =============================================================================

def compute_section_descriptors(events, features_list, sr, n_sections=4):
    """
    Divide the event list into n_sections temporal windows and
    compute aggregate descriptors for each: density, brightness,
    mean_harmonicity, mean_flatness.
    Returns list of section dicts.
    """
    n = len(events)
    if n == 0:
        return []
    chunk = max(1, n // n_sections)
    sections = []
    for si in range(n_sections):
        idx_s = si * chunk
        idx_e = (si + 1) * chunk if si < n_sections - 1 else n
        sel   = features_list[idx_s:idx_e]
        if not sel:
            continue
        total_dur = sum(f['duration'] for f in sel)
        span      = events[min(idx_e-1, n-1)]['end']/sr - events[idx_s]['start']/sr + 1e-6
        sections.append({
            'event_range':    (idx_s, idx_e),
            'density':        len(sel) / (span + 1e-6),
            'brightness':     float(np.mean([f['centroid'] for f in sel])),
            'harmonicity':    float(np.mean([f['harmonicity'] for f in sel])),
            'flatness':       float(np.mean([f['flatness'] for f in sel])),
            'mean_rms':       float(np.mean([f['rms'] for f in sel])),
            'total_dur':      total_dur,
        })
    return sections


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
    """
    Modulate raw plan values by user compositional parameters.
    All params are 0.0–1.0 floats.
    Returns a new plan array of the same shape.
    """
    plan = section_plan_np.copy()

    def slot(name):
        return PLAN_SLOTS[name]

    for i in range(len(plan)):
        plan[i, slot('repetition')]    = np.clip(plan[i, slot('repetition')]    * (0.5 + params['repetition']),      0, 1)
        plan[i, slot('fragmentation')] = np.clip(plan[i, slot('fragmentation')] * (0.5 + params['fragmentation']),   0, 1)
        plan[i, slot('overlap')]       = np.clip(plan[i, slot('overlap')]       * (0.2 + params['overlap'] * 0.8),   0, 1)
        plan[i, slot('memory')]        = np.clip(plan[i, slot('memory')]        * (0.3 + params['memory'] * 0.7),    0, 1)
        plan[i, slot('contrast')]      = np.clip(plan[i, slot('contrast')]      * (0.3 + params['contrast'] * 0.7),  0, 1)
        plan[i, slot('surprise')]      = np.clip(plan[i, slot('surprise')]      * params['surprise'],                0, 1)
        plan[i, slot('formal_weight')] = plan[i, slot('formal_weight')]

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
            'target_duration': 1.2, 'density': 0.5, 'coherence': 0.7,
            'contrast': 0.8, 'memory': 0.3, 'repetition': 0.4,
            'fragmentation': 0.3, 'overlap': 0.6, 'source_trace': 0.9,
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
            'target_duration': 1.5, 'density': 0.4, 'coherence': 0.6,
            'contrast': 0.4, 'memory': 0.95, 'repetition': 0.7,
            'fragmentation': 0.2, 'overlap': 0.4, 'source_trace': 0.85,
            'surprise': 0.15,
        },
        'ops': {'memory_depth': 4, 'recurrence': True},
    },

    'FragmentedLitany': {
        'description': (
            'Short micro-events are extracted and arranged into a slow, '
            'incantatory repetition. Each litany cycle slightly mutates '
            'the ordering or duration of its fragments. The form accumulates '
            'ritual weight through obsessive variation.'
        ),
        'params': {
            'target_duration': 1.3, 'density': 0.3, 'coherence': 0.9,
            'contrast': 0.2, 'memory': 0.8, 'repetition': 0.9,
            'fragmentation': 0.95, 'overlap': 0.1, 'source_trace': 0.95,
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
            'target_duration': 1.1, 'density': 0.65, 'coherence': 0.5,
            'contrast': 0.75, 'memory': 0.5, 'repetition': 0.5,
            'fragmentation': 0.4, 'overlap': 0.7, 'source_trace': 0.8,
            'surprise': 0.35,
        },
        'ops': {'braid': True, 'n_strands': 3},
    },

    'CollapsingRefrain': {
        'description': (
            'A strong opening phrase acts as a refrain. It returns three '
            'times, each time more fragmented and harmonically eroded. '
            'The final statement collapses into isolated residual events. '
            'Form is built entirely by progressive dissolution.'
        ),
        'params': {
            'target_duration': 1.4, 'density': 0.45, 'coherence': 0.6,
            'contrast': 0.5, 'memory': 0.85, 'repetition': 0.8,
            'fragmentation': 0.8, 'overlap': 0.2, 'source_trace': 0.9,
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
            'target_duration': 1.6, 'density': 0.35, 'coherence': 0.55,
            'contrast': 0.3, 'memory': 0.6, 'repetition': 0.6,
            'fragmentation': 0.15, 'overlap': 0.8, 'source_trace': 0.95,
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
            'target_duration': 1.0, 'density': 0.8, 'coherence': 0.75,
            'contrast': 0.4, 'memory': 0.7, 'repetition': 0.65,
            'fragmentation': 0.2, 'overlap': 0.9, 'source_trace': 0.99,
            'surprise': 0.1,
        },
        'ops': {'choir_voices': 4, 'phase_offset': True},
    },

    'HiddenSonata': {
        'description': (
            'A classical three-part sonata form is projected onto the '
            'event/phrase structure: an exposition introduces two contrasting '
            'phrase groups, a development section fragments and combines them, '
            'and a recapitulation restates the opening material, transformed. '
            'The hidden sonata is latent inside the source.'
        ),
        'params': {
            'target_duration': 1.8, 'density': 0.5, 'coherence': 0.65,
            'contrast': 0.7, 'memory': 0.9, 'repetition': 0.7,
            'fragmentation': 0.5, 'overlap': 0.35, 'source_trace': 0.85,
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
    """
    Generate a linear ordering of event indices with operations
    (repetition, fragmentation, overlap, memory callbacks, etc.).

    Returns a list of Operation dicts:
      {type, event_idx, start_time, gain, crossfade_ms, label}
    """
    n_events = len(events)

    sim_matrix = build_event_similarity_matrix(feat_vecs)

    ops_list = []
    cursor   = 0.0    # placement time in seconds

    target_dur = params.get('target_duration', 1.0) * sum(
        len(e['audio']) for e in events) / sr

    phrase_order = _plan_phrase_order(phrases, section_plan_np, params, ops, rng)

    memory_bank  = []    # (phrase_idx, start_time) of placed phrases
    used_events  = set()

    def slot(name):
        return PLAN_SLOTS[name]

    for phrase_pos, phrase_idx in enumerate(phrase_order):
        phrase    = phrases[phrase_idx]
        plan_row  = section_plan_np[min(phrase_idx, len(section_plan_np)-1)]

        ev_indices = phrase['event_indices']

        # ── Memory callback ──────────────────────────────────────────────
        if memory_bank and plan_row[slot('memory')] > 0.55 and rng.random() < plan_row[slot('memory')]:
            recall_phrase_idx, recall_time = rng.choice(memory_bank) if isinstance(memory_bank[0], tuple) else (memory_bank[0], 0)
            if isinstance(recall_phrase_idx, tuple):
                recall_phrase_idx = recall_phrase_idx[0]
            recall_phrase = phrases[min(recall_phrase_idx, len(phrases)-1)]
            for ei in recall_phrase['event_indices'][:2]:
                dur_s = len(events[ei]['audio']) / sr
                ops_list.append({
                    'type':          'recall',
                    'event_idx':     ei,
                    'start_time':    cursor,
                    'gain':          0.65,
                    'crossfade_ms':  30,
                    'label':         f'memory_recall(p{recall_phrase_idx})',
                })
                cursor += dur_s * 0.5

        # ── Fragmentation ────────────────────────────────────────────────
        if plan_row[slot('fragmentation')] > 0.6 and rng.random() < plan_row[slot('fragmentation')]:
            sub_ev = rng.choice(ev_indices) if len(ev_indices) > 0 else ev_indices[0]
            ops_list.append({
                'type':          'fragment',
                'event_idx':     int(sub_ev),
                'start_time':    cursor,
                'gain':          0.8,
                'crossfade_ms':  10,
                'slice_ratio':   rng.uniform(0.15, 0.45),
                'label':         f'fragment(p{phrase_idx},e{sub_ev})',
            })
            dur_s = len(events[int(sub_ev)]['audio']) / sr
            cursor += dur_s * rng.uniform(0.15, 0.45)

        # ── Main phrase placement ────────────────────────────────────────
        for pos_in_phrase, ei in enumerate(ev_indices):
            ev_dur_s = len(events[ei]['audio']) / sr

            # Repetition
            if plan_row[slot('repetition')] > 0.5 and rng.random() < plan_row[slot('repetition')] * 0.4:
                ops_list.append({
                    'type':          'repeat',
                    'event_idx':     ei,
                    'start_time':    max(0.0, cursor - ev_dur_s * rng.uniform(0.0, 0.3)),
                    'gain':          0.7,
                    'crossfade_ms':  20,
                    'label':         f'repeat(p{phrase_idx},e{ei})',
                })

            stretch = 1.0
            if plan_row[slot('stretch')] > 0.55:
                stretch = 1.0 + (plan_row[slot('stretch')] - 0.5) * params.get('fragmentation', 0.3)
                stretch = float(np.clip(stretch, 0.5, 3.0))

            ops_list.append({
                'type':          'place',
                'event_idx':     ei,
                'start_time':    cursor,
                'gain':          1.0,   # primary event: full gain; secondary ops use lower gain
                'crossfade_ms':  int(20 + plan_row[slot('overlap')] * 80),
                'stretch':       stretch,
                'label':         f'place(p{phrase_idx},e{ei})',
            })
            used_events.add(ei)

            gap = ev_dur_s * stretch
            # Cursor advances by full event length minus only the crossfade tail.
            # This keeps events mostly sequential; overlap is expressed via
            # crossfade_ms in the renderer, not via a large time offset.
            xfade_s = int(20 + plan_row[slot('overlap')] * 80) / 1000.0
            xfade_s = min(xfade_s, gap * 0.15)   # cap overlap at 15 % of event
            cursor += max(gap * 0.1, gap - xfade_s)

        # ── Braid: interleave with contrasting phrase ────────────────────
        if ops.get('braid') and plan_row[slot('braid')] > 0.45:
            contrast_idx = _find_contrast_phrase(phrase_idx, phrases, sim_matrix, feat_vecs, rng)
            if contrast_idx is not None:
                braid_evs = phrases[contrast_idx]['event_indices']
                braid_cursor = cursor - sum(
                    len(events[ei]['audio']) / sr for ei in ev_indices
                ) * 0.5
                for bei in braid_evs[:3]:
                    dur_s = len(events[bei]['audio']) / sr
                    ops_list.append({
                        'type':         'braid',
                        'event_idx':    bei,
                        'start_time':   max(0.0, braid_cursor),
                        'gain':         0.6,
                        'crossfade_ms': 25,
                        'label':        f'braid(p{phrase_idx}+p{contrast_idx},e{bei})',
                    })
                    braid_cursor += dur_s * 0.7

        # ── Collapse ─────────────────────────────────────────────────────
        if plan_row[slot('collapse')] > 0.7 and rng.random() < 0.3:
            cursor += rng.uniform(0.2, 0.6)   # silence gap

        # ── Echo ops ─────────────────────────────────────────────────────
        if ops.get('echo_depth') and ev_indices:
            echo_decay = ops.get('echo_decay', 0.5)
            echo_depth = ops.get('echo_depth', 2)
            src_ev     = ev_indices[0]
            ev_dur_s   = len(events[src_ev]['audio']) / sr
            for ech in range(1, echo_depth + 1):
                ops_list.append({
                    'type':         'echo',
                    'event_idx':    src_ev,
                    'start_time':   cursor + ev_dur_s * ech * 0.6,
                    'gain':         echo_decay ** ech,
                    'crossfade_ms': 15,
                    'label':        f'echo{ech}(p{phrase_idx},e{src_ev})',
                })

        # ── Inversion ────────────────────────────────────────────────────
        if plan_row[slot('inversion')] > 0.65 and rng.random() < 0.3:
            for ei in ev_indices[:2]:
                dur_s = len(events[ei]['audio']) / sr
                ops_list.append({
                    'type':         'invert',
                    'event_idx':    ei,
                    'start_time':   cursor,
                    'gain':         0.75,
                    'crossfade_ms': 15,
                    'label':        f'invert(p{phrase_idx},e{ei})',
                })
                cursor += dur_s * 0.8

        memory_bank.append((phrase_idx, cursor))

        # Early stop if we've exceeded target duration
        if cursor > target_dur * 1.1:
            break

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


def render_ops(ops_list, events, sr, target_dur_s, overlap_default_ms=20):
    """
    Render a sequence of operation dicts to an audio buffer.

    Design decisions to avoid tremolo / amplitude flutter:
    - Crossfade envelopes are applied ONLY at junctions where two events
      genuinely overlap (determined by whether the next op starts before
      the current one ends).  Non-overlapping events get a short 5 ms
      linear fade-in only (de-click), no fade-out.
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
            pad    = end_samp - len(output)
            output = np.concatenate([output, np.zeros(pad, dtype=np.float32)])

        output[start_samp:end_samp] += raw
        placements.append((start_samp, end_samp))

    # ── Trim to target duration ──────────────────────────────────────────
    tgt = int(target_dur_s * sr)
    if len(output) > tgt:
        output = output[:tgt]
    elif len(output) < tgt:
        output = np.concatenate([output, np.zeros(tgt - len(output), dtype=np.float32)])

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
      [4] density                 (0.0 – 1.0)
      [5] coherence               (0.0 – 1.0)
      [6] contrast                (0.0 – 1.0)
      [7] memory                  (0.0 – 1.0)
      [8] repetition              (0.0 – 1.0)
      [9] fragmentation           (0.0 – 1.0)
      [10] overlap                (0.0 – 1.0)
      [11] source_trace           (0.0 – 1.0)
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

    seed = cfg['seed']
    rng  = random.Random(seed)
    np_rng = np.random.RandomState(seed)
    # Reseed numpy random for the run
    np.random.seed(seed)

    print(f"[HNR] Preset: {preset_name} | Seed: {seed}", flush=True)
    print(f"[HNR] Loading audio: {cfg['input']}", flush=True)

    audio, sr = load_audio(cfg['input'])
    dur_in    = len(audio) / sr
    print(f"[HNR] Duration: {dur_in:.2f}s | SR: {sr}Hz", flush=True)

    # ── Stage 1: Segmentation ────────────────────────────────────────────
    print("[1/6] Segmenting events...", flush=True)
    min_dur = max(0.03, 0.04 * (1.0 - params['fragmentation']))
    events  = segment_events(audio, sr, min_dur_s=min_dur)
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
    n_ph    = len(phrases)
    print(f"      {n_ph} phrases found.", flush=True)

    # ── Stage 4: Section descriptors ─────────────────────────────────────
    print("[4/6] Computing section descriptors...", flush=True)
    n_sections = max(2, min(8, n_ph))
    sections   = compute_section_descriptors(events, features_list, sr, n_sections)

    # ── Stage 5: Hierarchical model ──────────────────────────────────────
    print("[5/6] Running hierarchical neural model...", flush=True)

    if TORCH_OK:
        torch.manual_seed(seed)
    np.random.seed(seed)

    phrase_arrays = []
    for ph in phrases:
        arr = feat_vecs[ph['event_indices']]
        phrase_arrays.append(arr)

    if TORCH_OK:
        model = HierarchicalRecompositionModel()
        model.eval()
        with torch.no_grad():
            phrase_tensors = [torch.from_numpy(arr) for arr in phrase_arrays]
            event_embs, phrase_embs, section_plan_t = model(phrase_tensors)
        section_plan_np = section_plan_t.numpy()
        phrase_embs_np  = phrase_embs.numpy()
    else:
        fb_model = NumpyFallbackModel(seed=seed)
        event_embs, phrase_embs_np, section_plan_np = fb_model.forward(phrase_arrays)

    # Ensure plan has one row per phrase
    if len(section_plan_np) < n_ph:
        tile = math.ceil(n_ph / max(1, len(section_plan_np)))
        section_plan_np = np.tile(section_plan_np, (tile, 1))[:n_ph]

    # Apply compositional parameter modulation
    section_plan_np = apply_compositional_params(section_plan_np, params)

    # ── Stage 6: Recomposition & rendering ───────────────────────────────
    print("[6/6] Building recomposition plan & rendering...", flush=True)

    # ── Choir mode: multiple offset copies ───────────────────────────────
    n_voices   = ops.get('choir_voices', 1)
    target_dur = dur_in * params['target_duration']

    if n_voices > 1:
        voice_buffers = []
        for v in range(n_voices):
            v_seed = seed + v * 137
            v_rng  = random.Random(v_seed)
            v_np   = np.random.RandomState(v_seed)
            v_plan = section_plan_np.copy()
            v_plan = v_plan + v_np.randn(*v_plan.shape) * 0.05
            v_plan = np.clip(v_plan, 0, 1)
            v_ops  = plan_event_ordering(
                events, feat_vecs, phrases, v_plan, params, ops, v_rng, sr)
            offset = v * dur_in / n_voices * 0.3
            for op in v_ops:
                op['start_time'] += offset
                op['gain']       *= (1.0 - v * 0.18)
            buf = render_ops(v_ops, events, sr, target_dur)
            voice_buffers.append(buf)

        max_len = max(len(b) for b in voice_buffers)
        output_audio = np.zeros(max_len, dtype=np.float32)
        for buf in voice_buffers:
            output_audio[:len(buf)] += buf / n_voices
    else:
        plan_ops     = plan_event_ordering(
            events, feat_vecs, phrases, section_plan_np, params, ops, rng, sr)
        output_audio = render_ops(plan_ops, events, sr, target_dur)

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

    # ── Write stats ──────────────────────────────────────────────────────
    stats = {
        'n_events':       n_ev,
        'n_phrases':      n_ph,
        'n_sections':     len(sections),
        'input_duration': f'{dur_in:.3f}',
        'output_duration':f'{len(output_audio)/sr:.3f}',
        'preset':         preset_name,
        'seed':           seed,
        'torch_used':     int(TORCH_OK),
        'mean_density':   f'{np.mean([s["density"] for s in sections]):.3f}' if sections else '0',
        'mean_brightness':f'{np.mean([s["brightness"] for s in sections]):.3f}' if sections else '0',
        'plan_rows':      len(section_plan_np),
    }
    write_stats(cfg['stats'], stats)
    print("[HNR] Done.", flush=True)


if __name__ == '__main__':
    main()
