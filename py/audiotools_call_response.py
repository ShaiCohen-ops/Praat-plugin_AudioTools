#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      audiotools_call_response.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     0.1 (2026) - proof of concept
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Capture + decision engine for AudioTools Intelligent Musical Call &
#   Response.  Launched by AudioTools_CallResponse.praat through a
#   BLOCKING runSubprocess, once per musical turn.  It
#     1. opens the microphone, calibrates the noise floor, waits for a
#        phrase, records it in RAM and detects its end   (listen)
#        - or reads a WAV exported by Praat               (analyze)
#     2. extracts harmonic / spectral / temporal / morphological
#        features with NumPy + SciPy only
#     3. scores the six AudioTools transformations with transparent
#        eligibility gates and normalised 0..1 suitability scores
#     4. maps the gesture onto bounded parameters for every candidate
#     5. writes the phrase (32-bit float WAV) and a line-oriented
#        key=value decision file (atomic rename), then EXITS.
#   It never transforms audio itself: every response is rendered by the
#   existing Praat AudioTools scripts, called from the Praat side.
#
# Commands (each one is a separate short-lived process):
#   probe         --out FILE [--live]      dependency check, writes FILE
#   devices       --out FILE               list audio input devices
#   listen        --session DIR --cycle N  [capture options]
#   analyze       --session DIR --cycle N --input WAV
#   cleanup       --session DIR            remove one session folder
#   cleanup-stale --base DIR               remove sessions older than 12 h
#   self-test     [--write-dir DIR]        synthetic six-category test
#
# Requirements:
#   Python >= 3.9, numpy, scipy, soundfile        (all commands)
#   sounddevice (PortAudio)                       (listen, devices only)
#   pip install numpy scipy soundfile sounddevice
#   librosa is deliberately NOT used: its import time (1-3 s) would be
#   paid on every turn, inside the musician's waiting time.
#
# Protocol (decision_NNN.txt, UTF-8, "\n" line endings, one key=value
# per line, values never contain newlines):
#   status=ok|timeout|silent_input|error   message=...
#   wav=<phrase wav>  sr=  channels=  duration=
#   mode=auto|manual  selected=<id>|passthrough  selected_score=
#   ranking=<id,id,...>  (eligible candidates above threshold, best first)
#   score_<id>=  eligible_<id>=0|1  reason_<id>=
#   p_<id>_<name>=<value>  for every candidate (named, not positional;
#                          the Praat dispatcher owns argument order)
#   seed=  t_phrase_end_epoch=  t_written_epoch=  t_detect_delay=
#   t_features=  t_select=  t_py_runtime=
#
# Notes:
#   - Thresholds and score centres are POC heuristics tuned on synthetic
#     signals, not universal acoustic constants.  They are collected in
#     the score functions below so they can be inspected and changed.
# ============================================================

import argparse
import math
import os
import shutil
import sys
import time
import zlib

T_PROCESS_START = time.perf_counter()
VERSION = "0.1"

TRANSFORM_IDS = ["paulstretch", "markov", "mds", "spiral", "metamod", "groove"]
TRANSFORM_NAMES = {
    "paulstretch": "Paulstretch (stable harmonic)",
    "markov": "Markov Soundscape Weaver (noisy / aperiodic)",
    "mds": "MDS Space Navigator (discrete attacks)",
    "spiral": "Spiral Pitch Dance (continuous glissando)",
    "metamod": "Metamodulator (complex dynamic envelope)",
    "groove": "Percussive Audio Groove Creator (variable density)",
}
# Deterministic tie-break: more specific categories first.
TIE_PRIORITY = ["spiral", "groove", "mds", "paulstretch", "markov", "metamod"]
CONFIDENCE_THRESHOLD = {
    "paulstretch": 0.50, "markov": 0.50, "mds": 0.50,
    "spiral": 0.50, "metamod": 0.45, "groove": 0.50,
}
AMBIGUITY_MARGIN = 0.08
MAX_RESPONSE_S = 20.0          # hard cap for stretched / generated answers
SESSION_PREFIX = "AudioTools_CR_"


# ============================================================
# small helpers
# ============================================================
def sig(x, centre, width):
    """Logistic ramp 0..1 centred on `centre`."""
    z = (x - centre) / max(width, 1e-9)
    if z > 40:
        return 1.0
    if z < -40:
        return 0.0
    return 1.0 / (1.0 + math.exp(-z))


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


def fnum(x, nd=4):
    if x is None or (isinstance(x, float) and (math.isnan(x) or math.isinf(x))):
        return "nan"
    return ("%." + str(nd) + "f") % x


def clean_value(v):
    s = str(v)
    return s.replace("\r", " ").replace("\n", " ")


