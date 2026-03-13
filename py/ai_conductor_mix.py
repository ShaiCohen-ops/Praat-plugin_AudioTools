#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - ai_conductor_mix.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.0 (2026) - Python-side rendering (sample-level mix)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Algorithmic Conductor – descriptor-driven ensemble mixer.
#   Receives: manifest (WAV paths), macro descriptors (from Praat).
#   Produces:
#     1. A stereo WAV rendered at sample level (smooth, click-free)
#     2. A tab-delimited mix plan CSV for Praat-side visualisation
#
#   Roles: leader, shadow, resonance, noise_fringe, pulse_carrier,
#          interruption, sustain_bed, contrast_voice, memory_trace,
#          silence
#   States: sparse, balanced, agitated, saturated, suspended, released
#
# Dependencies:
#   pip install numpy soundfile
#   Optional: pip install librosa  (better onset detection)
#
# ============================================================

import argparse
import csv
import math
import os
import sys
from collections import Counter

import numpy as np
import soundfile as sf

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

DESC_DIM = 10


# ─────────────────────────────────────────────────────────────────────────────
# AUDIO ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────

def load_audio_mono(path: str) -> tuple:
    audio, sr = sf.read(path, always_2d=True)
    mono = audio.mean(axis=1).astype(np.float32)
    return mono, sr


def load_audio_stereo(path: str, target_sr: int) -> tuple:
    """Load audio as (left, right) float64 arrays at target_sr."""
    audio, sr = sf.read(path, always_2d=True)
    audio = audio.astype(np.float64)
    if audio.shape[1] == 1:
        left = right = audio[:, 0]
    else:
        left  = audio[:, 0]
        right = audio[:, 1]
    if sr != target_sr and sr > 0:
        ratio = target_sr / sr
        new_len = int(len(left) * ratio)
        idx = np.linspace(0, len(left) - 1, new_len).astype(np.float64)
        idx_floor = idx.astype(int)
        idx_ceil  = np.minimum(idx_floor + 1, len(left) - 1)
        frac = idx - idx_floor
        left  = left[idx_floor] * (1 - frac) + left[idx_ceil] * frac
        right = right[idx_floor] * (1 - frac) + right[idx_ceil] * frac
    return left, right


def segment_fixed(audio, sr, frame_ms, hop_ms):
    frame_n = max(1, int(sr * frame_ms / 1000))
    hop_n   = max(1, int(sr * hop_ms  / 1000))
    segs, t, idx = [], 0, 0
    while t + frame_n <= len(audio):
        segs.append({"start_samp": t, "end_samp": t + frame_n,
                     "start_sec": t / sr, "dur_sec": frame_n / sr, "idx": idx})
        t += hop_n; idx += 1
    return segs


