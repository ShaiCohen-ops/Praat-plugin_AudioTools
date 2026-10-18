#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      audiotools_call_response.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     0.3.1 (2026) - Cleanup & Session Safety (Sonic Memory Upgrade from v0.2.0)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Capture + decision engine for AudioTools Intelligent Musical Call &
#   Response.  Two ways of running:
#
#   v0.2.0 CONTINUOUS ENGINE  (command: serve)
#     Started ONCE per performance (Praat -> blocking "launch" -> detached
#     "serve" process) and alive for the whole session:
#       input callback -> in_q -> DETECT+ANALYSE thread -> render_q
#         -> RENDER thread (headless "praat --run AudioTools_CallResponse.praat"
#            in render mode = the six AudioTools scripts, unmodified)
#         -> play_q -> PLAY thread -> output callback
#     The microphone stream stays open during analysis, rendering and
#     playback.  Python plays ONLY the WAV rendered by Praat (or, exactly as
#     in v0.1.3, the untransformed phrase when nothing qualifies or every
#     render fails - always logged).
#
#   v0.1.3 TURN-TAKING  (commands: listen / analyze, one process per turn)
#     Unchanged: opens the mic, records one phrase, analyses it, writes the
#     phrase WAV + decision file, exits; Praat renders and plays.
#
#   Both paths share the same feature extraction, scoring, eligibility
#   gates, parameter mapping and phrase detector.
#
# Changelog v0.3.1 - Cleanup & Session Safety (from v0.3.0):
#   Only session lifecycle / deletion changed; musical behaviour, retrieval
#   and the six transformations are identical to v0.3.0.
#   FIX: cleanup no longer deletes a session whose engine is still running.
#     It waits for the engine (PID + process start time), and if the
#     engine is still alive it deletes NOTHING and reports CLEANUP
#     INCOMPLETE; the engine then removes its own session when it exits.
#   FIX: crash recovery never removes a session whose engine is alive,
#     however long it has been quiet; a reused PID (same number, different
#     start time) counts as dead.
#   FIX: the Praat script no longer force-deletes files of a session folder
#     that Python's cleanup left in place; it shows CLEANUP INCOMPLETE.
#   Python cleanup commands return a non-zero exit code when something was
#     not removed (except with --report, used by the Praat script).
#
# Changelog v0.3.0 (Sonic Memory Upgrade from v0.2.0):
#   NEW three in-RAM corpora: A live phrases, B Praat-rendered responses
#     (analysed from their OWN audio, provenance root/parent/method/
#     generation, generation limit, near-identical results not stored),
#     C a read-only preloaded folder (energy-aware segmentation, re-indexed
#     at every start, audio re-read on demand when the RAM budget is full).
#   NEW retrieval: z-normalised distance per feature group (timbre, pitch
#     gesture, rhythm, envelope, duration) + a second-stage pitch/envelope
#     contour comparison; modes hybrid | timbre | pitch | rhythm | envelope |
#     contrast; minimum similarity, ranked candidates, controlled randomness,
#     cooldown, self / recent / same-family exclusion, novelty preference.
#   NEW decision layer: Transform (v0.2 behaviour) | Recall | Recall +
#     Transform | Hybrid (weighted), always falling back to Transform when no
#     qualified match exists.  Optional quiet layered response (off).
#   NEW "brain" worker thread: analysis moved out of the detector thread,
#     the detector never searches memory.
#   NEW zero-temporary-file lifecycle: the engine deletes everything it
#     created (WAVs, job files, logs, stderr) before reporting its final
#     status; "cleanup" waits for the engine process, deletes the session
#     with bounded retries and reports what could not be removed;
#     "cleanup-stale" removes only ABANDONED sessions (dead owner, no
#     recent activity) and orphan probe files.  No index or cache on disk.
#   PRESERVED: continuous listening, phrase detection, leakage handling,
#     v0.2 features/scoring/parameter mapping, the six transformations
#     rendered by the unchanged AudioTools scripts, MDS visualisation flag,
#     MAX MC behaviour of 8-Channel Speed Deviations, all v0.1.3 commands.
#
# Changelog v0.2.0:
#   PRESERVED from v0.1.3 (byte-identical code): feature extraction, the six
#     score functions, eligibility gates, safeguards, tie-break, confidence
#     thresholds, parameter mapping (incl. 8-Channel Speed Deviations MAX MC
#     deviation cap), PhraseDetector thresholds/hysteresis, listen / analyze /
#     probe / cleanup commands, decision-file protocol, self-test cases.
#   NEW continuous capture: "serve" command - persistent engine with
#     callback capture, bounded queues (pending phrases / pending responses,
#     overflow policy drop_oldest | drop_newest, every drop logged), one
#     render at a time, one playback at a time, separate input/output devices,
#     status file for the Praat display, stop request + Praat heartbeat,
#     per-job timestamps (onset, end, analysed, render start/end, play
#     start/end) in the optional debug log.
#   NEW leakage handling: speaker->mic leakage ESTIMATE (least-squares fit of
#     the played signal to the captured input, best lag in 0-500 ms), warning
#     above -20 dB, optional guard that (a) lifts the onset/offset thresholds
#     by the expected leakage level only while an answer is playing and
#     (b) discards a finished phrase only when >= 75 % of its energy is
#     explained by the playback.  This is NOT echo cancellation: the recorded
#     audio is never modified, and a performer playing over the answer still
#     triggers phrases.
#   ARCHITECTURE: PhraseDetector gains rearm() (continue listening after a
#     phrase) and an optional leakage hook (default None = v0.1.3 behaviour).
#     MAX_RESPONSE_S is now configurable (--max-response, default 20 s).
#   COMPATIBILITY: "devices" now lists output devices too.  The v0.1.3
#     commands accept the new optional --max-response argument.
#
# Commands:
#   launch        <serve arguments>        start "serve" detached, return at once
#   serve         --session DIR --script PRAAT_SCRIPT ...   continuous engine
#   probe         --out FILE [--live]      dependency check, writes FILE
#   devices       --out FILE               list audio input + output devices
#   listen        --session DIR --cycle N  [capture options]   (v0.1.3)
#   analyze       --session DIR --cycle N --input WAV         (v0.1.3)
#   cleanup       --session DIR            wait for the engine, remove the session
#   cleanup-stale --base DIR               remove abandoned sessions / probe files
#   self-test     [--write-dir DIR]        six-category + v0.2.0 + v0.3.0 tests
#
# Requirements:
#   Python >= 3.9, numpy, scipy, soundfile        (all commands)
#   sounddevice (PortAudio)                       (serve, listen, devices)
#   a Praat executable for headless rendering     (serve; found from the
#     Praat script's praatExe$ setting, PRAAT_EXE, PATH or standard folders)
#   pip install numpy scipy soundfile sounddevice
#   librosa is deliberately NOT used: its import time (1-3 s) would be
#   paid inside the musician's waiting time.
#
# Protocol (decision / job / status files: UTF-8, "\n" line endings, one
# key=value per line, values never contain newlines, written to *.tmp and
# renamed; the last line is end=1):
#   status=ok|timeout|silent_input|error   message=...
#   wav=<phrase wav>  sr=  channels=  duration=
#   mode=auto|manual  selected=<id>|passthrough  selected_score=
#   ranking=<id,id,...>  (eligible candidates above threshold, best first)
#   score_<id>=  eligible_<id>=0|1  reason_<id>=
#   p_<id>_<name>=<value>  for every candidate (named, not positional;
#                          the Praat dispatcher owns argument order)
#   seed=  t_phrase_end_epoch=  t_written_epoch=  t_detect_delay=
#   t_features=  t_select=  t_py_runtime=
#   render jobs add: out= result= plugin_root= max_response= job_id=
#
# Notes:
#   - Thresholds and score centres are POC heuristics tuned on synthetic
#     signals, not universal acoustic constants.
# ============================================================

import argparse
import collections
import math
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
import zlib

T_PROCESS_START = time.perf_counter()
VERSION = "0.3.1"