def write_kv_atomic(path, pairs):
    """Write key=value lines to path.tmp, then rename onto path."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        for k, v in pairs:
            fh.write("%s=%s\n" % (k, clean_value(v)))
        fh.write("end=1\n")
    os.replace(tmp, path)


def write_text_atomic(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    os.replace(tmp, path)


def import_dsp():
    import numpy as np                      # noqa: F401
    import scipy.signal                     # noqa: F401
    import scipy.fft                        # noqa: F401
    import soundfile                        # noqa: F401
    return np


# ============================================================
# DSP building blocks (numpy / scipy only)
# ============================================================
def to_mono(x):
    import numpy as np
    if x.ndim == 1:
        return x.astype(np.float64)
    return x.mean(axis=1).astype(np.float64)


def frame_signal(x, frame, hop):
    import numpy as np
    if len(x) < frame:
        x = np.pad(x, (0, frame - len(x)))
    n = 1 + (len(x) - frame) // hop
    idx = np.arange(frame)[None, :] + hop * np.arange(n)[:, None]
    return x[idx]


def rms_envelope_db(x, sr, hop_s=0.01, win_s=0.02):
    import numpy as np
    hop = max(1, int(round(hop_s * sr)))
    win = max(hop, int(round(win_s * sr)))
    pad = np.pad(x, (win // 2, win // 2))
    fr = frame_signal(pad, win, hop)
    r = np.sqrt(np.mean(fr ** 2, axis=1) + 1e-20)
    return 20 * np.log10(r + 1e-12)


def stft_mag(x, sr, n_fft=1024, hop=None):
    import numpy as np
    if hop is None:
        hop = int(round(0.01 * sr))
    pad = np.pad(x, (n_fft // 2, n_fft // 2))
    fr = frame_signal(pad, n_fft, hop) * np.hanning(n_fft)[None, :]
    return np.abs(np.fft.rfft(fr, axis=1)), np.fft.rfftfreq(n_fft, 1.0 / sr)


def mel_filterbank(sr, n_fft, n_mels=26, fmin=60.0, fmax=None):
    import numpy as np
    fmax = fmax or sr / 2
    def hz2mel(f):
        return 2595 * np.log10(1 + f / 700.0)
    def mel2hz(m):
        return 700 * (10 ** (m / 2595.0) - 1)
    mels = np.linspace(hz2mel(fmin), hz2mel(fmax), n_mels + 2)
    hz = mel2hz(mels)
    bins = np.fft.rfftfreq(n_fft, 1.0 / sr)
    fb = np.zeros((n_mels, len(bins)))
    for m in range(1, n_mels + 1):
        lo, ce, hi = hz[m - 1], hz[m], hz[m + 1]
        up = (bins - lo) / max(ce - lo, 1e-9)
        dn = (hi - bins) / max(hi - ce, 1e-9)
        fb[m - 1] = np.clip(np.minimum(up, dn), 0, None)
    return fb


def mfcc_from_mag(mag, fb, n_coef=12):
    import numpy as np
    import scipy.fft
    mel = np.log(np.maximum(mag ** 2 @ fb.T, 1e-12))
    return scipy.fft.dct(mel, type=2, norm="ortho", axis=1)[:, 1:n_coef + 1]


def yin_pitch(x, sr, fmin=50.0, fmax=1200.0, hop_s=0.01):
    """YIN (CMNDF) on a 16 kHz copy. Returns times, f0 (nan = unvoiced),
    aperiodicity (0 = perfectly periodic, 1 = noise)."""
    import numpy as np
    import scipy.signal
    target = 16000
    g = math.gcd(int(sr), target)
    y = scipy.signal.resample_poly(x, target // g, int(sr) // g) if sr != target else x
    W = 1024
    tau_max = int(target / fmin)              # 320
    tau_min = max(2, int(target / fmax))      # 13
    L = W - tau_max
    hop = int(round(hop_s * target))
    pad = np.pad(y, (W // 2, W // 2))
    fr = frame_signal(pad, W, hop)
    n = fr.shape[0]
    N = 2048
    A = np.fft.rfft(fr[:, :L], N, axis=1)
    B = np.fft.rfft(fr, N, axis=1)
    r = np.fft.irfft(np.conj(A) * B, N, axis=1)[:, :tau_max + 1]
    sq = fr ** 2
    cs = np.concatenate([np.zeros((n, 1)), np.cumsum(sq, axis=1)], axis=1)
    taus = np.arange(tau_max + 1)
    e0 = cs[:, L][:, None]
    et = cs[:, taus + L] - cs[:, taus]
    d = np.maximum(e0 + et - 2 * r, 0)
    d[:, 0] = 0
    cum = np.cumsum(d[:, 1:], axis=1)
    cmndf = np.ones_like(d)
    cmndf[:, 1:] = d[:, 1:] * taus[1:][None, :] / np.maximum(cum, 1e-12)
    f0 = np.full(n, np.nan)
    aper = np.ones(n)
    thr = 0.15
    for i in range(n):
        c = cmndf[i]
        seg = c[tau_min:tau_max]
        below = np.where(seg < thr)[0]
        if len(below):
            t = below[0] + tau_min
            while t + 1 < tau_max and c[t + 1] < c[t]:
                t += 1
        else:
            t = int(np.argmin(seg)) + tau_min
        aper[i] = float(clamp(c[t], 0.0, 1.0))
        # voicing gate = the standard YIN threshold; measured on the
        # self-test material: tones <= 0.05, inharmonic cluster ~0.20
        if c[t] < thr:
            if 1 <= t < tau_max:
                a, b, cc = c[t - 1], c[t], c[t + 1]
                den = a - 2 * b + cc
                tt = t + (0.5 * (a - cc) / den if abs(den) > 1e-12 else 0.0)
            else:
                tt = t
            f0[i] = target / tt
    times = np.arange(n) * hop / target
    return times, f0, aper


def praat_intensity(x, sr, min_pitch):
    """Approximation of Praat Sound: To Intensity (subtract mean = yes):
    squared signal under a Kaiser-20 window of physical length
    6.4/min_pitch (effective 3.2/min_pitch), step 0.8/min_pitch.
    Checked against Praat 7.0 To TextGrid (silences) on 26 signals x 8
    settings: exact segment count in 84%, otherwise off by one (dense
    material near the threshold)."""
    import numpy as np
    win = max(4, int(round(6.4 / min_pitch * sr)))
    hop = max(1, int(round(0.8 / min_pitch * sr)))
    w = np.kaiser(win, 20)
    w = w / w.sum()
    x = x - x.mean()
    n = 1 + max(0, (len(x) - win)) // hop
    if len(x) < win:
        return np.array([len(x) / 2 / sr]), np.array([-300.0])
    fr = frame_signal(x, win, hop)
    p = (fr ** 2) @ w
    db = 10 * np.log10(p / 4e-10 + 1e-30)
    t = (np.arange(n) * hop + win / 2) / sr
    return t, db


def praat_silences(t, db, dur, thr_db, min_silent, min_sounding):
    """Emulation of Intensity: To TextGrid (silences). Returns list of
    sounding intervals (start, end)."""
    import numpy as np
    mx = float(np.max(db))
    sounding = db >= mx - thr_db
    # frame boundaries halfway between frame centres
    edges = np.concatenate([[0.0], (t[1:] + t[:-1]) / 2, [dur]])
    ivs = []
    cur = bool(sounding[0])
    start = 0.0
    for i in range(1, len(sounding)):
        if bool(sounding[i]) != cur:
            ivs.append([start, edges[i], cur])
            start = edges[i]
            cur = bool(sounding[i])
    ivs.append([start, dur, cur])

    def merge(ivs):
        out = []
        for iv in ivs:
            if out and out[-1][2] == iv[2]:
                out[-1][1] = iv[1]
            else:
                out.append(list(iv))
        return out
    # 1. short silences become sounding
    for iv in ivs:
        if not iv[2] and iv[1] - iv[0] < min_silent:
            iv[2] = True
    ivs = merge(ivs)
    # 2. short soundings become silent
    for iv in ivs:
        if iv[2] and iv[1] - iv[0] < min_sounding:
            iv[2] = False
    ivs = merge(ivs)
    return [(a, b) for a, b, s in ivs if s]


def groove_event_emulation(x, sr, onset_thr_db=-20.0, min_silence=0.05, max_segment=0.15):
    """Mirror of the onset detector + 3-band classifier inside
    'Percussive Audio Groove Creator.praat' (v0.5.1), so eligibility is
    judged with the script's own rules. Returns (events, counts)."""
    import numpy as np
    dur = len(x) / sr
    t, db = praat_intensity(x, sr, 70.0)
    thr = float(np.max(db)) + onset_thr_db
    nyq = sr / 2
    events = []
    last = -1.0
    for f in range(2, len(db) - 2):
        tm = t[f]
        if not (0.02 < tm < dur - 0.05):
            continue
        if tm - last <= min_silence:
            continue
        c = db[f]
        if c > db[f - 1] and c > db[f - 2] and c > db[f + 1] and c > thr:
            a = int(max(0, tm - 0.005) * sr)
            b = int(min(dur, tm + max_segment) * sr)
            seg = x[a:b]
            if len(seg) / sr <= 0.015:
                continue
            nfft = 1 << int(math.ceil(math.log2(len(seg))))
            P = np.abs(np.fft.rfft(seg, nfft)) ** 2
            fq = np.fft.rfftfreq(nfft, 1.0 / sr)
            def band(lo, hi):
                hi = min(hi, nyq)
                if hi <= lo:
                    return 0.0
                return float(P[(fq >= lo) & (fq < hi)].sum())
            lo_e, mi_e, hi_e = band(20, 250), band(250, 4000), band(4000, 18000)
            tot = lo_e + mi_e + hi_e
            typ = 0
            if tot > 0:
                if lo_e / tot > 0.55:
                    typ = 1
                elif hi_e / tot > 0.35:
                    typ = 2
                elif mi_e / tot > 0.4:
                    typ = 3
            if typ:
                events.append((tm, typ))
                last = tm
    counts = [sum(1 for e in events if e[1] == k) for k in (1, 2, 3)]
    return events, counts


def onset_detect(mag, hop_s):
    """Spectral-flux onsets with an adaptive median threshold."""
    import numpy as np
    import scipy.signal
    lm = np.log1p(100 * mag / (mag.max() + 1e-12))
    flux = np.maximum(np.diff(lm, axis=0), 0).sum(axis=1)
    flux = np.concatenate([[0.0], flux])
    if flux.max() <= 0:
        return np.array([], dtype=int), flux
    nov = flux / flux.max()
    k = max(3, int(round(0.25 / hop_s)) | 1)
    med = scipy.signal.medfilt(nov, k)
    thr = med + 0.12 + 0.5 * np.std(nov)
    peaks, _ = scipy.signal.find_peaks(nov, height=thr,
                                       distance=max(1, int(round(0.05 / hop_s))))
    return peaks, nov