def segment_onset(audio, sr, min_gap_ms):
    if HAS_LIBROSA:
        onsets = librosa.onset.onset_detect(
            y=audio, sr=sr, units="samples", backtrack=True, delta=0.1)
    else:
        hop = int(sr * 0.01)
        n_frames = max(1, (len(audio) - hop) // hop)
        usable = n_frames * hop
        frames = audio[:usable].reshape(n_frames, hop)
        energy = np.sum(frames ** 2, axis=1)
        diff   = np.diff(energy, prepend=energy[0])
        thresh = diff.mean() + diff.std() * 1.5
        onsets = (np.where(diff > thresh)[0] * hop).astype(int)

    min_gap_samp = int(sr * min_gap_ms / 1000)
    filtered, last = [], -min_gap_samp - 1
    for o in onsets:
        if o - last >= min_gap_samp:
            filtered.append(o); last = o
    if not filtered:
        filtered = [0]

    segs = []
    for i, start in enumerate(filtered):
        end = filtered[i + 1] if i + 1 < len(filtered) else len(audio)
        dur = (end - start) / sr
        if dur > 0.01:
            segs.append({"start_samp": start, "end_samp": end,
                         "start_sec": start / sr, "dur_sec": dur, "idx": i})
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
    descs = np.zeros((len(segs), DESC_DIM), dtype=np.float32)
    eps = 1e-12; prev_mag = None

    for i, seg in enumerate(segs):
        chunk = audio[seg["start_samp"]:seg["end_samp"]]
        if len(chunk) < 2:
            continue
        n   = len(chunk)
        win = chunk * np.hanning(n)
        spec  = np.abs(np.fft.rfft(win))
        freqs = np.fft.rfftfreq(n, d=1.0 / sr)

        rms = float(np.sqrt(np.mean(chunk ** 2)))
        zcr = float(np.mean(np.abs(np.diff(np.sign(chunk))) / 2))
        spec_sum = spec.sum() + eps
        centroid = float(np.sum(freqs * spec) / spec_sum)
        bandwidth = float(np.sqrt(np.sum(((freqs - centroid)**2) * spec) / spec_sum))

        if prev_mag is None:
            flux = 0.0
        else:
            ml = min(len(spec), len(prev_mag))
            flux = float(np.sum(np.maximum(spec[:ml] - prev_mag[:ml], 0)))
        prev_mag = spec.copy()

        roughness = float(spec[freqs > 3000].sum() / spec_sum)

        n_fft = 1 << (2 * n - 1).bit_length()
        X = np.fft.rfft(chunk, n=n_fft)
        acorr = np.fft.irfft(X * np.conj(X))[:n]
        lo_lag, hi_lag = max(1, sr // 500), min(n - 1, sr // 50)
        pitch_salience = float(acorr[lo_lag:hi_lag].max() / acorr[0]) \
            if hi_lag > lo_lag and acorr[0] > eps else 0.0

        log_spec = np.log(spec + eps)
        ceps = np.abs(np.fft.irfft(log_spec))
        q_lo, q_hi = max(1, int(sr / 500)), min(len(ceps) - 1, int(sr / 50))
        hnr_proxy = float(ceps[q_lo:q_hi].max() / (np.abs(ceps).mean() + eps)) \
            if q_hi > q_lo and len(ceps) > 10 else 0.0

        attack_n = max(2, n // 5)
        attack_slope = float(
            np.sqrt(np.mean(chunk[:attack_n]**2) + eps) /
            (np.sqrt(np.mean(chunk[attack_n:]**2) + eps) + eps) - 1.0)

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


# ─────────────────────────────────────────────────────────────────────────────
# CONDUCTOR LOGIC
# ─────────────────────────────────────────────────────────────────────────────

def conduct(file_audios, file_srs, file_names, seg_mode, frame_ms, hop_ms,
            onset_gap_ms, style, memory_weight, tension_sens,
            allow_silence, nonlinear):
    n_files = len(file_audios)

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
    flat_descs = np.vstack(all_descs)
    max_dur = max(a.shape[0] / sr for a, sr in zip(file_audios, file_srs))

    # ── 2. Normalise ─────────────────────────────────────────────────────────
    col_min = flat_descs.min(axis=0)
    col_range = flat_descs.max(axis=0) - col_min + 1e-12
    flat_norm = (flat_descs - col_min) / col_range

    rms, flux, centroid = flat_norm[:, 0], flat_norm[:, 4], flat_norm[:, 2]
    rough, pitch_s, hnr = flat_norm[:, 5], flat_norm[:, 6], flat_norm[:, 7]
    attack_arr, stab = flat_norm[:, 8], flat_norm[:, 9]

    energy    = np.clip(rms * 0.6 + flux * 0.4, 0, 1)
    noisiness = np.clip((rough + (1 - pitch_s) + (1 - hnr)) / 3, 0, 1)
    bright, stabil, sharpness = centroid, stab, np.clip(attack_arr, 0, 1)

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
        order = np.argsort(arr)
        out = np.empty_like(arr, dtype=float)
        out[order] = np.linspace(0, 1, len(arr))
        return out

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
    state_ids = np.zeros(n_total, dtype=int)
    prom_vals = np.zeros(n_total, dtype=float)

    # ── 5. Temporal post-pass ────────────────────────────────────────────────
    sorted_gi = sorted(range(n_total), key=lambda i: all_segs[i][1]["start_sec"])
    last_leader_end, last_file_leader = -999.0, -1
    memory_energy = float(np.mean(energy))
    e_med = float(np.median(energy))

    for gi in sorted_gi:
        fi, seg = all_segs[gi]
        t_norm  = seg["start_sec"] / (max_dur + 1e-9)
        tension = get_tension(t_norm)
        e, s    = float(energy[gi]), float(stabil[gi])
        seg_start, seg_end = seg["start_sec"], seg["start_sec"] + seg["dur_sec"]

        memory_energy = memory_energy * (1 - memory_weight) + e * memory_weight
        prom = float(np.clip(rn["energy"][gi] * (0.4 + 0.6*tension) + rn["stab"][gi]*0.2, 0, 1))
        prom_vals[gi] = prom

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
                and memory_energy < float(np.percentile(energy, 20))
                and tension > 0.6
                and ROLES[role_ids[gi]] not in ["leader", "interruption"]):
            role_ids[gi] = ROLES.index("interruption")

    # ── 6a. Foreground guarantee ─────────────────────────────────────────────
    FOREGROUND = {"leader", "contrast_voice", "interruption", "pulse_carrier"}
    for fi in range(n_files):
        file_gis = [gi for gi in sorted_gi if all_segs[gi][0] == fi]
        if not any(ROLES[role_ids[gi]] in FOREGROUND for gi in file_gis):
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
        })

    plan_rows.sort(key=lambda r: (r["entry_time"], -r["priority"]))
    print(f"  Plan: {len(plan_rows)} events", flush=True)
    return plan_rows, max_dur