TRANSFORM_IDS = ["paulstretch", "markov", "mds", "spiral", "speeddev", "groove"]
TRANSFORM_NAMES = {
    "paulstretch": "Paulstretch (stable harmonic)",
    "markov": "Markov Soundscape Weaver (noisy / aperiodic)",
    "mds": "MDS Space Navigator (discrete attacks)",
    "spiral": "Spiral Pitch Dance (continuous glissando)",
    "speeddev": "8-Channel Speed Deviations (MAX MC; envelope-driven speed spread)",
    "groove": "Percussive Audio Groove Creator (variable density)",
}
# Deterministic tie-break: more specific categories first.
TIE_PRIORITY = ["spiral", "groove", "mds", "paulstretch", "markov", "speeddev"]
CONFIDENCE_THRESHOLD = {
    "paulstretch": 0.50, "markov": 0.50, "mds": 0.50,
    "spiral": 0.50, "speeddev": 0.45, "groove": 0.50,
}
AMBIGUITY_MARGIN = 0.08
MAX_RESPONSE_S = 20.0          # hard cap for stretched / generated answers
                               # (v0.2.0: overridden by --max-response)
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
    # v0.3.0 sonic memory: raw material for the retrieval descriptor (private
    # keys; the six-transformation classifier never reads them)
    F["_f0"] = f0
    F["_env"] = smooth
    F["_mfcc_mean"] = mf[sel].mean(axis=0) if sel.any() else mf.mean(axis=0)
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
    # 5 MC varispeed - complex dynamic envelope determines spread across 8 constant speeds
    c = {
        "dynamic_range": sig(F["env_dyn_range_db"], 10, 3),
        "env_peaks": sig(F["env_peaks"], 3, 1),
        "fluctuation_rate": sig(F["env_peak_rate"], 0.8, 0.3),
        "env_complexity": sig(F["env_complexity"], 0.3, 0.12),
    }
    w = {"dynamic_range": 1.0, "env_peaks": 1.0, "fluctuation_rate": 0.8, "env_complexity": 1.0}
    S["speeddev"], C["speeddev"] = wmean(c, w), c
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
    E["speeddev"] = gate([
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
    # The envelope-driven MC speed spread yields to strongly supported,
    # more input-specific and ELIGIBLE categories.
    E = eligibility(F)
    others = [v for k, v in S.items() if k != "speeddev" and E[k][0]]
    other = max(others) if others else 0.0
    dom = 1 - 0.45 * sig(other, 0.6, 0.08)
    S["speeddev"] *= dom
    if dom < 0.98:
        notes.append("speeddev x%.2f (an eligible specific category scores %.2f)" % (dom, other))
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
    # 5 MAX MC Deviate (v0.7): envelope controls speed deviation *between* channels.
    # Each channel runs at one constant playback speed. Pitch and D/s duration
    # change together; there is NO intra-channel time-varying acceleration.
    # Envelope variation is used as a musical gesture -> spatial/rate spread:
    # subtle fluctuations = subtle varispeed dispersion; intricate swells
    # = larger differences across eight static playback rates.
    dyn = sig(F["env_dyn_range_db"], 12.0, 4.0)
    complexity = sig(F["env_complexity"], 0.45, 0.20)
    peaks = sig(F["env_peaks"], 4.0, 1.25)
    spread = clamp(0.06 + 0.12 * dyn + 0.12 * complexity + 0.10 * peaks,
                   0.06, 0.40)
    # For d in [0,0.95], speed factors are uniform in [1-d,1+d].
    # All output durations obey D/(1+d) <= duration <= D/(1-d).
    # Use the slowest possible channel for an actual hard output cap.
    deviation_cap = max(0.0, 1.0 - dur / MAX_RESPONSE_S)
    spread = min(spread, deviation_cap, 0.40)
    P["speeddev"] = {
        "preset": "MAX MC Deviate (fresh random every run)",
        "deviation": round(spread, 4),
        "min_speed": round(1.0 - spread, 4),
        "max_speed": round(1.0 + spread, 4),
        "min_channel_duration_s": round(dur / (1.0 + spread), 3),
        "max_channel_duration_s": round(dur / max(1.0 - spread, 1e-6), 3),
        "engine": "MC-style varispeed (pitch follows speed)",
        "output": "MC stereo mix (odd L / even R)",
        "random_seed": 0,  # Preset overrides seed and draws fresh factors every time
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
        # v0.2.0: optional callable returning the expected speaker->mic
        # leakage level in dBFS (or None).  None = exact v0.1.3 behaviour.
        self.leak_level = None

    def thresholds(self):
        on = max(self.floor + self.sens, self.abs_min)
        off = on - self.hyst
        if self.leak_level is not None:
            lv = self.leak_level()
            if lv is not None:
                on = max(on, lv + 6.0)
                off = max(off, lv + 3.0)
        return on, off

    def rearm(self):
        """v0.2.0: continue listening after an 'end' without recalibrating.
        The noise floor is kept and the quiet tail after the phrase becomes
        the pre-roll of the next one."""
        tail = self.buf[self.last_active + 1:]
        self.pre = list(tail[-(self.pre_n + self.on_frames):])
        self.buf = []
        self.above = 0
        self.silent_run = 0
        self.ended_by = ""
        self.peak_db = -200.0
        self.state = "LISTENING"

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
             ("engine_version", VERSION),
             ("found", " ".join(found)), ("missing", "; ".join(missing))]
    write_kv_atomic(args.out, pairs)
    return 0


def cmd_devices(args):
    try:
        import sounddevice as sd
        lines, olines = [], []
        dflt = sd.default.device if sd.default.device else (None, None)
        default_in, default_out = dflt[0], dflt[1]
        for i, d in enumerate(sd.query_devices()):
            if d["max_input_channels"] > 0:
                lines.append("%s%3d  %-40s in:%d  %d Hz" % (
                    "*" if i == default_in else " ", i, d["name"][:40],
                    d["max_input_channels"], int(d["default_samplerate"])))
            if d.get("max_output_channels", 0) > 0:
                olines.append("%s%3d  %-40s out:%d  %d Hz" % (
                    "*" if i == default_out else " ", i, d["name"][:40],
                    d["max_output_channels"], int(d["default_samplerate"])))
        text = "Audio input devices (* = default):\n" + "\n".join(lines) + "\n"
        text += "\nAudio output devices (* = default):\n" + "\n".join(olines) + "\n"
        text += ("\nEnter the index or part of the name in the Input_device / "
                 "Output_device fields, or 'default'.\n"
                 "Use headphones or a separate output so the answers do not reach "
                 "the microphone.\n")
        status = "ok"
    except Exception as ex:                              # noqa: BLE001
        text = "Could not query audio devices: %s\n" % ex
        status = "error"
    write_text_atomic(args.out, text)
    return 0 if status == "ok" else 1


def resolve_device(sd, spec, kind="input"):
    spec = (spec or "").strip()
    if spec == "" or spec.lower() in ("default", "none"):
        return None
    if spec.lstrip("-").isdigit():
        return int(spec)
    key = "max_input_channels" if kind == "input" else "max_output_channels"
    hits = [i for i, d in enumerate(sd.query_devices())
            if d.get(key, 0) > 0 and spec.lower() in d["name"].lower()]
    if not hits:
        raise RuntimeError("no %s device matches '%s' (run 'List audio devices')" % (kind, spec))
    return hits[0]


def cmd_listen(args):
    global MAX_RESPONSE_S
    MAX_RESPONSE_S = float(getattr(args, "max_response", MAX_RESPONSE_S))
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
    global MAX_RESPONSE_S
    MAX_RESPONSE_S = float(getattr(args, "max_response", MAX_RESPONSE_S))
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
    """The ONLY way a session folder is removed after a normal run.
    v0.3.1: the folder is deleted only after the engine of THIS session
    (pid + start time from launch.txt) has really exited.  If it is still
    running after --wait seconds, NOTHING is deleted: the result is
    INCOMPLETE and a cleanup.pending marker asks the engine to remove the
    folder itself when it exits.  Exit code: 0 = folder gone, 1 = not
    removed, 2 = refused (not a session folder).  With --report one result
    line is printed and the exit code is always 0 (Praat reads the line with
    runSubprocess$, which would stop the script on a non-zero code)."""
    sess = args.session
    say = print if args.report else (lambda *a, **k: None)

    def done(rc, line):
        say(line)
        sys.stdout.flush()
        return 0 if args.report else rc
    if not os.path.exists(sess):
        return done(0, "CLEANUP OK files=0")
    if not safe_session_dir(sess):
        return done(2, "CLEANUP INCOMPLETE: refused (not a session folder): %s" % sess)
    info = read_kv(os.path.join(sess, "launch.txt"))
    t0 = time.time()
    while owner_alive(info) and time.time() - t0 < args.wait:
        time.sleep(0.1)
    if owner_alive(info):
        try:
            write_text_atomic(os.path.join(sess, "cleanup.pending"), "remove on exit\n")
        except OSError:
            pass
        t1 = time.time()                 # the engine may be exiting right now
        while owner_alive(info) and time.time() - t1 < 3.0:
            time.sleep(0.1)
        if owner_alive(info):
            return done(1, "CLEANUP INCOMPLETE: engine still running (pid %s) - nothing deleted; "
                           "it removes %s when it exits" % (info.get("pid"), sess))
    n = sum(len(f) for _, _, f in os.walk(sess))
    left = remove_tree(sess)
    if left:
        return done(1, "CLEANUP INCOMPLETE: %s" % "; ".join(left[:8]))
    return done(0, "CLEANUP OK files=%d" % n)


def read_kv(path):
    out = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "=" in line:
                    k, v = line.rstrip("\r\n").split("=", 1)
                    out[k] = v
    except OSError:
        pass
    return out


def session_activity(path):
    newest = 0.0
    for dirpath, _, names in os.walk(path):
        for n in names:
            try:
                newest = max(newest, os.path.getmtime(os.path.join(dirpath, n)))
            except OSError:
                pass
    try:
        newest = max(newest, os.path.getmtime(path))
    except OSError:
        pass
    return newest


STALE_ENGINE_S = 600        # dead engine + no activity for 10 min -> abandoned
STALE_NO_ENGINE_S = 12 * 3600   # session without an engine record (turn-taking,
                                # selected Sounds, device list) -> 12 h


def cmd_cleanup_stale(args):
    """Crash recovery at launch: remove ABANDONED sessions only.
    v0.3.1: a session whose engine (pid + start time) is alive is NEVER
    removed, however long it has been quiet.  A session is abandoned when
    its engine is gone (or a reused PID) and nothing in it changed for
    10 min; a session without an engine record after 12 h.  Orphan probe
    files go after 2 min.  Exit code 1 if an abandoned session could not be
    removed completely (0 with --report, which prints a summary line)."""
    now = time.time()
    removed, kept, failed = 0, 0, 0
    try:
        names = os.listdir(args.base)
    except OSError:
        names = []
    for name in names:
        p = os.path.join(args.base, name)
        try:
            if name.startswith(SESSION_PREFIX + "probe_") and os.path.isfile(p):
                if now - os.path.getmtime(p) > 120:
                    os.remove(p)
                    removed += 1
                continue
            if not (name.startswith(SESSION_PREFIX) and os.path.isdir(p)):
                continue
            info = read_kv(os.path.join(p, "launch.txt"))
            if info.get("pid"):
                if owner_alive(info):
                    kept += 1                       # active: never touched
                    continue
                limit = STALE_ENGINE_S
            else:
                limit = STALE_NO_ENGINE_S
            if now - session_activity(p) < limit:
                kept += 1
                continue
            if remove_tree(p, 8, 0.25):
                failed += 1
            else:
                removed += 1
        except OSError:
            failed += 1
    if args.report:
        print("STALE removed=%d kept=%d failed=%d" % (removed, kept, failed))
        return 0
    return 1 if failed else 0


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
    # 5 inharmonic sustained cluster with irregular swells: the envelope
    # controls the BETWEEN-channel speed spread, not time-varying speed.
    d = 4.0
    t = np.arange(int(d * sr)) / sr
    parts = [173 * r for r in (1.0, 1.618, 2.414, 3.303, 4.732, 6.171)]
    tone = sum(np.sin(2 * np.pi * p * t + k) / (k + 1) for k, p in enumerate(parts))
    sw = np.zeros_like(t)
    for c, w, a in [(0.3, 0.15, 1.0), (0.9, 0.1, 0.5), (1.4, 0.25, 0.9), (2.1, 0.08, 0.6),
                    (2.6, 0.2, 1.0), (3.2, 0.12, 0.4), (3.6, 0.15, 0.8)]:
        sw += a * np.exp(-0.5 * ((t - c) / w) ** 2)
    cases["speeddev"] = 0.3 * tone / np.max(np.abs(tone)) * (0.03 + sw / sw.max())
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
    print("\n" + "-" * 72 + "\nv0.2.0 continuous-engine unit tests (no audio hardware)")
    for name, fn in V020_TESTS:
        try:
            ok, detail = fn(sr)
        except Exception as ex:                              # noqa: BLE001
            ok, detail = False, "exception: %s" % ex
        print("[%s] %s: %s" % ("OK " if ok else "FAIL", name, detail))
        if not ok:
            failures += 1
    print("\n" + "-" * 72 + "\nv0.3.0 sonic-memory unit tests (in RAM; temporary test folders removed)")
    for name, fn in V030_TESTS:
        try:
            ok, detail = fn(sr)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            ok, detail = False, "exception: %s %s" % (ex, traceback.format_exc()[-300:])
        print("[%s] %s: %s" % ("OK " if ok else "FAIL", name, detail))
        if not ok:
            failures += 1
    print("\n%d failure(s)" % failures)
    return 1 if failures else 0


# ---------------- v0.2.0 unit tests ----------------
def _t_queue(sr):
    dropped = []
    class J:
        def __init__(self, i):
            self.tag, self.selected = "%04d" % i, "x"
    q = BoundedJobQueue("t", 3, "drop_oldest", lambda j, why: dropped.append(j.tag))
    for i in range(1, 6):
        q.put(J(i))
    order = [q.get(0).tag for _ in range(3)]
    ok1 = order == ["0003", "0004", "0005"] and dropped == ["0001", "0002"]
    dropped2 = []
    q2 = BoundedJobQueue("t", 2, "drop_newest", lambda j, why: dropped2.append(j.tag))
    for i in range(1, 5):
        q2.put(J(i))
    order2 = [q2.get(0).tag for _ in range(2)]
    ok2 = order2 == ["0001", "0002"] and dropped2 == ["0003", "0004"] and q2.get(0) is None
    return ok1 and ok2, ("drop_oldest kept %s dropped %s | drop_newest kept %s dropped %s"
                         % (order, dropped, order2, dropped2))


def _t_leak(sr):
    import numpy as np
    rng = np.random.default_rng(5)
    n = int(1.5 * sr)
    t = np.arange(n) / sr
    out = 0.3 * np.sin(2 * np.pi * 220 * t * (1 + 0.3 * t)) * (1 + 0.5 * rng.standard_normal(n))
    lag = int(0.035 * sr)
    L = int(1.0 * sr)
    mx = int(LEAK_MAX_LAG_S * sr)
    x = out[-(L + mx):]
    y_leak = 0.2 * out[-L - lag:-lag] + 0.002 * rng.standard_normal(L)       # -14 dB, 35 ms
    a, rho, lg = leak_fit(x, y_leak, mx)
    ok1 = abs(20 * math.log10(abs(a)) + 13.98) < 0.5 and abs(lg - lag) <= 1 and rho > 0.95
    player = 0.2 * np.sin(2 * np.pi * 330 * t[:L]) * np.exp(-t[:L])
    a2, rho2, _ = leak_fit(x, player + 0.002 * rng.standard_normal(L), mx)
    ok2 = rho2 * rho2 < 0.1
    mix = 0.05 * out[-L - lag:-lag] + player                          # performer over leak
    a3, rho3, lg3 = leak_fit(x, mix, mx)
    ok3 = rho3 * rho3 < LEAK_DISCARD_RHO2                             # performer kept
    return ok1 and ok2 and ok3, (
        "pure leak %.2f dB @ %.1f ms rho %.3f | independent player rho^2 %.3f | "
        "player over leak rho^2 %.2f (kept, < %.2f)" % (
            20 * math.log10(abs(a)), 1000 * lg / sr, rho, rho2 * rho2, rho3 * rho3,
            LEAK_DISCARD_RHO2))


def _t_ring(sr):
    import numpy as np
    r = Ring(sr, 2.0)
    blk = int(0.01 * sr)
    t0 = 1000.0
    for i in range(300):                    # 3 s of a ramp, ring keeps 2 s
        v = (np.arange(blk) + i * blk).astype(np.float32)
        r.append(v, t0 + (i + 1) * 0.01)
    seg = r.segment(t0 + 2.0, 0.5)          # samples [1.5 s, 2.0 s)
    exp = np.arange(int(1.5 * sr), int(2.0 * sr)).astype(np.float32)
    old = r.segment(t0 + 0.5, 0.2)          # older than history -> zeros
    return bool(np.array_equal(seg, exp) and not old.any()), "aligned segment, expired history = zeros"


def _t_rearm(sr):
    """Three phrases back to back in ONE stream: v0.2.0 continuous detection
    must find all three without recalibrating."""
    import numpy as np
    rng = np.random.default_rng(9)
    hop = int(0.01 * sr)
    nz_ = lambda s: 0.002 * rng.standard_normal(int(s * sr))
    def tone(f, s):
        tt = np.arange(int(s * sr)) / sr
        return 0.2 * np.sin(2 * np.pi * f * tt)
    stream = np.concatenate([nz_(1.0), tone(220, 1.0) + nz_(1.0), nz_(0.8),
                             tone(330, 0.7) + nz_(0.7), nz_(0.9), tone(440, 1.2) + nz_(1.2), nz_(1.0)])
    det = PhraseDetector(sr, 1, 9.0, 0.5, 0.6, 12.0, 0.25)
    lens = []
    for i in range(0, len(stream) - hop, hop):
        if det.feed(stream[i:i + hop]) == "end":
            lens.append(round(len(det.phrase_audio()) / sr, 2))
            det.rearm()
    ok = len(lens) == 3 and abs(lens[0] - 1.4) < 0.1 and abs(lens[1] - 1.1) < 0.1 and abs(lens[2] - 1.6) < 0.1
    return ok, "phrase lengths %s s (tone + 0.25 pre-roll + 0.15 tail)" % lens


def _t_guard(sr):
    """Leakage hook: lifts thresholds only while the hook reports a level;
    None restores the exact v0.1.3 thresholds."""
    det = PhraseDetector(sr, 1)
    det.floor = -60.0
    base = det.thresholds()
    det.leak_level = lambda: -30.0
    lifted = det.thresholds()
    det.leak_level = lambda: None
    back = det.thresholds()
    ok = base == (-51.0, -55.0) and lifted == (-24.0, -27.0) and back == base
    return ok, "v0.1.3 %s | playing with leak at -30 dBFS %s | idle %s" % (base, lifted, back)


def _t_path(sr):
    """PHAT path validation: real leakage under a performer is found at the
    right delay; a same-pitch performer against a phase-randomised
    (Paulstretch-like) answer with NO leakage is not a path."""
    import numpy as np
    rng = np.random.default_rng(3)
    L, mx = int(1.0 * sr), int(LEAK_MAX_LAG_S * sr)
    n = L + mx
    t = np.arange(n) / sr
    def harm(f, ph):
        return sum((0.7 ** i) * np.sin(2 * np.pi * (i + 1) * f * t + ph[i]) for i in range(8)) / 2.5
    perf = 0.3 * harm(220, np.zeros(8))
    base = harm(220, np.zeros(8)) + 0.01 * rng.standard_normal(n)
    X = np.fft.rfft(base)
    ans = 0.3 * np.fft.irfft(np.abs(X) * np.exp(1j * rng.uniform(0, 2 * np.pi, len(X))), n)
    lag = int(0.04 * sr)
    nz_ = 0.002 * rng.standard_normal(n)
    r0 = leak_path(ans, (perf + nz_)[-L:], mx, sr)
    res1 = []
    for trial in range(6):              # same pitch, random answer phases, both noisy
        same = 0.3 * harm(220, rng.uniform(0, 2 * np.pi, 8)) + 0.002 * rng.standard_normal(n)
        res1.append(leak_path(same, (perf + nz_)[-L:], mx, sr))
    y = 0.1 * np.concatenate([np.zeros(lag), ans])[:n] + perf + nz_
    r2 = leak_path(ans, y[-L:], mx, sr)
    y3 = 0.1 * np.concatenate([np.zeros(lag), ans])[:n] + nz_
    r3 = leak_path(ans, y3[-L:], mx, sr)
    g3 = 20 * math.log10(abs(r3["a"]) + 1e-12)
    ok = (not r0["plausible"] and not any(r["plausible"] for r in res1) and r2["plausible"]
          and abs(r2["lag"] - lag) <= 1 and r3["plausible"] and abs(g3 + 20) < 0.5
          and abs(r3["rho"]) >= LEAK_GAIN_RHO and abs(r2["rho"]) < LEAK_GAIN_RHO)
    return ok, ("no leak: paul answer %s (z %.1f) | same pitch x6: %d path(s), max dominance %.2f"
                " | -20 dB leak under performer: path at %.1f ms, gain frozen (rho %.2f)"
                " | -20 dB leak alone: %.2f dB (rho %.2f)" % (
                    "path" if r0["plausible"] else "no path", r0["z"],
                    sum(r["plausible"] for r in res1), max(r["dom"] for r in res1),
                    1000 * r2["lag"] / sr, r2["rho"], g3, r3["rho"]))


V020_TESTS = [("bounded queues + overflow policies", _t_queue),
              ("leakage least-squares estimate", _t_leak),
              ("leakage path validation (PHAT)", _t_path),
              ("wall-clock ring alignment", _t_ring),
              ("continuous re-arming detector", _t_rearm),
              ("leakage guard thresholds", _t_guard)]


# ---------------- v0.3.0 sonic-memory unit tests ----------------
def _mem_cfg(**kw):
    c = {"enabled": True, "response_mode": "hybrid", "use_A": True, "use_B": True,
         "use_C": True, "sim_mode": "hybrid", "min_similarity": 0.3, "w_live": 40.0,
         "w_processed": 30.0, "w_preloaded": 30.0, "p_transform": 40.0, "p_recall": 30.0,
         "p_recall_transform": 30.0, "max_generation": 2, "max_live": 100,
         "max_processed": 100, "max_ram_min": 30.0, "max_item_s": 15.0, "candidates": 5,
         "evolving": False, "cooldown": 4, "same_family_exclusion": False,
         "c_max_items": 300, "c_max_files": 200, "c_max_per_file": 20, "c_min_item_s": 0.5}
    c.update(kw)
    return c


_MEM_CACHE = {}


def _mem_items(sr):
    """The six synthetic gestures analysed once (features + descriptor)."""
    if "items" not in _MEM_CACHE:
        out = {}
        for name, audio in synth_cases(sr).items():
            F, info, desc = analyse_item(audio, sr)
            out[name] = (audio, F, info, desc)
        _MEM_CACHE["items"] = out
    return _MEM_CACHE["items"]


def _mem_fill(sr, corpus="A", **kw):
    import numpy as np
    mem = SonicMemory(_mem_cfg(**kw), 1234)
    for name, (audio, F, info, desc) in _mem_items(sr).items():
        iid = mem.new_id(corpus)
        mem.add(CorpusItem(iid, corpus, audio.astype(np.float32)[:, None], sr, F, desc, info,
                           time.time(), {"root": iid, "parent": None, "method": None,
                                         "generation": 0, "source": name}))
    return mem


def _variant(audio, sr):
    """Same gesture, slightly different take: 30 ms later, -1.5 dB, a little noise."""
    import numpy as np
    rng = np.random.default_rng(3)
    a = np.concatenate([np.zeros(int(0.03 * sr)), audio])[:len(audio)] * 0.84
    return a + 0.002 * rng.standard_normal(len(a))


def _t_mem_insert(sr):
    mem = _mem_fill(sr)
    c = mem.counts()
    ok = c == {"A": 6, "B": 0, "C": 0} and all(it.desc is not None for it in mem.items["A"])
    return ok, "counts %s, RAM %.1f s" % (c, mem.ram_seconds())


def _t_mem_rank(sr):
    mem = _mem_fill(sr)
    hits = []
    for name, (audio, F, info, desc) in _mem_items(sr).items():
        Fq, iq, dq = analyse_item(_variant(audio, sr), sr)
        best = mem.similarity(dq, mem.items["A"], "hybrid")[0]
        hits.append((name, best[0].p["source"], round(best[1], 2)))
    ok = all(a == b for a, b, _ in hits)
    return ok, "variant -> nearest: " + ", ".join("%s->%s %.2f" % h for h in hits)


def _t_mem_nopitch(sr):
    import numpy as np
    mem = _mem_fill(sr)
    rng = np.random.default_rng(5)
    noise = 0.2 * rng.standard_normal(int(2.0 * sr))
    F, info, d = analyse_item(noise, sr)
    res = mem.similarity(d, mem.items["A"], "pitch")
    res2 = mem.similarity(d, mem.items["A"], "hybrid")
    finite = all(np.isfinite(r[1]) for r in res + res2)
    return finite and not d["voiced"], "unpitched query: %d finite similarities, best %s %.2f" % (
        len(res2), res2[0][0].p["source"], res2[0][1])


def _t_mem_self(sr):
    mem = _mem_fill(sr)
    q = mem.items["A"][0]
    excluded = {q.id, mem.items["A"][1].id}
    seen = set()
    for _ in range(30):
        ch, top, why = mem.retrieve(q.desc, exclude_ids=excluded)
        seen |= {r["item"].id for r in top}
    ok = not (seen & excluded) and len(seen) > 0
    # an identical copy (sim >= 0.97) is never "recalled"
    mem.add(CorpusItem("A9999", "A", q.audio, q.sr, q.F, q.desc, q.info, time.time(),
                       {"root": "A9999", "generation": 0}))
    ch, top, why = mem.retrieve(q.desc, exclude_ids={q.id})
    ok = ok and all(r["item"].id != "A9999" for r in top)
    return ok, "excluded ids never ranked; identical copy refused"


def _t_mem_generation(sr):
    mem = _mem_fill(sr)
    for it in mem.items["A"]:
        it.p["generation"] = 2
    q = mem.items["A"][0]
    ch, top, why = mem.retrieve(q.desc, exclude_ids={q.id})
    rt2 = pick_recall_transform(ch, top, None, 2)
    for it in mem.items["A"]:
        it.p["generation"] = 1
    rt1 = pick_recall_transform(ch, top, None, 2)
    ok = rt2 is None and (rt1 is not None or not top)
    return ok, "generation-2 sources refused for Recall+Transform (max 2); generation 1 allowed"


def _t_mem_cooldown(sr):
    mem = _mem_fill(sr, cooldown=3)
    q = mem.items["A"][0]
    picks = []
    for _ in range(9):
        ch, top, why = mem.retrieve(q.desc, exclude_ids={q.id})
        if ch is None:
            picks.append(None)
            continue
        mem.mark_recalled(ch["item"])
        picks.append(ch["item"].id)
    rep = any(picks[i] is not None and picks[i] in picks[max(0, i - 3):i]
              for i in range(len(picks)))
    return not rep, "picks %s (no repeat within 3)" % picks


def _t_mem_empty(sr):
    mem = SonicMemory(_mem_cfg(), 1)
    d = _mem_items(sr)["paulstretch"][3]
    ch, top, why = mem.retrieve(d)
    a1 = mem.choose_action(ch, None)
    mem2 = SonicMemory(_mem_cfg(response_mode="recall"), 1)
    a2 = mem2.choose_action(None, None)
    mem3 = SonicMemory(_mem_cfg(response_mode="recall_transform"), 1)
    a3 = mem3.choose_action(None, None)
    ok = ch is None and a1[0] == a2[0] == a3[0] == "transform"
    return ok, "empty memory -> %s; Recall without match -> %s; R+T -> %s" % (a1[0], a2[0], a3[0])


def _t_mem_contrast(sr):
    mem = _mem_fill(sr, sim_mode="contrast", min_similarity=0.2, candidates=1)
    q = mem.items["A"][0]
    ch, top, why = mem.retrieve(q.desc, exclude_ids={q.id})
    ranked = mem.similarity(q.desc, [it for it in mem.items["A"] if it.id != q.id], "hybrid")
    ok = ch is not None and ch["item"] is ranked[-1][0]
    return ok, "contrast picks the least similar (%s, sim %.2f)" % (
        ch["item"].p["source"] if ch else "-", ch["sim"] if ch else 0)


def _t_mem_weights(sr):
    mem = SonicMemory(_mem_cfg(evolving=True, w_processed=0.0, use_C=False), 1)
    ok = True
    for p in (0.0, 0.3, 0.6, 1.0):
        w = mem.corpus_weights(p)
        ok = ok and w["B"] == 0 and w["C"] == 0 and w["A"] > 0
    mem2 = _mem_fill(sr, corpus="C", use_C=False)
    q = mem2.items["C"][0]
    ch, top, why = mem2.retrieve(q.desc)
    ok = ok and ch is None
    return ok, "manual 0 / disabled corpora stay 0 at every stage of the evolving curve"


def _t_mem_evict(sr):
    mem = _mem_fill(sr, max_live=3)
    ids = [it.id for it in mem.items["A"]]
    mem2 = _mem_fill(sr, max_ram_min=0.1)            # 6 s budget, 6 x ~3 s audio
    ok = ids == ["A0004", "A0005", "A0006"] and mem.evicted == 3 and \
        mem2.ram_seconds() <= 6.0 + 1e-6
    return ok, "count limit keeps %s; RAM limit %.1f s <= 6 s (%d evicted)" % (
        ids, mem2.ram_seconds(), mem2.evicted)


def _t_mem_corpus_c(sr):
    """Corpus C indexing is READ-ONLY: files hashed before and after, no new
    files anywhere in the folder; segments avoid silence and tiny bits."""
    import hashlib
    import tempfile
    import numpy as np
    import soundfile as sf
    items = _mem_items(sr)
    with tempfile.TemporaryDirectory(prefix="AudioTools_CR_selftest_") as tmp:
        sil = np.zeros(int(1.0 * sr))
        long_ = np.concatenate([sil, items["paulstretch"][0], sil, items["markov"][0], sil,
                                0.0005 * np.ones(int(0.05 * sr)), sil])
        sf.write(os.path.join(tmp, "take1.wav"), long_, sr, subtype="PCM_16")
        sf.write(os.path.join(tmp, "take2.flac"), items["spiral"][0], sr)
        open(os.path.join(tmp, "notes.txt"), "w").write("not audio")

        def snap():
            out = {}
            for n in sorted(os.listdir(tmp)):
                with open(os.path.join(tmp, n), "rb") as fh:
                    out[n] = (hashlib.sha256(fh.read()).hexdigest(),
                              os.path.getmtime(os.path.join(tmp, n)))
            return out
        before = snap()
        mem = SonicMemory(_mem_cfg(), 1)
        n, notes = index_preloaded(tmp, mem, _mem_cfg())
        after = snap()
        durs = [round(it.duration, 2) for it in mem.items["C"]]
        a = mem.items["C"][0]
        a.audio = None                                 # on-demand path
        reread = a.get_audio()
    ok = before == after and n >= 3 and min(durs) >= 0.5 and len(reread) > 0
    return ok, "%d segments %s, folder unchanged (%d files hashed)" % (n, durs, len(before))


def _t_mem_cleanup(sr):
    """v0.3.1 session safety (all in a temporary base folder):
    cleanup refuses while the engine lives and deletes after it exits;
    cleanup-stale keeps a quiet-but-alive session, removes a dead one and
    one whose PID was reused; a foreign folder is refused."""
    import tempfile
    import io
    import contextlib

    class NS:
        pass
    notes, ok = [], True
    with tempfile.TemporaryDirectory(prefix="atcr_base_") as base:
        def mk(name, info, age):
            d = os.path.join(base, name)
            os.makedirs(os.path.join(d, "sub"))
            open(os.path.join(d, "sub", "x.wav"), "wb").write(b"0" * 100)
            if info:
                write_kv_atomic(os.path.join(d, "launch.txt"), info)
            old = time.time() - age
            for dp, dn, ns in os.walk(d):
                for n_ in ns:
                    os.utime(os.path.join(dp, n_), (old, old))
                os.utime(dp, (old, old))
            return d
        owner = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
        try:
            tok = proc_start_token(owner.pid)
            live = mk(SESSION_PREFIX + "live", [("pid", owner.pid), ("start", tok)], 0)
            quiet = mk(SESSION_PREFIX + "quiet", [("pid", owner.pid), ("start", tok)], 7200)
            reused = mk(SESSION_PREFIX + "reused", [("pid", owner.pid), ("start", "x0")], 7200)
            dead = mk(SESSION_PREFIX + "dead", [("pid", 999999), ("start", "x1")], 7200)
            other = mk("MyCorpus", None, 7200)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                c = NS()
                c.session, c.wait, c.report = live, 0.0, False
                rc_live = cmd_cleanup(c)
                c.session, c.report = other, True
                cmd_cleanup(c)
                a = NS()
                a.base, a.report = base, True
                cmd_cleanup_stale(a)
            ok &= rc_live == 1 and os.path.isdir(live) and os.path.exists(
                os.path.join(live, "sub", "x.wav"))
            notes.append("live engine: cleanup rc %d, nothing deleted" % rc_live)
            ok &= os.path.isdir(quiet) and not os.path.exists(reused) and not os.path.exists(dead)
            ok &= os.path.isdir(other)
            notes.append("stale: quiet-but-alive kept, reused-PID and dead removed, "
                         "foreign refused")
        finally:
            owner.kill()
            owner.wait()
        c = NS()
        c.session, c.wait, c.report = live, 5.0, False
        rc_after = cmd_cleanup(c)
        ok &= rc_after == 0 and not os.path.exists(live)
        notes.append("after the engine exited: rc %d, folder removed" % rc_after)
        notes.append(buf.getvalue().strip().replace("\n", " | "))
    return ok, "; ".join(notes)


V030_TESTS = [("memory insertion", _t_mem_insert), ("similarity ranking", _t_mem_rank),
              ("missing pitch", _t_mem_nopitch), ("self / identity exclusion", _t_mem_self),
              ("generation limit", _t_mem_generation), ("cooldown", _t_mem_cooldown),
              ("empty-memory fallback", _t_mem_empty), ("contrast mode", _t_mem_contrast),
              ("weights never override 0", _t_mem_weights), ("eviction", _t_mem_evict),
              ("Corpus C read-only indexing", _t_mem_corpus_c),
              ("session cleanup safety", _t_mem_cleanup)]


# ============================================================
# v0.3.0 SONIC MEMORY
#   Three in-RAM corpora (A live phrases, B processed responses, C preloaded
#   reference), a normalised nearest-neighbour retrieval layer with a
#   second-stage contour comparison, and the Transform / Recall /
#   Recall + Transform decision layer.  The v0.2 classifier is not changed:
#   it is consulted for the live phrase and, for Recall + Transform, for the
#   RETRIEVED audio.  Nothing here touches the disk except reading the
#   user's Corpus C files (read-only).
# ============================================================
CORPUS_NAMES = {"A": "Live", "B": "Processed", "C": "Preloaded"}
SIM_MODES = {
    # group weights; "_contour" = share of the second-stage contour distance
    "hybrid": {"timbre": 0.35, "pitch": 0.20, "rhythm": 0.20, "envelope": 0.20,
               "duration": 0.05, "_contour": 0.25, "_contours": ("pitch", "env")},
    "timbre": {"timbre": 1.0, "_contour": 0.0, "_contours": ()},
    "pitch": {"pitch": 1.0, "_contour": 0.40, "_contours": ("pitch",)},
    "rhythm": {"rhythm": 0.85, "duration": 0.15, "_contour": 0.0, "_contours": ()},
    "envelope": {"envelope": 1.0, "_contour": 0.40, "_contours": ("env",)},
}
SIM_MODES["contrast"] = SIM_MODES["hybrid"]
# Prior spreads per descriptor dimension: blended with the corpus spread so
# that z-scores are meaningful even with only a few items in memory.
GROUP_PRIOR = {
    "timbre": [8.0] + [3.0] * 11 + [0.35, 0.5, 0.5, 6.0],
    "pitch": [0.25, 0.8, 4.0, 3.0, 4.0, 0.2, 0.2],
    "rhythm": [1.0, 0.4, 0.3, 0.5, 4.0, 0.25, 0.15, 0.5],
    "envelope": [5.0, 0.6, 0.25, 5.0, 0.15],
    "duration": [0.5],
}
SIM_SCALE = 0.8                  # similarity = exp(-SIM_SCALE * distance)
IDENTITY_SIM = 0.97              # a Praat result this close to its source is not stored
DUPLICATE_SIM = 0.995            # a stored sound this close to the phrase is the same
                                 #   recording (e.g. re-captured playback): never recalled
CONTOUR_BINS = 32


def _contour(values, valid, bins=CONTOUR_BINS):
    import numpy as np
    out = np.full(bins, np.nan)
    n = len(values)
    if n == 0:
        return out
    edges = np.linspace(0, n, bins + 1).astype(int)
    for b in range(bins):
        seg = values[edges[b]:max(edges[b + 1], edges[b] + 1)]
        ok = valid[edges[b]:max(edges[b + 1], edges[b] + 1)]
        if ok.any():
            out[b] = float(np.mean(seg[ok]))
    return out


def memory_descriptor(F):
    """Retrieval descriptor from the v0.2 feature set (+ private arrays).
    Groups of raw values (NaN = not measurable, e.g. pitch of noise) and two
    32-point contours: pitch in semitones around the phrase median, and the
    envelope in dB below its peak."""
    import numpy as np
    voiced = F.get("voiced_frames", 0) >= 20
    nan = float("nan")
    cen = max(F["centroid_mean"], 20.0)
    timbre = list(np.asarray(F.get("_mfcc_mean", np.zeros(12)), float)[:12])
    timbre += [math.log(cen), math.log10(F["flatness"] + 1e-4),
               F["spectral_variability"], clamp(F["hnr_db"], -10.0, 35.0)]
    if voiced:
        pitch = [F["voiced_ratio"], math.log2(max(nz(F["f0_median"], 100.0), 20.0)),
                 F["pitch_range_st"], F["pitch_slope_st_s"], F["pitch_net_change_st"],
                 F["pitch_monotonicity"], F["pitch_continuity"]]
    else:
        pitch = [F["voiced_ratio"]] + [nan] * 6
    rhythm = [F["onset_rate"], F["ioi_cv"], F["density_cv"], F["density_trend"],
              F["transient_strength_db"], F["perc_char"], F["silence_ratio"],
              math.log(F["ioi_median"]) if F["ioi_median"] > 0 else nan]
    envelope = [F["env_dyn_range_db"], F["env_peak_rate"], F["env_complexity"],
                F["energy_slope_db_s"], F["active_ratio"]]
    duration = [math.log(max(F["duration"], 0.05))]
    f0 = np.asarray(F.get("_f0", np.array([])), float)
    pc = np.full(CONTOUR_BINS, np.nan)
    if voiced and len(f0):
        ok = ~np.isnan(f0)
        st = np.where(ok, 12 * np.log2(np.where(ok, f0, 100.0) / 100.0), 0.0)
        med = float(np.median(st[ok])) if ok.any() else 0.0
        pc = _contour(st - med, ok)
    env = np.asarray(F.get("_env", np.array([])), float)
    ec = np.full(CONTOUR_BINS, np.nan)
    if len(env):
        rel = np.maximum(env - env.max(), -40.0)
        ec = _contour(rel, np.ones(len(rel), bool))
    g = {k: np.asarray(v, float) for k, v in (("timbre", timbre), ("pitch", pitch),
                                             ("rhythm", rhythm), ("envelope", envelope),
                                             ("duration", duration))}
    return {"groups": g, "pitch_contour": pc, "env_contour": ec, "voiced": voiced}


class CorpusItem:
    """One sound in memory.  audio may be None for a Corpus C segment kept
    on demand: get_audio() re-reads it from the ORIGINAL file (read-only)."""

    def __init__(self, iid, corpus, audio, sr, F, desc, info, t, provenance):
        self.id = iid
        self.corpus = corpus
        self.audio = audio
        self.sr = sr
        self.duration = F["duration"]
        self.F = F
        self.desc = desc
        self.info = info                       # v0.2 decision for THIS audio
        self.t = t
        self.p = dict(provenance)              # root, parent, method, generation, source
        self.gesture = info["selected"]
        self.recalls = 0
        self.src = None                        # (path, start, stop) for C on demand

    @property
    def generation(self):
        return self.p.get("generation", 0)

    @property
    def root(self):
        return self.p.get("root", self.id)

    def get_audio(self):
        if self.audio is not None:
            return self.audio
        import soundfile as sf
        path, start, stop = self.src
        a, sr = sf.read(path, start=start, stop=stop, dtype="float32", always_2d=True)
        return a

    def ram_seconds(self):
        return 0.0 if self.audio is None else len(self.audio) / float(self.sr)


class SonicMemory:
    """Owns the three corpora.  Used from ONE thread only (the engine's brain
    worker), so it needs no locks; the status writer reads plain counters."""

    def __init__(self, cfg, seed, log=None):
        import random
        self.cfg = cfg
        self.rng = random.Random(seed)
        self.seed = seed
        self.items = {"A": [], "B": [], "C": []}
        self.next = {"A": 1, "B": 1, "C": 1}
        self.recall_history = collections.deque(maxlen=max(0, int(cfg.get("cooldown", 4))))
        self.log = log or (lambda *a, **k: None)
        self.t0 = time.time()
        self.evicted = 0

    # ---------------- bookkeeping ----------------
    def counts(self):
        return {k: len(v) for k, v in self.items.items()}

    def ram_seconds(self):
        return sum(it.ram_seconds() for v in self.items.values() for it in v)

    def all_items(self):
        return self.items["A"] + self.items["B"] + self.items["C"]

    def find(self, iid):
        for v in self.items.values():
            for it in v:
                if it.id == iid:
                    return it
        return None

    def new_id(self, corpus):
        i = self.next[corpus]
        self.next[corpus] += 1
        return "%s%04d" % (corpus, i)

    def add(self, item):
        self.items[item.corpus].append(item)
        self.enforce_limits()
        return item

    def enforce_limits(self):
        c = self.cfg
        while len(self.items["A"]) > c["max_live"]:
            self._evict(self.items["A"][0], "live corpus limit")
        while len(self.items["B"]) > c["max_processed"]:
            self._evict(self.items["B"][0], "processed corpus limit")
        budget = 60.0 * c["max_ram_min"]
        while self.ram_seconds() > budget:
            loaded_c = [it for it in self.items["C"] if it.audio is not None and it.src]
            if loaded_c:                                  # C audio is re-loadable
                loaded_c[0].audio = None
                continue
            ab = self.items["A"] + self.items["B"]
            if not ab:
                break
            self._evict(min(ab, key=lambda it: it.t), "audio memory limit")

    def _evict(self, item, why):
        self.items[item.corpus].remove(item)
        item.audio = None
        self.evicted += 1
        self.log("memory: evicted %s (%s)" % (item.id, why))

    def clear(self):
        for v in self.items.values():
            for it in v:
                it.audio = None
                it.F = None
            v.clear()

    # ---------------- weights ----------------
    def corpus_weights(self, progress):
        """Manual weights, optionally shaped by the evolving-memory curve.
        The curve only MULTIPLIES: a corpus switched off or weighted 0 by the
        performer can never be brought back by the adaptive strategy."""
        c = self.cfg
        w = {"A": c["w_live"] if c["use_A"] else 0.0,
             "B": c["w_processed"] if c["use_B"] else 0.0,
             "C": c["w_preloaded"] if c["use_C"] else 0.0}
        if c.get("evolving"):
            p = clamp(progress, 0.0, 1.0)
            shape = {"C": 0.15 + (1 - p) ** 2, "A": 0.15 + 4 * p * (1 - p), "B": 0.15 + p ** 2}
            w = {k: w[k] * shape[k] for k in w}
        return w

    # ---------------- similarity ----------------
    def _scales(self, pool, qdesc):
        import numpy as np
        sc = {}
        for gname, prior in GROUP_PRIOR.items():
            rows = [it.desc["groups"][gname] for it in pool] + [qdesc["groups"][gname]]
            M = np.vstack(rows)
            with np.errstate(all="ignore"):
                sd = np.nanstd(M, axis=0) if len(rows) > 2 else np.zeros(M.shape[1])
            sd = np.where(np.isnan(sd), 0.0, sd)
            sc[gname] = np.sqrt(sd ** 2 + np.asarray(prior, float) ** 2)
        return sc

    @staticmethod
    def group_distance(a, b, scale):
        import numpy as np
        d = (a - b) / scale
        ok = ~np.isnan(d)
        if not ok.any():
            return None
        return float(np.sqrt(np.mean(d[ok] ** 2)))

    @staticmethod
    def contour_distance(qd, it, which):
        import numpy as np
        out = []
        if "pitch" in which:
            a, b = qd["pitch_contour"], it.desc["pitch_contour"]
            ok = ~np.isnan(a) & ~np.isnan(b)
            if ok.sum() >= 8:
                out.append(float(np.mean(np.abs(a[ok] - b[ok]))) / 3.0)
        if "env" in which:
            a, b = qd["env_contour"], it.desc["env_contour"]
            ok = ~np.isnan(a) & ~np.isnan(b)
            if ok.sum() >= 8:
                out.append(float(np.mean(np.abs(a[ok] - b[ok]))) / 6.0)
        return (sum(out) / len(out)) if out else None

    def similarity(self, qdesc, items, mode, scales=None):
        """[(item, sim, distance)] for every item, best first."""
        import math as _m
        if mode == "pitch" and not qdesc["voiced"]:
            # an unpitched phrase has no pitch gesture to compare: in PITCH
            # mode two noises would look identical (only the voiced ratio
            # is measurable), so such a query is ranked with HYBRID weights
            mode = "hybrid"
        W = SIM_MODES.get(mode, SIM_MODES["hybrid"])
        scales = scales or self._scales(items, qdesc)
        res = []
        for it in items:
            num = den = 0.0
            for gname, w in W.items():
                if gname.startswith("_") or w <= 0:
                    continue
                d = self.group_distance(qdesc["groups"][gname], it.desc["groups"][gname],
                                        scales[gname])
                if d is None:
                    continue
                if gname == "pitch" and (qdesc["voiced"] != it.desc["voiced"]):
                    d += 0.5                          # pitched vs unpitched
                num += w * d
                den += w
            dist = num / den if den > 0 else 3.0
            res.append([it, dist])
        res.sort(key=lambda r: r[1])
        wc = W.get("_contour", 0.0)
        if wc > 0:                                    # second stage, bounded
            for r in res[:max(15, 3 * self.cfg.get("candidates", 5))]:
                dc = self.contour_distance(qdesc, r[0], W["_contours"])
                if dc is not None:
                    r[1] = (1 - wc) * r[1] + wc * dc
            res.sort(key=lambda r: r[1])
        return [(it, _m.exp(-SIM_SCALE * d), d) for it, d in res]

    # ---------------- retrieval ----------------
    def retrieve(self, qdesc, exclude_ids=(), exclude_roots=(), progress=0.0, k=None):
        """Ranked qualified candidates and a weighted-random choice.
        Returns (choice or None, ranked list of dicts, reason)."""
        c = self.cfg
        k = k or c.get("candidates", 5)
        mode = c.get("sim_mode", "hybrid")
        weights = self.corpus_weights(progress)
        pool = [it for corp in ("A", "B", "C") if weights[corp] > 0 for it in self.items[corp]]
        if not pool:
            return None, [], "memory empty or all corpora disabled"
        recent = set(self.recall_history)
        last = self.recall_history[-1] if self.recall_history else None
        last_root = None
        if last and c.get("same_family_exclusion"):
            li = self.find(last)
            last_root = li.root if li else None
        pool = [it for it in pool if it.id not in exclude_ids and it.root not in exclude_roots
                and it.id not in recent and (last_root is None or it.root != last_root)
                and it.duration >= 0.3]
        if not pool:
            return None, [], "every stored sound is excluded (self / recent / cooldown)"
        ranked = self.similarity(qdesc, pool, mode)
        minsim = c.get("min_similarity", 0.5)
        qual = []
        for it, sim, dist in ranked:
            if mode == "contrast":
                score = 1.0 - sim
                if score < minsim:
                    continue
            else:
                if sim < minsim or sim >= DUPLICATE_SIM:
                    continue
                score = sim
            novelty = 1.0 / (1.0 + it.recalls)
            qual.append({"item": it, "sim": sim, "match": score,
                         "score": score * (1.0 + 0.15 * novelty), "dist": dist})
        if not qual:
            best = ranked[0][1] if ranked else 0.0
            return None, [], ("no stored sound reaches the minimum similarity %.2f "
                              "(best %.2f)" % (minsim, best))
        qual.sort(key=lambda r: -r["score"])
        top = qual[:k]
        best = top[0]["score"]
        probs = [weights[r["item"].corpus] * math.exp((r["score"] - best) / 0.05) for r in top]
        tot = sum(probs)
        if tot <= 0:
            return None, top, "all qualified candidates come from corpora weighted 0"
        x = self.rng.random() * tot
        for r, pr in zip(top, probs):
            x -= pr
            if x <= 0:
                return r, top, "ok"
        return top[-1], top, "ok"

    def mark_recalled(self, item):
        item.recalls += 1
        self.recall_history.append(item.id)

    # ---------------- decision ----------------
    def choose_action(self, candidate, rt_candidate):
        """TRANSFORM / RECALL / RECALL_TRANSFORM, never forcing a poor match:
        recall actions are only possible with a qualified candidate."""
        c = self.cfg
        mode = c.get("response_mode", "hybrid")
        if mode == "transform" or not c.get("enabled", True):
            return "transform", "response mode Transform"
        if mode == "recall":
            return ("recall", "response mode Recall") if candidate else \
                   ("transform", "Recall: no qualified match -> transform fallback")
        if mode == "recall_transform":
            return ("recall_transform", "response mode Recall + Transform") if rt_candidate \
                else ("transform", "Recall + Transform not possible -> transform fallback")
        opts = [("transform", c.get("p_transform", 40.0))]
        if candidate:
            opts.append(("recall", c.get("p_recall", 30.0)))
        if rt_candidate:
            opts.append(("recall_transform", c.get("p_recall_transform", 30.0)))
        tot = sum(max(0.0, w) for _, w in opts)
        if tot <= 0:
            return "transform", "all action weights 0 -> transform"
        x = self.rng.random() * tot
        for a, w in opts:
            x -= max(0.0, w)
            if x <= 0:
                return a, "hybrid draw"
        return opts[-1][0], "hybrid draw"


def pick_recall_transform(cand, top, forced, max_generation):
    """Recall + Transform candidate: the RETRIEVED audio must itself qualify
    for a transformation (v0.2 classifier on that audio) and its result must
    stay within the generation limit.  The weighted choice is tried first."""
    for r in ([cand] if cand else []) + [r for r in top if r is not cand]:
        it = r["item"]
        if it.generation + 1 > max_generation or it.duration < 0.4:
            continue
        dec = decide(it.F, forced) if forced else it.info
        if dec["selected"] != "passthrough":
            return dict(r, decision=dec)
    return None


def analyse_item(audio, sr, forced=None):
    """v0.2 features + v0.2 decision + v0.3 descriptor for any audio."""
    F = extract_features(audio, sr)
    info = decide(F, forced)
    return F, info, memory_descriptor(F)


def energy_segments(env_db, hop_s, min_len, max_len):
    """Musically usable regions of a long recording: energy-aware activity
    (peak - 35 dB, and 10 dB above the file's floor unless that is within
    20 dB of the peak), gaps under 0.25 s
    bridged, overlong regions split at their quietest point, short ones
    dropped.  Returns [(start_s, end_s)]."""
    import numpy as np
    if len(env_db) == 0:
        return []
    floor = float(np.percentile(env_db, 10))
    peak = float(env_db.max())
    # 10 dB over the floor - but a file that sounds all the way through has
    # no silent floor, so the threshold never rises above peak - 20 dB
    thr = max(peak - 35.0, min(floor + 10.0, peak - 20.0))
    act = env_db > thr
    segs, start = [], None
    for i, v in enumerate(act):
        if v and start is None:
            start = i
        elif not v and start is not None:
            segs.append([start, i])
            start = None
    if start is not None:
        segs.append([start, len(act)])
    merged = []
    gap = int(0.25 / hop_s)
    for s0, s1 in segs:
        if merged and s0 - merged[-1][1] <= gap:
            merged[-1][1] = s1
        else:
            merged.append([s0, s1])
    out = []
    mx, mn = int(max_len / hop_s), int(min_len / hop_s)
    for s0, s1 in merged:
        while s1 - s0 > mx:
            lo, hi = s0 + mx // 2, s0 + mx
            cut = lo + int(np.argmin(env_db[lo:hi])) if hi > lo else s0 + mx
            out.append((s0, cut))
            s0 = cut
        out.append((s0, s1))
    pad = int(0.05 / hop_s)
    return [(max(0, a - pad) * hop_s, min(len(env_db), b + pad) * hop_s)
            for a, b in out if b - a >= mn]


AUDIO_EXTS = (".wav", ".wave", ".aif", ".aiff", ".aifc", ".flac", ".ogg", ".oga",
              ".mp3", ".w64", ".caf", ".rf64", ".au", ".snd")


def index_preloaded(folder, memory, cfg, progress=None, log=None):
    """Corpus C: read the performer's folder READ-ONLY, segment, analyse,
    index in RAM.  Nothing is written anywhere.  Returns (n_items, notes)."""
    import numpy as np
    import soundfile as sf
    log = log or (lambda *a, **k: None)
    notes = []
    if not folder or not os.path.isdir(folder):
        return 0, ["Corpus C folder not found: %s" % folder]
    files = []
    for dirpath, dirnames, names in os.walk(folder):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for n in sorted(names):
            if not n.startswith(".") and n.lower().endswith(AUDIO_EXTS):
                files.append(os.path.join(dirpath, n))
        if len(files) >= cfg["c_max_files"]:
            files = files[:cfg["c_max_files"]]
            notes.append("Corpus C: only the first %d files are used" % cfg["c_max_files"])
            break
    n_items = 0
    budget = 60.0 * cfg["max_ram_min"]
    for fi, path in enumerate(files):
        if n_items >= cfg["c_max_items"]:
            notes.append("Corpus C: segment limit %d reached" % cfg["c_max_items"])
            break
        if progress:
            progress("indexing preloaded corpus: file %d/%d, %d sounds" %
                     (fi + 1, len(files), n_items))
        try:
            info = sf.info(path)
            sr = int(info.samplerate)
            hop = max(1, int(round(0.01 * sr)))
            env = []
            for blk in sf.blocks(path, blocksize=hop * 200, dtype="float32", always_2d=True):
                m = blk.mean(axis=1)
                n = len(m) // hop
                if n:
                    r = np.sqrt(np.mean(m[:n * hop].reshape(n, hop) ** 2, axis=1) + 1e-20)
                    env.append(20 * np.log10(r + 1e-12))
            env = np.concatenate(env) if env else np.zeros(0)
            segs = energy_segments(env, hop / sr, cfg["c_min_item_s"], cfg["max_item_s"])
            if len(segs) > cfg["c_max_per_file"]:            # spread over the file
                idx = np.linspace(0, len(segs) - 1, cfg["c_max_per_file"]).round().astype(int)
                segs = [segs[i] for i in sorted(set(idx))]
            for s0, s1 in segs:
                if n_items >= cfg["c_max_items"]:
                    break
                start, stop = int(s0 * sr), int(s1 * sr)
                a, _ = sf.read(path, start=start, stop=stop, dtype="float32", always_2d=True)
                if len(a) < int(0.3 * sr) or float(np.max(np.abs(a))) < 1e-4:
                    continue
                F, dec, desc = analyse_item(a.astype(np.float64)[:, 0] if a.shape[1] == 1
                                            else a.astype(np.float64), sr)
                iid = memory.new_id("C")
                it = CorpusItem(iid, "C", a, sr, F, desc, dec, time.time(),
                                {"root": iid, "parent": None, "method": None, "generation": 0,
                                 "source": "%s @ %.2f-%.2f s" % (os.path.basename(path), s0, s1)})
                it.src = (path, start, stop)
                if memory.ram_seconds() + it.ram_seconds() > budget:
                    it.audio = None                       # on demand from the original
                memory.items["C"].append(it)
                n_items += 1
        except Exception as ex:                           # noqa: BLE001
            notes.append("Corpus C: skipped %s (%s)" % (os.path.basename(path), ex))
    log("Corpus C: %d sounds from %d files" % (n_items, len(files)))
    return n_items, notes


# ============================================================
# v0.2.0 CONTINUOUS ENGINE  (command: serve)
# ============================================================
# Ownership (one owner per resource; no shared lock is held during
# analysis or rendering):
#   PortAudio input callback  copies each block into in_q (bounded; never
#                             blocks; a full queue is counted as an overrun)
#   DETECT thread   owns the PhraseDetector, the input ring and the leakage
#                   estimator; finalises phrases, analyses them with the
#                   unchanged v0.1.3 scoring, writes job files -> render_q
#   RENDER thread   owns the ONE headless Praat child process -> play_q
#   PLAY thread     owns what the output stream plays (one answer at a time)
#   PortAudio output callback  copies the current answer to the device and
#                   records what was played (for the leakage estimate)
#   MAIN thread     status file, stop request, Praat heartbeat, limits,
#                   ordered shutdown
STALE_RESPONSE_S = 90.0        # an answer older than this is dropped (logged)
RENDER_TIMEOUT_S = 180.0       # a Praat render taking longer is killed
HEARTBEAT_TIMEOUT_S = 20.0     # Praat GUI gone for this long -> engine stops
LEAK_MAX_LAG_S = 0.5           # speaker->mic search window
LEAK_DISCARD_RHO2 = 0.75       # >= 75 % of a phrase explained by playback
LEAK_Z_MIN = 12.0              # PHAT peak prominence for a plausible acoustic path
LEAK_LAG_MIN_S = 0.002         # path delays outside [2 ms, max - 5 ms] are not
LEAK_LAG_EDGE_S = 0.005        #   trusted (edge peaks = periodic ambiguity)
LEAK_DOMINANCE = 1.5           # main PHAT peak / next peak (periodic -> ~1)
LEAK_GAIN_RHO = 0.7            # gain updated only when the input is mostly leakage
# AudioTools_CallResponse.praat form, one value per field in form order.
# Render mode (env AUDIOTOOLS_CR_JOB) ignores the values, but "praat --run"
# requires one argument per field.  KEEP IN SYNC WITH THE PRAAT FORM.
RENDER_FORM_ARGS = ["Selected Sound(s)", "Automatic (gesture classifier)", "4",
                    "default", "default", "9", "0.5", "0.6", "12",
                    "0", "Transform only (v0.2)", "-",          # v0.3.0 memory fields
                    "0", "0", "0"]
DISPLAY_NAMES = {
    "paulstretch": "Paulstretch", "markov": "Markov Soundscape Weaver",
    "mds": "MDS Space Navigator", "spiral": "Spiral Pitch Dance",
    "speeddev": "8-Channel Speed Deviations", "groove": "Percussive Groove Creator",
    "passthrough": "Original phrase",
}


def db_of(x):
    import numpy as np
    e = float(np.sqrt(np.mean(np.square(x, dtype=np.float64)) + 1e-20)) if len(x) else 0.0
    return 20 * math.log10(e + 1e-12)


class BoundedJobQueue:
    """FIFO with a hard limit and an explicit overflow policy.
    drop_oldest: the oldest UNSTARTED job is removed to make room.
    drop_newest: the incoming job is rejected.
    Dropped jobs are handed to on_drop (outside the lock) - never silent."""

    def __init__(self, name, maxlen, policy, on_drop):
        self.name, self.maxlen = name, max(1, int(maxlen))
        self.policy = policy if policy in ("drop_oldest", "drop_newest") else "drop_oldest"
        self.on_drop = on_drop
        self._d = collections.deque()
        self._cv = threading.Condition()
        self.closed = False

    def put(self, job):
        dropped = None
        with self._cv:
            if len(self._d) >= self.maxlen:
                if self.policy == "drop_newest":
                    dropped = job
                else:
                    dropped = self._d.popleft()
                    self._d.append(job)
            else:
                self._d.append(job)
            self._cv.notify()
        if dropped is not None:
            self.on_drop(dropped, "%s full (%d, %s)" % (self.name, self.maxlen, self.policy))
        return dropped is not job

    def get(self, timeout=0.2):
        with self._cv:
            if not self._d and not self.closed:
                self._cv.wait(timeout)
            if self._d:
                return self._d.popleft()
            return None

    def drain(self):
        with self._cv:
            out = list(self._d)
            self._d.clear()
            return out

    def close(self):
        with self._cv:
            self.closed = True
            self._cv.notify_all()

    def __len__(self):
        return len(self._d)


class Ring:
    """Mono float32 history with the wall-clock time of its newest sample.
    segment(t_end, dur) returns the samples that ended at wall time t_end;
    samples outside the history come back as zeros (= silence)."""

    def __init__(self, sr, seconds):
        import numpy as np
        self.np = np
        self.sr = sr
        self.n = int(sr * seconds)
        self.buf = np.zeros(self.n, np.float32)
        self.w = 0
        self.t_last = None
        self.lock = threading.Lock()

    def append(self, mono, t_end):
        m = len(mono)
        with self.lock:
            if m >= self.n:
                mono, m = mono[-self.n:], self.n
            i = self.w % self.n
            k = min(m, self.n - i)
            self.buf[i:i + k] = mono[:k]
            if m > k:
                self.buf[:m - k] = mono[k:]
            self.w += m
            self.t_last = t_end

    def segment(self, t_end, dur):
        np = self.np
        L = int(round(dur * self.sr))
        out = np.zeros(max(L, 0), np.float32)
        with self.lock:
            if self.t_last is None or L <= 0:
                return out
            end = self.w - int(round((self.t_last - t_end) * self.sr))
            start = end - L
            lo, hi = max(start, self.w - self.n, 0), min(end, self.w)
            if hi > lo:
                idx = np.arange(lo, hi) % self.n
                out[lo - start:hi - start] = self.buf[idx]
        return out


def leak_fit(x, y, max_lag_n):
    """Least-squares fit y[n] ~ a * x[n + max_lag_n - lag], lag in 0..max_lag_n
    (x must hold len(y) + max_lag_n samples ending with y).  Returns
    (gain a, correlation rho at the best lag, lag in samples).  rho^2 is the
    fraction of y's energy explained by the delayed, scaled playback."""
    import numpy as np
    x = np.asarray(x, np.float64)
    y = np.asarray(y, np.float64)
    Ly = len(y)
    if Ly == 0 or len(x) < Ly + max_lag_n:
        return 0.0, 0.0, 0
    ey = float(np.dot(y, y))
    if ey <= 1e-12:
        return 0.0, 0.0, 0
    N = 1 << int(math.ceil(math.log2(len(x) + Ly)))
    r = np.fft.irfft(np.fft.rfft(x, N) * np.conj(np.fft.rfft(y, N)), N)[:max_lag_n + 1]
    cs = np.concatenate([[0.0], np.cumsum(x * x)])
    ks = np.arange(max_lag_n + 1)
    ex = cs[ks + Ly] - cs[ks]
    rho = r / np.sqrt(np.maximum(ex, 1e-20) * ey)
    rho[ex <= 1e-12] = 0.0
    b = int(np.argmax(np.abs(rho)))
    a = float(r[b] / ex[b]) if ex[b] > 1e-12 else 0.0
    return a, float(rho[b]), max_lag_n - b


def leak_path(x, y, max_lag_n, sr):
    """Robust speaker->mic path test.  The DELAY is found with a PHAT-weighted
    (phase-only) cross-correlation: a real acoustic path gives one sharp peak,
    while a performer who merely plays the same pitch as the answer does not
    (plain correlation of two periodic signals peaks at many lags).  The gain
    and rho are then the least-squares values at that delay.
    Returns dict(lag samples, z = peak prominence, a = gain, rho, plausible)."""
    import numpy as np
    x = np.asarray(x, np.float64)
    y = np.asarray(y, np.float64)
    Ly = len(y)
    res = {"lag": 0, "z": 0.0, "dom": 0.0, "a": 0.0, "rho": 0.0, "plausible": False}
    if Ly == 0 or len(x) < Ly + max_lag_n or float(np.dot(y, y)) <= 1e-12:
        return res
    N = 1 << int(math.ceil(math.log2(len(x) + Ly)))
    X = np.fft.rfft(x, N)
    Y = np.fft.rfft(y, N)
    G = X * np.conj(Y)
    r = np.fft.irfft(G / (np.abs(G) + 1e-12), N)[:max_lag_n + 1]
    b = int(np.argmax(r))
    guard = max(1, int(0.001 * sr))
    mask = np.ones(len(r), bool)
    mask[max(0, b - guard):b + guard + 1] = False
    z = float((r[b] - r[mask].mean()) / (r[mask].std() + 1e-12))
    mask2 = np.ones(len(r), bool)
    mask2[max(0, b - 2 * guard):b + 2 * guard + 1] = False
    second = float(r[mask2].max()) if mask2.any() else 0.0
    dom = float(r[b] / second) if second > 1e-12 else 99.0
    lag = max_lag_n - b
    seg = x[b:b + Ly]
    ex = float(np.dot(seg, seg))
    ey = float(np.dot(y, y))
    rt = float(np.dot(seg, y))
    res.update(lag=lag, z=z, dom=dom, a=(rt / ex if ex > 1e-12 else 0.0),
               rho=(rt / math.sqrt(ex * ey) if ex > 1e-12 else 0.0))
    res["plausible"] = (z >= LEAK_Z_MIN and dom >= LEAK_DOMINANCE and
                        int(LEAK_LAG_MIN_S * sr) <= lag <= max_lag_n - int(LEAK_LAG_EDGE_S * sr))
    return res


def praat_candidates(hint):
    c = []
    if hint and hint.lower() not in ("", "none", "auto"):
        c.append(hint)
    if os.environ.get("PRAAT_EXE"):
        c.append(os.environ["PRAAT_EXE"])
    for n in ("praat", "Praat", "praat_nogui", "praat_barren"):
        w = shutil.which(n)
        if w:
            c.append(w)
    home = os.path.expanduser("~")
    if sys.platform.startswith("win"):
        for base in (os.environ.get("ProgramFiles", ""), os.environ.get("ProgramFiles(x86)", ""),
                     os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs")):
            if base:
                c.append(os.path.join(base, "Praat", "Praat.exe"))
                c.append(os.path.join(base, "Praat.exe"))
        for d in ("Desktop", "Downloads", "Documents"):
            root = os.path.join(home, d)
            c.append(os.path.join(root, "Praat.exe"))
            try:
                for sub in os.listdir(root):
                    p = os.path.join(root, sub)
                    if os.path.isdir(p):
                        c.append(os.path.join(p, "Praat.exe"))
                        c.append(os.path.join(p, "audio", "Praat.exe"))
            except OSError:
                pass
    elif sys.platform == "darwin":
        c += ["/Applications/Praat.app/Contents/MacOS/Praat",
              os.path.join(home, "Applications/Praat.app/Contents/MacOS/Praat")]
    else:
        c += ["/usr/bin/praat", "/usr/local/bin/praat", os.path.join(home, "bin/praat")]
    seen, out = set(), []
    for x in c:
        if x and x not in seen:
            seen.add(x)
            out.append(x)
    return out


class PraatRenderer:
    """Runs AudioTools_CallResponse.praat headless in render mode, one job at
    a time.  The child is a tracked Popen: killed on timeout and on stop."""

    def __init__(self, hint, script, session, log):
        self.script, self.session, self.log = script, session, log
        self.exe, self.flags, self.version, self.error = "", [], 0, ""
        self.proc = None
        self.lock = threading.Lock()
        self.hint = hint

    @staticmethod
    def _resolve(path):
        path = os.path.expanduser(path or "")
        if os.path.isdir(path):
            for exe in ("Praat.exe", "praat.exe", "Praat", "praat", "praat_nogui",
                        "praat_barren", "Praat.app/Contents/MacOS/Praat"):
                cand = os.path.join(path, exe)
                if os.path.isfile(cand):
                    return cand
            return ""
        return path if os.path.isfile(path) else (shutil.which(path) or "")

    def _popen_kwargs(self):
        kw = {}
        if sys.platform.startswith("win"):
            kw["creationflags"] = 0x08000000          # CREATE_NO_WINDOW
        return kw

    def probe(self, path):
        """Prove an executable by RUNNING a script that writes praatVersion
        to a marker file (Windows Praat's stdout is empty or UTF-16)."""
        path = self._resolve(path)
        if not path:
            return False
        marker = os.path.join(self.session, "praat_probe.txt")
        script = os.path.join(self.session, "praat_probe.praat")
        with open(script, "w", encoding="utf-8") as fh:
            fh.write('form: "probe"\n    sentence: "Out", ""\nendform\n'
                     'writeFileLine: out$, praatVersion\n')
        for flags in (["--FULL-TRUST", "--no-pref-files"], ["--no-pref-files"]):
            try:
                if os.path.exists(marker):
                    os.remove(marker)
                subprocess.run([path] + flags + ["--run", script, marker],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               timeout=60, **self._popen_kwargs())
            except Exception as ex:                          # noqa: BLE001
                self.error = "%s: %s" % (path, ex)
                continue
            if os.path.exists(marker):
                try:
                    with open(marker, encoding="utf-8", errors="replace") as fh:
                        v = int(float(fh.read().split()[0]))
                except Exception:                            # noqa: BLE001
                    v = 0
                self.exe, self.flags, self.version = path, flags, v
                for f in (marker, script):
                    try:
                        os.remove(f)
                    except OSError:
                        pass
                return True
        return False

    def find(self):
        for c in praat_candidates(self.hint):
            if self.probe(c):
                return True
        self.error = ("no runnable Praat executable found - set praatExe$ at the top "
                      "of AudioTools_CallResponse.praat (the executable or its folder)")
        return False

    def kill(self):
        with self.lock:
            p = self.proc
        if p is not None and p.poll() is None:
            try:
                p.terminate()
                p.wait(2)
            except Exception:                                # noqa: BLE001
                try:
                    p.kill()
                    p.wait(2)
                except Exception:                            # noqa: BLE001
                    pass

    def render(self, job, stop_ev, max_response, plugin_root):
        """Returns (ok, message).  On success job.answer/answer_sr/used are set."""
        import soundfile as sf
        jobf = os.path.join(self.session, "job_%s.txt" % job.tag)
        out = os.path.join(self.session, "out_%s.wav" % job.tag)
        res = os.path.join(self.session, "res_%s.txt" % job.tag)
        plog = os.path.join(self.session, "praat_%s.log" % job.tag)
        job.files += [jobf, out, res, plog]
        write_kv_atomic(jobf, list(job.pairs) + [
            ("wav", job.wav), ("out", out), ("result", res), ("plugin_root", plugin_root),
            ("max_response", fnum(max_response, 3)), ("job_id", job.tag)])
        env = dict(os.environ)
        env["AUDIOTOOLS_CR_JOB"] = jobf
        argv = [self.exe] + self.flags + ["--run", self.script] + RENDER_FORM_ARGS
        with open(plog, "wb") as lf:
            try:
                p = subprocess.Popen(argv, stdout=lf, stderr=subprocess.STDOUT, env=env,
                                     **self._popen_kwargs())
            except Exception as ex:                          # noqa: BLE001
                return False, "cannot start Praat: %s" % ex
            with self.lock:
                self.proc = p
            t0 = time.time()
            reason = ""
            while p.poll() is None:
                if stop_ev.is_set():
                    reason = "session stopped"
                elif time.time() - t0 > RENDER_TIMEOUT_S:
                    reason = "render timeout (%.0f s)" % RENDER_TIMEOUT_S
                if reason:
                    self.kill()
                    break
                time.sleep(0.02)
            with self.lock:
                self.proc = None
        if reason:
            return False, reason
        meta = {}
        try:
            with open(res, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if "=" in line:
                        k, v = line.rstrip("\r\n").split("=", 1)
                        meta[k] = v
        except OSError:
            tail = ""
            try:
                with open(plog, "rb") as fh:
                    raw = fh.read()[-600:]
                tail = raw.replace(b"\x00", b"").decode("utf-8", "replace").strip()
            except OSError:
                pass
            return False, "Praat wrote no result (exit %s) %s" % (p.returncode, tail[-300:])
        job.praat_log = meta.get("log", "")
        if meta.get("end") != "1" or meta.get("status") != "ok":
            return False, meta.get("msg", "render failed")
        try:
            a, sr = sf.read(out, dtype="float32", always_2d=True)
        except Exception as ex:                              # noqa: BLE001
            return False, "cannot read rendered WAV: %s" % ex
        used = meta.get("used", "")
        if used not in TRANSFORM_IDS:
            return False, "render reported an unknown transformation '%s'" % used
        job.answer, job.answer_sr, job.used = a, int(sr), used
        job.praat_sec = meta.get("sec", "")
        return True, meta.get("msg", "ok")


class Job:
    def __init__(self, jid, audio, sr, t):
        self.id = jid
        self.tag = "%04d" % jid
        self.audio = audio            # frames x channels float32 (musician)
        self.sr = sr
        self.t = dict(t)              # wall-clock timestamps
        self.selected = ""
        self.used = ""
        self.pairs = []
        self.wav = ""
        self.files = []
        self.answer = None
        self.answer_sr = sr
        self.msg = ""
        self.praat_log = ""
        self.praat_sec = ""
        # v0.3.0 sonic memory
        self.kind = "transform"       # transform | recall | recall_transform
        self.phrase_id = ""           # Corpus A id of the live phrase
        self.source_id = ""           # corpus id of the audio sent to Praat
        self.source_corpus = "A"
        self.recall_item = None
        self.match = None
        self.gen_out = 1              # generation of a Praat result
        self.layer = None             # optional quiet recalled layer
        self.layer_sr = sr
        self.action_name = ""


def pid_alive(pid):
    """True while process `pid` exists (no psutil; Windows via ctypes)."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if sys.platform.startswith("win"):
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.windll.kernel32
        h = k32.OpenProcess(0x1000, False, pid)          # QUERY_LIMITED_INFORMATION
        if not h:
            return False
        code = wintypes.DWORD()
        ok = k32.GetExitCodeProcess(h, ctypes.byref(code))
        k32.CloseHandle(h)
        return bool(ok) and code.value == 259             # STILL_ACTIVE
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def proc_start_token(pid):
    """v0.3.1: an identity token for process `pid` = its start time as the
    OS reports it ("" if unknown).  A PID number alone can be reused by an
    unrelated process; PID + start time cannot."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return ""
    if pid <= 0:
        return ""
    try:
        if sys.platform.startswith("win"):
            import ctypes
            from ctypes import wintypes
            k32 = ctypes.windll.kernel32
            h = k32.OpenProcess(0x1000, False, pid)
            if not h:
                return ""
            try:
                c, e, k, u = (wintypes.FILETIME() for _ in range(4))
                if not k32.GetProcessTimes(h, ctypes.byref(c), ctypes.byref(e),
                                           ctypes.byref(k), ctypes.byref(u)):
                    return ""
                return "w%d" % ((c.dwHighDateTime << 32) | c.dwLowDateTime)
            finally:
                k32.CloseHandle(h)
        if os.path.exists("/proc/%d/stat" % pid):
            with open("/proc/%d/stat" % pid) as fh:
                raw = fh.read()
            return "l" + raw[raw.rindex(")") + 2:].split()[19]      # field 22: starttime
        out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True,
                             text=True, timeout=5).stdout.strip()
        return ("m" + out.replace(" ", "_")) if out else ""
    except Exception:                                        # noqa: BLE001
        return ""


def owner_alive(info):
    """v0.3.1: is the engine recorded in launch.txt (pid + start token) still
    running?  A live PID whose start time differs is a REUSED PID = dead."""
    pid = info.get("pid")
    if not pid or not pid_alive(pid):
        return False
    tok = info.get("start", "")
    if not tok:
        return True                  # identity unknown: treat as alive (never delete)
    now = proc_start_token(pid)
    return (not now) or now == tok


def remove_tree(path, attempts=40, delay=0.25):
    """Delete a session folder with bounded retries (Windows file locks).
    Returns the list of paths that could NOT be removed (empty = success)."""
    for _ in range(attempts):
        if not os.path.exists(path):
            return []
        for dirpath, dirnames, names in os.walk(path, topdown=False):
            for n in names:
                try:
                    os.remove(os.path.join(dirpath, n))
                except OSError:
                    pass
            for d in dirnames:
                try:
                    os.rmdir(os.path.join(dirpath, d))
                except OSError:
                    pass
        try:
            os.rmdir(path)
        except OSError:
            pass
        if not os.path.exists(path):
            return []
        time.sleep(delay)
    left = []
    for dirpath, dirnames, names in os.walk(path):
        left += [os.path.join(dirpath, n) for n in names]
    return left or [path]


# files the Praat GUI still needs after the engine has finished; everything
# else in the session folder belongs to the engine and is deleted by it
PRAAT_OWNED = ("status.txt", "summary.txt", "praat_alive.txt", "stop.request", "launch.txt",
               "cleanup.pending")


class Engine:
    def __init__(self, args, sd):
        import numpy as np
        self.np, self.sd, self.a = np, sd, args
        self.sr, self.ch = int(args.sr), int(args.channels)
        self.session = args.session
        self.stop_ev = threading.Event()
        self.in_q = queue.Queue(maxsize=3000)          # 30 s of 10 ms blocks
        self.phrase_q = BoundedJobQueue("pending phrases", args.max_pending,
                                        args.overflow, self._dropped)
        self.render_q = BoundedJobQueue("pending renders", args.max_pending,
                                        args.overflow, self._dropped)
        self.play_q = BoundedJobQueue("pending responses", args.max_responses,
                                      args.overflow, self._dropped)
        self.b_q = queue.Queue(maxsize=8)               # Praat results -> Corpus B
        self.det = PhraseDetector(self.sr, self.ch, args.sensitivity, args.min_phrase,
                                  args.end_silence, args.max_phrase, args.preroll)
        if args.leak_guard:
            self.det.leak_level = self._expected_leak_db
        self.hop_s = self.det.hop_s
        self.in_ring = Ring(self.sr, 3.0)
        self.out_ring = Ring(self.sr, args.max_phrase + LEAK_MAX_LAG_S + 2.0)
        self.c = collections.Counter()
        self.state, self.message, self.processing, self.playing = "starting", "", "", ""
        self.stage = "start"
        self.input_db = -120.0
        self.leak_db, self.leak_rho = None, 0.0
        self.leak_lag, self.leak_cand, self.leak_conf = None, None, 0
        self.out_hold_db, self.out_hold_t = -120.0, 0.0
        self.cur, self.cur_pos = None, 0
        self.play_done = threading.Event()
        self.out_ch = 1
        self.next_id = 1
        self.fatal = ""
        self.summary = []
        self.events = []
        self.delays = []
        self.t_start = time.time()
        self.t_activity = time.time()
        self.log_fh = None
        if args.debug_log and args.debug_log.lower() != "none":
            try:
                self.log_fh = open(args.debug_log, "a", encoding="utf-8")
            except OSError:
                self.log_fh = None
        self.renderer = PraatRenderer(args.praat, args.script, self.session, self.log)
        # ---- v0.3.0 sonic memory ----
        self.mcfg = {
            "enabled": bool(args.memory) and args.response_mode != "transform",
            "response_mode": args.response_mode, "use_A": bool(args.use_a),
            "use_B": bool(args.use_b), "use_C": bool(args.use_c),
            "sim_mode": args.sim_mode, "min_similarity": args.min_sim,
            "w_live": args.w_live, "w_processed": args.w_processed,
            "w_preloaded": args.w_preloaded, "p_transform": args.p_transform,
            "p_recall": args.p_recall, "p_recall_transform": args.p_recall_transform,
            "max_generation": args.max_generation, "max_live": args.max_live,
            "max_processed": args.max_processed, "max_ram_min": args.max_ram_min,
            "max_item_s": args.max_item_s, "candidates": args.candidates,
            "evolving": bool(args.evolving), "layered": bool(args.layered),
            "recent_exclude": args.recent_exclude, "cooldown": args.cooldown,
            "same_family_exclusion": bool(args.same_family),
            "c_max_items": args.c_max_items, "c_max_files": args.c_max_files,
            "c_max_per_file": args.c_max_per_file, "c_min_item_s": args.c_min_item_s,
        }
        seed = args.seed if args.seed > 0 else 1 + (zlib.crc32(self.session.encode()) % 2000000000)
        self.memory = SonicMemory(self.mcfg, seed, self.log)
        self.last_recall, self.last_match, self.last_action = "", "", ""
        self.fault = os.environ.get("AUDIOTOOLS_CR_FAULT", "")   # test hook, inert by default

    # ---------------- logging ----------------
    def log(self, msg, event=False):
        line = "%8.3f  %s" % (time.time() - self.t_start, msg)
        if event:
            self.events.append(line)
        if self.log_fh:
            try:
                self.log_fh.write(line + "\n")
                self.log_fh.flush()
            except (OSError, ValueError):
                pass

    def _dropped(self, job, why):
        self.c["dropped"] += 1
        self.log("DROPPED job %s (%s): %s" % (job.tag, job.selected or "unanalysed", why), True)
        self._cleanup_job(job)

    def _cleanup_job(self, job):
        for f in job.files:
            for _ in range(20):                          # Windows: bounded retries
                try:
                    if os.path.exists(f):
                        os.remove(f)
                    break
                except OSError:
                    time.sleep(0.05)
        job.files = []

    def _check_fault(self, where):
        if self.fault == where:
            self.fault = ""
            raise RuntimeError("injected test fault in %s worker" % where)

    # ---------------- audio callbacks (no DSP, no I/O, no locks held long) --------
    def _in_cb(self, indata, frames, tinfo, status):
        if status:
            self.c["input_status"] += 1
        try:
            self.in_q.put_nowait((indata.copy(), time.time()))
        except queue.Full:
            self.c["overruns"] += 1

    def _out_cb(self, outdata, frames, tinfo, status):
        if status:
            self.c["output_status"] += 1
        buf = self.cur
        if buf is None:
            outdata.fill(0)
        else:
            p = self.cur_pos
            n = min(frames, len(buf) - p)
            outdata[:n] = buf[p:p + n]
            if n < frames:
                outdata[n:] = 0
            self.cur_pos = p + n
            if self.cur_pos >= len(buf):
                self.cur = None
                self.play_done.set()
        mono = outdata[:, 0] if outdata.shape[1] == 1 else outdata.mean(axis=1)
        t = time.time()
        self.out_ring.append(mono, t)
        lv = db_of(mono)
        held = self.out_hold_db - 20.0 * (t - self.out_hold_t)
        if lv >= held:
            self.out_hold_db, self.out_hold_t = lv, t

    def _out_level_now(self):
        return self.out_hold_db - 20.0 * (time.time() - self.out_hold_t)

    def _expected_leak_db(self):
        if self.leak_db is None:
            return None
        lv = self._out_level_now()
        if lv < -70:
            return None
        return lv + self.leak_db

    # ---------------- DETECT thread (detection only; never searches memory) ----
    def _detect_loop(self):
        np = self.np
        hop = self.det.hop
        pending = np.zeros((0, self.ch), np.float32)
        t_leak = 0.0
        try:
            while not self.stop_ev.is_set():
                try:
                    block, tb = self.in_q.get(timeout=0.2)
                except queue.Empty:
                    continue
                mono = block[:, 0] if block.shape[1] == 1 else block.mean(axis=1)
                self.in_ring.append(mono, tb)
                pending = np.concatenate([pending, block], axis=0) if len(pending) else block
                while len(pending) >= hop:
                    ev = self.det.feed(pending[:hop])
                    lv = db_of(pending[:hop, 0] if self.ch == 1 else pending[:hop].mean(axis=1))
                    self.input_db = max(lv, self.input_db - 1.5)
                    pending = pending[hop:]
                    if ev == "onset":
                        self.log("onset (floor %.1f dBFS, thr %.1f)" %
                                 (self.det.floor, self.det.thresholds()[0]))
                    elif ev == "discarded":
                        self.log("short trigger discarded (< %.2f s)" % self.a.min_phrase)
                    elif ev == "end":
                        self._finalize(tb)
                        self.det.rearm()
                if tb - t_leak >= 1.0:
                    t_leak = tb
                    self._update_leak(tb)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            self.fatal = "detector failed: %s" % ex
            self.log(self.fatal + " | " + traceback.format_exc().replace("\n", " | "), True)
            self.stop_ev.set()

    def _update_leak(self, t_end):
        """A leakage level is trusted only for a VALIDATED path: a sharp PHAT
        peak at a plausible delay, confirmed by two consecutive estimates
        within 1 ms.  Otherwise any previous estimate decays."""
        if self._out_level_now() < -50:
            return
        y = self.in_ring.segment(t_end, 1.0)
        x = self.out_ring.segment(t_end, 1.0 + LEAK_MAX_LAG_S)
        if db_of(x) < -55 or db_of(y) < -70:
            return
        r = leak_path(x, y, int(LEAK_MAX_LAG_S * self.sr), self.sr)
        self.leak_rho = r["rho"]
        if r["plausible"] and r["a"] != 0:
            if self.leak_cand is not None and abs(r["lag"] - self.leak_cand) <= int(0.001 * self.sr):
                self.leak_conf += 1
            else:
                self.leak_conf = 1
            self.leak_cand = r["lag"]
        else:
            self.leak_conf, self.leak_cand = 0, None
        if self.leak_conf >= 2:
            self.leak_lag = r["lag"]
            if abs(r["rho"]) >= LEAK_GAIN_RHO:
                g = 20 * math.log10(abs(r["a"]))
                self.leak_db = g if self.leak_db is None else max(g, self.leak_db - 0.5)
                self.log("leakage path %.1f dB at %.1f ms (z %.0f, dominance %.1f, rho %.2f)" %
                         (g, 1000.0 * r["lag"] / self.sr, r["z"], r["dom"], r["rho"]))
            else:
                self.log("leakage path confirmed at %.1f ms; gain kept (performer playing, "
                         "rho %.2f)" % (1000.0 * r["lag"] / self.sr, r["rho"]))
        elif self.leak_db is not None and self.leak_conf == 0:
            self.leak_db -= 3.0
            if self.leak_db < -80:
                self.leak_db, self.leak_lag = None, None
        if self.leak_db is not None and self.leak_db > -20 and not self.c["leak_warned"]:
            self.c["leak_warned"] = 1
            self.log("WARNING: speaker->microphone leakage %.1f dB - use headphones or "
                     "separate the output from the microphone" % self.leak_db, True)

    def _finalize(self, tb):
        """Cut the finished phrase, run the (cheap) leakage check, hand it to
        the brain worker.  Analysis and memory work happen THERE."""
        np = self.np
        d = self.det
        tail = int(round(0.15 / d.hop_s))
        end_idx = min(len(d.buf), d.last_active + 1 + tail)
        audio = d.phrase_audio()
        t_audio_end = tb - (len(d.buf) - end_idx) * d.hop_s
        t_end = tb - d.silence_frames_after_last_active() * d.hop_s
        dur = len(audio) / self.sr
        t_audio_start = t_audio_end - dur
        t_onset = t_audio_start + d.start_active * d.hop_s
        jid = self.next_id
        self.next_id += 1
        job = Job(jid, audio.astype(np.float32), self.sr,
                  {"onset": t_onset, "end": t_end, "detected": time.time()})
        self.c["phrases"] += 1
        self.t_activity = time.time()
        self.log("phrase %s: %.2f s, ended by %s, detection delay %.3f s" %
                 (job.tag, dur, d.ended_by, time.time() - t_end))
        mono = audio[:, 0] if audio.shape[1] == 1 else audio.mean(axis=1)
        if self.a.leak_guard and self.leak_lag is not None and self._out_level_now() > -70:
            x = self.out_ring.segment(t_audio_end, dur + LEAK_MAX_LAG_S)
            if db_of(x) > -55:
                mx = int(LEAK_MAX_LAG_S * self.sr)
                a, rho, lag = leak_fit(x, mono, mx)
                tol = int(0.001 * self.sr)
                if abs(lag - self.leak_lag) > tol:
                    a, rho, lag = 0.0, 0.0, lag
                if rho * rho >= LEAK_DISCARD_RHO2:
                    self.c["leak_discarded"] += 1
                    self.log("phrase %s DISCARDED as playback leakage: %.0f %% of its energy "
                             "is the delayed answer (gain %.1f dB, lag %.0f ms)" %
                             (job.tag, 100 * rho * rho, 20 * math.log10(abs(a) + 1e-12),
                              1000.0 * lag / self.sr), True)
                    return
        if dur < 0.25:
            self.c["too_short"] += 1
            self.log("phrase %s too short for analysis (%.3f s)" % (job.tag, dur), True)
            return
        self.phrase_q.put(job)

    # ---------------- BRAIN thread: analysis, memory, decision ----------------
    def _brain_loop(self):
        try:
            while not self.stop_ev.is_set():
                job = self.phrase_q.get(0.05)
                if job is not None:
                    self._check_fault("brain")
                    self._think(job)
                    continue
                try:
                    done = self.b_q.get_nowait()
                except queue.Empty:
                    continue
                self._insert_processed(done)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            self.fatal = "analysis worker failed: %s" % ex
            self.log(self.fatal + " | " + traceback.format_exc().replace("\n", " | "), True)
            self.stop_ev.set()

    def _forced(self):
        return None if self.a.force in ("", "auto") else self.a.force

    def _write_input(self, job, audio, sr, name):
        import soundfile as sf
        path = os.path.join(self.session, "%s_%s.wav" % (name, job.tag))
        job.files.append(path)                            # tracked BEFORE writing
        sf.write(path, audio, sr, subtype="FLOAT")
        job.wav = path

    def _think(self, job):
        np = self.np
        t0 = time.perf_counter()
        a64 = job.audio.astype(np.float64)
        a_in = a64[:, 0] if a64.shape[1] == 1 else a64
        try:
            F = extract_features(a_in, self.sr)
            t1 = time.perf_counter()
            info = decide(F, self._forced())
            nch = 1 if a_in.ndim == 1 else a_in.shape[1]
            seed = audio_seed(a_in)
            P = params_all(F, a_in, self.sr, nch, seed)
            desc = memory_descriptor(F) if self.mcfg["enabled"] else None
            t2 = time.perf_counter()
        except Exception as ex:                              # noqa: BLE001
            self.c["failed"] += 1
            self.log("phrase %s analysis failed: %s" % (job.tag, ex), True)
            return
        job.t["analysed"] = time.time()
        mem = self.memory
        job.phrase_id = mem.new_id("A")
        action, why, cand, rt = "transform", "sonic memory off", None, None
        t_mem = time.perf_counter()
        if self.mcfg["enabled"]:
            recentA = [it.id for it in mem.items["A"][-self.mcfg["recent_exclude"]:]] \
                if self.mcfg["recent_exclude"] > 0 else []
            horizon = 60.0 * (self.a.session_minutes if self.a.session_minutes > 0 else 20.0)
            progress = (time.time() - self.t_start) / horizon
            cand, top, why = mem.retrieve(desc, exclude_ids={job.phrase_id} | set(recentA),
                                          exclude_roots=set(recentA), progress=progress)
            rt = pick_recall_transform(cand, top, self._forced(), self.mcfg["max_generation"])
            action, why2 = mem.choose_action(cand, rt)
            why = why2 if cand or rt else why + " -> transform"
        t_mem = time.perf_counter() - t_mem
        job.kind = action
        if action == "recall":
            it = cand["item"]
            mem.mark_recalled(it)
            job.recall_item, job.match, job.selected = it, cand["match"], "recall"
            job.source_id, job.source_corpus = it.id, it.corpus
            job.action_name = "Recall %s (%s)" % (it.id, CORPUS_NAMES[it.corpus])
            self.last_recall, self.last_match = "Corpus %s" % it.corpus, "%.2f" % cand["match"]
        elif action == "recall_transform":
            it = rt["item"]
            mem.mark_recalled(it)
            ia = it.get_audio()
            ia64 = ia.astype(np.float64)
            ia_in = ia64[:, 0] if ia64.shape[1] == 1 else ia64
            iseed = audio_seed(ia_in)
            dec = rt["decision"]
            iP = params_all(it.F, ia_in, it.sr, 1 if ia_in.ndim == 1 else ia_in.shape[1], iseed)
            job.pairs = decision_pairs(it.F, dec, iP, [
                ("status", "ok"), ("message", "ok"), ("source", "corpus %s" % it.id),
                ("duration", fnum(it.F["duration"], 4)), ("sr", it.sr), ("seed", iseed),
                ("t_phrase_end_epoch", "%.4f" % job.t["end"])])
            self._write_input(job, ia_in.astype(np.float32), it.sr, "c")
            job.selected, job.match = dec["selected"], rt["match"]
            job.source_id, job.source_corpus = it.id, it.corpus
            job.gen_out = it.generation + 1
            job.action_name = "%s on %s" % (DISPLAY_NAMES.get(job.selected, job.selected), it.id)
            self.last_recall, self.last_match = "Corpus %s" % it.corpus, "%.2f" % rt["match"]
        else:
            job.selected = info["selected"]
            job.source_id, job.source_corpus, job.gen_out = job.phrase_id, "A", 1
            job.action_name = DISPLAY_NAMES.get(job.selected, job.selected)
            if job.selected != "passthrough":
                self._write_input(job, a_in.astype(np.float32), self.sr, "p")
            job.pairs = decision_pairs(F, info, P, [
                ("status", "ok"), ("message", "ok"), ("source", "live continuous"),
                ("duration", fnum(F["duration"], 4)), ("sr", self.sr), ("channels", nch),
                ("seed", seed), ("t_features", fnum(t1 - t0, 4)), ("t_select", fnum(t2 - t1, 4)),
                ("t_phrase_end_epoch", "%.4f" % job.t["end"])])
            if self.mcfg["layered"] and cand is not None:
                it = cand["item"]
                job.layer, job.layer_sr = it.get_audio(), it.sr
                mem.mark_recalled(it)
            if not self.mcfg["enabled"]:
                self.last_recall, self.last_match = "", ""
        self.last_action = job.action_name
        self.log("phrase %s (%s) -> %s (%s)%s  [analysis %.0f ms, memory search %.0f ms over %d "
                 "sounds]" % (job.tag, job.phrase_id, job.action_name, why,
                              "" if job.match is None else "  match %.2f" % job.match,
                              1000 * (t2 - t0), 1000 * t_mem, sum(mem.counts().values())), True)
        if self.log_fh:
            rep = build_report(F, info, P, "Phrase %s - live continuous, %.2f s" %
                               (job.tag, F["duration"]))
            self.log("analysis %s (features %.3f s, selection %.3f s)\n%s" %
                     (job.tag, t1 - t0, t2 - t1, rep.rstrip()))
        # the live phrase enters Corpus A only AFTER its own retrieval
        if self.mcfg["enabled"] and self.mcfg["use_A"]:
            a_store = job.audio[:int(self.mcfg["max_item_s"] * self.sr)]
            mem.add(CorpusItem(job.phrase_id, "A", a_store, self.sr, F, desc, info, time.time(),
                               {"root": job.phrase_id, "parent": None, "method": None,
                                "generation": 0, "source": "live phrase %s" % job.tag}))
        self.render_q.put(job)

    def _insert_processed(self, r):
        """A genuinely NEW Praat result becomes a Corpus B entry, analysed
        from its own audio (not from its source).  `r` is a snapshot made by
        the render worker (tag, answer, sr, used, source_id, gen_out)."""
        mem = self.memory
        if not (self.mcfg["enabled"] and self.mcfg["use_B"]) or r["answer"] is None:
            return
        if r["gen_out"] > self.mcfg["max_generation"]:
            self.log("job %s: generation %d > %d - not stored" %
                     (r["tag"], r["gen_out"], self.mcfg["max_generation"]))
            return
        np = self.np
        sr = r["sr"]
        a = r["answer"][:int(self.mcfg["max_item_s"] * sr)]
        if len(a) < int(0.3 * sr):
            return
        a64 = a.astype(np.float64)
        F, dec, desc = analyse_item(a64[:, 0] if a64.shape[1] == 1 else a64, sr)
        parent = mem.find(r["source_id"])
        if parent is not None:
            sim = mem.similarity(desc, [parent], "hybrid")[0][1]
            if sim >= IDENTITY_SIM:
                self.log("job %s: result almost identical to %s (%.2f) - not stored" %
                         (r["tag"], parent.id, sim), True)
                return
        iid = mem.new_id("B")
        root = parent.root if parent is not None else r["source_id"]
        mem.add(CorpusItem(iid, "B", a.astype(np.float32), sr, F, desc, dec,
                           time.time(), {"root": root, "parent": r["source_id"],
                                         "method": r["used"], "generation": r["gen_out"],
                                         "source": "%s of %s" % (r["used"], r["source_id"])}))
        self.log("memory: %s = %s of %s (generation %d)" %
                 (iid, r["used"], r["source_id"], r["gen_out"]), True)

    # ---------------- RENDER thread ----------------
    def _render_loop(self):
        try:
            while not self.stop_ev.is_set():
                job = self.render_q.get(0.2)
                if job is None:
                    continue
                self._check_fault("render")
                if job.kind == "recall":
                    a = job.recall_item.get_audio()
                    job.answer, job.answer_sr, job.used = a, job.recall_item.sr, "recall"
                    job.msg = "recalled %s" % job.recall_item.id
                elif job.selected == "passthrough":
                    job.answer, job.answer_sr, job.used = job.audio, job.sr, "passthrough"
                    job.msg = "no transformation reached its confidence threshold"
                    self.c["passthrough"] += 1
                    self.log("job %s: %s - answering with the phrase itself" % (job.tag, job.msg), True)
                else:
                    self.processing = job.action_name
                    job.t["render_start"] = time.time()
                    ok, msg = self.renderer.render(job, self.stop_ev, self.a.max_response,
                                                   self.a.plugin_root)
                    job.t["render_end"] = time.time()
                    self.processing = ""
                    if self.stop_ev.is_set():
                        self.c["dropped"] += 1
                        self.log("job %s (%s): render interrupted by stop (%s) - not played" %
                                 (job.tag, job.selected, msg), True)
                        self._cleanup_job(job)
                        break
                    if self.log_fh and job.praat_log:
                        self.log("praat %s: %s" % (job.tag, job.praat_log))
                    if ok:
                        job.msg = msg
                        if job.used != job.selected:
                            self.log("job %s: %s failed in Praat, runner-up %s used" %
                                     (job.tag, job.selected, job.used), True)
                        try:
                            # a snapshot: the play worker releases job.answer later
                            self.b_q.put_nowait({"tag": job.tag, "answer": job.answer,
                                                 "sr": job.answer_sr, "used": job.used,
                                                 "source_id": job.source_id,
                                                 "gen_out": job.gen_out})
                        except queue.Full:
                            self.log("job %s: memory insert queue full - result not stored" %
                                     job.tag, True)
                    else:
                        self.c["failed"] += 1
                        job.answer, job.answer_sr, job.used = job.audio, job.sr, "passthrough"
                        job.msg = "render failed: %s" % msg
                        self.log("job %s (%s): %s - answering with the untransformed phrase" %
                                 (job.tag, job.selected, job.msg), True)
                    self.log("job %s rendered in %.2f s" %
                             (job.tag, job.t["render_end"] - job.t["render_start"]))
                    self._cleanup_job(job)                # Praat files: no longer needed
                self.play_q.put(job)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            self.fatal = "render worker failed: %s" % ex
            self.log(self.fatal + " | " + traceback.format_exc().replace("\n", " | "), True)
            self.stop_ev.set()

    # ---------------- PLAY thread ----------------
    def _prepare(self, a, sr):
        """Format conversion only (sample rate, channel count, length cap):
        the audio itself is the Praat-rendered (or recalled) sound."""
        np = self.np
        import scipy.signal
        if sr != self.sr:
            g = math.gcd(int(sr), self.sr)
            a = scipy.signal.resample_poly(a, self.sr // g, int(sr) // g, axis=0).astype(np.float32)
        if a.shape[1] == self.out_ch:
            b = a
        elif self.out_ch == 1:
            b = a.mean(axis=1, keepdims=True)
        elif a.shape[1] == 1:
            b = np.repeat(a, self.out_ch, axis=1)
        else:
            b = np.zeros((len(a), self.out_ch), np.float32)
            b[:, :min(a.shape[1], self.out_ch)] = a[:, :self.out_ch]
        cap = int(self.a.max_response * self.sr)
        truncated = False
        if len(b) > cap:
            b = b[:cap].copy()
            f = min(len(b), int(0.05 * self.sr))
            b[-f:] *= np.linspace(1, 0, f, dtype=np.float32)[:, None]
            truncated = True
        return np.ascontiguousarray(b, np.float32), truncated

    def _mix_layer(self, buf, job):
        """Optional layered response: the recalled sound 9 dB under the
        transformation, same single output stream, peak-limited to 0.95."""
        np = self.np
        lay, _ = self._prepare(job.layer, job.layer_sr)
        n = max(len(buf), len(lay))
        out = np.zeros((n, buf.shape[1]), np.float32)
        out[:len(buf)] += buf
        out[:len(lay)] += 0.355 * lay
        pk = float(np.max(np.abs(out))) if len(out) else 0.0
        if pk > 0.95:
            out *= 0.95 / pk
        return np.ascontiguousarray(out[:int(self.a.max_response * self.sr)])

    def _play_loop(self):
        try:
            while not self.stop_ev.is_set():
                job = self.play_q.get(0.2)
                if job is None:
                    continue
                self._check_fault("play")
                age = time.time() - job.t["end"]
                if age > STALE_RESPONSE_S:
                    self._dropped(job, "stale: %.0f s after the phrase ended" % age)
                    continue
                if job.kind == "recall":
                    name = job.action_name
                elif job.kind == "recall_transform" and job.used != "passthrough":
                    name = "%s on %s" % (DISPLAY_NAMES.get(job.used, job.used), job.source_id)
                else:
                    name = DISPLAY_NAMES.get(job.used, job.used)
                buf, trunc = self._prepare(job.answer, job.answer_sr)
                if job.layer is not None:
                    buf = self._mix_layer(buf, job)
                    name += " + layer"
                if trunc:
                    self.log("job %s answer truncated to %.1f s (Max_response_s)" %
                             (job.tag, self.a.max_response), True)
                job.t["play_start"] = time.time()
                if self.a.play:
                    self.playing = name
                    self.play_done.clear()
                    self.cur_pos = 0
                    self.cur = buf
                    while not self.play_done.wait(0.05):
                        if self.stop_ev.is_set():
                            self.cur = None
                            break
                    self.playing = ""
                job.t["play_end"] = time.time()
                self.t_activity = time.time()
                if self.stop_ev.is_set() and self.cur is None and not self.play_done.is_set():
                    self.log("job %s interrupted by stop" % job.tag, True)
                delay = job.t["play_start"] - job.t["end"]
                self.delays.append(delay)
                self.c["done"] += 1
                self.c["kind_" + job.kind] += 1
                self.summary.append("%s  %-34s in %5.2f s -> out %5.2f s   delay %5.2f s" % (
                    job.tag, name, len(job.audio) / job.sr, len(buf) / self.sr, delay))
                tt = job.t

                def rel(k):
                    return ("%.3f" % (tt[k] - tt["end"])) if k in tt else "-"
                self.log("job %s TIMING rel. to phrase end: onset %s | analysed %s | render %s..%s"
                         " | play %s..%s  (phrase end -> answer %.3f s)" %
                         (job.tag, rel("onset"), rel("analysed"), rel("render_start"),
                          rel("render_end"), rel("play_start"), rel("play_end"), delay))
                self._cleanup_job(job)
                job.answer = job.layer = job.recall_item = None
        except Exception as ex:                              # noqa: BLE001
            import traceback
            self.fatal = "playback worker failed: %s" % ex
            self.log(self.fatal + " | " + traceback.format_exc().replace("\n", " | "), True)
            self.stop_ev.set()

    # ---------------- status ----------------
    def status_pairs(self, final=False):
        lk = "none" if self.leak_db is None else fnum(self.leak_db, 1)
        mc = self.memory.counts()
        return [
            ("state", self.state), ("stage", self.stage), ("mode", "continuous"),
            ("memory", "on" if self.mcfg["enabled"] else "off"),
            ("listening", "on" if (self.state == "running" and not final) else "off"),
            ("phrase", 1 if self.det.state == "PHRASE" else 0),
            ("processing", self.processing), ("playing", self.playing),
            ("pending", len(self.phrase_q) + len(self.render_q) + len(self.play_q)),
            ("pending_render", len(self.render_q)), ("pending_play", len(self.play_q)),
            ("phrases", self.c["phrases"]), ("done", self.c["done"]),
            ("dropped", self.c["dropped"]), ("failed", self.c["failed"]),
            ("leak_discarded", self.c["leak_discarded"]), ("overruns", self.c["overruns"]),
            ("input_status", self.c["input_status"]), ("output_status", self.c["output_status"]),
            ("input_db", fnum(self.input_db, 1)), ("leak_db", lk),
            ("leak_warning", 1 if (self.leak_db is not None and self.leak_db > -20) else 0),
            ("mem_live", mc["A"]), ("mem_processed", mc["B"]), ("mem_preloaded", mc["C"]),
            ("mem_audio_min", fnum(self.memory.ram_seconds() / 60.0, 1)),
            ("recall", self.last_recall), ("match", self.last_match),
            ("action", self.last_action),
            ("message", self.message), ("uptime", fnum(time.time() - self.t_start, 1)),
            ("heartbeat", "%.3f" % time.time()),
        ]

    def write_status(self, final=False):
        path = os.path.join(self.session, "status.txt")
        for _ in range(5):
            try:
                write_kv_atomic(path, self.status_pairs(final))
                return
            except PermissionError:                         # Windows: file being read
                time.sleep(0.02)
            except OSError:
                return

    # ---------------- main ----------------
    def run(self):
        sd = self.sd
        a = self.a
        self.write_status()
        if not self.renderer.find():
            return self.finish("error", self.renderer.error)
        self.log("Praat renderer: %s (version %d, flags %s)" %
                 (self.renderer.exe, self.renderer.version, " ".join(self.renderer.flags)), True)
        if self.mcfg["enabled"] and self.mcfg["use_C"] and a.corpus_c not in ("", "none"):
            def progress(msg):
                self.message = msg
                self.write_status()
                if os.path.exists(os.path.join(self.session, "stop.request")):
                    raise KeyboardInterrupt
            try:
                n, notes = index_preloaded(a.corpus_c, self.memory, self.mcfg, progress, self.log)
            except KeyboardInterrupt:
                return self.finish("stopped", "stopped while indexing the preloaded corpus")
            for nt in notes:
                self.log(nt, True)
            self.log("Corpus C indexed: %d sounds (%.1f min of audio in RAM)" %
                     (n, self.memory.ram_seconds() / 60.0), True)
            self.message = ""
        try:
            in_dev = resolve_device(sd, a.device, "input")
            out_dev = resolve_device(sd, a.output_device, "output")
            info = (sd.query_devices(out_dev) if out_dev is not None
                    else sd.query_devices(kind="output"))
            self.out_ch = 2 if int(info.get("max_output_channels", 2)) >= 2 else 1
            self.in_stream = sd.InputStream(samplerate=self.sr, channels=self.ch, dtype="float32",
                                            blocksize=self.det.hop, device=in_dev,
                                            callback=self._in_cb)
            self.out_stream = sd.OutputStream(samplerate=self.sr, channels=self.out_ch,
                                              dtype="float32", blocksize=self.det.hop,
                                              device=out_dev, callback=self._out_cb)
        except Exception as ex:                              # noqa: BLE001
            return self.finish("error", "cannot open audio devices: %s" % ex)
        threads = [threading.Thread(target=f, name=n, daemon=True) for f, n in (
            (self._detect_loop, "detect"), (self._brain_loop, "brain"),
            (self._render_loop, "render"), (self._play_loop, "play"))]
        reason, state = "", "stopped"
        try:
            self.in_stream.start()
            self.out_stream.start()
        except Exception as ex:                              # noqa: BLE001
            self._close_streams()
            return self.finish("error", "cannot start audio streams: %s" % ex)
        for t in threads:
            t.start()
        self.state, self.stage = "running", "running"
        self.log("engine running: in %s / out %s (%d ch), %d Hz, pending<=%d, responses<=%d, "
                 "overflow %s, max response %.1f s, leakage guard %s, sonic memory %s (%s, %s), "
                 "seed %d" % (a.device, a.output_device, self.out_ch, self.sr, a.max_pending,
                              a.max_responses, a.overflow, a.max_response,
                              "on" if a.leak_guard else "off",
                              "on" if self.mcfg["enabled"] else "off", a.response_mode,
                              a.sim_mode, self.memory.seed), True)
        stop_file = os.path.join(self.session, "stop.request")
        alive_file = os.path.join(self.session, "praat_alive.txt")
        t_last_status = 0.0
        try:
            while True:
                time.sleep(0.05)
                now = time.time()
                if self.fatal:
                    reason, state = self.fatal, "error"
                elif os.path.exists(stop_file):
                    reason = "stopped by the user"
                elif a.heartbeat:
                    try:
                        beat = os.path.getmtime(alive_file)
                    except OSError:
                        beat = self.t_start
                    if now - beat > HEARTBEAT_TIMEOUT_S:
                        reason = "Praat stopped responding (no heartbeat for %.0f s)" % (now - beat)
                if not reason and a.session_minutes > 0 and now - self.t_start > 60 * a.session_minutes:
                    reason = "session length reached (%.0f min)" % a.session_minutes
                if (not reason and a.idle_stop > 0 and now - self.t_activity > a.idle_stop
                        and self.det.state != "PHRASE" and not self.processing
                        and not self.playing and len(self.phrase_q) + len(self.render_q)
                        + len(self.play_q) == 0):
                    reason = "no phrase for %.0f s" % a.idle_stop
                if not reason:
                    try:
                        if not self.in_stream.active:
                            reason, state = "audio input stream stopped", "error"
                        elif not self.out_stream.active:
                            reason, state = "audio output stream stopped", "error"
                    except Exception:                        # noqa: BLE001
                        pass
                    if not reason and not all(t.is_alive() for t in threads):
                        reason, state = (self.fatal or "a worker thread ended unexpectedly"), "error"
                if reason:
                    break
                if now - t_last_status >= 0.1:
                    self.write_status()
                    t_last_status = now
        except KeyboardInterrupt:
            reason = "interrupted"
        # ---- STOP REQUESTED -> WORKERS STOPPED ----
        self.state, self.stage, self.message = "stopping", "stop_requested", reason
        self.write_status()
        self.stop_ev.set()
        for q_ in (self.phrase_q, self.render_q, self.play_q):
            q_.close()
        self.cur = None
        self.renderer.kill()                             # only our own Praat child
        for t in threads:
            t.join(5)
        alive = [t.name for t in threads if t.is_alive()]
        if alive:
            self.renderer.kill()
            for t in threads:
                t.join(5)
            alive = [t.name for t in threads if t.is_alive()]
        self.stage = "workers_stopped"
        self._close_streams()
        if self.det.state == "PHRASE":
            self.log("phrase in progress at stop was not processed", True)
        for q_, what in ((self.phrase_q, "unanalysed"), (self.render_q, "unrendered"),
                         (self.play_q, "unplayed")):
            for job in q_.drain():
                self.c["dropped"] += 1
                self.log("job %s %s at stop - not played" % (job.tag, what), True)
                self._cleanup_job(job)
        if alive:
            self.log("WARNING: worker(s) still alive after 10 s: %s" % ", ".join(alive), True)
        return self.finish(state, reason)

    def _close_streams(self):
        for name in ("in_stream", "out_stream"):
            s = getattr(self, name, None)
            if s is None:
                continue
            try:
                s.stop()
            except Exception:                                # noqa: BLE001
                pass
            try:
                s.close()
            except Exception:                                # noqa: BLE001
                pass
            setattr(self, name, None)

    def finish(self, state, reason):
        """FILE HANDLES CLOSED -> engine temp deleted.  Everything the engine
        created is removed here; only the small hand-over files the Praat GUI
        still reads remain, and Praat's cleanup removes those and the folder."""
        self.state, self.message = state, reason
        self.log("%s: %s" % (state.upper(), reason), True)
        np = self.np
        mc = self.memory.counts()
        lines = ["state=" + state, "reason=" + reason]
        lines.append("phrases=%d answers=%d dropped=%d failed=%d passthrough=%d "
                     "leak_discarded=%d overruns=%d input_status=%d output_status=%d" % (
                         self.c["phrases"], self.c["done"], self.c["dropped"], self.c["failed"],
                         self.c["passthrough"], self.c["leak_discarded"], self.c["overruns"],
                         self.c["input_status"], self.c["output_status"]))
        lines.append("memory live=%d processed=%d preloaded=%d answers transform=%d recall=%d "
                     "recall_transform=%d evicted=%d" % (
                         mc["A"], mc["B"], mc["C"], self.c["kind_transform"],
                         self.c["kind_recall"], self.c["kind_recall_transform"],
                         self.memory.evicted))
        if self.delays:
            d = np.array(self.delays)
            lines.append("delay phrase end -> answer: mean %.2f s, min %.2f s, max %.2f s" %
                         (d.mean(), d.min(), d.max()))
        if self.leak_db is not None:
            lines.append("leakage estimate %.1f dB" % self.leak_db)
        lines += ["answer " + s for s in self.summary]
        lines += ["event " + e.strip() for e in self.events]
        if state == "error":                 # engine_stderr.txt is deleted below
            try:
                with open(os.path.join(self.session, "engine_stderr.txt"), encoding="utf-8",
                          errors="replace") as fh:
                    lines += ["stderr " + l for l in fh.read().strip().splitlines()[-6:]]
            except OSError:
                pass
        # release memory and every handle we own
        self.memory.clear()
        if self.log_fh:
            for l in lines[:5]:
                self.log("SUMMARY " + l)
            try:
                self.log_fh.close()
            except OSError:
                pass
            self.log_fh = None
        try:
            if sys.stderr is not None and getattr(sys.stderr, "name", "").endswith("engine_stderr.txt"):
                f = sys.stderr
                sys.stderr = open(os.devnull, "w")
                f.close()
        except Exception:                                    # noqa: BLE001
            pass
        self.stage = "handles_closed"
        # delete every engine-owned file in the session (bounded retries)
        left = []
        try:
            for n in os.listdir(self.session):
                if n in PRAAT_OWNED:
                    continue
                p = os.path.join(self.session, n)
                ok = False
                for _ in range(20):
                    try:
                        if os.path.isdir(p):
                            ok = not remove_tree(p, 4, 0.05)
                        else:
                            os.remove(p)
                            ok = True
                        break
                    except OSError:
                        time.sleep(0.1)
                if not ok and os.path.exists(p):
                    left.append(n)
        except OSError:
            pass
        lines.insert(2, "engine_files_left=%d%s" % (len(left), (" " + ";".join(left)) if left else ""))
        self.stage = "engine_temp_deleted" if not left else "engine_temp_incomplete"
        try:
            write_text_atomic(os.path.join(self.session, "summary.txt"), "\n".join(lines) + "\n")
        except OSError:
            pass
        self.write_status(final=True)
        return 0 if state != "error" else 1


def cmd_serve(args):
    global MAX_RESPONSE_S
    MAX_RESPONSE_S = float(args.max_response)
    if not os.path.isdir(args.session):
        return 1                      # session already removed by Praat
    try:
        _boot_status(args.session, "starting", "loading numpy / scipy")
        import_dsp()
        _boot_status(args.session, "starting", "loading soundfile / sounddevice")
        import soundfile                                     # noqa: F401
        import sounddevice as sd
        _boot_status(args.session, "starting", "finding a Praat executable for rendering")
        if (not os.path.isdir(args.session) or
                os.path.exists(os.path.join(args.session, "stop.request"))):
            return 1                  # Praat gave up (or stopped) while we were loading
    except Exception as ex:                                  # noqa: BLE001
        write_kv_atomic(os.path.join(args.session, "status.txt"),
                        [("state", "error"), ("message", "missing Python package: %s" % ex)])
        return 1
    eng = None
    try:
        eng = Engine(args, sd)
        rc = eng.run()
    except Exception as ex:                                  # noqa: BLE001
        import traceback
        rc = 1
        msg = "engine crashed: %s | %s" % (ex, traceback.format_exc().replace("\n", " | ")[-500:])
        if eng is not None:
            try:
                eng.stop_ev.set()
                eng.renderer.kill()
                eng._close_streams()
                eng.finish("error", msg)
            except Exception:                                # noqa: BLE001
                pass
        try:
            write_kv_atomic(os.path.join(args.session, "status.txt"),
                            [("state", "error"), ("message", msg)])
        except OSError:
            pass
    abandoned = eng is not None and eng.message.startswith("Praat stopped responding")
    pending = os.path.exists(os.path.join(args.session, "cleanup.pending"))
    if abandoned or pending:
        # nobody is left to clean up (Praat gone), or Praat's cleanup found
        # this engine still running and deleted NOTHING: the engine is the
        # owner, it is about to exit, so it removes its own session now
        try:
            if sys.stderr is not None and getattr(sys.stderr, "name", "").endswith(".txt"):
                f = sys.stderr
                sys.stderr = open(os.devnull, "w")
                f.close()
        except Exception:                                    # noqa: BLE001
            pass
        time.sleep(0.5)
        if safe_session_dir(args.session):
            remove_tree(args.session)
    return rc


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
        p.add_argument("--max-response", dest="max_response", type=float, default=20.0)
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
    p = sub.add_parser("serve")
    p.add_argument("--session", required=True)
    p.add_argument("--script", required=True, help="AudioTools_CallResponse.praat (render mode)")
    p.add_argument("--praat", default="none", help="Praat executable or its folder")
    p.add_argument("--plugin-root", dest="plugin_root", required=True)
    p.add_argument("--force", default="auto")
    p.add_argument("--device", default="default")
    p.add_argument("--output-device", dest="output_device", default="default")
    p.add_argument("--sr", type=float, default=44100)
    p.add_argument("--channels", type=int, default=1)
    p.add_argument("--sensitivity", type=float, default=9.0)
    p.add_argument("--min-phrase", dest="min_phrase", type=float, default=0.5)
    p.add_argument("--end-silence", dest="end_silence", type=float, default=0.6)
    p.add_argument("--max-phrase", dest="max_phrase", type=float, default=12.0)
    p.add_argument("--preroll", type=float, default=0.25)
    p.add_argument("--max-pending", dest="max_pending", type=int, default=3)
    p.add_argument("--max-responses", dest="max_responses", type=int, default=3)
    p.add_argument("--overflow", default="drop_oldest", choices=["drop_oldest", "drop_newest"])
    p.add_argument("--max-response", dest="max_response", type=float, default=20.0)
    p.add_argument("--session-minutes", dest="session_minutes", type=float, default=60.0)
    p.add_argument("--idle-stop", dest="idle_stop", type=float, default=300.0)
    p.add_argument("--leak-guard", dest="leak_guard", type=int, default=1)
    p.add_argument("--play", type=int, default=1)
    p.add_argument("--heartbeat", type=int, default=1,
                   help="stop when the Praat GUI stops writing praat_alive.txt")
    p.add_argument("--debug-log", dest="debug_log", default="none")
    # ---- v0.3.0 sonic memory ----
    p.add_argument("--memory", type=int, default=1)
    p.add_argument("--response-mode", dest="response_mode", default="hybrid",
                   choices=["transform", "recall", "recall_transform", "hybrid"])
    p.add_argument("--use-a", dest="use_a", type=int, default=1)
    p.add_argument("--use-b", dest="use_b", type=int, default=1)
    p.add_argument("--use-c", dest="use_c", type=int, default=0)
    p.add_argument("--corpus-c", dest="corpus_c", default="none")
    p.add_argument("--sim-mode", dest="sim_mode", default="hybrid",
                   choices=["hybrid", "timbre", "pitch", "rhythm", "envelope", "contrast"])
    p.add_argument("--min-sim", dest="min_sim", type=float, default=0.45)
    p.add_argument("--w-live", dest="w_live", type=float, default=40.0)
    p.add_argument("--w-processed", dest="w_processed", type=float, default=30.0)
    p.add_argument("--w-preloaded", dest="w_preloaded", type=float, default=30.0)
    p.add_argument("--p-transform", dest="p_transform", type=float, default=40.0)
    p.add_argument("--p-recall", dest="p_recall", type=float, default=30.0)
    p.add_argument("--p-recall-transform", dest="p_recall_transform", type=float, default=30.0)
    p.add_argument("--max-generation", dest="max_generation", type=int, default=2)
    p.add_argument("--max-live", dest="max_live", type=int, default=100)
    p.add_argument("--max-processed", dest="max_processed", type=int, default=100)
    p.add_argument("--max-ram-min", dest="max_ram_min", type=float, default=30.0)
    p.add_argument("--max-item-s", dest="max_item_s", type=float, default=15.0)
    p.add_argument("--candidates", type=int, default=5)
    p.add_argument("--evolving", type=int, default=0)
    p.add_argument("--layered", type=int, default=0)
    p.add_argument("--recent-exclude", dest="recent_exclude", type=int, default=2)
    p.add_argument("--cooldown", type=int, default=4)
    p.add_argument("--same-family", dest="same_family", type=int, default=0)
    p.add_argument("--c-max-items", dest="c_max_items", type=int, default=300)
    p.add_argument("--c-max-files", dest="c_max_files", type=int, default=200)
    p.add_argument("--c-max-per-file", dest="c_max_per_file", type=int, default=20)
    p.add_argument("--c-min-item-s", dest="c_min_item_s", type=float, default=0.5)
    p.add_argument("--seed", type=int, default=0)
    p = sub.add_parser("cleanup")
    p.add_argument("--session", required=True)
    p.add_argument("--wait", type=float, default=15.0)
    p.add_argument("--report", action="store_true",
                   help="print one result line (Praat reads it with runSubprocess$)")
    p = sub.add_parser("cleanup-stale")
    p.add_argument("--base", required=True)
    p.add_argument("--report", action="store_true")
    p = sub.add_parser("self-test")
    p.add_argument("--write-dir", dest="write_dir", default="")
    args = ap.parse_args(argv)
    if getattr(args, "force", "auto") not in ["auto", ""] + TRANSFORM_IDS:
        args.force = "auto"
    fn = {"probe": cmd_probe, "devices": cmd_devices, "listen": cmd_listen, "serve": cmd_serve,
          "analyze": cmd_analyze, "cleanup": cmd_cleanup,
          "cleanup-stale": cmd_cleanup_stale, "self-test": cmd_self_test}[args.cmd]
    return fn(args)


def cmd_launch(rest):
    """v0.2.0: start the continuous engine as a DETACHED process and return
    at once.  Praat calls this with an ordinary (blocking) runSubprocess - the
    same mechanism as v0.1.3 - instead of "asynchronous runSubprocess", whose
    child never ran on a Windows test machine.  The engine gets this Python's
    absolute path, no inherited handles (stdin/stdout/stderr -> DEVNULL, so
    Praat's blocking call can finish) and its own process group."""
    if "--session" not in rest:
        sys.stderr.write("launch: --session is required\n")
        return 2
    sess = rest[rest.index("--session") + 1]
    os.makedirs(sess, exist_ok=True)
    argv = [sys.executable, os.path.abspath(__file__), "serve"] + list(rest)
    kw = dict(stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
              stderr=subprocess.DEVNULL, close_fds=True, cwd=sess)
    if sys.platform.startswith("win"):
        # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW
        kw["creationflags"] = 0x00000008 | 0x00000200 | 0x08000000
    else:
        kw["start_new_session"] = True
    try:
        p = subprocess.Popen(argv, **kw)
    except Exception as ex:                                  # noqa: BLE001
        _boot_status(sess, "error", "cannot start the engine process: %s" % ex)
        sys.stderr.write("launch failed: %s\n" % ex)
        return 1
    try:
        write_kv_atomic(os.path.join(sess, "launch.txt"),
                        [("pid", p.pid), ("start", proc_start_token(p.pid)),
                         ("python", sys.executable)])
    except OSError:
        pass
    return 0


def _serve_boot(argv):
    """v0.2.0: the engine runs detached with NO stdout/stderr, so a start-up
    failure would be invisible.  Before
    any import or argument parsing: write status 'starting' and send stderr to
    <session>/engine_stderr.txt.  Returns the session folder or None."""
    if len(argv) < 2 or argv[1] != "serve" or "--session" not in argv:
        return None
    try:
        sess = argv[argv.index("--session") + 1]
        if not os.path.isdir(sess):
            # v0.3.0: Praat has already given up and removed the session -
            # never re-create it (no temporary file may outlive a session)
            sys.exit(0)
        sys.stderr = open(os.path.join(sess, "engine_stderr.txt"), "a",
                          encoding="utf-8", buffering=1)
        if sys.stdout is None:
            sys.stdout = sys.stderr
        _boot_status(sess, "starting", "Python %s started (%s); loading packages" %
                     (sys.version.split()[0], sys.executable))
        return sess
    except Exception:                                        # noqa: BLE001
        return None


def _boot_status(sess, state, message):
    try:
        write_kv_atomic(os.path.join(sess, "status.txt"),
                        [("state", state), ("message", message),
                         ("uptime", fnum(time.perf_counter() - T_PROCESS_START, 1))])
    except Exception:                                        # noqa: BLE001
        pass


if __name__ == "__main__":
    # --self-test is accepted as an alias of the self-test command
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.argv[1] = "self-test"
    if len(sys.argv) > 1 and sys.argv[1] == "launch":
        sys.exit(cmd_launch(sys.argv[2:]))
    _sess = _serve_boot(sys.argv)
    if _sess is None:
        sys.exit(main())
    try:
        _rc = main()
    except SystemExit as _ex:                                # e.g. an argument error
        if _ex.code not in (0, None):
            _boot_status(_sess, "error", "engine exited during start-up (code %s) - see "
                         "engine_stderr.txt: %s" % (_ex.code, " | ".join(
                             open(os.path.join(_sess, "engine_stderr.txt"),
                                  encoding="utf-8", errors="replace").read()
                             .strip().splitlines()[-3:])))
        raise
    except BaseException as _ex:                             # noqa: BLE001
        import traceback
        _boot_status(_sess, "error", "engine crashed: %s | %s" % (
            _ex, traceback.format_exc().replace("\n", " | ")[-600:]))
        raise
    sys.exit(_rc)
