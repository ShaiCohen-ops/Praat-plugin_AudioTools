#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - ai_conductor_mix.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   AI Conductor - PyTorch ensemble intelligence.
#   Receives: manifest (WAV paths), macro descriptors (from Praat).
#   Produces: time-based mix plan CSV for Praat to render.
#
#   Roles: leader, shadow, resonance, noise_fringe, pulse_carrier,
#          interruption, sustain_bed, contrast_voice, memory_trace,
#          silence
#   States: sparse, balanced, agitated, saturated, suspended, released
#
# Dependencies:
#   pip install torch numpy scipy soundfile librosa
#
# ============================================================

import argparse
import csv
import math
import os
import sys
import time

import numpy as np
import soundfile as sf
import torch
import torch.nn as nn
import torch.nn.functional as F

# ── Optional librosa for onset detection ──────────────────────────────────────
try:
    import librosa
    HAS_LIBROSA = True
except ImportError:
    HAS_LIBROSA = False

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

# Descriptor dimension per segment (computed in extract_segment_descriptors)
DESC_DIM = 10   # rms, zcr, centroid, bandwidth, flux, roughness,
                # pitch_salience, hnr_proxy, attack_slope, temporal_stability

# ─────────────────────────────────────────────────────────────────────────────
# CONDUCTOR NEURAL NETWORK
# ─────────────────────────────────────────────────────────────────────────────

class ConductorAttention(nn.Module):
    """
    Transformer-style attention over ensemble segments.
    Input:  (n_files, n_segs, desc_dim)   - per-file segment descriptors
    Output: role logits + prominence + state logits per (file, seg) position
    """

    def __init__(self, desc_dim: int = DESC_DIM, d_model: int = 64,
                 n_heads: int = 4, n_layers: int = 2,
                 n_files: int = 2, n_roles: int = N_ROLES,
                 n_states: int = N_STATES):
        super().__init__()
        self.input_proj = nn.Linear(desc_dim + 2, d_model)  # +2 for file_id, time_norm

        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=0.0, batch_first=True
        )
        self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=n_layers)

        self.role_head      = nn.Linear(d_model, n_roles)
        self.prominence_head = nn.Sequential(
            nn.Linear(d_model, 16), nn.ReLU(), nn.Linear(16, 1), nn.Sigmoid()
        )
        self.state_head     = nn.Linear(d_model, n_states)

    def forward(self, x: torch.Tensor) -> dict:
        # x: (total_segs, desc_dim+2)
        h = self.input_proj(x)                       # (T, d_model)
        h = h.unsqueeze(0)                            # (1, T, d_model) batch=1
        h = self.transformer(h).squeeze(0)            # (T, d_model)

        role_logits  = self.role_head(h)              # (T, n_roles)
        prominence   = self.prominence_head(h)        # (T, 1)
        state_logits = self.state_head(h)             # (T, n_states)

        return {
            "role_logits":  role_logits,
            "prominence":   prominence,
            "state_logits": state_logits,
            "hidden":       h
        }


class MemoryModule(nn.Module):
    """
    GRU memory that carries conductor state across the timeline.
    Input:  current hidden (d_model,) + prev memory (d_mem,)
    Output: updated memory (d_mem,)
    """

    def __init__(self, d_model: int = 64, d_mem: int = 32):
        super().__init__()
        self.gru_cell = nn.GRUCell(d_model, d_mem)
        self.d_mem    = d_mem

    def forward(self, h_t: torch.Tensor,
                mem: torch.Tensor) -> torch.Tensor:
        return self.gru_cell(h_t, mem)


# ─────────────────────────────────────────────────────────────────────────────
# AUDIO ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────

def load_audio_mono(path: str) -> tuple[np.ndarray, int]:
    audio, sr = sf.read(path, always_2d=True)
    mono = audio.mean(axis=1).astype(np.float32)
    return mono, sr