# ─────────────────────────────────────────────────────────────────────────────
# SAMPLE-LEVEL RENDERER — continuous gain envelope (no segment chopping)
# ─────────────────────────────────────────────────────────────────────────────

def render_mix(plan_rows, file_paths, target_sr, max_dur, result_path):
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
    def fast_smooth(arr, kernel):
        n = len(arr)
        k = len(kernel)
        if n == 0 or k == 0: return arr
        n_fft = 1 << (n + k - 1).bit_length()
        arr_f = np.fft.rfft(arr, n=n_fft)
        ker_f = np.fft.rfft(kernel, n=n_fft)
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

        # Build gain and pan envelopes (per-sample)
        gain_env = np.zeros(n_src, dtype=np.float64)

        rows = file_rows.get(fi, [])
        for row in rows:
            # Use exact sample positions
            src_sr = row["src_sr"]
            if src_sr == target_sr:
                ss = row["src_start_samp"]
                se = row["src_end_samp"]
            else:
                ratio = target_sr / src_sr
                ss = int(round(row["src_start_samp"] * ratio))
                se = int(round(row["src_end_samp"] * ratio))

            ss = max(0, min(ss, n_src))
            se = max(ss, min(se, n_src))

            if se > ss:
                # For overlapping segments from the same file, use max gain
                # (later segments overwrite if higher gain)
                seg_slice = slice(ss, se)
                new_gain = row["gain"]
                # Take the maximum of existing and new gain (avoids dips
                # when segments overlap within the same file)
                gain_env[seg_slice] = np.maximum(gain_env[seg_slice], new_gain)

        # ── Smooth the gain envelope to eliminate step transitions ────
        # Use a Hanning window and FFT convolution for fast, smooth transitions
        if smooth_n > 1 and n_src > smooth_n * 2:
            kernel = np.hanning(smooth_n * 2 + 1)
            kernel /= kernel.sum()
            gain_env = fast_smooth(gain_env, kernel)

        # ── Build per-sample pan L/R envelopes ───────────────────────
        pan_l_env = np.zeros(n_src, dtype=np.float64)
        pan_r_env = np.zeros(n_src, dtype=np.float64)

        for row in rows:
            src_sr = row["src_sr"]
            if src_sr == target_sr:
                ss = row["src_start_samp"]
                se = row["src_end_samp"]
            else:
                ratio = target_sr / src_sr
                ss = int(round(row["src_start_samp"] * ratio))
                se = int(round(row["src_end_samp"] * ratio))
            ss = max(0, min(ss, n_src))
            se = max(ss, min(se, n_src))
            if se <= ss:
                continue

            pan = row["pan"]
            pan_angle = (pan + 1.0) / 2.0 * (math.pi / 2.0)
            pl = math.cos(pan_angle)
            pr = math.sin(pan_angle)
            # Where gain_env > 0, set pan (last writer wins per sample)
            pan_l_env[ss:se] = pl
            pan_r_env[ss:se] = pr

        # ── Smooth pan envelopes too ─────────────────────────────────
        if smooth_n > 1 and n_src > smooth_n * 2:
            pan_l_env = fast_smooth(pan_l_env, kernel)
            pan_r_env = fast_smooth(pan_r_env, kernel)

        # ── Apply envelopes to full file and accumulate ONCE ─────────
        scaled_L = src_L.astype(np.float64) * gain_env * pan_l_env
        scaled_R = src_R.astype(np.float64) * gain_env * pan_r_env

        # Place into output buffer (source position = output position)
        out_len = min(n_src, n_out)
        buf_L[:out_len] += scaled_L[:out_len]
        buf_R[:out_len] += scaled_R[:out_len]

        print(f"      gain range: {gain_env.min():.4f}–{gain_env.max():.4f}  "
              f"active: {np.count_nonzero(gain_env)}/{n_src} samples",
              flush=True)

    # ── Diagnostics ──────────────────────────────────────────────────────
    check_r = max(1, int(0.003 * target_sr))
    all_starts = sorted(set(
        row["src_start_samp"] if row["src_sr"] == target_sr
        else int(round(row["src_start_samp"] * target_sr / row["src_sr"]))
        for row in plan_rows
    ))
    dbg_dips = 0
    for bp in all_starts:
        if bp < check_r or bp + check_r >= len(buf_L):
            continue
        at_bp  = abs(buf_L[bp]) + abs(buf_R[bp])
        before = abs(buf_L[bp - check_r]) + abs(buf_R[bp - check_r])
        after  = abs(buf_L[bp + check_r]) + abs(buf_R[bp + check_r])
        avg = (before + after) / 2.0
        if avg > 1e-6 and at_bp < avg * 0.3:
            dbg_dips += 1
            if dbg_dips <= 5:
                print(f"    DIP at sample {bp} ({bp/target_sr:.4f}s): "
                      f"boundary={at_bp:.6f} vs surround={avg:.6f}",
                      flush=True)
    if dbg_dips > 5:
        print(f"    ... and {dbg_dips - 5} more dips", flush=True)
    if dbg_dips == 0:
        print(f"    No amplitude dips detected", flush=True)

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
    sf.write(result_path, stereo, target_sr, subtype="PCM_16")
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