# ============================================================
# feature extraction
# ============================================================
def extract_features(audio, sr):
    import numpy as np
    import scipy.signal
    x = to_mono(audio)
    dur = len(x) / sr
    F = {"duration": dur, "sr": sr}
    hop_s = 0.01

    # ---- energy envelope ----
    env = rms_envelope_db(x, sr, hop_s)
    peak_db = float(env.max())
    floor_db = float(max(np.percentile(env, 5), peak_db - 60))
    active = env > max(floor_db + 6, peak_db - 40)
    F["active_ratio"] = float(active.mean())
    smooth = np.convolve(env, np.ones(5) / 5, mode="same")
    act_vals = smooth[active] if active.any() else smooth
    F["env_dyn_range_db"] = float(np.percentile(act_vals, 95) - np.percentile(smooth, 10))
    pk, _ = scipy.signal.find_peaks(smooth, prominence=6, distance=int(0.1 / hop_s))
    pk = [p for p in pk if smooth[p] > peak_db - 30]
    F["env_peaks"] = len(pk)
    F["env_peak_rate"] = len(pk) / max(dur, 1e-6)
    d1 = np.diff(smooth[active]) if active.sum() > 3 else np.array([0.0])
    F["env_complexity"] = float(np.std(d1))
    if active.sum() > 3:
        ta = np.arange(len(env))[active] * hop_s
        F["energy_slope_db_s"] = float(np.polyfit(ta, smooth[active], 1)[0])
    else:
        F["energy_slope_db_s"] = 0.0

    # ---- silent gaps inside the phrase (between first and last activity) ----
    gaps = []
    if active.any():
        ia = np.where(active)[0]
        inner = active[ia[0]:ia[-1] + 1]
        run = 0
        for v in inner:
            if not v:
                run += 1
            else:
                if run * hop_s >= 0.08:
                    gaps.append(run * hop_s)
                run = 0
        F["silence_ratio"] = float(1 - inner.mean())
    else:
        F["silence_ratio"] = 1.0
    F["silent_gaps_n"] = len(gaps)
    F["gap_median"] = float(np.median(gaps)) if gaps else 0.0

    # ---- pitch / periodicity ----
    pt, f0, aper = yin_pitch(x, sr, hop_s=hop_s)
    n = min(len(f0), len(active))
    f0, aper, act_p = f0[:n], aper[:n], active[:n]
    voiced = (~np.isnan(f0)) & act_p
    F["voiced_ratio"] = float(voiced.sum() / max(act_p.sum(), 1))
    per = 1 - aper[act_p] if act_p.any() else np.array([0.0])
    pmed = float(clamp(np.median(per), 1e-4, 0.9999))
    F["periodicity"] = pmed
    F["hnr_db"] = float(10 * math.log10(pmed / (1 - pmed)))
    if voiced.sum() >= 5:
        st = 12 * np.log2(f0[voiced] / 100.0)
        tv = np.arange(n)[voiced] * hop_s
        st_s = scipy.signal.medfilt(st, 5) if len(st) >= 5 else st
        F["f0_median"] = float(100 * 2 ** (np.median(st_s) / 12))
        F["f0_p5"] = float(100 * 2 ** (np.percentile(st_s, 5) / 12))
        F["f0_p95"] = float(100 * 2 ** (np.percentile(st_s, 95) / 12))
        F["pitch_range_st"] = float(np.percentile(st_s, 95) - np.percentile(st_s, 5))
        slope = float(np.polyfit(tv, st_s, 1)[0]) if len(tv) > 2 else 0.0
        F["pitch_slope_st_s"] = slope
        F["f0_std_st"] = float(np.std(st_s - np.polyval(np.polyfit(tv, st_s, 1), tv))
                               if len(tv) > 2 else 0.0) if F["pitch_range_st"] < 2 else float(np.std(st_s))
        q = max(1, len(st_s) // 10)
        F["pitch_net_change_st"] = float(np.median(st_s[-q:]) - np.median(st_s[:q]))
        ds = np.diff(st_s)
        jumps = np.abs(ds) > 2.0
        moving = ds[~jumps]
        sgn = np.sign(F["pitch_net_change_st"]) or 1.0
        F["pitch_monotonicity"] = float(np.sum(np.maximum(moving * sgn, 0)) /
                                        max(np.sum(np.abs(moving)), 1e-9))
        # continuity: longest voiced run (allow 30 ms holes) / voiced frames
        runs, cur, hole = [], 0, 0
        for v in voiced:
            if v:
                cur += 1 + hole if cur else 1
                hole = 0
            else:
                hole += 1
                if hole > 3:
                    if cur:
                        runs.append(cur)
                    cur, hole = 0, 0
        if cur:
            runs.append(cur)
        F["pitch_continuity"] = float(max(runs) / max(voiced.sum(), 1)) if runs else 0.0
        F["voiced_runs"] = len(runs)
        F["pitch_breaks_per_s"] = float((int(jumps.sum()) + max(len(runs) - 1, 0)) / max(dur, 1e-6))
        F["pitch_rate_st_s"] = float(np.mean(np.abs(moving)) / hop_s) if len(moving) else 0.0
    else:
        for k in ("f0_median", "f0_p5", "f0_p95"):
            F[k] = float("nan")
        for k in ("pitch_range_st", "pitch_slope_st_s", "f0_std_st", "pitch_net_change_st",
                  "pitch_monotonicity", "pitch_continuity", "pitch_breaks_per_s",
                  "pitch_rate_st_s"):
            F[k] = 0.0
        F["voiced_runs"] = 0
    F["voiced_frames"] = int(voiced.sum())

    # ---- spectrum ----
    hop = int(round(hop_s * sr))
    mag, fq = stft_mag(x, sr, 1024, hop)
    m = min(len(mag), len(active))
    mag, act_s = mag[:m], active[:m]
    P = mag ** 2
    band = (fq >= 50) & (fq <= min(16000, sr / 2))
    Pb = P[:, band] + 1e-20
    cen = (P[:, band] @ fq[band]) / np.maximum(P[:, band].sum(axis=1), 1e-20)
    flat = np.exp(np.mean(np.log(Pb), axis=1)) / np.mean(Pb, axis=1)
    sel = act_s if act_s.sum() > 3 else np.ones(m, bool)
    F["centroid_mean"] = float(np.mean(cen[sel]))
    F["centroid_cv"] = float(np.std(np.log(cen[sel] + 1)) )
    F["flatness"] = float(np.median(flat[sel]))
    lm = np.log1p(100 * mag / (mag.max() + 1e-12))
    fl = np.concatenate([[0.0], np.sqrt((np.maximum(np.diff(lm, axis=0), 0) ** 2).sum(axis=1))])
    flv = fl[sel]
    F["flux_mean"] = float(np.mean(flv))
    F["flux_cv"] = float(np.std(flv) / max(np.mean(flv), 1e-9))
    F["spectral_abruptness"] = float(np.percentile(flv, 95) / max(np.median(flv), 1e-9))
    fb = mel_filterbank(sr, 1024)
    mf = mfcc_from_mag(mag, fb)
    F["mfcc_frame_var"] = float(np.mean(np.std(mf[sel], axis=0)))
    seg_len = max(1, int(round(0.25 / hop_s)))
    blocks = [mf[i:i + seg_len][sel[i:i + seg_len]] for i in range(0, m, seg_len)]
    blocks = [b.mean(axis=0) for b in blocks if len(b) >= 3]
    F["spectral_variability"] = float(np.mean(np.std(np.array(blocks), axis=0))) if len(blocks) > 1 else 0.0

    # ---- onsets / temporal ----
    pk_on, nov = onset_detect(mag, hop_s)
    pk_on = np.array([p for p in pk_on if p < len(active) and
                      (active[max(0, p - 1):p + 4].any())], dtype=int)
    on_t = pk_on * hop_s
    F["onsets_n"] = int(len(on_t))
    act_dur = max(float(active.sum()) * hop_s, 0.1)
    F["onset_rate"] = float(len(on_t) / max(dur, 1e-6))
    if len(on_t) >= 2:
        ioi = np.diff(on_t)
        F["ioi_median"] = float(np.median(ioi))
        F["ioi_cv"] = float(np.std(ioi) / max(np.mean(ioi), 1e-9))
        F["ioi_min"] = float(np.min(ioi))
    else:
        F["ioi_median"] = 0.0
        F["ioi_cv"] = 0.0
        F["ioi_min"] = 0.0
    if dur >= 1.5 and len(on_t) >= 3:
        cs, wl = [], 1.0
        for s0 in np.arange(0, dur - wl + 1e-9, 0.25):
            cs.append(np.sum((on_t >= s0) & (on_t < s0 + wl)))
        cs = np.array(cs, float)
        F["density_cv"] = float(np.std(cs) / max(np.mean(cs), 1e-9))
        half = dur / 2
        r1 = np.sum(on_t < half) / half
        r2 = np.sum(on_t >= half) / half
        F["density_trend"] = float((r2 - r1) / max((r1 + r2) / 2, 1e-9))
    else:
        F["density_cv"] = 0.0
        F["density_trend"] = 0.0
    # attack sharpness and decay per onset -> transient / impulsive character
    rises, imp = [], []
    for p in pk_on:
        a = max(0, p - 3)
        top = min(len(smooth) - 1, p + 4)
        pkv = float(np.max(env[p:top + 1])) if top >= p else float(env[p])
        rise = pkv - float(env[a])
        later = min(len(env) - 1, p + 15)
        decay = pkv - float(np.mean(env[min(later, len(env) - 1):min(later + 3, len(env))]))
        rises.append(rise)
        imp.append(sig(rise, 10, 3) * sig(decay, 12, 4))
    F["transient_strength_db"] = float(np.median(rises)) if rises else 0.0
    impulsive = float(np.mean(imp)) if imp else 0.0
    F["impulsive"] = impulsive
    F["perc_char"] = float(impulsive * (1 - 0.65 * sig(F["hnr_db"], 6, 3)))

    # ---- Praat-emulated segmentation (MDS Space Navigator) ----
    t_i, db_i = praat_intensity(x, sr, 100.0)
    mds_cfg = None
    for thr in (25.0, 20.0, 30.0, 35.0):
        for msil in (0.1, 0.06):
            segs = praat_silences(t_i, db_i, dur, thr, msil, 0.1)
            if len(segs) >= 3:
                mds_cfg = (thr, msil, segs)
                break
        if mds_cfg:
            break
    if mds_cfg is None:
        segs = praat_silences(t_i, db_i, dur, 25.0, 0.1, 0.1)
        mds_cfg = (25.0, 0.1, segs)
    thr, msil, segs = mds_cfg
    F["mds_thr_db"] = thr
    F["mds_min_silent"] = msil
    F["mds_segments"] = len(segs)
    F["mds_seg_median_dur"] = float(np.median([b - a for a, b in segs])) if segs else 0.0
    if len(segs) >= 2:
        gaps_m = [segs[i + 1][0] - segs[i][1] for i in range(len(segs) - 1)]
        F["mds_gap_median"] = float(np.median(gaps_m))
    else:
        F["mds_gap_median"] = 0.0
    if len(segs) >= 2:
        means, within = [], []
        for a, b in segs:
            ia, ib = int(a / hop_s), int(b / hop_s)
            blk = mf[ia:max(ib, ia + 1)]
            if len(blk):
                means.append(blk.mean(axis=0))
                within.append(np.mean(np.std(blk, axis=0)) if len(blk) > 1 else 0.0)
        means = np.array(means)
        if len(means) >= 2:
            dd = [np.linalg.norm(means[i] - means[j]) for i in range(len(means))
                  for j in range(i + 1, len(means))]
            F["mds_timbre_spread"] = float(np.mean(dd) / max(np.mean(within) + 1.0, 1e-9))
        else:
            F["mds_timbre_spread"] = 0.0
    else:
        F["mds_timbre_spread"] = 0.0

    # ---- Praat-emulated percussive events (Groove Creator) ----
    gcfg = None
    for othr in (-20.0, -25.0, -30.0):
        ev, cnt = groove_event_emulation(x, sr, othr, 0.05, 0.15)
        if len(ev) >= 3:
            gcfg = (othr, ev, cnt)
            break
    if gcfg is None:
        ev, cnt = groove_event_emulation(x, sr, -20.0, 0.05, 0.15)
        gcfg = (-20.0, ev, cnt)
    F["groove_onset_thr_db"] = gcfg[0]
    F["groove_events"] = len(gcfg[1])
    F["groove_bass"], F["groove_hh"], F["groove_snare"] = gcfg[2]
    F["groove_types"] = sum(1 for c in gcfg[2] if c > 0)

    # ---- Markov grain bookkeeping (script rule: nGrains >= 2k, dur >= 4 grains) ----
    F["markov_grains_80ms"] = int(math.floor((dur - 0.08) / 0.04) + 1) if dur > 0.08 else 0

    # keep arrays for parameter mapping (not reported)
    F["_per"] = 1 - aper
    F["_active"] = active
    F["_hop"] = hop_s
    return F


# ============================================================
# transformation scoring: eligibility + score + params
# ============================================================
def nz(v, default=0.0):
    return default if v is None or (isinstance(v, float) and math.isnan(v)) else v


def raw_scores(F):
    """Component scores (0..1) per transformation, before safeguards."""
    S, C = {}, {}
    # 1 Paulstretch - stable harmonic, sustained
    c = {
        "harmonic": sig(F["hnr_db"], 6, 3),
        "voiced": sig(F["voiced_ratio"], 0.6, 0.1),
        "pitch_stable": 1 - sig(F["f0_std_st"], 1.0, 0.4),
        "low_density": 1 - sig(F["onset_rate"], 2.0, 0.7),
        "sustained": 1 - sig(F["silence_ratio"], 0.25, 0.08),
        "no_glissando": 1 - sig(F["pitch_range_st"], 4, 1.2),
        "stable_envelope": 1 - sig(F["env_peak_rate"], 1.0, 0.35),
        "flat_dynamics": 1 - sig(F["env_dyn_range_db"], 9, 2.5),
    }
    w = {"harmonic": 1.2, "voiced": 1.0, "pitch_stable": 1.2, "low_density": 1.0,
         "sustained": 1.0, "no_glissando": 1.0, "stable_envelope": 0.8,
         "flat_dynamics": 1.0}
    S["paulstretch"], C["paulstretch"] = wmean(c, w), c
    # 2 Markov - noisy, aperiodic, timbrally varying, continuous
    c = {
        "flat_spectrum": sig(F["flatness"], 0.2, 0.06),
        "aperiodic": 1 - sig(F["hnr_db"], 3, 2.5),
        "unvoiced": 1 - sig(F["voiced_ratio"], 0.4, 0.12),
        "timbral_variation": sig(F["spectral_variability"], 1.0, 0.5),
        "continuous": 1 - sig(F["silence_ratio"], 0.3, 0.08),
    }
    w = {"flat_spectrum": 1.3, "aperiodic": 1.0, "unvoiced": 0.8,
         "timbral_variation": 0.8, "continuous": 1.0}
    S["markov"], C["markov"] = wmean(c, w), c
    # 3 MDS - discrete separable segments with distinct timbres
    c = {
        "segments": sig(F["mds_segments"], 3.5, 0.8),
        "separated": sig(F["silence_ratio"], 0.15, 0.06),
        "onset_density": sig(F["onset_rate"], 1.2, 0.5),
        "timbre_diff": sig(F["mds_timbre_spread"], 0.6, 0.25),
    }
    w = {"segments": 1.2, "separated": 1.0, "onset_density": 0.8, "timbre_diff": 0.8}
    S["mds"], C["mds"] = wmean(c, w), c
    # 4 Spiral - continuous voiced glissando
    c = {
        "pitch_range": sig(F["pitch_range_st"], 4, 1.2),
        "monotonic": sig(F["pitch_monotonicity"], 0.6, 0.1),
        "continuous": sig(F["pitch_continuity"], 0.6, 0.1),
        "voiced": sig(F["voiced_ratio"], 0.6, 0.1),
        "trend": sig(abs(F["pitch_net_change_st"]), 3, 1),
        "unfragmented": 1 - sig(F["pitch_breaks_per_s"], 1.0, 0.4),
    }
    w = {"pitch_range": 1.2, "monotonic": 1.0, "continuous": 1.0, "voiced": 0.8,
         "trend": 1.0, "unfragmented": 0.8}
    S["spiral"], C["spiral"] = wmean(c, w), c
    # 5 Metamodulator - complex dynamic envelope
    c = {
        "dynamic_range": sig(F["env_dyn_range_db"], 10, 3),
        "env_peaks": sig(F["env_peaks"], 3, 1),
        "fluctuation_rate": sig(F["env_peak_rate"], 0.8, 0.3),
        "env_complexity": sig(F["env_complexity"], 0.3, 0.12),
    }
    w = {"dynamic_range": 1.0, "env_peaks": 1.0, "fluctuation_rate": 0.8, "env_complexity": 1.0}
    S["metamod"], C["metamod"] = wmean(c, w), c
    # 6 Groove - percussive events with changing density
    c = {
        "percussive": sig(F["perc_char"], 0.45, 0.1),
        "events": sig(F["groove_events"], 4, 1.2),
        "onset_rate": sig(F["onset_rate"], 2.0, 0.8),
        "density_change": sig(max(F["density_cv"], abs(F["density_trend"])), 0.25, 0.08),
        "transients": sig(F["transient_strength_db"], 10, 3),
        "drum_classes": sig(F["groove_types"], 1.5, 0.3),
    }
    w = {"percussive": 1.3, "events": 1.0, "onset_rate": 0.8, "density_change": 0.8,
         "transients": 0.8, "drum_classes": 0.6}
    S["groove"], C["groove"] = wmean(c, w), c
    return S, C


def wmean(c, w):
    return sum(c[k] * w[k] for k in c) / sum(w[k] for k in c)


def eligibility(F):
    """Hard gates per transformation, mirroring each script's input needs.
    Returns {id: (ok, reason)}."""
    E = {}
    def gate(conds):
        bad = [msg for ok, msg in conds if not ok]
        return (len(bad) == 0, "; ".join(bad) if bad else "ok")
    E["paulstretch"] = gate([
        (F["duration"] >= 0.4, "phrase shorter than 0.4 s"),
        (F["voiced_ratio"] >= 0.35, "voiced ratio %.2f < 0.35" % F["voiced_ratio"]),
        (F["hnr_db"] >= 2.0, "harmonicity %.1f dB < 2" % F["hnr_db"]),
    ])
    E["markov"] = gate([
        (F["markov_grains_80ms"] >= 8, "fewer than 8 grains of 80 ms (script needs 2 x states)"),
        (F["flatness"] >= 0.05 or F["hnr_db"] < 6,
         "spectrum neither flat (%.2f) nor aperiodic (%.1f dB)" % (F["flatness"], F["hnr_db"])),
    ])
    E["mds"] = gate([
        (F["mds_segments"] >= 3,
         "Praat silence segmentation finds %d segment(s) < 3" % F["mds_segments"]),
        (F["mds_seg_median_dur"] >= 0.1, "segments too short for MFCC analysis"),
    ])
    E["spiral"] = gate([
        (F["voiced_frames"] >= 20, "no valid pitch trajectory (%d voiced frames)" % F["voiced_frames"]),
        (F["voiced_ratio"] >= 0.4, "voiced ratio %.2f < 0.4" % F["voiced_ratio"]),
        (F["pitch_range_st"] >= 2.0, "pitch range %.1f st < 2" % F["pitch_range_st"]),
        (F["pitch_continuity"] >= 0.4, "pitch contour fragmented (continuity %.2f)" % F["pitch_continuity"]),
    ])
    E["metamod"] = gate([
        (F["env_peaks"] >= 2, "fewer than 2 dynamic peaks"),
        (F["env_dyn_range_db"] >= 6, "dynamic range %.1f dB < 6" % F["env_dyn_range_db"]),
    ])
    E["groove"] = gate([
        (F["groove_events"] >= 3,
         "Groove Creator detector finds %d classified event(s) < 3" % F["groove_events"]),
        (F["perc_char"] >= 0.25, "not percussive enough (%.2f < 0.25)" % F["perc_char"]),
    ])
    return E


def score_all(F):
    """Raw scores -> cross-category safeguards -> eligibility mask."""
    S, C = raw_scores(F)
    notes = []
    # glissando must not read as stable harmonic material
    g = sig(F["pitch_range_st"], 5, 1.5) * sig(F["pitch_monotonicity"], 0.6, 0.1)
    if g > 0.05:
        S["paulstretch"] *= (1 - 0.5 * g)
        notes.append("paulstretch x%.2f (glissando safeguard)" % (1 - 0.5 * g))
    # noisy percussion must not read as a continuous noise texture
    pc = F["perc_char"]
    S["markov"] *= (1 - 0.6 * pc)
    if pc > 0.05:
        notes.append("markov x%.2f (percussive safeguard)" % (1 - 0.6 * pc))
    # tonal attack sequences belong to MDS more than to the drum classifier
    S["mds"] *= (1 - 0.5 * pc)
    if pc > 0.05:
        notes.append("mds x%.2f (percussive events prefer Groove)" % (1 - 0.5 * pc))
    # the envelope category yields to a strongly supported, ELIGIBLE
    # specific category
    E = eligibility(F)
    others = [v for k, v in S.items() if k != "metamod" and E[k][0]]
    other = max(others) if others else 0.0
    dom = 1 - 0.45 * sig(other, 0.6, 0.08)
    S["metamod"] *= dom
    if dom < 0.98:
        notes.append("metamod x%.2f (an eligible specific category scores %.2f)" % (dom, other))
    return S, C, E, notes


def decide(F, forced=None):
    S, C, E, notes = score_all(F)
    ranking = [k for k in TRANSFORM_IDS if E[k][0] and S[k] >= CONFIDENCE_THRESHOLD[k]]
    ranking.sort(key=lambda k: (-round(S[k], 6), TIE_PRIORITY.index(k)))
    info = {"scores": S, "components": C, "elig": E, "notes": notes, "ranking": ranking}
    if forced and forced in TRANSFORM_IDS:
        info["mode"] = "manual"
        info["selected"] = forced
        if not E[forced][0]:
            info["warning"] = "manual choice is INELIGIBLE: " + E[forced][1]
    else:
        info["mode"] = "auto"
        info["selected"] = ranking[0] if ranking else "passthrough"
    if len(ranking) >= 2 and S[ranking[0]] - S[ranking[1]] < AMBIGUITY_MARGIN:
        info["ambiguous"] = "%s %.3f vs %s %.3f" % (ranking[0], S[ranking[0]],
                                                    ranking[1], S[ranking[1]])
    return info


# ---------------- parameter mapping ----------------
def params_all(F, audio, sr, nch, seed):
    P = {}
    dur = F["duration"]
    # 1 Paulstretch: stability -> stretch, response length capped
    stab = 0.5 * (sig(F["hnr_db"], 6, 3) + (1 - sig(F["f0_std_st"], 1.0, 0.4)))
    stretch = 2.0 + 4.0 * stab
    crop = (0.0, dur)
    if dur * stretch > MAX_RESPONSE_S:
        stretch = max(2.0, MAX_RESPONSE_S / dur)
        if dur * stretch > MAX_RESPONSE_S + 1e-6:
            crop = most_stable_window(F, MAX_RESPONSE_S / stretch)
    f0m = nz(F["f0_median"], 200.0)
    P["paulstretch"] = {
        "stretch": round(stretch, 3),
        "window": 0.35 if f0m < 110 else 0.25,
        "overlap": 75,
        "stereo": 1,
        "phase_offset": 0.3,
        "crop_start": round(crop[0], 4),
        "crop_end": round(crop[1], 4),
        "expected_out_s": round((crop[1] - crop[0]) * stretch, 2),
    }
    # 2 Markov: spectral variability -> states, flux changes -> grain
    g_ms = clamp(110 - 30 * sig(F["flux_cv"], 1.0, 0.4), 50, 140)
    k = int(round(4 + 4 * sig(F["spectral_variability"], 1.0, 0.5)))
    n_gr = math.floor((dur - g_ms / 1000) / (g_ms / 1000 * 0.5)) + 1 if dur > g_ms / 1000 else 0
    while k > 2 and n_gr < 2 * k:
        k -= 1
    if dur < 4 * g_ms / 1000:
        g_ms = clamp(dur / 4 * 1000 * 0.95, 20, 140)
    P["markov"] = {
        "grain_ms": round(g_ms, 1),
        "analysis_overlap": 0.5,
        "states": k,
        "randomness": round(clamp(0.1 + 0.3 * sig(F["centroid_cv"], 0.2, 0.08), 0.1, 0.4), 3),
        "out_dur": round(clamp(1.25 * dur, 4.0, MAX_RESPONSE_S), 2),
        "synth_overlap": 0.5,
        "varispeed": 0.0,
        "jitter": 0.1,
        "density_var": round(clamp(0.25 * F["density_cv"], 0.0, 0.3), 3),
        "decorrelation": 0.3 if nch >= 1 else -1,
        "seed": seed,
        "grains_available": n_gr,
    }
    # 3 MDS: segmentation emulated in Python with the script's own rules
    segd = F["mds_seg_median_dur"] or 0.2
    gap = F["mds_gap_median"] or 0.1
    P["mds"] = {
        "silence_threshold_db": F["mds_thr_db"],
        "min_silent": F["mds_min_silent"],
        "min_sounding": 0.1,
        "max_formant": 5500,
        "n_formants": 5,
        "n_mfcc": 12,
        "between": round(clamp(0.5 * gap, 0.03, 0.2), 3),
        "expected_segments": F["mds_segments"],
        "segment_median_s": round(segd, 3),
    }
    # 4 Spiral: range -> semitones, movement rate -> acceleration, length -> spirals
    fl = nz(F["f0_p5"], 80.0)
    fh = nz(F["f0_p95"], 600.0)
    floor_p = clamp(0.7 * fl, 50.0, 400.0)
    ceil_p = clamp(1.5 * fh, floor_p * 2, min(1200.0, 0.45 * sr - 1))
    P["spiral"] = {
        "spirals": int(clamp(round(1 + dur / 3.0), 1, 3)),
        "semitones": round(clamp(F["pitch_range_st"], 3.0, 12.0), 2),
        "acceleration": round(clamp(1 + F["pitch_rate_st_s"] / 30.0, 1.0, 2.0), 3),
        "time_step": 0.005,
        "floor": round(floor_p, 1),
        "ceiling": round(ceil_p, 1),
    }
    # 5 Metamodulator: Manual Sinusoidal FM; envelope chooses its settings
    if F["voiced_ratio"] >= 0.4 and not math.isnan(nz(F["f0_median"], float("nan"))):
        carrier = clamp(F["f0_median"], 80.0, 600.0)
    else:
        carrier = clamp(F["centroid_mean"] / 8.0, 100.0, 500.0)
    cx = sig(F["env_complexity"], 0.5, 0.2)
    P["metamod"] = {
        "carrier": round(carrier, 2),
        "start_freq": 100,
        "end_freq": 800,
        "depth_hz": round(carrier * (0.2 + 0.8 * cx), 2),
        "rate_hz": round(clamp(F["env_peak_rate"], 0.5, 8.0), 3),
        "dry_wet": round(15 + 45 * sig(F["env_dyn_range_db"], 12, 4), 1),
        "safety": 0.99,
    }
    # 6 Groove: IOIs -> tempo (with documented fallback), density -> groove
    tempo, reliable = estimate_tempo(F)
    beat = 60.0 / tempo
    bars = min((1, 2, 4), key=lambda b: abs(b * 4 * beat - dur))
    dt, dcv = F["density_trend"], F["density_cv"]
    if F["onset_rate"] < 1.0:
        pattern = "Sparse Minimal"
    elif dt > 0.5:
        pattern = "Double-time Feel"
    elif dt < -0.5:
        pattern = "Half-time Feel"
    elif dcv > 0.6:
        pattern = "Breakbeat"
    elif F["ioi_cv"] > 0.5:
        pattern = "Syncopated Funk"
    else:
        pattern = "Standard 4/4"
    P["groove"] = {
        "bars": bars,
        "pattern": pattern,
        "tempo": round(tempo, 2),
        "tempo_reliable": int(reliable),
        "onset_thr_db": F["groove_onset_thr_db"],
        "min_silence": round(clamp(0.5 * F["ioi_min"], 0.03, 0.08) if F["ioi_min"] > 0 else 0.05, 3),
        "max_segment": 0.15,
        "density": round(clamp(0.35 + 0.08 * F["onset_rate"], 0.3, 0.9), 3),
        "clip_max": 0.12,
        "attack": 0.002,
        "release": 0.05,
        "shape": 1.2,
        "stereo": 1,
    }
    return P


def estimate_tempo(F):
    """Median IOI folded into 80-160 BPM. Unreliable -> 100 BPM fallback."""
    if F["onsets_n"] >= 4 and F["ioi_median"] > 0 and F["ioi_cv"] <= 0.6:
        bpm = 60.0 / F["ioi_median"]
        while bpm < 80:
            bpm *= 2
        while bpm >= 160:
            bpm /= 2
        return bpm, True
    return 100.0, False


def most_stable_window(F, length):
    import numpy as np
    per = F["_per"]
    act = F["_active"][:len(per)]
    hop = F["_hop"]
    w = max(1, int(round(length / hop)))
    score = per[:len(act)] * act
    if len(score) <= w:
        return (0.0, F["duration"])
    cs = np.concatenate([[0], np.cumsum(score)])
    best = int(np.argmax(cs[w:] - cs[:-w]))
    return (best * hop, min(F["duration"], best * hop + length))


def audio_seed(audio):
    import numpy as np
    b = np.ascontiguousarray(audio, dtype=np.float32).tobytes()
    return 1 + (zlib.crc32(b) % 2000000000)


# ============================================================
# phrase detection (pure state machine, testable without hardware)
# ============================================================
class PhraseDetector:
    """IDLE -> (calibrate) -> LISTENING -> PHRASE -> done.
    Feed blocks of exactly `hop` frames.  Hysteresis: onset needs
    `on_frames` consecutive frames above floor + sensitivity; the phrase
    stays alive while frames exceed (onset threshold - hysteresis);
    `end_silence` of continuous quiet ends it; phrases shorter than
    `min_phrase` are discarded as false triggers."""

    def __init__(self, sr, channels, sensitivity_db=9.0, min_phrase=0.5,
                 end_silence=0.6, max_phrase=12.0, preroll=0.25, hop_s=0.01,
                 calib_s=0.5, hysteresis_db=4.0, abs_min_db=-65.0):
        import numpy as np
        self.np = np
        self.sr, self.ch = sr, channels
        self.hop = int(round(hop_s * sr))
        self.hop_s = self.hop / sr
        self.sens, self.hyst, self.abs_min = sensitivity_db, hysteresis_db, abs_min_db
        self.min_phrase, self.end_silence, self.max_phrase = min_phrase, end_silence, max_phrase
        self.pre_n = max(1, int(round(preroll / self.hop_s)))
        self.calib_n = max(1, int(round(calib_s / self.hop_s)))
        self.on_frames = 3
        self.state = "CALIBRATING"
        self.calib = []
        self.floor = None
        self.pre = []
        self.buf = []
        self.above = 0
        self.frames_in = 0
        self.silent_run = 0
        self.last_active = 0
        self.start_active = 0
        self.false_triggers = 0
        self.digital_silence = True
        self.ended_by = ""
        self.peak_db = -200.0

    def thresholds(self):
        on = max(self.floor + self.sens, self.abs_min)
        return on, on - self.hyst

    def feed(self, block):
        np = self.np
        self.frames_in += 1
        mono = block.mean(axis=1) if block.ndim == 2 else block
        e = float(np.sqrt(np.mean(mono.astype(np.float64) ** 2) + 1e-20))
        db = 20 * math.log10(e + 1e-12)
        if e > 1e-7:
            self.digital_silence = False
        if self.state == "CALIBRATING":
            self.calib.append(db)
            self.pre.append(block)
            self.pre = self.pre[-self.pre_n:]
            if len(self.calib) >= self.calib_n:
                self.floor = float(np.percentile(self.calib, 30))
                self.state = "LISTENING"
            return None
        if self.state == "LISTENING":
            on, _ = self.thresholds()
            if db > on:
                self.above += 1
                self.pre.append(block)
                if self.above >= self.on_frames:
                    self.state = "PHRASE"
                    keep = self.pre_n + self.above
                    self.buf = list(self.pre[-keep:])
                    self.pre = []
                    self.start_active = len(self.buf) - self.above
                    self.last_active = len(self.buf) - 1
                    self.silent_run = 0
                    self.peak_db = db
                    return "onset"
            else:
                self.above = 0
                # adaptive floor: rises slowly, falls quickly
                a = 0.03 if db > self.floor else 0.2
                self.floor += a * (db - self.floor)
                self.pre.append(block)
            self.pre = self.pre[-(self.pre_n + self.on_frames):]
            return None
        if self.state == "PHRASE":
            self.buf.append(block)
            _, off = self.thresholds()
            if db > off:
                self.last_active = len(self.buf) - 1
                self.silent_run = 0
                self.peak_db = max(self.peak_db, db)
            else:
                self.silent_run += 1
            active_len = (self.last_active - self.start_active + 1) * self.hop_s
            total_len = (len(self.buf) - self.start_active) * self.hop_s
            if self.silent_run * self.hop_s >= self.end_silence:
                if active_len < self.min_phrase:
                    self.false_triggers += 1
                    self.state = "LISTENING"
                    self.pre = self.buf[-self.pre_n:]
                    self.buf = []
                    self.above = 0
                    return "discarded"
                self.ended_by = "silence"
                self.state = "DONE"
                return "end"
            if total_len >= self.max_phrase:
                self.ended_by = "max_duration"
                self.state = "DONE"
                return "end"
        return None

    def phrase_audio(self, tail_s=0.15):
        np = self.np
        tail = int(round(tail_s / self.hop_s))
        end = min(len(self.buf), self.last_active + 1 + tail)
        return np.concatenate(self.buf[:end], axis=0)

    def silence_frames_after_last_active(self):
        return len(self.buf) - 1 - self.last_active


# ============================================================
# reports
# ============================================================
REPORT_KEYS = [
    ("duration", "s"), ("active_ratio", ""), ("hnr_db", "dB"), ("periodicity", ""),
    ("voiced_ratio", ""), ("f0_median", "Hz"), ("f0_std_st", "st"),
    ("pitch_range_st", "st"), ("pitch_slope_st_s", "st/s"), ("pitch_net_change_st", "st"),
    ("pitch_monotonicity", ""), ("pitch_continuity", ""), ("pitch_breaks_per_s", "/s"),
    ("centroid_mean", "Hz"), ("centroid_cv", ""), ("flatness", ""), ("flux_mean", ""),
    ("flux_cv", ""), ("spectral_variability", ""), ("spectral_abruptness", ""),
    ("env_dyn_range_db", "dB"), ("env_peaks", ""), ("env_peak_rate", "/s"),
    ("env_complexity", "dB/fr"), ("energy_slope_db_s", "dB/s"),
    ("onsets_n", ""), ("onset_rate", "/s"), ("ioi_median", "s"), ("ioi_cv", ""),
    ("density_cv", ""), ("density_trend", ""), ("transient_strength_db", "dB"),
    ("impulsive", ""), ("perc_char", ""), ("silence_ratio", ""), ("silent_gaps_n", ""),
    ("mds_segments", ""), ("mds_timbre_spread", ""), ("groove_events", ""),
    ("groove_types", ""), ("markov_grains_80ms", ""),
]


def morphology_line(F):
    e = "rising" if F["energy_slope_db_s"] > 2 else "falling" if F["energy_slope_db_s"] < -2 else "level"
    d = ("accelerating" if F["density_trend"] > 0.3 else
         "decelerating" if F["density_trend"] < -0.3 else "steady")
    p = ("rising" if F["pitch_net_change_st"] > 2 else
         "falling" if F["pitch_net_change_st"] < -2 else "stable") if F["voiced_frames"] >= 20 else "unpitched"
    s = "abrupt" if F["spectral_abruptness"] > 4 else "gradual"
    return "energy %s | density %s | pitch %s | spectral change %s" % (e, d, p, s)


def build_report(F, info, P, header=""):
    L = []
    if header:
        L.append(header)
    L.append("-- Features --")
    row = []
    for k, u in REPORT_KEYS:
        v = F.get(k)
        s = ("%d" % v) if isinstance(v, int) else fnum(v, 3)
        row.append("%s %s%s" % (k, s, (" " + u) if u else ""))
        if len(row) == 3:
            L.append("  " + "   ".join(row))
            row = []
    if row:
        L.append("  " + "   ".join(row))
    L.append("  morphology: " + morphology_line(F))
    L.append("-- Scores (threshold) / eligibility --")
    for k in TRANSFORM_IDS:
        ok, why = info["elig"][k]
        comp = " ".join("%s=%.2f" % (a, b) for a, b in info["components"][k].items())
        L.append("  %-11s %.3f (%.2f)  %s" % (k, info["scores"][k], CONFIDENCE_THRESHOLD[k],
                                              "eligible" if ok else "REJECTED: " + why))
        L.append("      " + comp)
    for n in info["notes"]:
        L.append("  safeguard: " + n)
    below = [k for k in TRANSFORM_IDS if info["elig"][k][0] and k not in info["ranking"]]
    for k in below:
        L.append("  rejected %s: score below confidence threshold" % k)
    L.append("-- Decision --")
    L.append("  mode %s -> %s" % (info["mode"], info["selected"]))
    if info["selected"] == "passthrough":
        L.append("  no candidate reached its threshold: the phrase is returned untransformed")
    if "ambiguous" in info:
        L.append("  AMBIGUOUS: " + info["ambiguous"])
    if "warning" in info:
        L.append("  WARNING: " + info["warning"])
    if info["selected"] in P:
        L.append("  params: " + " ".join("%s=%s" % kv for kv in P[info["selected"]].items()))
    return "\n".join(L) + "\n"


def decision_pairs(F, info, P, extra):
    pairs = list(extra)
    pairs += [("mode", info["mode"]), ("selected", info["selected"]),
              ("selected_score", fnum(info["scores"].get(info["selected"], 0.0), 4)),
              ("ranking", ",".join(info["ranking"]))]
    if "ambiguous" in info:
        pairs.append(("ambiguous", info["ambiguous"]))
    if "warning" in info:
        pairs.append(("warning", info["warning"]))
    for k in TRANSFORM_IDS:
        pairs.append(("score_" + k, fnum(info["scores"][k], 4)))
        pairs.append(("eligible_" + k, 1 if info["elig"][k][0] else 0))
        pairs.append(("reason_" + k, info["elig"][k][1]))
        for name, v in P[k].items():
            pairs.append(("p_%s_%s" % (k, name), v))
    pairs.append(("morphology", morphology_line(F)))
    return pairs


def analyse_and_write(audio, sr, args, extra, t_end_epoch=None, detect_delay=None):
    t0 = time.perf_counter()
    F = extract_features(audio, sr)
    t1 = time.perf_counter()
    forced = None if args.force in ("", "auto") else args.force
    info = decide(F, forced)
    nch = 1 if audio.ndim == 1 else audio.shape[1]
    seed = audio_seed(audio)
    P = params_all(F, audio, sr, nch, seed)
    t2 = time.perf_counter()
    rep = build_report(F, info, P, "Cycle %s - %s, %.2f s, %d Hz, %d ch" %
                       (args.cycle, extra[0][1] if extra else "", F["duration"], sr, nch))
    rep += "-- Timing --\n  features %.3f s   selection %.3f s\n" % (t1 - t0, t2 - t1)
    if detect_delay is not None:
        rep += "  phrase-end detection delay %.3f s\n" % detect_delay
    sess = args.session
    rep_path = os.path.join(sess, "report_%03d.txt" % int(args.cycle))
    write_text_atomic(rep_path, rep)
    pairs = [("status", "ok"), ("message", "ok")] + list(extra) + [
        ("duration", fnum(F["duration"], 4)), ("sr", sr), ("channels", nch),
        ("seed", seed), ("report", rep_path),
        ("t_features", fnum(t1 - t0, 4)), ("t_select", fnum(t2 - t1, 4)),
    ]
    if t_end_epoch is not None:
        pairs.append(("t_phrase_end_epoch", "%.4f" % t_end_epoch))
    if detect_delay is not None:
        pairs.append(("t_detect_delay", fnum(detect_delay, 4)))
    pairs = decision_pairs(F, info, P, pairs)
    pairs.append(("t_written_epoch", "%.4f" % time.time()))
    pairs.append(("t_py_runtime", fnum(time.perf_counter() - T_PROCESS_START, 4)))
    write_kv_atomic(decision_path(args), pairs)
    return F, info, P


def decision_path(args):
    return os.path.join(args.session, "decision_%03d.txt" % int(args.cycle))


def write_status(args, status, message, extra=()):
    pairs = [("status", status), ("message", message)] + list(extra)
    pairs.append(("t_py_runtime", fnum(time.perf_counter() - T_PROCESS_START, 4)))
    write_kv_atomic(decision_path(args), pairs)


# ============================================================
# commands
# ============================================================
def cmd_probe(args):
    found, missing = [], []
    mods = ["numpy", "scipy", "soundfile"] + (["sounddevice"] if args.live else [])
    for m in mods:
        try:
            __import__(m)
            found.append(m)
        except Exception as ex:                          # noqa: BLE001
            missing.append("%s (%s)" % (m, str(ex).split("\n")[0][:80]))
    pairs = [("status", "ok" if not missing else "missing"),
             ("python", sys.executable), ("version", sys.version.split()[0]),
             ("found", " ".join(found)), ("missing", "; ".join(missing))]
    write_kv_atomic(args.out, pairs)
    return 0


def cmd_devices(args):
    try:
        import sounddevice as sd
        lines = []
        default_in = sd.default.device[0] if sd.default.device else None
        for i, d in enumerate(sd.query_devices()):
            if d["max_input_channels"] > 0:
                lines.append("%s%3d  %-40s in:%d  %d Hz" % (
                    "*" if i == default_in else " ", i, d["name"][:40],
                    d["max_input_channels"], int(d["default_samplerate"])))
        text = "Audio input devices (* = default):\n" + "\n".join(lines) + "\n"
        text += ("\nEnter the index or part of the name in the Input_device field, "
                 "or 'default'.\n")
        status = "ok"
    except Exception as ex:                              # noqa: BLE001
        text = "Could not query audio devices: %s\n" % ex
        status = "error"
    write_text_atomic(args.out, text)
    return 0 if status == "ok" else 1


def resolve_device(sd, spec):
    spec = (spec or "").strip()
    if spec == "" or spec.lower() == "default":
        return None
    if spec.lstrip("-").isdigit():
        return int(spec)
    hits = [i for i, d in enumerate(sd.query_devices())
            if d["max_input_channels"] > 0 and spec.lower() in d["name"].lower()]
    if not hits:
        raise RuntimeError("no input device matches '%s' (run 'List audio input devices')" % spec)
    return hits[0]


def cmd_listen(args):
    try:
        np = import_dsp()
        import soundfile as sf
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "missing Python package: %s" % ex)
        return 1
    try:
        import sounddevice as sd
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "sounddevice/PortAudio unavailable: %s" % ex)
        return 1
    import queue
    q = queue.Queue()
    det = PhraseDetector(int(args.sr), int(args.channels), args.sensitivity,
                         args.min_phrase, args.end_silence, args.max_phrase,
                         args.preroll)
    overflow = [0]

    def cb(indata, frames, tinfo, status):
        if status:
            overflow[0] += 1
        q.put((indata.copy(), time.time()))

    try:
        dev = resolve_device(sd, args.device)
        stream = sd.InputStream(samplerate=int(args.sr), channels=int(args.channels),
                                dtype="float32", blocksize=det.hop, device=dev,
                                callback=cb)
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "cannot open audio input: %s" % ex)
        return 1
    t_open = time.time()
    t_onset = None
    pending = np.zeros((0, int(args.channels)), dtype=np.float32)
    result = None
    t_end_epoch = None
    t_last_block = t_open
    try:
        with stream:
            while True:
                try:
                    block, tb = q.get(timeout=0.5)
                except queue.Empty:
                    if time.time() - t_open > 5 and det.frames_in == 0:
                        write_status(args, "error", "audio input delivers no data")
                        return 1
                    continue
                t_last_block = tb
                pending = np.concatenate([pending, block], axis=0)
                while len(pending) >= det.hop:
                    ev = det.feed(pending[:det.hop])
                    pending = pending[det.hop:]
                    if ev == "onset":
                        t_onset = tb
                    elif ev == "end":
                        result = det.phrase_audio()
                        t_end_epoch = tb - det.silence_frames_after_last_active() * det.hop_s
                        break
                if result is not None:
                    break
                waited = tb - t_open
                if det.state in ("CALIBRATING", "LISTENING") and waited > args.timeout:
                    if det.digital_silence:
                        write_status(args, "silent_input",
                                     "input was digital silence for %.0f s - check the "
                                     "microphone permission / device" % waited)
                    else:
                        write_status(args, "timeout",
                                     "no phrase within %.0f s (noise floor %.1f dBFS, "
                                     "false triggers %d)" % (waited, det.floor or -200,
                                                             det.false_triggers))
                    return 0
    except KeyboardInterrupt:
        write_status(args, "error", "capture interrupted by the user")
        return 1
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "capture failed: %s" % ex)
        return 1
    t_final = time.time()
    detect_delay = t_final - t_end_epoch
    wav = os.path.join(args.session, "q_%03d.wav" % int(args.cycle))
    audio = result if int(args.channels) > 1 else result[:, 0]
    sf.write(wav, audio, int(args.sr), subtype="FLOAT")
    extra = [("source", "live microphone"), ("wav", wav),
             ("ended_by", det.ended_by), ("false_triggers", det.false_triggers),
             ("noise_floor_dbfs", fnum(det.floor, 1)),
             ("onset_threshold_dbfs", fnum(det.thresholds()[0], 1)),
             ("input_overflows", overflow[0])]
    try:
        analyse_and_write(audio.astype(np.float64), int(args.sr), args, extra,
                          t_end_epoch, detect_delay)
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "analysis failed: %s" % ex, [("wav", wav)])
        return 1
    return 0