def segment_fixed(audio: np.ndarray, sr: int,
                  frame_ms: float, hop_ms: float) -> list[dict]:
    frame_n = max(1, int(sr * frame_ms / 1000))
    hop_n   = max(1, int(sr * hop_ms  / 1000))
    segs = []
    t = 0
    idx = 0
    while t + frame_n <= len(audio):
        segs.append({"start_samp": t, "end_samp": t + frame_n,
                     "start_sec":  t / sr,
                     "dur_sec":    frame_n / sr, "idx": idx})
        t   += hop_n
        idx += 1
    return segs


def segment_onset(audio: np.ndarray, sr: int,
                  min_gap_ms: float) -> list[dict]:
    if HAS_LIBROSA:
        onsets = librosa.onset.onset_detect(
            y=audio, sr=sr, units="samples",
            backtrack=True, delta=0.1
        )
    else:
        # Simple energy-based onset fallback
        hop  = int(sr * 0.01)
        energy = np.array([
            np.sum(audio[i:i+hop]**2)
            for i in range(0, len(audio) - hop, hop)
        ])
        diff   = np.diff(energy, prepend=energy[0])
        thresh = diff.mean() + diff.std() * 1.5
        onset_frames = np.where(diff > thresh)[0]
        onsets = (onset_frames * hop).astype(int)

    min_gap_samp = int(sr * min_gap_ms / 1000)
    # Filter onsets by minimum gap
    filtered = []
    last = -min_gap_samp - 1
    for o in onsets:
        if o - last >= min_gap_samp:
            filtered.append(o)
            last = o
    if not filtered:
        filtered = [0]

    segs = []
    for i, start in enumerate(filtered):
        end = filtered[i+1] if i+1 < len(filtered) else len(audio)
        dur = (end - start) / sr
        if dur > 0.01:
            segs.append({"start_samp": start, "end_samp": end,
                         "start_sec":  start / sr,
                         "dur_sec":    dur, "idx": i})
    return segs


def segment_hybrid(audio: np.ndarray, sr: int,
                   frame_ms: float, hop_ms: float,
                   min_gap_ms: float) -> list[dict]:
    onset_segs = segment_onset(audio, sr, min_gap_ms)
    fixed_segs = segment_fixed(audio, sr, frame_ms, hop_ms)

    # Merge: keep onset boundaries, subdivide long onset regions with fixed
    hybrid = []
    idx = 0
    for os in onset_segs:
        dur = os["dur_sec"]
        if dur > frame_ms / 1000 * 3:
            # Subdivide
            sub = segment_fixed(
                audio[os["start_samp"]:os["end_samp"]], sr, frame_ms, hop_ms
            )
            for s in sub:
                s["start_samp"] += os["start_samp"]
                s["end_samp"]   += os["start_samp"]
                s["start_sec"]   = s["start_samp"] / sr
                s["idx"]         = idx
                hybrid.append(s)
                idx += 1
        else:
            os["idx"] = idx
            hybrid.append(os)
            idx += 1
    return hybrid if hybrid else fixed_segs


