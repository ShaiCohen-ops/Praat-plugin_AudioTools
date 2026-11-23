#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - rhythmic_imprinting.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Rhythmic Imprinting (RI) - Python engine.
#   Called by Rhythmic_Imprinting.praat.
#
#   Two recordings: A = Rhythm/Gesture Driver, B = Sound Material.
#   Rhythmic Imprinting transfers A's timing and gestural organisation
#   to B's recorded sonic material. Exchanging A and B changes the
#   direction of the imprint and the audible source identity.
#   The engine segments both into whole gestures, describes each
#   gesture by the temporal trajectories of seven descriptors,
#   learns a joint self-supervised embedding of the gestures of BOTH
#   recordings, matches every gesture of A to a gesture of B, and
#   sequences the B gestures (Viterbi) so that neighbouring choices
#   form phrases. It returns a placement plan; Praat cuts the
#   original B audio (all channels, full precision) and assembles it.
#   No audio is transformed here: no stretching, no pitch shifting,
#   no spectral processing. The only amplitude changes are one gain
#   per placed gesture and raised-cosine edge fades.
#
# Pipeline:
#   1. Read the two mono ANALYSIS WAVs written by Praat (highest-RMS
#      channel of each Sound, peak-scaled; analysis only).
#   2. Frame descriptors, 10 ms hop: RMS, spectral centroid, spread,
#      flux, zero-crossing rate, noisiness (spectral flatness) and a
#      low-weight periodicity (window-corrected autocorrelation).
#      No pitch track: periodicity is the only voicing-like channel,
#      so unvoiced material is first-class.
#   3. Adaptive segmentation: hysteresis level gate RELATIVE to each
#      recording's own peak/floor + an onset novelty (positive level
#      slope and spectral flux, robust-z) with a moving-median
#      threshold. Gestures are split at onsets even when no silence
#      separates them; short pieces are merged across the weakest
#      boundary; long ones split at the strongest internal novelty.
#   4. Each gesture -> [T=64, 7] trajectory, PER-SOURCE robust
#      normalisation (so "bright for this voice" and "bright for this
#      cello" become comparable), event-relative envelope channel,
#      duration kept as a separate scalar.
#   5. Representations:
#        Acoustic - 32 handcrafted summary descriptors (mean, sd,
#                   slope, start-to-end change per channel; attack,
#                   peak position, temporal centroid, end level).
#        Joint CNN - the Recomposer v1.2.3 multi-scale 1-D CNN
#                   (k=9 / k=21 -> pool 4 -> k=9 -> mean+max -> dense),
#                   re-implemented BATCHED in NumPy, trained with the
#                   same symmetric NT-Xent loss on events of BOTH
#                   recordings in source-balanced batches with
#                   gesture-preserving augmentations. Embeddings are
#                   source-centred before cross-source comparison.
#        Hybrid   - equal blend of the two (each scaled to its own
#                   90th percentile).
#   6. Diagnostics: representation collapse (effective rank, mean
#      cosine), source-identity bias (cross-validated logistic
#      regression), augmentation retrieval vs an UNTRAINED network,
#      rank agreement with the DTW trajectory distance.
#   7. Matching cost per (A, B) pair:
#        (1-m) * representation + m * DTW trajectory + w * duration
#   8. Sequencing: Viterbi over the top-K candidates of every A
#      gesture with a transition cost that targets a junction /
#      timbral-family distance tau_i = c * (B quantile of A's own
#      transition rank) - continuity at c = 0, contrast where A
#      itself contrasts at c = 1. Source successors (B gesture k
#      followed by k+1) get a phrase bonus. Optional global
#      repetition avoidance by iterated usage penalties.
#   9. Placement: Following keeps every onset of A; Dialogue lets
#      successor chains of B keep B's own inter-onset timing inside
#      an A phrase (bounded drift, re-synchronised at A's phrase
#      boundaries) and adds seeded emission noise (substitutions).
#
# Changelog v1.2 (2026) - second review:
#   - Representation Integrity Check (technical soundness, now including
#     second-seed rank agreement >= 0.50 and validation actually run) is
#     SEPARATE from the Cross-Instrument Correspondence Evaluation (listener
#     anchors). CNN / Hybrid are used only if integrity passes and the anchors
#     do not show them WORSE than Acoustic; the report always states the added
#     value of the learned representation (ESTABLISHED / NOT DETECTED /
#     NEGATIVE / UNDECIDED / NOT EVALUATED).
#   - Strictly balanced batches (k per recording, no replacement).
#   - Held-out split: >= 3 per recording, >= 4 left to train; otherwise
#     VALIDATION INSUFFICIENT fails integrity (v1.1 skipped it silently).
#   - Two caches: features + DTW (method-independent) and CNN training.
#
# Changelog v1.1 (2026) - external review repairs:
#   - Coverage: extension of a short B gesture stops at B's own level gate
#     (v1.0 ran on into B's silence and counted it as covered). Two coverages
#     reported: timeline and sounding.
#   - Reliability gate with automatic Acoustic fallback (collapse, centred
#     source bias > 0.85, or no mean retrieval gain over an untrained network,
#     in-sample and held-out).
#   - 150 training steps (was 500): the same CNN at 150 steps matched the
#     designed classes across recordings better than at 500 (0.99 vs 0.88,
#     synthetic pair, 3 seeds). A CNN-vs-CNN comparison, not CNN vs Acoustic.
#   - training = validated: held-out check (20% of gestures never trained on)
#     and a second-seed stability check.
#   - Cache of analysis + training + DTW (.npz + JSON, no pickle) keyed on the
#     audio bytes and the analysis settings only.
#   - Multichannel analysis from the mean power spectrum of all channels.
#   - Optional listener anchor pairs: external, training-free test of
#     cross-instrument correspondence with a bootstrap interval.
#   - Config values type-coerced (a string "0.9" no longer crashes).
#
# Dependencies: Python 3.8+, numpy, scikit-learn. Nothing else.
# No network, no pretrained weights, no model files written.
# ============================================================

import json
import math
import os
import struct
import sys
import time
import traceback

import numpy as np

VERSION = "1.2"

HOP_S = 0.010            # analysis hop
T_FIXED = 64             # gesture trajectory length (CNN input)
T_DTW = 32               # trajectory length for DTW
N_CH = 7
CH_NAMES = ["envelope", "centroid", "spread", "flux", "zcr", "noisiness", "periodicity"]
TRAJ_W = np.array([2.0, 1.0, 0.75, 1.0, 0.75, 1.0, 0.5], dtype=np.float32)
ENV_FLOOR_DB = 48.0

D_EMB = 32
CNN_STEPS = 150          # measured: this CNN at 150 steps gave better cross-recording class
                         # correspondence than the same CNN at 500 (0.99 vs 0.88, synthetic
                         # pair, 3 seeds) - longer training learns each recording's specifics
CNN_BATCH = 64
CNN_LR = 1e-3
CNN_TAU = 0.3
AUG_SCALE = (0.4, 2.5)
AUG_OFFSET = 1.2

# Sequencing weights (relative to emission costs scaled to their 90th percentile)
SEQ_LAMBDA = {"following": 0.2, "dialogue": 0.3}   # transition (continuity/contrast) weight
SEQ_MU = 0.2                                       # per extra use of the same B gesture
SEQ_REPEAT = 0.6                                   # immediate repeat of the same B gesture

ANCHOR_MIN_PAIRS = 5          # below this the anchor test gives no verdict
SEED_STABILITY_MIN = 0.5      # second-seed distance-rank agreement required by the integrity check

MIN_EVENTS_PER_SOURCE_CNN = 6
MIN_EVENTS_TOTAL_CNN = 20
LIMITED_EVENTS_TOTAL = 60


class RIError(Exception):
    pass


# ─────────────────────────────────────────────────────────────────────────────
# Logging / status
# ─────────────────────────────────────────────────────────────────────────────

_LOG_PATH = ""


def log(msg):
    line = str(msg)
    if _LOG_PATH:
        try:
            with open(_LOG_PATH, "a", encoding="utf-8") as f:
                f.write(line + "\n")
            return
        except Exception:
            pass
    print(line, file=sys.stderr, flush=True)


def write_status(path, text):
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text.strip() + "\n")
    except Exception:
        pass


# ─────────────────────────────────────────────────────────────────────────────
# 1. WAV reading (stdlib only; PCM 8/16/24/32, float 32/64, EXTENSIBLE)
# ─────────────────────────────────────────────────────────────────────────────

def read_wav(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise RIError(f"Not a RIFF/WAVE file: {path}")
    pos, fmt, raw = 12, None, None
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = int.from_bytes(data[pos + 4:pos + 8], "little")
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = body
        elif cid == b"data":
            raw = body
        pos += 8 + size + (size & 1)
    if fmt is None or raw is None:
        raise RIError(f"WAV without fmt/data chunk: {path}")
    tag, nch, sr = struct.unpack("<HHI", fmt[:8])
    bits = struct.unpack("<H", fmt[14:16])[0]
    if tag == 0xFFFE and len(fmt) >= 26:
        tag = struct.unpack("<H", fmt[24:26])[0]
    bps = bits // 8
    if nch < 1 or bps < 1:
        raise RIError(f"Unsupported WAV layout: {path}")
    n = len(raw) // (bps * nch)
    raw = raw[:n * bps * nch]
    if tag == 3 and bits == 32:
        x = np.frombuffer(raw, "<f4").astype(np.float64)
    elif tag == 3 and bits == 64:
        x = np.frombuffer(raw, "<f8").astype(np.float64)
    elif tag == 1 and bits == 16:
        x = np.frombuffer(raw, "<i2").astype(np.float32) / np.float32(32768.0)
    elif tag == 1 and bits == 24:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v >= (1 << 23), v - (1 << 24), v)
        x = v.astype(np.float64) / float(1 << 23)
    elif tag == 1 and bits == 32:
        x = np.frombuffer(raw, "<i4").astype(np.float64) / float(1 << 31)
    elif tag == 1 and bits == 8:
        x = (np.frombuffer(raw, np.uint8).astype(np.float64) - 128.0) / 128.0
    else:
        raise RIError(f"Unsupported WAV encoding (tag {tag}, {bits} bit): {path}")
    x = x.reshape(n, nch)
    x = x[:, 0] if nch == 1 else x                  # multichannel kept for power-sum analysis
    x = np.nan_to_num(x.astype(np.float32, copy=False), nan=0.0, posinf=0.0, neginf=0.0)
    return x.astype(np.float32), int(sr)


# ─────────────────────────────────────────────────────────────────────────────
# 2. Frame descriptors
# ─────────────────────────────────────────────────────────────────────────────

def _smooth(x, w):
    w = int(w)
    if w < 2 or len(x) < 2:
        return np.asarray(x, dtype=np.float64).copy()
    k = np.ones(w) / w
    p = w // 2
    xp = np.pad(np.asarray(x, dtype=np.float64), (p, w - 1 - p), mode="edge")
    return np.convolve(xp, k, mode="valid")