def cmd_analyze(args):
    try:
        np = import_dsp()
        import soundfile as sf
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "missing Python package: %s" % ex)
        return 1
    try:
        audio, sr = sf.read(args.input, dtype="float64", always_2d=False)
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "cannot read %s: %s" % (args.input, ex))
        return 1
    if audio.ndim == 2 and audio.shape[1] == 1:
        audio = audio[:, 0]
    dur = len(audio) / sr
    if dur < 0.25:
        write_status(args, "error", "phrase too short (%.3f s < 0.25 s)" % dur)
        return 1
    if float(np.max(np.abs(audio))) < 1e-6:
        write_status(args, "silent_input", "the selected Sound is silent")
        return 0
    try:
        analyse_and_write(audio, int(sr), args, [("source", "selected Sound"),
                                                 ("wav", args.input)])
    except Exception as ex:                              # noqa: BLE001
        import traceback
        write_status(args, "error", "analysis failed: %s | %s" %
                     (ex, traceback.format_exc().replace("\n", " | ")[-400:]))
        return 1
    return 0


def safe_session_dir(path):
    base = os.path.basename(os.path.normpath(path))
    return base.startswith(SESSION_PREFIX) and os.path.isdir(path)


def cmd_cleanup(args):
    if safe_session_dir(args.session):
        shutil.rmtree(args.session, ignore_errors=True)
    return 0