def extract_descriptors(audio: np.ndarray, sr: int,
                        segs: list[dict]) -> np.ndarray:
    """
    Returns (n_segs, DESC_DIM) float32 array.
    Columns: rms, zcr, centroid, bandwidth, flux, roughness,
             pitch_salience, hnr_proxy, attack_slope, temporal_stability
    """
    descs = np.zeros((len(segs), DESC_DIM), dtype=np.float32)

    prev_mag = None
    for i, seg in enumerate(segs):
        chunk = audio[seg["start_samp"]:seg["end_samp"]]
        if len(chunk) < 2:
            continue

        n     = len(chunk)
        win   = chunk * np.hanning(n)
        spec  = np.abs(np.fft.rfft(win))
        freqs = np.fft.rfftfreq(n, d=1.0/sr)
        eps   = 1e-12

        # RMS
        rms = float(np.sqrt(np.mean(chunk**2)))

        # ZCR
        zcr = float(np.mean(np.abs(np.diff(np.sign(chunk))) / 2))

        # Spectral centroid
        spec_sum = spec.sum() + eps
        centroid = float(np.sum(freqs * spec) / spec_sum)

        # Spectral bandwidth
        bandwidth = float(np.sqrt(np.sum(((freqs - centroid)**2) * spec) / spec_sum))

        # Spectral flux
        if prev_mag is None:
            flux = 0.0
        else:
            diff_mag = spec[:len(prev_mag)] - prev_mag[:len(spec)]
            flux = float(np.sum(np.maximum(diff_mag, 0)))
        prev_mag = spec.copy()

        # Roughness (sum of high-freq energy ratio)
        hi_idx   = freqs > 3000
        roughness = float(spec[hi_idx].sum() / (spec_sum))

        # Pitch salience (autocorr peak prominence)
        acorr = np.correlate(chunk, chunk, mode="full")
        acorr = acorr[n-1:]
        if len(acorr) > sr // 50:
            peak_region = acorr[sr//500 : sr//50]
            if len(peak_region) > 0:
                pitch_salience = float(peak_region.max() / (acorr[0] + eps))
            else:
                pitch_salience = 0.0
        else:
            pitch_salience = 0.0

        # HNR proxy (ratio of harmonic to noise via cepstrum peak)
        ceps = np.abs(np.fft.irfft(np.log(spec + eps)))
        if len(ceps) > 10:
            q_lo = int(sr / 500)
            q_hi = int(sr / 50)
            q_lo = max(1, q_lo)
            q_hi = min(len(ceps)-1, q_hi)
            if q_hi > q_lo:
                hnr_proxy = float(ceps[q_lo:q_hi].max() / (np.abs(ceps).mean() + eps))
            else:
                hnr_proxy = 0.0
        else:
            hnr_proxy = 0.0

        # Attack slope (energy rise in first 20% of segment)
        attack_n  = max(2, n // 5)
        attack_rms = np.sqrt(np.mean(chunk[:attack_n]**2) + eps)
        body_rms   = np.sqrt(np.mean(chunk[attack_n:]**2) + eps)
        attack_slope = float(attack_rms / (body_rms + eps) - 1.0)

        # Temporal stability (1 - normalised std of short-term energy)
        frame_e  = np.array([chunk[j:j+32].__pow__(2).mean()
                             for j in range(0, n-32, 32)])
        if len(frame_e) > 1 and frame_e.mean() > eps:
            stab = 1.0 - min(1.0, float(frame_e.std() / (frame_e.mean() + eps)))
        else:
            stab = 1.0

        descs[i] = [rms, zcr, centroid, bandwidth, flux, roughness,
                    pitch_salience, hnr_proxy, attack_slope, stab]

    # Return raw (un-normalised) descriptors — global normalisation
    # happens in conduct() after all files are stacked together
    return descs


# ─────────────────────────────────────────────────────────────────────────────
# RELATION MODEL
# ─────────────────────────────────────────────────────────────────────────────

def build_relation_matrix(all_descs: list[np.ndarray]) -> np.ndarray:
    """
    Builds a (total_segs, total_segs) relation matrix encoding
    similarity, contrast, masking risk, and complementarity.
    Returns values in [-1, 1] where +1 = highly similar, -1 = strong contrast.
    """
    flat = np.vstack(all_descs)   # (total_segs, DESC_DIM)
    n    = flat.shape[0]
    rel  = np.zeros((n, n), dtype=np.float32)

    for i in range(n):
        for j in range(n):
            if i == j:
                rel[i, j] = 1.0
            else:
                # Cosine similarity as base
                a, b = flat[i], flat[j]
                denom = (np.linalg.norm(a) * np.linalg.norm(b)) + 1e-12
                cos_sim = float(np.dot(a, b) / denom)

                # Masking risk: high if both have similar centroid + high rms
                centroid_diff = abs(a[2] - b[2])
                rms_prod      = a[0] * b[0]
                masking_risk  = float(np.exp(-centroid_diff * 5) * rms_prod)

                rel[i, j] = cos_sim - masking_risk * 0.3
    return rel


# ─────────────────────────────────────────────────────────────────────────────
# CONDUCTOR LOGIC
# ─────────────────────────────────────────────────────────────────────────────

def conduct(
    file_audios:     list[np.ndarray],
    file_srs:        list[int],
    file_names:      list[str],
    seg_mode:        str,
    frame_ms:        float,
    hop_ms:          float,
    onset_gap_ms:    float,
    style:           str,
    memory_weight:   float,
    tension_sens:    float,
    allow_silence:   bool,
    nonlinear:       bool
) -> list[dict]:
    """
    Main conductor pipeline.
    Returns list of plan rows (dicts) for CSV output.
    """
    device = torch.device("cpu")
    n_files = len(file_audios)

    # ── 1. Segmentation ──────────────────────────────────────────────────────
    print("  Segmenting ensemble...", flush=True)
    all_segs  = []
    all_descs = []

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

    n_total    = len(all_segs)
    flat_descs = np.vstack(all_descs)   # (n_total, DESC_DIM) — raw values
    max_dur    = max(a.shape[0] / sr for a, sr in zip(file_audios, file_srs))

    # ── 2. Global normalisation then percentile ranks ─────────────────────────
    # Normalise each column across ALL segments from ALL files together
    col_min = flat_descs.min(axis=0)
    col_max = flat_descs.max(axis=0)
    col_range = col_max - col_min + 1e-12
    flat_norm = (flat_descs - col_min) / col_range   # (n_total, DESC_DIM) in [0,1]

    # Descriptor columns: rms(0) zcr(1) centroid(2) bandwidth(3) flux(4)
    #                     roughness(5) pitch_salience(6) hnr(7) attack(8) stab(9)
    rms      = flat_norm[:, 0]
    flux     = flat_norm[:, 4]
    centroid = flat_norm[:, 2]
    rough    = flat_norm[:, 5]
    pitch_s  = flat_norm[:, 6]
    hnr      = flat_norm[:, 7]
    attack   = flat_norm[:, 8]
    stab     = flat_norm[:, 9]

    # Composite scores
    energy    = np.clip(rms * 0.6 + flux * 0.4, 0, 1)
    noisiness = np.clip((rough + (1 - pitch_s) + (1 - hnr)) / 3, 0, 1)
    bright    = centroid
    stabil    = stab
    sharpness = np.clip(attack, 0, 1)

    # Percentile-based thresholds — always distribute roles regardless of
    # absolute descriptor values. Top 20% energy = leader candidates, etc.
    def pct(arr, p):
        return float(np.percentile(arr, p))

    thr_energy_high   = pct(energy,    75)   # top 25% = high energy
    thr_energy_mid    = pct(energy,    40)   # above 40th pct = mid
    thr_energy_low    = pct(energy,    20)   # below 20th pct = quiet
    thr_bright_high   = pct(bright,    65)
    thr_noise_high    = pct(noisiness, 70)
    thr_noise_low     = pct(noisiness, 35)
    thr_stab_high     = pct(stabil,    60)
    thr_stab_low      = pct(stabil,    30)
    thr_pitch_high    = pct(pitch_s,   60)
    thr_hnr_high      = pct(hnr,       60)
    thr_attack_high   = pct(sharpness, 65)
    thr_flux_low      = pct(flux,      35)

    print(f"    Descriptor ranges — energy: {energy.min():.3f}-{energy.max():.3f} "
          f"| bright: {bright.min():.3f}-{bright.max():.3f} "
          f"| noise: {noisiness.min():.3f}-{noisiness.max():.3f}", flush=True)
    print(f"    Thresholds — energy hi/mid/lo: {thr_energy_high:.3f}/{thr_energy_mid:.3f}/{thr_energy_low:.3f} "
          f"| bright_hi: {thr_bright_high:.3f} | noise_hi: {thr_noise_high:.3f}", flush=True)

    # Time position normalised to [0,1] within each file
    file_durs = [a.shape[0] / sr for a, sr in zip(file_audios, file_srs)]
    time_pos = np.array([
        seg["start_sec"] / (file_durs[fi] + 1e-9)
        for fi, seg in all_segs
    ], dtype=np.float32)

    # ── 3. Global tension curve (shared across all files) ────────────────────
    # Tension is a smooth function of time, shaped by style
    # It drives: density, role diversity, silence probability
    n_frames_tension = 100
    t_axis = np.linspace(0, 1, n_frames_tension)

    if style == "dramatic":
        # Rise → peak at 0.65 → sharp fall → brief climax near end
        tension_curve = (np.sin(t_axis * np.pi) ** 0.7
                         + 0.3 * np.sin(t_axis * 2 * np.pi))
    elif style == "minimal":
        # Stays low, gentle swell in middle
        tension_curve = 0.2 + 0.3 * np.sin(t_axis * np.pi)
    elif style == "dense":
        # High throughout, small valleys
        tension_curve = 0.7 + 0.25 * np.sin(t_axis * 4 * np.pi)
    else:  # neutral
        tension_curve = 0.4 + 0.2 * np.sin(t_axis * np.pi)

    tension_curve = np.clip(tension_curve, 0, 1)

    def get_tension(t_norm):
        idx = int(np.clip(t_norm * (n_frames_tension - 1), 0, n_frames_tension - 1))
        return float(tension_curve[idx])

    # ── 4. Role assignment — score-based winner-takes-all ────────────────────
    # Compute a fitness score for each role for every segment using single
    # descriptors (no compound AND). The role with the highest score wins.
    # Style weights modulate which roles score higher globally.
    print("  Assigning roles...", flush=True)

    sorted_gi = sorted(range(n_total), key=lambda i: all_segs[i][1]["start_sec"])

    role_ids  = np.zeros(n_total, dtype=int)
    state_ids = np.zeros(n_total, dtype=int)
    prom_vals = np.zeros(n_total, dtype=float)

    # Rank-normalise each descriptor to [0,1] so scores are comparable
    def rank_norm(arr):
        order = np.argsort(arr)
        out   = np.empty_like(arr, dtype=float)
        out[order] = np.linspace(0, 1, len(arr))
        return out

    rn_energy  = rank_norm(energy)
    rn_bright  = rank_norm(bright)
    rn_noise   = rank_norm(noisiness)
    rn_stab    = rank_norm(stabil)
    rn_attack  = rank_norm(sharpness)
    rn_hnr     = rank_norm(hnr)
    rn_flux    = rank_norm(flux)
    rn_pitch   = rank_norm(pitch_s)

    # Style multipliers per role  (leader, shadow, resonance, noise_fringe,
    # pulse_carrier, interruption, sustain_bed, contrast_voice, memory_trace, silence)
    STYLE_W = {
        #              ld    sh    re    nf    pc    it    sb    cv    mt    si
        "neutral":  [1.0, 0.6, 0.9, 0.7, 0.9, 0.8, 0.8, 0.9, 0.7, 0.4],
        "dramatic": [1.4, 0.5, 0.7, 0.6, 1.0, 1.3, 0.5, 1.2, 0.5, 0.2],
        "minimal":  [0.8, 0.7, 1.1, 0.5, 0.6, 0.4, 1.2, 0.8, 1.1, 0.8],
        "dense":    [1.0, 0.8, 1.1, 1.0, 1.2, 0.9, 1.0, 1.1, 0.6, 0.1],
    }
    sw = STYLE_W.get(style, STYLE_W["neutral"])

    # Pre-compute per-segment role scores  shape: (n_total, N_ROLES)
    # Each row: [leader, shadow, resonance, noise_fringe, pulse_carrier,
    #            interruption, sustain_bed, contrast_voice, memory_trace, silence]
    scores = np.column_stack([
        rn_energy * 0.7 + rn_bright * 0.3,                        # leader
        (1-rn_energy) * 0.4 + rn_stab * 0.6,                      # shadow
        rn_hnr * 0.5 + rn_stab * 0.3 + (1-rn_noise) * 0.2,       # resonance
        rn_noise * 0.6 + (1-rn_pitch) * 0.4,                      # noise_fringe
        rn_attack * 0.5 + rn_energy * 0.3 + rn_stab * 0.2,        # pulse_carrier
        rn_energy * 0.5 + rn_flux * 0.3 + rn_attack * 0.2,        # interruption
        rn_stab * 0.5 + (1-rn_energy) * 0.3 + (1-rn_flux) * 0.2, # sustain_bed
        rn_bright * 0.5 + rn_pitch * 0.3 + (1-rn_noise) * 0.2,    # contrast_voice
        (1-rn_energy) * 0.5 + rn_stab * 0.3 + (1-rn_flux) * 0.2, # memory_trace
        (1-rn_energy) * 0.8 + (1-rn_flux) * 0.2,                  # silence
    ]) * np.array(sw)  # apply style weights

    # Silence only eligible when allowed
    if not allow_silence:
        scores[:, ROLES.index("silence")] = -1.0

    # First pass: assign best-scoring role to every segment
    role_ids = scores.argmax(axis=1).astype(int)

    # ── 5. Temporal post-pass: enforce conductor rules over time ─────────────
    last_leader_end  = -999.0
    last_file_leader = -1
    memory_energy    = float(np.mean(energy))

    for gi in sorted_gi:
        fi, seg   = all_segs[gi]
        t_norm    = seg["start_sec"] / (max_dur + 1e-9)
        tension   = get_tension(t_norm)
        e         = float(energy[gi])
        s         = float(stabil[gi])
        seg_start = seg["start_sec"]
        seg_end   = seg_start + seg["dur_sec"]

        memory_energy = memory_energy * (1 - memory_weight) + e * memory_weight

        prom = float(np.clip(rn_energy[gi] * (0.4 + 0.6 * tension)
                             + rn_stab[gi] * 0.2, 0, 1))
        prom_vals[gi] = prom

        # State
        e_med = float(np.median(energy))
        if tension > 0.75:
            state = STATES.index("agitated") if e > e_med else STATES.index("saturated")
        elif tension > 0.5:
            state = STATES.index("balanced") if s > 0.5 else STATES.index("saturated")
        elif tension > 0.25:
            state = STATES.index("sparse") if e < e_med else STATES.index("balanced")
        else:
            state = STATES.index("suspended") if s > 0.5 else STATES.index("released")
        state_ids[gi] = state

        # Leader: enforce gap + file alternation
        if ROLES[role_ids[gi]] == "leader":
            gap_needed = 2.0 / (tension + 0.2)
            if seg_start < last_leader_end + gap_needed or fi == last_file_leader:
                # Reassign to second-best non-leader role
                row = scores[gi].copy()
                row[ROLES.index("leader")] = -1.0
                role_ids[gi] = int(row.argmax())
            else:
                last_leader_end  = seg_end
                last_file_leader = fi

        # Nonlinear: sudden high energy after quiet → interruption
        if (nonlinear
                and float(rn_energy[gi]) > 0.80
                and memory_energy < float(np.percentile(energy, 30))
                and tension > 0.4
                and ROLES[role_ids[gi]] not in ["leader", "interruption"]):
            role_ids[gi] = ROLES.index("interruption")

    # ── 6. Post-pass: ensure every file has at least one foreground role ──────
    FOREGROUND = {"leader", "contrast_voice", "interruption", "pulse_carrier"}
    for fi in range(n_files):
        file_gis = [gi for gi in sorted_gi if all_segs[gi][0] == fi]
        if not any(ROLES[role_ids[gi]] in FOREGROUND for gi in file_gis):
            best = max(file_gis, key=lambda g: float(energy[g]))
            role_ids[best] = ROLES.index("leader")
            prom_vals[best] = max(prom_vals[best], 0.65)
            print(f"    File {fi+1}: promoted to leader (no foreground)", flush=True)

    # ── 6. Masking awareness ──────────────────────────────────────────────────
    for gi in sorted_gi:
        if ROLES[role_ids[gi]] in ["silence", "leader", "interruption"]:
            continue
        fi, seg = all_segs[gi]
        st = seg["start_sec"]
        en = st + seg["dur_sec"]
        for gj in sorted_gi:
            if gj == gi or all_segs[gj][0] == fi:
                continue
            fj, segj = all_segs[gj]
            stj = segj["start_sec"]
            enj = stj + segj["dur_sec"]
            overlap = min(en, enj) - max(st, stj)
            if overlap > 0.05:
                cent_diff = abs(centroid[gi] - centroid[gj])
                masking_risk = float(np.exp(-cent_diff * 4)
                                     * (rms[gi] + rms[gj]))
                if masking_risk > 0.55 and prom_vals[gi] < prom_vals[gj]:
                    if ROLES[role_ids[gi]] not in ["sustain_bed", "shadow",
                                                    "memory_trace"]:
                        role_ids[gi] = ROLES.index("shadow")
                        prom_vals[gi] *= 0.65

    # ── 7. Gain table ─────────────────────────────────────────────────────────
    ROLE_GAIN_BASE = {
        "leader":         0.90,
        "shadow":         0.45,
        "resonance":      0.60,
        "noise_fringe":   0.35,
        "pulse_carrier":  0.70,
        "interruption":   0.88,
        "sustain_bed":    0.40,
        "contrast_voice": 0.75,
        "memory_trace":   0.30,
        "silence":        0.00,
    }

    # ── 8. Build plan rows ────────────────────────────────────────────────────
    print("  Assembling mix plan...", flush=True)
    plan_rows = []

    for gi in sorted_gi:
        fi, seg = all_segs[gi]
        role_label  = ROLES[role_ids[gi]]
        state_label = STATES[state_ids[gi]]

        if role_label == "silence":
            continue

        gain_base = ROLE_GAIN_BASE[role_label]
        gain      = gain_base * (0.5 + 0.5 * float(prom_vals[gi]))
        gain      = round(float(np.clip(gain, 0.05, 1.0)), 4)

        entry_time = round(seg["start_sec"], 4)
        exit_time  = round(seg["start_sec"] + seg["dur_sec"], 4)
        transform  = round(float(1.0 - prom_vals[gi]) * 0.4, 3)

        layer = (0 if role_label in ["leader", "interruption", "contrast_voice"]
                 else 1 if role_label in ["pulse_carrier", "resonance", "shadow"]
                 else 2)

        plan_rows.append({
            "time":        entry_time,
            "file_index":  fi + 1,
            "file_name":   file_names[fi],
            "seg_index":   seg["idx"],
            "src_start":   round(seg["start_sec"], 4),
            "src_dur":     round(seg["dur_sec"], 4),
            "gain":        gain,
            "role":        role_label,
            "layer_group": layer,
            "entry_time":  entry_time,
            "exit_time":   exit_time,
            "transform":   transform,
            "state":       state_label,
            "density":     round(gain / 0.9, 3),
            "priority":    round(float(prom_vals[gi]), 4),
        })

    plan_rows.sort(key=lambda r: (r["entry_time"], -r["priority"]))
    print(f"  Plan: {len(plan_rows)} events", flush=True)
    return plan_rows, max_dur


# ─────────────────────────────────────────────────────────────────────────────
# I/O HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def read_manifest(path: str) -> list[dict]:
    entries = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                continue
            entries.append({
                "index":    int(parts[0]),
                "name":     parts[1],
                "wav_path": parts[2],
                "duration": float(parts[3]) if len(parts) > 3 else None,
                "sr":       int(parts[4])   if len(parts) > 4 else None,
                "channels": int(parts[5])   if len(parts) > 5 else None,
            })
    return entries


def write_plan_csv(path: str, rows: list[dict], max_dur: float = 0.0) -> None:
    if not rows:
        return
    fieldnames = [
        "time", "file_index", "file_name", "seg_index",
        "src_start", "src_dur", "gain", "role", "layer_group",
        "entry_time", "exit_time", "transform", "state",
        "density", "priority"
    ]
    with open(path, "w", newline="", encoding="utf-8") as f:
        # First line: max_dur sentinel so Praat uses longest-file duration
        f.write("#max_dur=" + str(round(max_dur, 6)) + "\n")
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="AI Conductor Mix - PyTorch Engine")
    parser.add_argument("manifest_file",    type=str)
    parser.add_argument("descriptor_file",  type=str)
    parser.add_argument("mix_plan_file",    type=str)
    parser.add_argument("done_file",        type=str)
    parser.add_argument("--style",          type=str,  default="dramatic")
    parser.add_argument("--seg_mode",       type=str,  default="onset")
    parser.add_argument("--frame_ms",       type=float, default=80.0)
    parser.add_argument("--hop_ms",         type=float, default=40.0)
    parser.add_argument("--onset_gap_ms",   type=float, default=50.0)
    parser.add_argument("--memory",         type=float, default=0.4)
    parser.add_argument("--tension",        type=float, default=0.6)
    parser.add_argument("--allow_silence",  type=int,   default=1)
    parser.add_argument("--nonlinear",      type=int,   default=1)
    args = parser.parse_args()

    print("=== AI Conductor Mix - PyTorch Engine ===", flush=True)
    print(f"Style: {args.style}  |  Seg: {args.seg_mode}  |  "
          f"Memory: {args.memory:.2f}  |  Tension: {args.tension:.2f}", flush=True)

    # ── Read manifest ─────────────────────────────────────────────────────────
    manifest = read_manifest(args.manifest_file)
    print(f"Ensemble: {len(manifest)} files", flush=True)

    # ── Load audio ────────────────────────────────────────────────────────────
    print("Loading audio...", flush=True)
    file_audios = []
    file_srs    = []
    file_names  = []
    for entry in manifest:
        if not os.path.isfile(entry["wav_path"]):
            print(f"  WARNING: WAV not found: {entry['wav_path']}", flush=True)
            continue
        audio, sr = load_audio_mono(entry["wav_path"])
        file_audios.append(audio)
        file_srs.append(sr)
        file_names.append(entry["name"])
        print(f"  [{entry['index']}] {entry['name']} | "
              f"{len(audio)/sr:.2f}s @ {sr}Hz", flush=True)

    if len(file_audios) < 2:
        print("ERROR: Need at least 2 loadable audio files.", flush=True)
        # Write done sentinel anyway so Praat doesn't hang
        with open(args.done_file, "w") as f:
            f.write("error\n")
        sys.exit(1)

    # ── Run conductor ─────────────────────────────────────────────────────────
    plan, _max_dur = conduct(
        file_audios   = file_audios,
        file_srs      = file_srs,
        file_names    = file_names,
        seg_mode      = args.seg_mode,
        frame_ms      = args.frame_ms,
        hop_ms        = args.hop_ms,
        onset_gap_ms  = args.onset_gap_ms,
        style         = args.style,
        memory_weight = args.memory,
        tension_sens  = args.tension,
        allow_silence = bool(args.allow_silence),
        nonlinear     = bool(args.nonlinear),
    )

    # ── Write plan ────────────────────────────────────────────────────────────
    write_plan_csv(args.mix_plan_file, plan, max_dur=_max_dur)
    print(f"Plan written: {args.mix_plan_file}  ({len(plan)} events)", flush=True)

    # ── Summary ───────────────────────────────────────────────────────────────
    from collections import Counter
    role_counts  = Counter(r["role"]  for r in plan)
    state_counts = Counter(r["state"] for r in plan)
    print("Role distribution:", dict(role_counts), flush=True)
    print("State distribution:", dict(state_counts), flush=True)

    if plan:
        total_dur = max(r["exit_time"] for r in plan)
        print(f"Total conducted duration: {total_dur:.2f}s", flush=True)

    # ── Write done sentinel ───────────────────────────────────────────────────
    with open(args.done_file, "w") as f:
        f.write("ok\n")
    print("OK: conductor done", flush=True)


if __name__ == "__main__":
    main()

# ============================================================