def analyse(x, sr):
    """Frame descriptors on a 10 ms grid. Frame k is centred at k*hop + hop/2.

    Multichannel input [n, C] is analysed from the MEAN POWER SPECTRUM of all
    channels (and mean channel power for RMS): every channel's gestures count,
    and anti-phase material cannot cancel as it would in a sample-domain sum.
    A single channel gives exactly the mono analysis."""
    x = np.asarray(x, np.float32)
    if x.ndim == 1:
        x = x[:, None]
    C = x.shape[1]
    hop = max(1, int(round(HOP_S * sr)))
    n = max(1, int(math.ceil(len(x) / hop)))
    n_fft = 1 << int(round(math.log2(max(256.0, 0.04 * sr))))
    win = np.hanning(n_fft + 2)[1:-1].astype(np.float32)
    pad = n_fft // 2
    centers = np.arange(n) * hop + hop // 2
    sws = []
    for ch in range(C):
        xp = np.zeros(len(x) + 2 * pad + n_fft + hop, np.float32)
        xp[pad:pad + len(x)] = x[:, ch]
        sws.append(np.lib.stride_tricks.sliding_window_view(xp, n_fft))

    freqs = np.fft.rfftfreq(n_fft, 1.0 / sr)
    band = (freqs >= 20) & (freqs <= min(16000.0, sr / 2.0))
    fband = (freqs >= 100) & (freqs <= min(12000.0, sr * 0.45))
    fb = freqs[band].astype(np.float64)
    lag_lo = max(2, int(sr / 1000.0))
    lag_hi = min(int(sr / 60.0), n_fft // 2 - 1)
    w_ac = np.fft.irfft(np.abs(np.fft.rfft(win.astype(np.float64))) ** 2)
    w_ac = w_ac / w_ac[0]
    w_ac_corr = np.maximum(w_ac[:lag_hi + 1], 0.1)
    mag_scale = 1.0 / (np.sum(win) / 2.0)

    cen = np.zeros(n)
    spr = np.zeros(n)
    flux = np.zeros(n)
    flat = np.zeros(n)
    per = np.zeros(n)
    prevL = None
    for c0 in range(0, n, 1024):
        c1 = min(n, c0 + 1024)
        pw = None
        for sw in sws:
            spec = np.fft.rfft(sw[centers[c0:c1]] * win[None, :], axis=1)
            a2 = (spec.real.astype(np.float64) ** 2 + spec.imag.astype(np.float64) ** 2)
            pw = a2 if pw is None else pw + a2
        mag = np.sqrt(pw / C) * mag_scale
        mb = mag[:, band]
        s = mb.sum(axis=1) + 1e-12
        c = (mb * fb[None, :]).sum(axis=1) / s
        cen[c0:c1] = c
        spr[c0:c1] = np.sqrt((mb * (fb[None, :] - c[:, None]) ** 2).sum(axis=1) / s)
        L = 20.0 * np.log10(mb + 1e-4)     # dB spectrum, floor -80 dB re full scale
        if prevL is None:
            prevL = L[:1]
        dL = np.diff(np.vstack([prevL, L]), axis=0)
        flux[c0:c1] = np.maximum(dL, 0.0).mean(axis=1)
        prevL = L[-1:]
        pf = mag[:, fband] ** 2 + 1e-14
        flat[c0:c1] = np.exp(np.mean(np.log(pf), axis=1)) / (np.mean(pf, axis=1) + 1e-14)
        if lag_hi > lag_lo:
            ac = np.fft.irfft(mag ** 2, axis=1)[:, :lag_hi + 1]
            acn = ac / (ac[:, :1] + 1e-14) / w_ac_corr[None, :]
            per[c0:c1] = np.clip(acn[:, lag_lo:lag_hi + 1].max(axis=1), 0.0, 1.0)

    # RMS and ZCR over 20 ms windows, chunked (no whole-signal float64 cumsum:
    # a 10-minute 48 kHz file would otherwise need several 230 MB arrays).
    w = max(2, int(round(0.02 * sr)))
    half = w // 2
    vws = []
    for ch in range(C):
        xr = np.zeros(len(x) + 2 * half + w, np.float32)
        xr[half:half + len(x)] = x[:, ch]
        vws.append(np.lib.stride_tricks.sliding_window_view(xr, w))
    rms = np.zeros(n)
    zcr = np.zeros(n)
    for c0 in range(0, n, 2048):
        pw_sum = 0.0
        z_w = 0.0
        for vw in vws:
            fr = vw[centers[c0:c0 + 2048]].astype(np.float64)
            p_ = np.mean(fr * fr, axis=1)
            sg = fr >= 0
            pw_sum = pw_sum + p_
            z_w = z_w + p_ * np.mean(sg[:, 1:] != sg[:, :-1], axis=1)
        rms[c0:c0 + 2048] = np.sqrt(pw_sum / C)
        zcr[c0:c0 + 2048] = z_w / np.maximum(pw_sum, 1e-20)      # energy-weighted across channels
    db = 20.0 * np.log10(rms + 1e-10)
    feat = {
        "sr": sr, "hop": hop, "hop_s": hop / sr, "n": n, "n_samples": len(x), "channels": C,
        "db": db, "centroid": cen, "spread": spr, "flux": flux,
        "zcr": np.clip(zcr, 0, 1), "flatness": np.clip(flat, 0, 1), "periodicity": per,
    }
    for k in ("db", "centroid", "spread", "flux", "zcr", "flatness", "periodicity"):
        feat[k] = np.nan_to_num(np.asarray(feat[k], dtype=np.float64), nan=0.0,
                                posinf=0.0, neginf=-200.0)
    return feat


# ─────────────────────────────────────────────────────────────────────────────
# 3. Adaptive segmentation
# ─────────────────────────────────────────────────────────────────────────────

def _robust_z(x, mask, floor=1e-9):
    """Robust z. `floor` is an absolute minimum spread: on a pure tone the MAD of
    centroid or periodicity is ~0 and numerical ripple would read as change."""
    v = x[mask] if np.any(mask) else x
    med = float(np.median(v))
    mad = float(np.median(np.abs(v - med))) * 1.4826
    if mad < 1e-9:
        mad = float(np.std(v)) + 1e-9
    return (x - med) / max(mad, floor)


def _moving_median(x, w):
    w = max(3, int(w) | 1)
    p = w // 2
    xp = np.pad(x, (p, p), mode="edge")
    out = np.empty_like(x)
    view = np.lib.stride_tricks.sliding_window_view(xp, w)
    for c0 in range(0, len(x), 8192):
        out[c0:c0 + 8192] = np.median(view[c0:c0 + 8192], axis=1)
    return out


def segment(feat, sens, min_dur, max_dur):
    db = feat["db"]
    n = len(db)
    hop_s = feat["hop_s"]
    info = {"gate_on_db": float("nan"), "peak_db": float("nan"), "floor_db": float("nan"),
            "onsets": 0, "dropped_short": 0, "merged": 0, "split_long": 0,
            "split_flat": 0, "regions": 0, "continuous": False}
    if n < 3:
        return [], np.zeros(n), info
    min_f = max(2, int(round(min_dur / hop_s)))
    max_f = max(min_f + 1, int(round(max_dur / hop_s)))
    peak = float(np.percentile(db, 99.5))
    floor = float(np.percentile(db, 5))
    info["peak_db"], info["floor_db"] = peak, floor
    if peak < -90.0:
        return [], np.zeros(n), info
    span = 30.0 + 25.0 * sens
    on = max(peak - span, floor + 6.0)
    if peak - floor < 10.0:
        on = floor - 1.0          # near-constant level: everything sounds, novelty decides
        info["continuous"] = True
    off = on - 4.0
    info["gate_on_db"] = on

    gate = np.zeros(n, bool)
    state = False
    for k in range(n):
        if state:
            state = db[k] > off
        else:
            state = db[k] > on
        gate[k] = state
    # bridge very short gaps (<60 ms) inside a gesture
    gmax = max(1, int(round(0.06 / hop_s)))
    k = 0
    while k < n:
        if not gate[k]:
            j = k
            while j < n and not gate[j]:
                j += 1
            if 0 < k and j < n and (j - k) <= gmax:
                gate[k:j] = True
            k = j
        else:
            k += 1

    # Onset novelty in PHYSICAL units (a robust z of the level slope is inflated
    # by the recording's own dynamics and missed clear 30 dB attacks):
    #   rise  - dB gained over the minimum of the preceding 60 ms, 20 ms ahead
    #   flux  - positive dB-spectrum change, relative to its 90th percentile
    #   timbre - checkerboard change of robust-z centroid / noisiness /
    #           periodicity / ZCR (+-80 ms), so a legato change of sound
    #           quality without a level rise is still an onset.
    # An onset must be MUSICALLY real: rise >= min_rise OR a timbre change.
    # Without this, the random level fluctuation of stationary noise (breath,
    # flautando) reads as a string of onsets.
    dbs = _smooth(db, 3)
    rise = np.zeros(n)
    for k in range(n):
        rise[k] = max(0.0, dbs[min(n - 1, k + 2)] - dbs[max(0, k - 6):k + 1].min())
    fl = feat["flux"]
    flq = float(np.percentile(fl[gate], 90)) if np.any(gate) else float(np.percentile(fl, 90))
    min_rise = 9.0 - 6.0 * sens
    # floors: 1/4 octave centroid, 0.25 decade flatness, 0.08 periodicity, 0.01 ZCR
    tz = np.stack([_robust_z(np.log2(np.maximum(feat["centroid"], 20.0)), gate, 0.25),
                   _robust_z(np.log10(feat["flatness"] + 1e-5), gate, 0.25),
                   _robust_z(feat["periodicity"], gate, 0.08),
                   _robust_z(feat["zcr"], gate, 0.01)], axis=1)
    tz = np.clip(tz, -4, 4)
    hw = max(3, int(round(0.08 / hop_s)))
    timbre_nov = np.zeros(n)
    csum = np.vstack([np.zeros((1, 4)), np.cumsum(tz, axis=0)])
    for k in range(hw, n - hw):
        before = (csum[k] - csum[k - hw]) / hw
        after = (csum[k + hw] - csum[k]) / hw
        timbre_nov[k] = float(np.linalg.norm(after - before)) / 2.0
    timbre_thr = 1.6 - 0.8 * sens
    nov = _smooth(rise / 6.0 + 0.5 * np.minimum(fl / max(flq, 1e-9), 3.0) + 0.5 * timbre_nov, 3)
    cand = []
    for k in range(1, n - 1):
        if not gate[k]:
            continue
        lo, hi = max(0, k - 4), min(n, k + 5)
        if nov[k] >= nov[lo:hi].max() and nov[k] > nov[k - 1]:
            r = rise[max(0, k - 3):min(n, k + 4)].max()
            tch = timbre_nov[max(0, k - 3):min(n, k + 4)].max()
            if r >= min_rise or tch >= timbre_thr:
                cand.append(k)
    # minimum spacing, strongest first
    acc = []
    for k in sorted(cand, key=lambda q: -nov[q]):
        if all(abs(k - a) >= min_f for a in acc):
            acc.append(k)
    onsets = sorted(acc)
    info["onsets"] = len(onsets)

    regions = []
    k = 0
    while k < n:
        if gate[k]:
            j = k
            while j < n and gate[j]:
                j += 1
            regions.append((k, j))
            k = j
        else:
            k += 1
    info["regions"] = len(regions)

    segs = []
    oi = 0
    for r, (rs, re_) in enumerate(regions):
        cuts = [rs]
        while oi < len(onsets) and onsets[oi] < re_:
            if onsets[oi] > rs + 1:
                cuts.append(onsets[oi])
            oi += 1
        cuts.append(re_)
        for a, b in zip(cuts[:-1], cuts[1:]):
            if b > a:
                segs.append([a, b, r])

    strength = nov.copy()
    # merge too-short pieces across the weaker boundary
    while True:
        short = [i for i, s in enumerate(segs) if s[1] - s[0] < min_f]
        if not short:
            break
        i = min(short, key=lambda q: segs[q][1] - segs[q][0])
        left = i - 1 if i > 0 and segs[i - 1][2] == segs[i][2] and segs[i - 1][1] == segs[i][0] else None
        right = i + 1 if i + 1 < len(segs) and segs[i + 1][2] == segs[i][2] and segs[i + 1][0] == segs[i][1] else None
        if left is None and right is None:
            segs.pop(i)
            info["dropped_short"] += 1
            continue
        if right is None or (left is not None and strength[segs[i][0]] <= strength[segs[i + 1][0]]):
            segs[left][1] = segs[i][1]
            segs.pop(i)
        else:
            segs[i][1] = segs[right][1]
            segs.pop(right)
        info["merged"] += 1

    # Repeated articulations (tremolo, trill, flutter, bow-stroke chains): three
    # or more contiguous short pieces with steady durations and the same timbre
    # are ONE gesture with internal movement, not separate gestures. Kept
    # separable at very high sensitivity.
    if sens <= 0.85 and len(segs) >= 2:
        # (a) crescendo lead-in: the gate opened on the quiet start of a swell and
        #     the "onset" fired part-way up. Short, rising, >= 12 dB below the
        #     piece it leads into, contiguous -> one gesture.
        i = 0
        while i + 1 < len(segs):
            s, e, r = segs[i]
            s2, e2, r2 = segs[i + 1]
            if r2 == r and s2 == e and (e - s) * hop_s < 0.25:
                pk1, pk2 = db[s:e].max(), db[s2:e2].max()
                q = max(1, (e - s) // 3)
                rising = db[e - q:e].mean() > db[s:s + q].mean() + 3.0
                if pk1 < pk2 - 12.0 and rising:
                    segs[i][1] = e2
                    segs.pop(i + 1)
                    info["merged"] += 1
                    info["lead_ins"] = info.get("lead_ins", 0) + 1
                    continue
            i += 1
        # (b) repeated articulation runs
        if len(segs) >= 3:
            tm = np.array([tz[s:e].mean(axis=0) for s, e, _ in segs])
            pk = np.array([db[s:e].max() for s, e, _ in segs])
            merged_runs = []
            i = 0
            while i < len(segs):
                j = i
                while (j + 1 < len(segs) and segs[j + 1][2] == segs[j][2] and segs[j + 1][0] == segs[j][1]
                       and (segs[j + 1][1] - segs[j + 1][0]) * hop_s < 0.4
                       and (segs[j][1] - segs[j][0]) * hop_s < 0.4
                       and abs(pk[j + 1] - pk[j]) < 6.0
                       and np.linalg.norm(tm[j + 1] - tm[j]) / 2.0 < 0.8):
                    j += 1
                if j - i + 1 >= 3:
                    durs = np.array([segs[q][1] - segs[q][0] for q in range(i, j + 1)], float)
                    if np.std(durs) / max(np.mean(durs), 1e-9) < 0.6:
                        merged_runs.append((i, j))
                        i = j + 1
                        continue
                i += 1
            for i, j in reversed(merged_runs):
                segs[i][1] = segs[j][1]
                del segs[i + 1:j + 1]
                info["merged"] += j - i
                info["repeat_runs"] = info.get("repeat_runs", 0) + 1

    # split too-long pieces at the strongest internal novelty
    out = []
    flat_thr = min_rise / 6.0
    for s, e, r in segs:
        while e - s > max_f:
            lo = s + min_f
            hi = min(s + max_f, e - min_f)
            if hi > lo:
                cut = lo + int(np.argmax(nov[lo:hi + 1]))
                if nov[cut] < flat_thr:
                    info["split_flat"] += 1
            else:
                cut = s + max_f
                info["split_flat"] += 1
            out.append((s, cut))
            info["split_long"] += 1
            s = cut
        out.append((s, e))
    info["gate"] = gate
    return out, nov, info


# ─────────────────────────────────────────────────────────────────────────────
# 4. Gesture trajectories
# ─────────────────────────────────────────────────────────────────────────────

def _resample_rows(M, T):
    """M [n, F] -> [T, F] by linear interpolation on normalised time."""
    n = M.shape[0]
    if n == 1:
        return np.repeat(M, T, axis=0)
    pos = np.linspace(0.0, n - 1.0, T)
    lo = np.floor(pos).astype(int)
    hi = np.minimum(lo + 1, n - 1)
    fr = (pos - lo)[:, None]
    return M[lo] * (1 - fr) + M[hi] * fr


def build_events(feat, segs, name):
    """Return dict with per-event raw trajectories and metadata (before normalisation)."""
    db = feat["db"]
    hop_s = feat["hop_s"]
    raw = []
    meta = []
    for s, e in segs:
        d = db[s:e]
        pk = float(d.max())
        env = np.clip(d - pk, -ENV_FLOOR_DB, 0.0)
        valid = d > pk - 45.0
        idx = np.arange(e - s)
        chans = [(env + ENV_FLOOR_DB) / ENV_FLOOR_DB]
        for key, fn in (("centroid", lambda v: np.log2(np.maximum(v, 20.0))),
                        ("spread", lambda v: np.log2(v + 50.0)),
                        ("flux", lambda v: v),
                        ("zcr", lambda v: v),
                        ("flatness", lambda v: np.log10(v + 1e-5)),
                        ("periodicity", lambda v: v)):
            v = fn(feat[key][s:e])
            if not np.all(valid):
                v = np.interp(idx, idx[valid], v[valid])
            chans.append(v)
        M = np.stack(chans, axis=1)
        raw.append(M)
        p = 10 ** (d / 10.0)
        meta.append({
            "src": name, "s": int(s), "e": int(e),
            "start": s * hop_s, "end": e * hop_s, "dur": (e - s) * hop_s,
            "level_db": float(10 * np.log10(np.mean(p) + 1e-20)),
            "peak_db": pk,
        })
    return raw, meta


def source_normalise(raw):
    """Per-source robust z of channels 1..6 over all event frames; channel 0 rescaled."""
    if not raw:
        return [], None
    allf = np.vstack(raw)
    med = np.median(allf, axis=0)
    iqr = np.percentile(allf, 75, axis=0) - np.percentile(allf, 25, axis=0)
    sd = iqr / 1.349
    sd = np.where(sd < 1e-6, np.std(allf, axis=0) + 1e-6, sd)
    out = []
    for M in raw:
        Z = M.copy()
        Z[:, 1:] = (M[:, 1:] - med[1:]) / sd[1:]
        Z[:, 0] = (M[:, 0] - 0.5) * 2.5
        out.append(np.clip(Z, -4.0, 4.0))
    return out, (med, sd)


def to_tensor(trajs, T):
    X = np.zeros((len(trajs), T, N_CH), np.float32)
    for i, M in enumerate(trajs):
        X[i] = _resample_rows(M, T)
    return np.nan_to_num(X)


# ─────────────────────────────────────────────────────────────────────────────
# 5a. Acoustic (handcrafted) baseline descriptors
# ─────────────────────────────────────────────────────────────────────────────

def summary_descriptors(X):
    N, T, F = X.shape
    t = np.linspace(-0.5, 0.5, T)
    q = max(1, T // 4)
    mean = X.mean(axis=1)
    sd = X.std(axis=1)
    slope = (X * t[None, :, None]).sum(axis=1) / (t ** 2).sum()
    delta = X[:, -q:, :].mean(axis=1) - X[:, :q, :].mean(axis=1)
    envdb = (X[:, :, 0] / 2.5 + 0.5) * ENV_FLOOR_DB - ENV_FLOOR_DB
    t01 = np.linspace(0, 1, T)
    peak_pos = np.argmax(envdb, axis=1) / (T - 1)
    above = envdb >= -3.0
    attack = np.argmax(above, axis=1) / (T - 1)
    p = 10 ** (envdb / 10.0)
    tcent = (p * t01[None, :]).sum(axis=1) / (p.sum(axis=1) + 1e-12)
    endlev = envdb[:, -q:].mean(axis=1) / ENV_FLOOR_DB
    extra = np.stack([peak_pos, attack, tcent, endlev], axis=1)
    return np.concatenate([mean, sd, slope, delta, extra], axis=1).astype(np.float64)


def standardise_cols(S):
    mu = S.mean(axis=0)
    sd = S.std(axis=0)
    sd = np.where(sd < 1e-9, 1.0, sd)
    return (S - mu) / sd, mu, sd


# ─────────────────────────────────────────────────────────────────────────────
# 5b. Batched NumPy CNN (architecture of recomposer.py v1.2.3)
# ─────────────────────────────────────────────────────────────────────────────

def _conv_fwd(x, W, b):
    B, T, C = x.shape
    k, _, Co = W.shape
    p = k // 2
    xp = np.pad(x, ((0, 0), (p, p), (0, 0)), mode="edge")
    col = np.lib.stride_tricks.sliding_window_view(xp, k, axis=1)      # [B,T,C,k]
    col = np.ascontiguousarray(col.transpose(0, 1, 3, 2)).reshape(B, T, k * C)
    Wf = W.reshape(k * C, Co)
    return col @ Wf + b, (col, Wf, k, p, C)


def _conv_bwd(dout, cache, need_dx=True):
    col, Wf, k, p, C = cache
    B, T, Co = dout.shape
    dW = (col.reshape(-1, k * C).T @ dout.reshape(-1, Co)).reshape(k, C, Co)
    db = dout.sum(axis=(0, 1))
    if not need_dx:
        return None, dW, db
    dcol = (dout @ Wf.T).reshape(B, T, k, C)
    dxp = np.zeros((B, T + 2 * p, C), dout.dtype)
    for j in range(k):
        dxp[:, j:j + T, :] += dcol[:, :, j, :]
    dx = dxp[:, p:p + T, :].copy()
    if p > 0:   # forward used edge padding: padded gradients belong to the edge samples
        dx[:, 0, :] += dxp[:, :p, :].sum(axis=1)
        dx[:, -1, :] += dxp[:, p + T:, :].sum(axis=1)
    return dx, dW, db


def _pool_fwd(x, s):
    B, T, C = x.shape
    To = T // s
    xc = x[:, :To * s].reshape(B, To, s, C)
    out = xc.max(axis=2)
    mask = xc == out[:, :, None, :]
    return out, (mask, s, T)


def _pool_bwd(dout, cache):
    mask, s, T = cache
    cnt = np.maximum(mask.sum(axis=2, keepdims=True), 1)
    d = dout[:, :, None, :] * mask / cnt
    B, To, _, C = d.shape
    dx = d.reshape(B, To * s, C)
    if dx.shape[1] < T:
        dx = np.pad(dx, ((0, 0), (0, T - dx.shape[1]), (0, 0)))
    return dx


class BatchCNN:
    """Branch A conv k=9 (F->8), branch B conv k=21 (F->8), concat 16,
    max-pool 4, conv k=9 (16->16), global mean+max (32), dense 32->D."""

    def __init__(self, F, seed):
        rng = np.random.default_rng(seed)

        def he(shape, fan):
            return (rng.standard_normal(shape) * math.sqrt(2.0 / fan)).astype(np.float32)

        self.p = {
            "WA": he((9, F, 8), 9 * F), "bA": np.zeros(8, np.float32),
            "WB": he((21, F, 8), 21 * F), "bB": np.zeros(8, np.float32),
            "W2": he((9, 16, 16), 9 * 16), "b2": np.zeros(16, np.float32),
            "Wd": he((32, D_EMB), 32), "bd": np.zeros(D_EMB, np.float32),
        }
        self.m = {k: np.zeros_like(v) for k, v in self.p.items()}
        self.v = {k: np.zeros_like(v) for k, v in self.p.items()}
        self.t = 0
        self.valid = False

    def forward(self, x):
        P = self.p
        a_pre, ca = _conv_fwd(x, P["WA"], P["bA"])
        b_pre, cb = _conv_fwd(x, P["WB"], P["bB"])
        a = np.maximum(a_pre, 0)
        b = np.maximum(b_pre, 0)
        cat = np.concatenate([a, b], axis=2)
        pool, pc = _pool_fwd(cat, 4)
        c2_pre, c2c = _conv_fwd(pool, P["W2"], P["b2"])
        c2 = np.maximum(c2_pre, 0)
        mx = c2.max(axis=1)
        gp = np.concatenate([c2.mean(axis=1), mx], axis=1)
        emb = gp @ P["Wd"] + P["bd"]
        cache = (a_pre, ca, b_pre, cb, pc, c2_pre, c2c, c2, mx, gp)
        return emb, cache

    def backward(self, demb, cache):
        P = self.p
        a_pre, ca, b_pre, cb, pc, c2_pre, c2c, c2, mx, gp = cache
        g = {}
        g["Wd"] = gp.T @ demb
        g["bd"] = demb.sum(axis=0)
        dgp = demb @ P["Wd"].T
        C = c2.shape[2]
        Tp = c2.shape[1]
        ismax = (c2 == mx[:, None, :])
        cnt = np.maximum(ismax.sum(axis=1, keepdims=True), 1)
        dc2 = dgp[:, None, :C] / Tp + ismax * dgp[:, None, C:] / cnt
        dc2 = dc2 * (c2_pre > 0)
        dpool, g["W2"], g["b2"] = _conv_bwd(dc2, c2c, need_dx=True)
        dcat = _pool_bwd(dpool, pc)
        da = dcat[:, :, :8] * (a_pre > 0)
        dbb = dcat[:, :, 8:] * (b_pre > 0)
        _, g["WA"], g["bA"] = _conv_bwd(da, ca, need_dx=False)
        _, g["WB"], g["bB"] = _conv_bwd(dbb, cb, need_dx=False)
        return g

    def adam(self, g, lr, b1=0.9, b2=0.999, eps=1e-8):
        self.t += 1
        for k in self.p:
            gk = g[k].astype(np.float32)
            self.m[k] = b1 * self.m[k] + (1 - b1) * gk
            self.v[k] = b2 * self.v[k] + (1 - b2) * gk * gk
            mh = self.m[k] / (1 - b1 ** self.t)
            vh = self.v[k] / (1 - b2 ** self.t)
            self.p[k] = (self.p[k] - lr * mh / (np.sqrt(vh) + eps)).astype(np.float32)

    def embed(self, X):
        out = np.zeros((len(X), D_EMB), np.float32)
        for c0 in range(0, len(X), 256):
            out[c0:c0 + 256] = self.forward(X[c0:c0 + 256].astype(np.float32))[0]
        return out


def l2n(E):
    return E / np.maximum(np.linalg.norm(E, axis=1, keepdims=True), 1e-8)


def nt_xent(Ea_raw, Ep_raw, tau=CNN_TAU):
    """Symmetric NT-Xent (as recomposer.py), returning grads w.r.t. raw embeddings."""
    B = Ea_raw.shape[0]
    Ea, Ep = l2n(Ea_raw), l2n(Ep_raw)

    def one(Q, K):
        S = Q @ K.T / tau
        S = S - S.max(axis=1, keepdims=True)
        ex = np.exp(S)
        den = ex.sum(axis=1, keepdims=True)
        loss = -(S[np.arange(B), np.arange(B)] - np.log(den[:, 0])).mean()
        dS = ex / den
        dS[np.arange(B), np.arange(B)] -= 1.0
        dS /= (B * tau)
        return loss, dS @ K, dS.T @ Q

    l1, dQa, dKp = one(Ea, Ep)
    l2, dQp, dKa = one(Ep, Ea)
    dEa = 0.5 * (dQa + dKa)
    dEp = 0.5 * (dKp + dQp)

    def back(dn, raw):
        nr = np.maximum(np.linalg.norm(raw, axis=1, keepdims=True), 1e-8)
        en = raw / nr
        return (dn - (dn * en).sum(axis=1, keepdims=True) * en) / nr

    return 0.5 * (l1 + l2), back(dEa, Ea_raw), back(dEp, Ep_raw)


def augment(Xb, rng, scale=None, offset=None):
    """Gesture-preserving views: small end-crops, gentle monotonic time warp,
    strong per-channel scale/offset jitter, light noise, 5% frame dropout
    (bridged by neighbours). No reversal, no channel shuffling, no large time
    shifts: the order of onset, growth, turning points and decay is kept."""
    B, T, F = Xb.shape
    t = np.linspace(0.0, 1.0, T)
    c0 = rng.uniform(0.0, 0.06, (B, 1))
    c1 = 1.0 - rng.uniform(0.0, 0.06, (B, 1))
    amp = rng.uniform(-0.045, 0.045, (B, 1))
    fr = rng.uniform(0.5, 1.5, (B, 1))
    tw = t[None, :] + amp * np.sin(np.pi * fr * t[None, :])
    tw = np.clip(c0 + (c1 - c0) * np.clip(tw, 0, 1), 0, 1)
    pos = tw * (T - 1)
    lo = np.floor(pos).astype(int)
    hi = np.minimum(lo + 1, T - 1)
    w = (pos - lo)[:, :, None]
    X = np.take_along_axis(Xb, lo[:, :, None], axis=1) * (1 - w) + \
        np.take_along_axis(Xb, hi[:, :, None], axis=1) * w
    # Strong per-channel affine jitter: the temporal SHAPE of every channel is
    # kept, its absolute value and excursion are not. Measured on the synthetic
    # voice/cello pair (3 seeds): cross-recording class correspondence 0.31 with
    # mild jitter (x0.85-1.15, +-0.15), 0.80 at x0.5-1.8 / +-0.8, 0.83 here,
    # 0.90 at x0.3-3.0 / +-2.0 where within-recording separation began to drop.
    mu = X.mean(axis=1, keepdims=True)
    sc = AUG_SCALE if scale is None else scale
    of = AUG_OFFSET if offset is None else offset
    X = mu + (X - mu) * rng.uniform(sc[0], sc[1], (B, 1, F))
    X = X + rng.uniform(-of, of, (B, 1, F))
    X = X + rng.normal(0.0, 0.05, X.shape)
    drop = rng.random((B, T)) < 0.05
    if np.any(drop):
        prv = np.concatenate([X[:, :1], X[:, :-1]], axis=1)
        nxt = np.concatenate([X[:, 1:], X[:, -1:]], axis=1)
        X = np.where(drop[:, :, None], 0.5 * (prv + nxt), X)
    return X.astype(np.float32)


def train_cnn(X, src, seed, steps=CNN_STEPS):
    cnn = BatchCNN(X.shape[2], seed)
    init = {k: v.copy() for k, v in cnn.p.items()}
    rng = np.random.default_rng(seed + 1)
    vrng = np.random.default_rng(seed + 2)
    ia = np.where(src == 0)[0]
    ib = np.where(src == 1)[0]
    # Strictly balanced batches: k gestures from EACH recording, without
    # replacement (a duplicate inside an NT-Xent batch is its own false
    # negative). v1.1 filled the rest of the batch from the larger recording,
    # e.g. 6 A + 58 B when A had 6 gestures and B 100.
    k = max(2, min(CNN_BATCH // 2, len(ia), len(ib)))
    cnn.batch_k = k
    # fixed validation views: deterministic checkpoint selection
    vidx = np.concatenate([vrng.choice(ia, k, replace=False), vrng.choice(ib, k, replace=False)])
    va, vp = augment(X[vidx], vrng), augment(X[vidx], vrng)
    best = float("inf")
    best_p = {k: v.copy() for k, v in cnn.p.items()}
    hist = []
    diverged = False
    t0 = time.time()
    for step in range(steps):
        batch = np.concatenate([rng.choice(ia, k, replace=False), rng.choice(ib, k, replace=False)])
        xa, xp = augment(X[batch], rng), augment(X[batch], rng)
        Ea, ca = cnn.forward(xa)
        Ep, cp = cnn.forward(xp)
        loss, dEa, dEp = nt_xent(Ea, Ep)
        if not np.isfinite(loss) or loss > 1e4:
            diverged = True
            break
        ga = cnn.backward(dEa, ca)
        gp = cnn.backward(dEp, cp)
        g = {k: ga[k] + gp[k] for k in ga}
        lr = CNN_LR * (0.1 + 0.9 * 0.5 * (1 + math.cos(math.pi * step / steps)))
        cnn.adam(g, lr)
        if step % 20 == 19 or step == steps - 1:
            vl = nt_xent(cnn.forward(va)[0], cnn.forward(vp)[0])[0]
            hist.append((step + 1, float(loss), float(vl)))
            if np.isfinite(vl) and vl < best:
                best = vl
                best_p = {k: v.copy() for k, v in cnn.p.items()}
    if diverged:
        cnn.p = init
        cnn.valid = False
    else:
        cnn.p = best_p
        cnn.valid = True
    cnn.history = hist
    cnn.best_val = best
    cnn.train_seconds = time.time() - t0
    return cnn


# ─────────────────────────────────────────────────────────────────────────────
# 6. Representation diagnostics
# ─────────────────────────────────────────────────────────────────────────────

def collapse_stats(E):
    U = l2n(E.astype(np.float64))
    n = len(U)
    G = U @ U.T
    mean_cos = float((G.sum() - n) / max(1, n * (n - 1)))
    s = np.linalg.svd(U - U.mean(axis=0), compute_uv=False)
    p = s ** 2 / max(1e-12, float((s ** 2).sum()))
    p = p[p > 1e-12]
    eff_rank = float(np.exp(-(p * np.log(p)).sum())) if len(p) else 0.0
    return mean_cos, eff_rank


def source_bias(Z, src, seed):
    """Balanced accuracy of predicting the source recording from a representation."""
    try:
        from sklearn.linear_model import LogisticRegression
        from sklearn.model_selection import StratifiedKFold, cross_val_score
    except Exception:
        return float("nan")
    n_min = int(min((src == 0).sum(), (src == 1).sum()))
    if n_min < 3:
        return float("nan")
    k = min(5, n_min)
    try:
        cv = StratifiedKFold(n_splits=k, shuffle=True, random_state=seed)
        clf = LogisticRegression(max_iter=2000, C=1.0)
        sc = cross_val_score(clf, Z, src, cv=cv, scoring="balanced_accuracy")
        return float(np.mean(sc))
    except Exception:
        return float("nan")


def retrieval_top1(R_orig, R_aug):
    A = l2n(R_orig.astype(np.float64))
    B = l2n(R_aug.astype(np.float64))
    nn = np.argmax(B @ A.T, axis=1)
    return float(np.mean(nn == np.arange(len(A))))


def _ranks(x):
    r = np.empty(len(x))
    r[np.argsort(x, kind="mergesort")] = np.arange(len(x))
    return r


def spearman(a, b):
    a = np.asarray(a, float).ravel()
    b = np.asarray(b, float).ravel()
    if len(a) < 3 or np.std(a) < 1e-12 or np.std(b) < 1e-12:
        return float("nan")
    return float(np.corrcoef(_ranks(a), _ranks(b))[0, 1])


# ─────────────────────────────────────────────────────────────────────────────
# 7. Distances
# ─────────────────────────────────────────────────────────────────────────────

def scale90(M):
    v = M[np.isfinite(M)]
    q = float(np.percentile(v, 90)) if v.size else 1.0
    return M / max(q, 1e-9)


def euclid(P, Q):
    d2 = (P ** 2).sum(1)[:, None] + (Q ** 2).sum(1)[None, :] - 2 * P @ Q.T
    return np.sqrt(np.maximum(d2, 0.0))


def cosine_dist(P, Q):
    return np.clip(1.0 - l2n(P) @ l2n(Q).T, 0.0, 2.0)


def lockstep(XA, XB):
    w = TRAJ_W / TRAJ_W.sum()
    out = np.zeros((len(XA), len(XB)), np.float64)
    for i in range(len(XA)):
        d = (XB - XA[i][None]) ** 2
        out[i] = np.sqrt((d * w).sum(axis=2)).mean(axis=1)
    return out


def dtw_pairs(XA, XB, pairs, band):
    """Symmetric (diagonal weight 2) Sakoe-Chiba DTW, normalised by 2T.
    The diagonal path gives exactly the lockstep distance, so DTW <= lockstep."""
    w = (TRAJ_W / TRAJ_W.sum()).astype(np.float32)
    T = XA.shape[1]
    res = np.zeros(len(pairs), np.float64)
    INF = np.float32(1e9)
    for c0 in range(0, len(pairs), 512):
        pr = pairs[c0:c0 + 512]
        A = XA[pr[:, 0]]
        B = XB[pr[:, 1]]
        C = np.sqrt((((A[:, :, None, :] - B[:, None, :, :]) ** 2) * w).sum(-1))
        P = len(pr)
        D = np.full((P, T + 1, T + 1), INF, np.float32)
        D[:, 0, 0] = 0
        for i in range(1, T + 1):
            for j in range(max(1, i - band), min(T, i + band) + 1):
                c = C[:, i - 1, j - 1]
                D[:, i, j] = np.minimum(np.minimum(D[:, i - 1, j - 1] + 2 * c, D[:, i - 1, j] + c),
                                        D[:, i, j - 1] + c)
        res[c0:c0 + P] = D[:, T, T] / (2.0 * T)
    return res


def duration_dist(dA, dB):
    return np.minimum(1.0, np.abs(np.log(dA[:, None] / dB[None, :])) / math.log(4.0))


# ─────────────────────────────────────────────────────────────────────────────
# 8. Sequencing
# ─────────────────────────────────────────────────────────────────────────────

def viterbi(em, K, trans_fn):
    """em [N, M] full emission matrix; candidates = K lowest per row."""
    N, M = em.shape
    K = min(K, M)
    cand = np.argsort(em, axis=1, kind="mergesort")[:, :K]
    ec = np.take_along_axis(em, cand, axis=1)
    cost = ec[0].copy()
    back = np.zeros((N, K), int)
    for i in range(1, N):
        Tm = trans_fn(i, cand[i - 1], cand[i])
        tot = cost[:, None] + Tm
        back[i] = np.argmin(tot, axis=0)
        cost = tot[back[i], np.arange(K)] + ec[i]
    path = np.zeros(N, int)
    path[-1] = int(np.argmin(cost))
    for i in range(N - 1, 0, -1):
        path[i - 1] = back[i, path[i]]
    return cand[np.arange(N), path]


def plan_sequence(em_raw, ctx, P, rng):
    """Return chosen B index per A event plus per-step diagnostics."""
    nA, nB = em_raw.shape
    dialogue = P["mode"] == "dialogue"
    c = P["contrast"]
    K = 24 if dialogue else 12
    lam = SEQ_LAMBDA["dialogue" if dialogue else "following"]
    succ_f = 0.25 if dialogue else 0.5
    rep_pen = SEQ_REPEAT if P["avoid_rep"] else 0.15
    mu = SEQ_MU if P["avoid_rep"] else 0.0

    em = em_raw.copy()
    if dialogue:
        u = np.clip(rng.random(em.shape), 1e-12, 1 - 1e-12)
        em = em + (0.10 + 0.15 * c) * (-np.log(-np.log(u)))

    Dtr = ctx["DtrB"]
    contig = ctx["contigB"]
    tau = ctx["tau"]
    lam_i = ctx["lam_scale"]

    def trans(i, prev, cur):
        D = Dtr[np.ix_(prev, cur)].copy()
        succ = (cur[None, :] == prev[:, None] + 1) & contig[prev][:, None]
        D = np.where(succ, D * succ_f, D)
        cost = lam * lam_i[i - 1] * np.abs(D - c * tau[i - 1])
        cost = cost + np.where(cur[None, :] == prev[:, None], rep_pen, 0.0)
        return cost

    def total(p):
        c_ = float(em[np.arange(nA), p].sum())
        for i in range(1, nA):
            c_ += float(trans(i, p[i - 1:i], p[i:i + 1])[0, 0])
        use = np.bincount(p, minlength=nB)
        return c_ + mu * float(np.maximum(use - 1, 0).sum())

    path = viterbi(em, K, trans)
    if mu > 0:
        # Global repetition avoidance. Viterbi cannot see reuse across the whole
        # sequence, so over-used B gestures get an ACCUMULATING surcharge and the
        # path with the lowest true total (matching + transitions + mu per extra
        # use) is kept. (Penalising only the latest path's usage oscillates.)
        # A B gesture used more than `cap` times keeps the A gestures that need
        # it most (largest loss if moved to their next-best choice); only the
        # other (A, B) cells are surcharged, and the surcharge accumulates. A
        # uniform per-B penalty instead makes every A gesture flock to the same
        # next-best B gesture (measured: max reuse 3 -> 12 over six rounds).
        cap = max(1, int(math.ceil(nA / nB)))
        best_p, best_c = path, total(path)
        pen = np.zeros_like(em)
        srt = np.sort(em, axis=1)
        for _ in range(8):
            use = np.bincount(path, minlength=nB)
            over = np.where(use > cap)[0]
            if len(over) == 0:
                break
            for b in over:
                rows = np.where(path == b)[0]
                second = np.where(srt[rows, 0] < em[rows, b] - 1e-12, srt[rows, 0], srt[rows, 1])
                regret = second - em[rows, b]
                keep = rows[np.argsort(-regret)[:cap]]
                move = np.setdiff1d(rows, keep)
                pen[move, b] += mu
            path = viterbi(em + pen, K, trans)
            c_ = total(path)
            if c_ < best_c - 1e-12:
                best_p, best_c = path, c_
        path = best_p
    best_raw = np.argmin(em_raw, axis=1)
    subst = path != best_raw
    return path, subst


# ─────────────────────────────────────────────────────────────────────────────
# 9. Placement
# ─────────────────────────────────────────────────────────────────────────────

def place(path, evA, evB, ctx, P):
    srB = P["sr_b"]
    nBs = P["n_samples_b"]
    xf = P["xfade_s"]
    flex = P["flex"]
    dialogue = P["mode"] == "dialogue"
    pre = min(0.025, 0.75 * xf)
    dyn = 0.7 if dialogue else 1.0
    relA = np.array([e["level_db"] for e in evA]) - max(e["level_db"] for e in evA)
    relB = np.array([e["level_db"] for e in evB]) - max(e["level_db"] for e in evB)
    phrase_start = ctx["phrase_start"]
    phrase_len = ctx["phrase_len"]
    contig = ctx["contigB"]
    rows = []
    drift = 0.0
    prev_out = None
    for i, j in enumerate(path):
        a, b = evA[i], evB[j]
        target = a["dur"]
        slot = (evA[i + 1]["start"] - a["start"]) if i + 1 < len(evA) else a["dur"] + 0.5
        L = b["dur"]
        extended = 0
        fill_ratio = 0.5 if dialogue else 0.8
        if L < fill_ratio * target:
            Lx = min(target if not dialogue else 0.8 * target, b["dur"] * (1.0 + 2.0 * flex))
            Lx = min(Lx, nBs / srB - b["start"])
            # Never extend into B's silence: stop at the first frame after the
            # gesture where B's own level gate is closed. (v1.0 extended freely
            # and counted the silence as covered material.)
            Lx = min(Lx, ctx["soundB_end"][j] - b["start"])
            if Lx > L + 1e-3:
                L, extended = Lx, 1
        # timing
        successor = int(i > 0 and j == path[i - 1] + 1 and contig[path[i - 1]])
        if dialogue:
            if phrase_start[i]:
                drift = 0.0
            if successor and not phrase_start[i] and prev_out is not None:
                natural = prev_out + (b["start"] - evB[path[i - 1]]["start"])
                lim = min(1.5, 0.4 * phrase_len[i])
                drift = float(np.clip(natural - a["start"], -lim, lim))
            else:
                drift *= 0.5
            out_start = a["start"] + drift
        else:
            out_start = a["start"]
        max_len = slot * ((1.5 if dialogue else 1.25) + flex) + 0.05
        truncated = 0
        fout = xf
        if L > max_len:
            L = max_len
            truncated = 1
            fout = max(xf, min(0.08, 0.3 * L))
        src_start = max(0.0, b["start"] - pre)
        lead = b["start"] - src_start
        o_start = max(0.0, out_start - lead)
        total = L + lead
        n = int(round(total * srB))
        s0 = int(round(src_start * srB))
        n = max(2, min(n, nBs - s0))
        o0 = int(round(o_start * srB))
        fin_n = min(int(round(xf * srB)), n // 2)
        fout_n = min(int(round(fout * srB)), n - fin_n)
        g_db = float(np.clip(relA[i] - relB[j], -12.0, 9.0)) * dyn
        prev_out = out_start
        rows.append({
            "a_event": i + 1, "b_event": int(j) + 1,
            "out_s0": o0, "src_s0": s0, "n": n, "fin_n": fin_n, "fout_n": fout_n,
            "gain": 10 ** (g_db / 20.0), "gain_db": g_db,
            "out_start_s": o0 / srB, "out_end_s": (o0 + n) / srB,
            "a_start_s": a["start"], "a_end_s": a["end"],
            "b_start_s": b["start"], "b_end_s": b["end"],
            "src_start_s": s0 / srB, "src_end_s": (s0 + n) / srB,
            "successor": successor, "extended": extended, "truncated": truncated,
        })
    return rows


def coverage(rows, evA, a_total, gateB=None, hopB=None):
    """Two coverages of A's sounding time, on a 10 ms grid:
    timeline - some B material is placed there (may be B's silence);
    sounding - the B material placed there is above B's own level gate.
    Returns (timeline, sounding, longest timeline gap, longest sounding gap)."""
    grid = np.arange(0.0, a_total + 0.5, 0.01)
    sound = np.zeros(len(grid), bool)
    for e in evA:
        sound |= (grid >= e["start"]) & (grid < e["end"])
    cov = np.zeros(len(grid), bool)
    act = np.zeros(len(grid), bool)
    for r in rows:
        m = (grid >= r["out_start_s"]) & (grid < r["out_end_s"])
        cov |= m
        if gateB is not None:
            st = r["src_start_s"] + (grid[m] - r["out_start_s"])
            k = np.clip((st / hopB).astype(int), 0, len(gateB) - 1)
            idx = np.where(m)[0]
            act[idx[gateB[k]]] = True
    if gateB is None:
        act = cov

    def longest(mask):
        g = best = 0
        for k in range(len(grid)):
            if sound[k] and not mask[k]:
                g += 1
                best = max(best, g)
            else:
                g = 0
        return best * 0.01

    if not sound.any():
        return 1.0, 1.0, 0.0, 0.0
    n = sound.sum()
    return (float((sound & cov).sum() / n), float((sound & act).sum() / n),
            longest(cov), longest(act))


def _pearson_rows(P, Q):
    P = P - P.mean(axis=1, keepdims=True)
    Q = Q - Q.mean(axis=1, keepdims=True)
    den = np.sqrt((P ** 2).sum(1) * (Q ** 2).sum(1))
    r = np.where(den > 1e-9, (P * Q).sum(1) / np.maximum(den, 1e-12), np.nan)
    return r


def plan_metrics(path, rows, XA, XB, ctx, a_total, ref_path=None):
    env_r = _pearson_rows(XA[:, :, 0], XB[path, :, 0])
    desc_r = np.nanmean(np.stack([_pearson_rows(XA[:, :, c], XB[path, :, c]) for c in range(1, N_CH)]), axis=0)
    junc = [ctx["juncB"][path[i - 1], path[i]] for i in range(1, len(path))]
    cov, act, gap, gap_act = coverage(rows, ctx["evA"], a_total, ctx.get("gateB"), ctx.get("hopB"))
    use = np.bincount(path)
    m = {
        "dtw_mean": float(np.mean(ctx["dtw_full"][np.arange(len(path)), path])),
        "env_corr": float(np.nanmean(env_r)),
        "desc_corr": float(np.nanmean(desc_r)),
        "junction_mean": float(np.mean(junc)) if junc else 0.0,
        "successor_frac": float(np.mean([r["successor"] for r in rows])) if rows else 0.0,
        "unique_b": int((use > 0).sum()),
        "max_reuse": int(use.max()) if len(use) else 0,
        "coverage": cov, "longest_gap_s": gap,
        "sounding_coverage": act, "longest_silent_s": gap_act,
        "extended": int(sum(r["extended"] for r in rows)),
        "truncated": int(sum(r["truncated"] for r in rows)),
    }
    if ref_path is not None:
        m["agree_acoustic"] = float(np.mean(path == ref_path))
    return m


# ─────────────────────────────────────────────────────────────────────────────
# Output
# ─────────────────────────────────────────────────────────────────────────────

PLAN_COLS = ["a_event", "b_event", "out_s0", "src_s0", "n", "fin_n", "fout_n", "gain", "gain_db",
             "out_start_s", "out_end_s", "a_start_s", "a_end_s", "b_start_s", "b_end_s",
             "src_start_s", "src_end_s", "cost", "d_rep", "d_traj", "d_dur",
             "successor", "extended", "truncated", "substitution"]


def write_plan(path, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(PLAN_COLS) + "\n")
        for r in rows:
            vals = []
            for k in PLAN_COLS:
                v = r[k]
                if isinstance(v, (int, np.integer)):
                    vals.append(str(int(v)))
                else:
                    vals.append(f"{float(v):.6f}")
            f.write("\t".join(vals) + "\n")


def write_events(path, ev, extra_name=None, extra=None):
    cols = ["event", "start_s", "end_s", "dur_s", "level_db"] + ([extra_name] if extra_name else [])
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(cols) + "\n")
        for i, e in enumerate(ev):
            row = [str(i + 1), f"{e['start']:.6f}", f"{e['end']:.6f}", f"{e['dur']:.6f}", f"{e['level_db']:.3f}"]
            if extra_name:
                row.append(str(int(extra[i])))
            f.write("\t".join(row) + "\n")


def fmt(x, d=3):
    if x is None or (isinstance(x, float) and not np.isfinite(x)):
        return "n/a"
    return f"{x:.{d}f}"


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Two caches (plain .npz + JSON, no pickle; newest CACHE_KEEP of each kind kept)
#   feat - analysis, segmentation, trajectories, DTW on the lock-step and
#          Acoustic shortlists. Depends on the audio, sensitivity and duration
#          limits ONLY, so switching Acoustic <-> CNN <-> Hybrid reuses it.
#   cnn  - training, diagnostics, validation and the DTW of the extra pairs the
#          CNN shortlists. Depends on the features + seed + training mode.
# ─────────────────────────────────────────────────────────────────────────────

CACHE_KEEP = 8


def audio_hash(cfg):
    import hashlib
    h = hashlib.sha1()
    for k in ("a_wav", "b_wav"):
        with open(cfg[k], "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def feat_key(ah, P):
    import hashlib
    return hashlib.sha1((ah + json.dumps([VERSION, "feat", P["sens"], P["min_dur"], P["max_dur"]])).encode()
                        ).hexdigest()[:20]


def cnn_key(fk, P):
    import hashlib
    return hashlib.sha1((fk + json.dumps([VERSION, "cnn", P["seed"], P["training"], CNN_STEPS, CNN_BATCH,
                                          AUG_SCALE, AUG_OFFSET, CNN_LR, CNN_TAU])).encode()).hexdigest()[:20]


def _jsonable(o):
    if hasattr(o, "item"):
        return o.item()
    return str(o)


def cache_load(d, kind, key):
    if not d:
        return None
    path = os.path.join(d, f"ri_{kind}_{key}.npz")
    if not os.path.isfile(path):
        return None
    try:
        z = np.load(path, allow_pickle=False)
        meta = json.loads(str(z["__meta__"]))
        out = {k: v for k, v in meta.items() if k != "__none__"}
        for k in z.files:
            if k != "__meta__":
                out[k] = z[k]
        for k in meta.get("__none__", []):
            out[k] = None
        os.utime(path, None)
        return out
    except Exception as e:
        log(f"  cache read failed ({e}); recomputing")
        return None


def cache_save(d, kind, key, S):
    if not d:
        return
    try:
        os.makedirs(d, exist_ok=True)
        meta, arrs, nones = {}, {}, []
        for k, v in S.items():
            if isinstance(v, np.ndarray):
                arrs[k] = v
            elif v is None:
                nones.append(k)
            else:
                meta[k] = v
        meta["__none__"] = nones
        tmp = os.path.join(d, f"ri_{kind}_{key}.tmp.npz")
        np.savez_compressed(tmp, __meta__=np.array(json.dumps(meta, default=_jsonable)), **arrs)
        os.replace(tmp, os.path.join(d, f"ri_{kind}_{key}.npz"))
        files = sorted((os.path.join(d, f) for f in os.listdir(d)
                        if f.startswith(f"ri_{kind}_") and f.endswith(".npz")),
                       key=os.path.getmtime, reverse=True)
        for f in files[CACHE_KEEP:]:
            os.remove(f)
    except Exception as e:
        log(f"  cache write skipped ({e})")


def stage_features(cfg, P):
    """Analysis, segmentation, trajectories and DTW (lock-step + Acoustic
    shortlists). Independent of method, seed and every compositional setting."""
    report = []
    warn = []
    stats = {}
    xa, sra = read_wav(cfg["a_wav"])
    xb, srb = read_wav(cfg["b_wav"])
    P["sr_b"] = srb
    P["n_samples_b"] = len(xb)
    a_total = len(xa) / sra
    log(f"[RI {VERSION}] A: {a_total:.2f} s @ {sra} Hz | B: {len(xb)/srb:.2f} s @ {srb} Hz")
    report.append(f"Analysis channels: A {1 if xa.ndim == 1 else xa.shape[1]}, B {1 if xb.ndim == 1 else xb.shape[1]} "
                  f"(mean power spectrum of all channels)")
    for nm, x, sr in (("A", xa, sra), ("B", xb, srb)):
        if len(x) < int(0.1 * sr):
            raise RIError(f"Recording {nm} is shorter than 0.1 s; nothing to segment.")
        if float(np.max(np.abs(x))) < 1e-5:
            raise RIError(f"Recording {nm} is silent (peak below -100 dBFS).")

    # ── analysis + segmentation ──
    t0 = time.time()
    fA = analyse(xa, sra)
    fB = analyse(xb, srb)
    segA, novA, infA = segment(fA, P["sens"], P["min_dur"], P["max_dur"])
    segB, novB, infB = segment(fB, P["sens"], P["min_dur"], P["max_dur"])
    log(f"  analysis+segmentation {time.time()-t0:.2f} s")
    for nm, segs, inf in (("A", segA, infA), ("B", segB, infB)):
        report.append(f"Segmentation {nm}: {len(segs)} gestures | gate {fmt(inf['gate_on_db'],1)} dB "
                      f"(peak {fmt(inf['peak_db'],1)}, floor {fmt(inf['floor_db'],1)}) | onsets {inf['onsets']} | "
                      f"merged {inf['merged']} | dropped short {inf['dropped_short']} | split long {inf['split_long']}"
                      f" ({inf['split_flat']} without a clear onset)")
        if inf["continuous"]:
            warn.append(f"{nm}: level range under 10 dB - treated as continuous sound; gestures come from novelty and "
                        f"the maximum duration only.")
    if len(segA) < 2:
        raise RIError(f"Recording A yields {len(segA)} gesture(s). Raise Segmentation sensitivity or lower "
                        f"Minimum gesture duration.")
    if len(segB) < 2:
        raise RIError(f"Recording B yields {len(segB)} gesture(s). Raise Segmentation sensitivity or lower "
                        f"Minimum gesture duration.")
    if len(segB) < 6:
        warn.append(f"B has only {len(segB)} gestures: matching has very little choice and repetition is unavoidable.")

    rawA, evA = build_events(fA, segA, "A")
    rawB, evB = build_events(fB, segB, "B")
    nA, nB = len(evA), len(evB)
    trA, _ = source_normalise(rawA)
    trB, _ = source_normalise(rawB)
    XA = to_tensor(trA, T_FIXED)
    XB = to_tensor(trB, T_FIXED)
    XAd = to_tensor(trA, T_DTW)
    XBd = to_tensor(trB, T_DTW)
    stats.update({"n_a": nA, "n_b": nB})

    # ── acoustic representation ──
    S_all = summary_descriptors(np.concatenate([XA, XB]))
    S_all, s_mu, s_sd = standardise_cols(S_all)
    SA, SB = S_all[:nA], S_all[nA:]
    dim = S_all.shape[1]
    rep_ac = scale90(euclid(SA, SB) / math.sqrt(dim))

    # ── trajectory distances (lockstep everywhere, DTW on a shortlist) ──
    t0 = time.time()
    lock = lockstep(XAd, XBd)
    band = max(1, int(round(0.15 * T_DTW)))

    # DTW on the lock-step and Acoustic shortlists (the CNN stage adds its own)
    Kshort = min(nB, 24)
    mask = np.zeros((nA, nB), bool)
    for sset in (np.argsort(lock, axis=1)[:, :Kshort], np.argsort(rep_ac, axis=1)[:, :Kshort]):
        mask[np.repeat(np.arange(nA), sset.shape[1]), sset.ravel()] = True
    pairs = np.argwhere(mask)
    dtw_full = lock.copy()
    dvals = dtw_pairs(XAd, XBd, pairs, band)
    dtw_full[pairs[:, 0], pairs[:, 1]] = np.minimum(dvals, lock[pairs[:, 0], pairs[:, 1]])
    log(f"  distances ({len(pairs)} DTW pairs) {time.time()-t0:.2f} s")
    return {"evA": evA, "evB": evB, "XA": XA, "XB": XB, "XAd": XAd, "XBd": XBd,
            "dtw_full": dtw_full, "dtw_mask": mask, "lock": lock,
            "gateB": infB["gate"], "hopB": fB["hop_s"],
            "a_total": a_total, "srb": srb, "n_samples_b": len(xb),
            "report": report, "warn": warn}


def _holdout_split(src, seed):
    """20% of EACH recording held out, at least 3, leaving at least 4 per
    recording for training. Returns (held-out idx, train idx, reason)."""
    hr = np.random.default_rng(seed)
    ho = []
    for nm, sidx in (("A", np.where(src == 0)[0]), ("B", np.where(src == 1)[0])):
        k = max(3, int(round(0.2 * len(sidx))))
        if len(sidx) - k < 4:
            return None, None, (f"recording {nm} has {len(sidx)} gestures; holding out {k} would leave "
                                f"{len(sidx) - k} (< 4) for training")
        ho.extend(hr.choice(sidx, k, replace=False).tolist())
    ho = np.array(sorted(ho), int)
    return ho, np.setdiff1d(np.arange(len(src)), ho), ""


def stage_cnn(F, P):
    """Joint CNN training, diagnostics, validation, and DTW for the extra
    pairs the CNN shortlists."""
    report = []
    warn = []
    XA, XB, XAd, XBd = F["XA"], F["XB"], F["XAd"], F["XBd"]
    nA, nB = len(XA), len(XB)
    X_all = np.concatenate([XA, XB])
    src = np.concatenate([np.zeros(nA, int), np.ones(nB, int)])
    S_all, s_mu, s_sd = standardise_cols(summary_descriptors(X_all))
    out = {"E": None, "cnn_ok": False, "diag": {}, "dtw_extra_idx": np.zeros((0, 2), int),
           "dtw_extra_val": np.zeros(0), "report": report, "warn": warn}
    if nA < MIN_EVENTS_PER_SOURCE_CNN or nB < MIN_EVENTS_PER_SOURCE_CNN or nA + nB < MIN_EVENTS_TOTAL_CNN:
        out["cnn_status"] = (f"NOT TRAINED - {nA} + {nB} gestures is below the minimum "
                             f"({MIN_EVENTS_PER_SOURCE_CNN} per recording, {MIN_EVENTS_TOTAL_CNN} total)")
        warn.append("Joint CNN unavailable: too few gestures. CNN choices fall back to the Acoustic "
                    "representation and are labelled as such.")
        return out
    log(f"  training joint CNN on {nA}+{nB} gestures ({CNN_STEPS} steps)...")
    cnn = train_cnn(X_all, src, P["seed"])
    if not cnn.valid:
        out["cnn_status"] = "TRAINING DIVERGED - fell back to Acoustic"
        warn.append("Joint CNN training diverged; CNN choices fall back to Acoustic.")
        return out
    E = cnn.embed(X_all).astype(np.float64)
    h = cnn.history
    out["cnn_status"] = (f"trained {CNN_STEPS} steps in {cnn.train_seconds:.1f} s, balanced batches "
                         f"{cnn.batch_k}+{cnn.batch_k} | loss {h[0][1]:.3f} -> {h[-1][1]:.3f} | best val "
                         f"{cnn.best_val:.3f} (chance level ~{math.log(2 * cnn.batch_k):.2f})")
    if nA + nB < LIMITED_EVENTS_TOTAL:
        warn.append(f"Only {nA + nB} gestures in total: the learned representation rests on very little "
                    f"data. Treat CNN results as exploratory.")
    vr = np.random.default_rng(P["seed"] + 77)
    Xaug = augment(X_all, vr, scale=(0.85, 1.15), offset=0.15)   # mild, gesture-preserving
    rnd = BatchCNN(N_CH, P["seed"] + 999)
    mc, er = collapse_stats(E)
    EA, EB = l2n(E[:nA]), l2n(E[nA:])
    Ec = np.concatenate([l2n(EA - EA.mean(0)), l2n(EB - EB.mean(0))])
    diag = {"ret_cnn": retrieval_top1(E, cnn.embed(Xaug).astype(np.float64)),
            "ret_rnd": retrieval_top1(rnd.embed(X_all), rnd.embed(Xaug)),
            "ret_ac": retrieval_top1(S_all, (summary_descriptors(Xaug) - s_mu) / s_sd),
            "mean_cos": mc, "eff_rank": er,
            "bias_raw": source_bias(l2n(E), src, P["seed"]),
            "bias_centred": source_bias(Ec, src, P["seed"]),
            "bias_ac": source_bias(S_all, src, P["seed"]),
            "validation": "NOT RUN (Quick)", "validation_reason": ""}
    rep_cnn = scale90(cosine_dist(Ec[:nA], Ec[nA:]))
    if P["training"] == "validated" or P["stability"]:
        cnn2 = train_cnn(X_all, src, P["seed"] + 101)
        E2 = cnn2.embed(X_all).astype(np.float64)
        E2A, E2B = l2n(E2[:nA]), l2n(E2[nA:])
        rep2 = scale90(cosine_dist(l2n(E2A - E2A.mean(0)), l2n(E2B - E2B.mean(0))))
        diag["seed_rank_agree"] = spearman(rep_cnn, rep2)
        diag["seed_nn_agree"] = float(np.mean(np.argmin(rep_cnn, 1) == np.argmin(rep2, 1)))
        diag["ret_cnn2"] = retrieval_top1(E2, cnn2.embed(Xaug).astype(np.float64))
        ho, tr, why = _holdout_split(src, P["seed"] + 303)
        if ho is None:
            diag["validation"] = "INSUFFICIENT"
            diag["validation_reason"] = why
        else:
            cnn_h = train_cnn(X_all[tr], src[tr], P["seed"] + 202)
            Xh = X_all[ho]
            Xh_aug = augment(Xh, np.random.default_rng(P["seed"] + 404), scale=(0.85, 1.15), offset=0.15)
            rnd_h = BatchCNN(N_CH, P["seed"] + 998)
            diag.update({"validation": "DONE", "ho_n": float(len(ho)),
                         "ho_ret_cnn": retrieval_top1(cnn_h.embed(Xh), cnn_h.embed(Xh_aug)),
                         "ho_ret_rnd": retrieval_top1(rnd_h.embed(Xh), rnd_h.embed(Xh_aug)),
                         "ho_ret_ac": retrieval_top1((summary_descriptors(Xh) - s_mu) / s_sd,
                                                     (summary_descriptors(Xh_aug) - s_mu) / s_sd)})
    # DTW for the pairs only the CNN shortlists (so CNN choices are scored by
    # true DTW too, not by the lock-step upper bound)
    Kshort = min(nB, 24)
    sset = np.argsort(rep_cnn, axis=1)[:, :Kshort]
    want = np.zeros((nA, nB), bool)
    want[np.repeat(np.arange(nA), Kshort), sset.ravel()] = True
    extra = np.argwhere(want & ~F["dtw_mask"])
    dtw_full = F["dtw_full"].copy()
    if len(extra):
        band = max(1, int(round(0.15 * T_DTW)))
        vals = np.minimum(dtw_pairs(XAd, XBd, extra, band), F["lock"][extra[:, 0], extra[:, 1]])
        dtw_full[extra[:, 0], extra[:, 1]] = vals
        out["dtw_extra_idx"], out["dtw_extra_val"] = extra, vals
    pairs = np.argwhere(F["dtw_mask"] | want)
    S_A, S_B = S_all[:nA], S_all[nA:]
    rep_ac = scale90(euclid(S_A, S_B) / math.sqrt(S_all.shape[1]))
    diag["rank_traj_cnn"] = spearman(rep_cnn[pairs[:, 0], pairs[:, 1]], dtw_full[pairs[:, 0], pairs[:, 1]])
    diag["rank_traj_ac"] = spearman(rep_ac[pairs[:, 0], pairs[:, 1]], dtw_full[pairs[:, 0], pairs[:, 1]])
    diag["rank_cnn_ac"] = spearman(rep_cnn.ravel(), rep_ac.ravel())
    out.update({"E": E, "cnn_ok": True, "diag": diag})
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Listener anchor pairs: an EXTERNAL test of cross-instrument correspondence.
# The user names (A time, B time) pairs judged behaviourally similar by ear.
# They are never used for training, so this measures what each representation
# found on its own: where does the listener's B gesture rank among all of B?
# ─────────────────────────────────────────────────────────────────────────────

def _event_at(ev, t):
    for i, e in enumerate(ev):
        if e["start"] <= t < e["end"]:
            return i
    c = np.array([0.5 * (e["start"] + e["end"]) for e in ev])
    i = int(np.argmin(np.abs(c - t)))
    return i if abs(c[i] - t) <= 0.5 else None


def anchor_eval(path, evA, evB, reps, seed):
    lines = []
    try:
        rows = [l.rstrip("\n").split("\t") for l in open(path, encoding="utf-8") if l.strip()]
    except Exception as e:
        return [f"Anchor pairs: could not read ({e})"], {}
    head = [h.strip().lower() for h in rows[0]]
    if "a_time" not in head or "b_time" not in head:
        return ["Anchor pairs: the Table needs columns a_time and b_time (seconds)"], {}
    ia, ib = head.index("a_time"), head.index("b_time")
    pairs = []
    skipped = 0
    for r in rows[1:]:
        try:
            i, j = _event_at(evA, float(r[ia])), _event_at(evB, float(r[ib]))
        except (ValueError, IndexError):
            i = j = None
        if i is None or j is None:
            skipped += 1
        else:
            pairs.append((i, j))
    nB = len(evB)
    if not pairs or nB < 3:
        return [f"Anchor pairs: none usable ({skipped} outside any gesture)"], {}
    P = np.array(pairs)
    lines.append(f"Listener anchor pairs: {len(P)} used ({skipped} skipped). Rank of your B gesture among all {nB} "
                 f"B gestures for its A gesture: 0 = ranked first, 0.5 = chance, 1 = last.")
    pct = {}
    for name, R in reps.items():
        if R is None:
            continue
        rk = np.array([(R[i] < R[i, j]).sum() for i, j in P], float)
        pct[name] = rk / (nB - 1)
        lines.append(f"  {name:<10} mean rank {pct[name].mean():.3f} | first choice {int((rk == 0).sum())}/{len(P)} | "
                     f"top-3 {int((rk < 3).sum())}/{len(P)}")
    verdicts = {"n_pairs": len(P)}
    for name in ("cnn", "hybrid"):
        if name not in pct:
            continue
        rng = np.random.default_rng(seed + 505)
        diff = pct[name] - pct["acoustic"]
        boots = np.array([diff[rng.integers(0, len(diff), len(diff))].mean() for _ in range(2000)])
        lo, hi = np.percentile(boots, [2.5, 97.5])
        if len(P) < ANCHOR_MIN_PAIRS:
            v = "INSUFFICIENT PAIRS"
        else:
            v = "BETTER" if hi < 0 else "WORSE" if lo > 0 else "NO DETECTABLE DIFFERENCE"
        verdicts[name] = v
        verdicts[name + "_diff"] = float(diff.mean())
        lines.append(f"  {name.upper()} - Acoustic mean rank {diff.mean():+.3f}, 95% bootstrap interval "
                     f"[{lo:+.3f}, {hi:+.3f}]: {v}"
                     + (f" (fewer than {ANCHOR_MIN_PAIRS} pairs: no verdict)" if len(P) < ANCHOR_MIN_PAIRS else
                        " (fewer than 10 pairs: interval is wide)" if len(P) < 10 else ""))
    return lines, verdicts


def run(cfg):
    t_start = time.time()
    report = []
    warn = []
    stats = {}

    P = {
        "sens": float(np.clip(float(cfg.get("sensitivity", 0.5)), 0.0, 1.0)),
        "min_dur": float(max(0.03, float(cfg.get("min_dur", 0.08)))),
        "max_dur": float(cfg.get("max_dur", 2.5)),
        "method": str(cfg.get("method", "hybrid")).lower(),
        "morph": float(np.clip(float(cfg.get("morph", 0.5)), 0.0, 1.0)),
        "contrast": float(np.clip(float(cfg.get("contrast", 0.5)), 0.0, 1.0)),
        "flex": float(np.clip(float(cfg.get("flex", 0.5)), 0.0, 1.0)),
        "xfade_s": float(np.clip(float(cfg.get("xfade_ms", 12.0)), 0.0, 200.0)) / 1000.0,
        "mode": str(cfg.get("mode", "following")).lower(),
        "seed": int(float(cfg.get("seed", 1))),
        "avoid_rep": bool(int(float(cfg.get("avoid_rep", 1)))),
        "training": str(cfg.get("training", "validated")).lower(),
        "stability": bool(int(float(cfg.get("stability_check", 0)))),
    }
    P["max_dur"] = max(P["max_dur"], 2.0 * P["min_dur"])
    if P["method"] not in ("acoustic", "cnn", "hybrid", "compare"):
        raise RIError(f"Unknown method {P['method']}")
    if P["mode"] not in ("following", "dialogue"):
        raise RIError(f"Unknown mode {P['mode']}")
    rng = np.random.default_rng(P["seed"])

    cdir = cfg.get("cache_dir", "")
    fkey = feat_key(audio_hash(cfg), P)
    F = cache_load(cdir, "feat", fkey)
    feat_note = "reused"
    if F is None:
        F = stage_features(cfg, P)
        cache_save(cdir, "feat", fkey, F)
        feat_note = "computed"
    report.extend(F["report"])
    warn.extend(F["warn"])
    need_cnn = P["method"] in ("cnn", "hybrid", "compare")
    C = None
    cnn_note = "not needed"
    if need_cnn:
        ckey = cnn_key(fkey, P)
        C = cache_load(cdir, "cnn", ckey)
        cnn_note = "reused"
        if C is None:
            C = stage_cnn(F, P)
            cache_save(cdir, "cnn", ckey, C)
            cnn_note = "computed"
        warn.extend(C["warn"])
    report.append(f"Cache: features + DTW {feat_note} | CNN training {cnn_note}")
    evA, evB, XA, XB = F["evA"], F["evB"], F["XA"], F["XB"]
    if C is not None:
        E, cnn_ok, cnn_status, diag = C["E"], bool(C["cnn_ok"]), C["cnn_status"], C["diag"]
    else:
        E, cnn_ok, cnn_status, diag = None, False, "not requested", {}
    dtw_full = F["dtw_full"].copy()
    if C is not None and len(C["dtw_extra_idx"]):
        ix = np.asarray(C["dtw_extra_idx"], int).reshape(-1, 2)
        dtw_full[ix[:, 0], ix[:, 1]] = C["dtw_extra_val"]
    gateB, hopB = F["gateB"].astype(bool), F["hopB"]
    a_total, srb = F["a_total"], F["srb"]
    P["sr_b"] = srb
    P["n_samples_b"] = F["n_samples_b"]
    nA, nB = len(evA), len(evB)
    dA = np.array([e["dur"] for e in evA])
    dB = np.array([e["dur"] for e in evB])
    traj = scale90(dtw_full)
    S_all = standardise_cols(summary_descriptors(np.concatenate([XA, XB])))[0]
    SA, SB = S_all[:nA], S_all[nA:]
    dim = S_all.shape[1]
    rep_ac = scale90(euclid(SA, SB) / math.sqrt(dim))
    famA_ac = scale90(euclid(SA, SA) / math.sqrt(dim))
    famB_ac = scale90(euclid(SB, SB) / math.sqrt(dim))
    rep_cnn = None
    if cnn_ok:
        EA, EB = l2n(E[:nA]), l2n(E[nA:])
        rep_cnn = scale90(cosine_dist(l2n(EA - EA.mean(0)), l2n(EB - EB.mean(0))))
        famA_cnn = scale90(cosine_dist(EA, EA))
        famB_cnn = scale90(cosine_dist(EB, EB))

    anchor_lines, anchor = [], {}
    if cfg.get("anchors"):
        reps_eval = {"acoustic": rep_ac, "DTW traj": traj}
        if cnn_ok:
            reps_eval["cnn"] = rep_cnn
            reps_eval["hybrid"] = 0.5 * rep_ac + 0.5 * rep_cnn
        anchor_lines, anchor = anchor_eval(cfg["anchors"], evA, evB, reps_eval, P["seed"])

    # ── (1) Representation Integrity Check: is the learned space technically
    # sound? It says NOTHING about whether it matches instruments well.
    integ = []
    if cnn_ok:
        d = diag
        if d.get("mean_cos", 0) > 0.9 or d.get("eff_rank", 99) < 2.0:
            integ.append("representation collapse")
        if np.isfinite(d.get("bias_centred", np.nan)) and d["bias_centred"] > 0.85:
            integ.append(f"source-identity bias {d['bias_centred']:.2f} > 0.85")
        gains = [d.get("ret_cnn", 0) - d.get("ret_rnd", 0)]
        if "ret_cnn2" in d:
            gains.append(d["ret_cnn2"] - d.get("ret_rnd", 0))
        if "ho_ret_cnn" in d:
            gains.append(d["ho_ret_cnn"] - d["ho_ret_rnd"])
        d["gate_gain"] = float(np.mean(gains))
        if d["gate_gain"] <= 0.0:
            integ.append(f"no retrieval gain over an untrained network ({d['gate_gain']:+.2f})")
        sra = d.get("seed_rank_agree")
        if sra is not None and np.isfinite(sra) and sra < SEED_STABILITY_MIN:
            integ.append(f"unstable across seeds (distance rank agreement {sra:.3f} < {SEED_STABILITY_MIN:.2f})")
        if P["training"] == "validated" and d.get("validation") != "DONE":
            integ.append("VALIDATION INSUFFICIENT: " + (d.get("validation_reason") or "held-out check not run"))
    integrity_pass = bool(cnn_ok and not integ)
    if not cnn_ok:
        integrity_label = "NOT APPLICABLE (" + cnn_status.split(" - ")[0].lower() + ")"
    elif integrity_pass:
        integrity_label = "PASSED" + (" (technical checks only: Quick mode, NOT validated)"
                                      if P["training"] != "validated" else "")
    else:
        integrity_label = "FAILED - " + "; ".join(integ)

    # ── (2) Cross-Instrument Correspondence Evaluation: does the CNN rank the
    # listener's own voice/cello pairs closer than the Acoustic descriptors?
    def verdict(meth):
        return anchor.get(meth) if anchor else None

    def cnn_usable(meth):
        return integrity_pass and verdict(meth) != "WORSE"

    if not cnn_ok:
        added_value = "NOT APPLICABLE"
    elif not anchor or "cnn" not in anchor:
        added_value = ("NOT EVALUATED - no listener anchor pairs. There is NO evidence that the CNN adds "
                       "anything beyond the Acoustic descriptors.")
    else:
        v = anchor["cnn"]
        added_value = {"BETTER": "ESTABLISHED for these pairs - the CNN ranks your pairs closer than Acoustic.",
                       "NO DETECTABLE DIFFERENCE": "NOT DETECTED - on your pairs the CNN adds nothing measurable "
                                                   "beyond the Acoustic descriptors.",
                       "WORSE": "NEGATIVE - on your pairs the CNN is WORSE than the Acoustic descriptors.",
                       "INSUFFICIENT PAIRS": f"UNDECIDED - fewer than {ANCHOR_MIN_PAIRS} usable pairs."}[v]
    cnn_state = {}
    for meth in ("cnn", "hybrid"):
        if not cnn_ok:
            cnn_state[meth] = "fallback"
        elif cnn_usable(meth):
            cnn_state[meth] = "used"
        else:
            cnn_state[meth] = "unreliable" if P["method"] == "compare" else "fallback"
    if cnn_ok and P["method"] in ("cnn", "hybrid") and cnn_state[P["method"]] == "fallback":
        whys = []
        if not integrity_pass:
            whys.append("integrity check failed")
        if verdict(P["method"]) == "WORSE":
            whys.append("listener anchors show it ranks your pairs FURTHER than Acoustic")
        why = " and ".join(whys)
        warn.append(f"{P['method']}: the learned representation is NOT used ({why}); the Acoustic "
                    f"representation is used instead (labelled acoustic fallback).")
    if P["method"] == "compare" and cnn_ok and "used" not in (cnn_state["cnn"], cnn_state["hybrid"]):
        warn.append("Compare: CNN and Hybrid are rendered so they can be heard, but labelled UNRELIABLE.")
    elif P["method"] == "compare" and cnn_ok and cnn_state["cnn"] != cnn_state["hybrid"]:
        warn.append(f"Compare: CNN {cnn_state['cnn']}, Hybrid {cnn_state['hybrid']} (listener anchors judged them "
                    f"separately).")

    dd = duration_dist(dA, dB)
    w_dur = 0.6 * (1.0 - P["flex"])

    # ── transition context ──
    def states(X, a, b):
        return X[:, a:b, 1:].mean(axis=1)
    q = max(1, T_FIXED // 5)
    endA, startA = states(XA, T_FIXED - q, T_FIXED), states(XA, 0, q)
    endB, startB = states(XB, T_FIXED - q, T_FIXED), states(XB, 0, q)
    juncB = scale90(euclid(endB, startB) / math.sqrt(N_CH - 1))
    juncA = scale90(euclid(endA, startA) / math.sqrt(N_CH - 1))
    run_end = np.zeros(len(gateB) + 1, int)          # end frame of the gated run containing k
    run_end[len(gateB)] = len(gateB)
    for k in range(len(gateB) - 1, -1, -1):
        run_end[k] = run_end[k + 1] if gateB[k] else k
    soundB_end = np.array([max(e["end"], run_end[min(e["e"], len(gateB) - 1)] * hopB
                               if gateB[min(e["e"], len(gateB) - 1)] else e["end"]) for e in evB])
    contigB = np.array([(evB[j + 1]["start"] - evB[j]["end"]) < 0.3 if j + 1 < nB else False
                        for j in range(nB)], bool)
    gaps = np.array([evA[i + 1]["start"] - evA[i]["end"] for i in range(nA - 1)])
    if len(gaps):
        gthr = max(0.25, float(np.percentile(gaps, 80)))
        boundary = gaps >= gthr
    else:
        boundary = np.zeros(0, bool)
    phrase_start = np.zeros(nA, bool)
    phrase_start[0] = True
    phrase_start[1:] = boundary
    # phrase length for each event
    phrase_len = np.zeros(nA)
    starts = list(np.where(phrase_start)[0]) + [nA]
    for a, b in zip(starts[:-1], starts[1:]):
        phrase_len[a:b] = evA[b - 1]["end"] - evA[a]["start"]
    lam_scale = np.where(boundary, 0.3, 1.0) if len(boundary) else np.zeros(0)
    report.append(f"A phrases: {int(phrase_start.sum())} (boundaries at gaps >= "
                  f"{fmt(gthr if len(gaps) else float('nan'), 2)} s)")

    def make_ctx(famA, famB):
        DtrB = 0.5 * juncB + 0.5 * famB
        DtrA = np.array([0.5 * juncA[i, i + 1] + 0.5 * famA[i, i + 1] for i in range(nA - 1)])
        off = ~np.eye(nB, dtype=bool)
        poolv = DtrB[off]
        if poolv.size == 0:
            poolv = np.array([0.0])
        if len(DtrA):
            rA = _ranks(DtrA) / max(1, len(DtrA) - 1)
            tau = np.quantile(poolv, np.clip(rA, 0, 1))
        else:
            tau = np.zeros(0)
        return {"DtrB": DtrB, "contigB": contigB, "tau": tau, "lam_scale": lam_scale,
                "phrase_start": phrase_start, "phrase_len": phrase_len, "juncB": juncB,
                "evA": evA, "dtw_full": dtw_full, "gateB": gateB, "hopB": hopB,
                "soundB_end": soundB_end}

    methods = ["acoustic", "cnn", "hybrid"] if P["method"] == "compare" else [P["method"]]
    if P["method"] == "acoustic":
        methods = ["acoustic"]
    results = {}
    ref_path = None
    for meth in (["acoustic"] + [m for m in methods if m != "acoustic"]):
        if meth == "acoustic":
            rep, famA, famB = rep_ac, famA_ac, famB_ac
            label = "acoustic"
        elif cnn_state[meth] == "fallback":
            rep, famA, famB = rep_ac, famA_ac, famB_ac
            label = meth + " (acoustic fallback)"
        elif meth == "cnn":
            rep, famA, famB = rep_cnn, famA_cnn, famB_cnn
            label = "cnn" if cnn_state["cnn"] == "used" else "cnn (UNRELIABLE)"
        else:
            rep = 0.5 * rep_ac + 0.5 * rep_cnn
            famA = 0.5 * famA_ac + 0.5 * famA_cnn
            famB = 0.5 * famB_ac + 0.5 * famB_cnn
            label = "hybrid" if cnn_state["hybrid"] == "used" else "hybrid (UNRELIABLE)"
        em = (1 - P["morph"]) * rep + P["morph"] * traj + w_dur * dd
        ctx = make_ctx(famA, famB)
        mrng = np.random.default_rng(P["seed"] + 13)   # identical noise for every method
        path, subst = plan_sequence(em, ctx, P, mrng)
        rows = place(path, evA, evB, ctx, P)
        for i, r in enumerate(rows):
            j = path[i]
            r["cost"] = float(em[i, j])
            r["d_rep"] = float(rep[i, j])
            r["d_traj"] = float(traj[i, j])
            r["d_dur"] = float(dd[i, j])
            r["substitution"] = int(subst[i])
        if meth == "acoustic":
            ref_path = path.copy()
        met = plan_metrics(path, rows, XA, XB, ctx, a_total, ref_path if meth != "acoustic" else None)
        met["substitutions"] = int(subst.sum())
        met["label"] = label
        results[meth] = (path, rows, met)

    # ── write outputs ──
    out_methods = ["acoustic", "cnn", "hybrid"] if P["method"] == "compare" else [P["method"]]
    total_s = a_total
    for meth in out_methods:
        path, rows, met = results[meth]
        rows_sorted = sorted(rows, key=lambda r: (r["out_s0"], r["a_event"]))
        write_plan(cfg["plan_prefix"] + meth + ".tsv", rows_sorted)
        total_s = max(total_s, max(r["out_end_s"] for r in rows) + 0.05)
    main = P["method"] if P["method"] != "compare" else "hybrid"
    pmain = results[main][0]
    useB = np.bincount(pmain, minlength=nB)
    write_events(cfg["events_a"], evA, "matched_b", pmain + 1)
    write_events(cfg["events_b"], evB, "used", useB)

    # ── report ──
    report.append(f"Gestures: A {nA} (mean {fmt(float(dA.mean()),2)} s) | B {nB} (mean {fmt(float(dB.mean()),2)} s)")
    report.append(f"Joint CNN: {cnn_status}")
    if diag:
        report.append(f"  Collapse test: mean cosine {fmt(diag['mean_cos'])} | effective rank "
                      f"{fmt(diag['eff_rank'],1)} of {D_EMB}")
        report.append(f"  Source-identity bias (balanced accuracy, 0.5 = none): CNN raw {fmt(diag['bias_raw'],2)} | "
                      f"CNN source-centred {fmt(diag['bias_centred'],2)} | Acoustic {fmt(diag['bias_ac'],2)}")
        report.append(f"  Mild-perturbation retrieval top-1: trained CNN {fmt(diag['ret_cnn'],2)} | untrained CNN "
                      f"{fmt(diag['ret_rnd'],2)} | Acoustic {fmt(diag['ret_ac'],2)}")
        report.append(f"  Rank agreement with DTW trajectory distance: CNN {fmt(diag.get('rank_traj_cnn'),2)} | "
                      f"Acoustic {fmt(diag.get('rank_traj_ac'),2)} | CNN vs Acoustic {fmt(diag.get('rank_cnn_ac'),2)}")
        if "seed_rank_agree" in diag:
            report.append(f"  Seed stability (2nd seed): distance rank agreement {fmt(diag['seed_rank_agree'],2)} | "
                          f"same nearest B {fmt(diag['seed_nn_agree'],2)}")
        if "ho_ret_cnn" in diag:
            report.append(f"  Held-out check ({int(diag['ho_n'])} gestures never trained on), retrieval top-1: "
                          f"trained CNN {fmt(diag['ho_ret_cnn'],2)} | untrained {fmt(diag['ho_ret_rnd'],2)} | "
                          f"Acoustic {fmt(diag['ho_ret_ac'],2)}")
        vtxt = diag.get("validation", "NOT RUN")
        if vtxt == "INSUFFICIENT":
            vtxt = "INSUFFICIENT - " + diag.get("validation_reason", "")
        report.append(f"  Validation: {vtxt}")
    if cnn_ok or need_cnn:
        report.append(f"REPRESENTATION INTEGRITY CHECK: {integrity_label}")
        report.append("  (technical soundness only: no collapse, centred source bias <= 0.85, retrieval gain over an "
                      f"untrained network, second-seed rank agreement >= {SEED_STABILITY_MIN:.2f}, validation "
                      "actually run. Passing says NOTHING about cross-instrument matching quality.)")
        report.append("CROSS-INSTRUMENT CORRESPONDENCE EVALUATION:")
        if anchor_lines:
            report.extend("  " + l for l in anchor_lines)
        else:
            report.append("  No listener anchor pairs supplied.")
        if "ho_ret_cnn" in diag:
            report.append(f"  Proxy only (not decisive): held-out retrieval CNN {fmt(diag['ho_ret_cnn'],2)} vs "
                          f"Acoustic {fmt(diag['ho_ret_ac'],2)}.")
        report.append(f"  ADDED VALUE OF THE LEARNED REPRESENTATION: {added_value}")
        report.append(f"  Use: CNN {cnn_state['cnn']} | Hybrid {cnn_state['hybrid']}")
    elif anchor_lines:
        report.extend(anchor_lines)
    report.append(f"Matching: morph weight {fmt(P['morph'],2)} | duration weight {fmt(w_dur,2)} | "
                  f"continuity/contrast {fmt(P['contrast'],2)} | mode {P['mode']} | repetition avoidance "
                  f"{'on' if P['avoid_rep'] else 'off'} | seed {P['seed']}")
    report.append("Plans (identical segmentation, costs and synthesis settings):")
    report.append("  method              DTW   env_r desc_r junct  succ  uniqB reuse  time sound silent_s subst agreeAc")
    for meth in (["acoustic", "cnn", "hybrid"] if P["method"] == "compare" else [P["method"]]):
        m = results[meth][2]
        report.append(f"  {m['label']:<19} {m['dtw_mean']:.3f} {m['env_corr']:6.2f} {m['desc_corr']:6.2f} "
                      f"{m['junction_mean']:.3f} {m['successor_frac']:5.2f} {m['unique_b']:5d} {m['max_reuse']:5d} "
                      f"{m['coverage']:5.2f} {m['sounding_coverage']:5.2f} {m['longest_silent_s']:8.2f} {m['substitutions']:5d} "
                      f"{fmt(m.get('agree_acoustic', float('nan')),2):>7}")
    report.append("  DTW lower = closer whole-gesture trajectory; env_r/desc_r = mean shape correlation A vs chosen B; "
                  "junct = timbral jump between consecutive B choices; succ = share of B source successors.")
    report.append("  time = share of A's sounding time with B material placed; sound = share where that B material is "
                  "itself sounding (above B's level gate); silent_s = longest stretch of A's sounding time without "
                  "sounding B material.")
    mm = results[main][2]
    if mm["sounding_coverage"] < 0.85:
        warn.append(f"Sounding B material covers {mm['sounding_coverage']*100:.0f}% of A's sounding time "
                    f"(timeline {mm['coverage']*100:.0f}%; longest stretch without sounding B "
                    f"{mm['longest_silent_s']:.2f} s). B's sounding gestures are shorter than A's: lower Duration "
                    f"flexibility (longer B gestures preferred) or use B material with longer gestures.")

    with open(cfg["report"], "w", encoding="utf-8", newline="\n") as f:
        for line in report:
            f.write(line + "\n")
        for w in warn:
            f.write("WARNING: " + w + "\n")
    with open(cfg["stats"], "w", encoding="utf-8", newline="\n") as f:
        kv = {
            "version": VERSION, "n_a": nA, "n_b": nB, "total_s": round(total_s, 6),
            "total_n": int(math.ceil(total_s * srb)), "sr_b": srb,
            "cnn_ok": int(cnn_ok), "integrity": ("passed" if integrity_pass else "failed" if cnn_ok else "n/a"),
            "state_cnn": cnn_state["cnn"], "state_hybrid": cnn_state["hybrid"],
            "added_value": added_value.split(" - ")[0].split(" for ")[0].replace(" ", "_"), "cnn_status": cnn_status.split(" - ")[0].split(" |")[0].split(",")[0],
            "main_method": main, "mode": P["mode"],
            "coverage": round(mm["coverage"], 4), "longest_gap_s": round(mm["longest_gap_s"], 3),
            "sounding_coverage": round(mm["sounding_coverage"], 4),
            "longest_silent_s": round(mm["longest_silent_s"], 3),
            "dtw_mean": round(mm["dtw_mean"], 4), "env_corr": round(mm["env_corr"], 4),
            "unique_b": mm["unique_b"], "max_reuse": mm["max_reuse"],
            "successor_frac": round(mm["successor_frac"], 3),
            "agree_acoustic": round(mm.get("agree_acoustic", float("nan")), 3) if "agree_acoustic" in mm else "n/a",
            "bias_centred": round(diag["bias_centred"], 3) if diag else "n/a",
            "eff_rank": round(diag["eff_rank"], 2) if diag else "n/a",
            "ret_cnn": round(diag["ret_cnn"], 3) if diag else "n/a",
            "ret_rnd": round(diag["ret_rnd"], 3) if diag else "n/a",
            "warnings": len(warn), "seconds": round(time.time() - t_start, 2),
        }
        for k, v in kv.items():
            f.write(f"{k}={v}\n")
    log(f"  done in {time.time()-t_start:.2f} s")
    results["_debug"] = {"evA": evA, "evB": evB, "rep_ac": rep_ac, "traj": traj, "dd": dd,
                         "rep_cnn": rep_cnn if cnn_ok else None, "diag": diag, "warn": warn,
                         "report": report}
    return results


def main():
    global _LOG_PATH
    if len(sys.argv) < 2:
        print("usage: rhythmic_imprinting.py config.json", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        cfg = json.load(f)
    _LOG_PATH = cfg.get("log", "")
    status = cfg.get("status", "")
    try:
        run(cfg)
        write_status(status, "ok")
    except RIError as e:
        log("ERROR: " + str(e))
        write_status(status, "error: " + str(e))
        sys.exit(1)
    except BaseException:
        log("FATAL: unhandled exception\n" + traceback.format_exc())
        write_status(status, "error: unhandled exception (see log)")
        sys.exit(1)


if __name__ == "__main__":
    main()