def cmd_cleanup_stale(args):
    now = time.time()
    try:
        for name in os.listdir(args.base):
            p = os.path.join(args.base, name)
            if name.startswith(SESSION_PREFIX) and os.path.isdir(p):
                if now - os.path.getmtime(p) > 12 * 3600:
                    shutil.rmtree(p, ignore_errors=True)
    except Exception:                                    # noqa: BLE001
        pass
    return 0


# ============================================================
# self-test: six synthetic gestures + phrase-detector stream test
# ============================================================
def synth_cases(sr=44100):
    import numpy as np
    rng = np.random.default_rng(7)
    def harm(f, n=8, roll=0.7):
        return sum((roll ** k) * np.sin(2 * np.pi * (k + 1) * f) for k in range(n))
    cases = {}
    # 1 stable harmonic tone with gentle vibrato
    d = 3.0
    t = np.arange(int(d * sr)) / sr
    ph = np.cumsum(220 * (1 + 0.004 * np.sin(2 * np.pi * 5 * t))) / sr
    env = np.minimum(1, t / 0.15) * np.minimum(1, (d - t) / 0.3)
    cases["paulstretch"] = 0.3 * env * harm(ph) / 2.5
    # 2 broadband noise with a slowly wandering band (timbral variation)
    import scipy.signal as ss
    n = rng.standard_normal(int(d * sr))
    out = np.zeros_like(n)
    blk = int(0.25 * sr)
    for i in range(0, len(n), blk):
        fc = 500 + 5000 * rng.random()
        b, a = ss.butter(2, [fc / (sr / 2) * 0.5, min(0.95, fc / (sr / 2) * 2.5)], "band")
        out[i:i + blk] = ss.lfilter(b, a, n[i:i + blk])
    out = 0.6 * out + 0.4 * n
    cases["markov"] = 0.25 * out / np.max(np.abs(out)) * np.minimum(1, t / 0.1) * np.minimum(1, (d - t) / 0.2)
    # 3 tonal plucks, different pitches and timbres, separated by silence
    x = np.zeros(int(3.6 * sr))
    pos = 0.05
    for i, (f, roll) in enumerate([(196, 0.5), (523, 0.8), (330, 0.3), (784, 0.7),
                                   (262, 0.9), (440, 0.4)]):
        L = int(0.32 * sr)
        tt = np.arange(L) / sr
        note = harm(f * tt, 10, roll) * np.exp(-tt * 9) * np.minimum(1, tt / 0.004)
        a = int(pos * sr)
        x[a:a + L] += 0.35 * note / np.max(np.abs(note))
        pos += 0.58
    cases["mds"] = x
    # 4 continuous glissando 200 -> 650 Hz
    d = 3.0
    t = np.arange(int(d * sr)) / sr
    f = 200 * (650 / 200) ** (t / d)
    ph = np.cumsum(f) / sr
    cases["spiral"] = 0.3 * np.minimum(1, t / 0.1) * np.minimum(1, (d - t) / 0.2) * harm(ph, 6, 0.6) / 2.2
    # 5 inharmonic sustained cluster with irregular swells (complex envelope)
    d = 4.0
    t = np.arange(int(d * sr)) / sr
    parts = [173 * r for r in (1.0, 1.618, 2.414, 3.303, 4.732, 6.171)]
    tone = sum(np.sin(2 * np.pi * p * t + k) / (k + 1) for k, p in enumerate(parts))
    sw = np.zeros_like(t)
    for c, w, a in [(0.3, 0.15, 1.0), (0.9, 0.1, 0.5), (1.4, 0.25, 0.9), (2.1, 0.08, 0.6),
                    (2.6, 0.2, 1.0), (3.2, 0.12, 0.4), (3.6, 0.15, 0.8)]:
        sw += a * np.exp(-0.5 * ((t - c) / w) ** 2)
    cases["metamod"] = 0.3 * tone / np.max(np.abs(tone)) * (0.03 + sw / sw.max())
    # 6 drum-like sequence, accelerating
    d = 4.0
    x = np.zeros(int(d * sr))
    times = list(np.cumsum([0.05] + [0.5] * 3 + [0.3] * 4 + [0.18] * 7 + [0.12] * 6))
    kinds = ["k", "h", "s", "h", "k", "h", "s", "h", "k", "h", "s", "h", "k", "h", "s",
             "h", "k", "h", "s", "h", "k", "s"]
    for tm, kd in zip(times, kinds):
        if tm > d - 0.2:
            break
        L = int(0.2 * sr)
        tt = np.arange(L) / sr
        if kd == "k":
            s = np.sin(2 * np.pi * np.cumsum(120 * np.exp(-tt * 25) + 45) / sr) * np.exp(-tt * 18)
        elif kd == "s":
            nn = rng.standard_normal(L)
            b, a = ss.butter(2, [800 / (sr / 2), 3500 / (sr / 2)], "band")
            s = 0.7 * ss.lfilter(b, a, nn) * np.exp(-tt * 22) + 0.4 * np.sin(2 * np.pi * 190 * tt) * np.exp(-tt * 30)
        else:
            nn = rng.standard_normal(L)
            b, a = ss.butter(4, 6000 / (sr / 2), "high")
            s = ss.lfilter(b, a, nn) * np.exp(-tt * 60)
        s = s / np.max(np.abs(s))
        a0 = int(tm * sr)
        x[a0:a0 + L] += 0.4 * s[:max(0, min(L, len(x) - a0))]
    cases["groove"] = x
    return cases