def write_plan_csv(path, rows, max_dur=0.0):
    if not rows: return
    fld = ["time","file_index","file_name","seg_index","src_start","src_dur",
           "gain","role","layer_group","entry_time","exit_time","transform",
           "state","density","priority","pan"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        f.write(f"#max_dur={round(max_dur,6)}\n")
        w = csv.DictWriter(f, fieldnames=fld, delimiter="\t", extrasaction="ignore")
        w.writeheader(); w.writerows(rows)


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="Algorithmic Conductor v3")
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
    args = ap.parse_args()

    print("=== Algorithmic Conductor Mix v3 ===", flush=True)
    print(f"Style: {args.style} | Seg: {args.seg_mode} | "
          f"Mem: {args.memory:.2f} | Tens: {args.tension:.2f}", flush=True)

    manifest = read_manifest(args.manifest_file)
    print(f"Ensemble: {len(manifest)} files", flush=True)

    print("Loading audio...", flush=True)
    file_audios, file_srs, file_names, file_paths = [], [], [], []
    for entry in manifest:
        if not os.path.isfile(entry["wav_path"]):
            print(f"  WARNING: not found: {entry['wav_path']}", flush=True)
            continue
        audio, sr = load_audio_mono(entry["wav_path"])
        file_audios.append(audio); file_srs.append(sr)
        file_names.append(entry["name"]); file_paths.append(entry["wav_path"])
        print(f"  [{entry['index']}] {entry['name']} | {len(audio)/sr:.2f}s @ {sr}Hz", flush=True)

    if len(file_audios) < 2:
        print("ERROR: Need >=2 audio files.", flush=True)
        with open(args.done_file, "w") as f: f.write("error\n")
        sys.exit(1)

    plan, _max_dur = conduct(
        file_audios, file_srs, file_names, args.seg_mode,
        args.frame_ms, args.hop_ms, args.onset_gap_ms,
        args.style, args.memory, args.tension,
        bool(args.allow_silence), bool(args.nonlinear))

    write_plan_csv(args.mix_plan_file, plan, max_dur=_max_dur)
    print(f"Plan CSV: {args.mix_plan_file} ({len(plan)} events)", flush=True)

    target_sr = max(file_srs)
    result_wav = args.result_wav or args.mix_plan_file.replace(".csv", "_mix.wav")

    actual_dur = render_mix(plan, file_paths, target_sr, _max_dur, result_wav)

    rc = Counter(r["role"] for r in plan)
    sc = Counter(r["state"] for r in plan)
    print(f"Roles: {dict(rc)}", flush=True)
    print(f"States: {dict(sc)}", flush=True)
    print(f"Duration: {actual_dur:.2f}s", flush=True)

    with open(args.done_file, "w") as f: f.write("ok\n")
    print("OK: conductor done", flush=True)


if __name__ == "__main__":
    main()