def detector_stream_test(sr=44100):
    """Feed the PhraseDetector a synthetic stream: room noise, a click
    (false trigger), a phrase with an internal 0.3 s pause, then silence."""
    import numpy as np
    rng = np.random.default_rng(3)
    hop = int(0.01 * sr)
    noise = lambda s: 0.002 * rng.standard_normal(int(s * sr))
    t = np.arange(int(1.2 * sr)) / sr
    tone = 0.2 * np.sin(2 * np.pi * 330 * t)
    burst = 0.15 * rng.standard_normal(int(0.15 * sr))   # 150 ms knock: onset, too short
    click = np.zeros(int(0.05 * sr))
    click[:int(0.01 * sr)] = 0.3                         # 10 ms click: never an onset
    stream = np.concatenate([noise(1.0), click + noise(0.05), noise(0.8),
                             burst + noise(0.15), noise(1.0),
                             tone[:int(0.8 * sr)] + noise(0.8), noise(0.3),
                             tone[:int(0.7 * sr)] + noise(0.7), noise(1.5)])
    det = PhraseDetector(sr, 1, 9.0, 0.5, 0.6, 12.0, 0.25)
    events = []
    for i in range(0, len(stream) - hop, hop):
        ev = det.feed(stream[i:i + hop])
        if ev:
            events.append((ev, round(i / sr, 2)))
        if ev == "end":
            break
    ph = det.phrase_audio()
    # expected: click ignored, knock = onset + discarded, phrase with its
    # internal 0.3 s pause kept whole (0.25 pre-roll + 1.8 s + 0.15 tail)
    ok = ([e[0] for e in events] == ["onset", "discarded", "onset", "end"]
          and det.false_triggers == 1 and 2.0 < len(ph) / sr < 2.4)
    return ok, events, len(ph) / sr, det


def cmd_self_test(args):
    np = import_dsp()
    import soundfile as sf
    sr = 44100
    cases = synth_cases(sr)
    failures = 0
    print("=" * 72)
    print("AudioTools Call & Response %s - self-test (synthetic, in memory)" % VERSION)
    print("=" * 72)

    class A:
        force = "auto"
    for expected, audio in cases.items():
        t0 = time.perf_counter()
        F = extract_features(audio, sr)
        t1 = time.perf_counter()
        info = decide(F)
        P = params_all(F, audio, sr, 1, audio_seed(audio))
        t2 = time.perf_counter()
        got = info["selected"]
        status = "OK " if got == expected else "FAIL"
        if got != expected:
            failures += 1
        print("\n[%s] case '%s' -> selected '%s'   (features %.2f s, select %.3f s)" %
              (status, expected, got, t1 - t0, t2 - t1))
        print(build_report(F, info, P).rstrip())
        if args.write_dir:
            os.makedirs(args.write_dir, exist_ok=True)
            sf.write(os.path.join(args.write_dir, "selftest_%s.wav" % expected),
                     audio.astype(np.float32), sr, subtype="FLOAT")
    ok, events, plen, det = detector_stream_test(sr)
    print("\n[%s] phrase detector stream test: events %s, phrase %.2f s, floor %.1f dBFS" %
          ("OK " if ok else "FAIL", events, plen, det.floor))
    if not ok:
        failures += 1
    print("\n%d failure(s)" % failures)
    return 1 if failures else 0


# ============================================================
def main(argv=None):
    ap = argparse.ArgumentParser(description="AudioTools Call & Response engine")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("probe")
    p.add_argument("--out", required=True)
    p.add_argument("--live", action="store_true")
    p = sub.add_parser("devices")
    p.add_argument("--out", required=True)
    for name in ("listen", "analyze"):
        p = sub.add_parser(name)
        p.add_argument("--session", required=True)
        p.add_argument("--cycle", required=True)
        p.add_argument("--force", default="auto")
        if name == "analyze":
            p.add_argument("--input", required=True)
        else:
            p.add_argument("--device", default="default")
            p.add_argument("--sr", type=float, default=44100)
            p.add_argument("--channels", type=int, default=1)
            p.add_argument("--sensitivity", type=float, default=9.0)
            p.add_argument("--min-phrase", dest="min_phrase", type=float, default=0.5)
            p.add_argument("--end-silence", dest="end_silence", type=float, default=0.6)
            p.add_argument("--max-phrase", dest="max_phrase", type=float, default=12.0)
            p.add_argument("--preroll", type=float, default=0.25)
            p.add_argument("--timeout", type=float, default=30.0)
    p = sub.add_parser("cleanup")
    p.add_argument("--session", required=True)
    p = sub.add_parser("cleanup-stale")
    p.add_argument("--base", required=True)
    p = sub.add_parser("self-test")
    p.add_argument("--write-dir", dest="write_dir", default="")
    args = ap.parse_args(argv)
    if getattr(args, "force", "auto") not in ["auto", ""] + TRANSFORM_IDS:
        args.force = "auto"
    fn = {"probe": cmd_probe, "devices": cmd_devices, "listen": cmd_listen,
          "analyze": cmd_analyze, "cleanup": cmd_cleanup,
          "cleanup-stale": cmd_cleanup_stale, "self-test": cmd_self_test}[args.cmd]
    return fn(args)


if __name__ == "__main__":
    # --self-test is accepted as an alias of the self-test command
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.argv[1] = "self-test"
    sys.exit(main())
