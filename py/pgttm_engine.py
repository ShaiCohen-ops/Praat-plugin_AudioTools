"""
pgttm_engine.py — Probabilistic GTTM Acoustic-Grammar Engine  v1.4

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Acoustic_Grammar_Reducer.praat — not directly):
    python pgttm_engine.py
        --features        acoustic_features.csv
        --audio           temp_pgttm_analysis.wav
        --sound_name      <name>
        --duration        <total_dur_s>
        --time_step       0.01
        --out_textgrid    gttm_output.TextGrid
        --out_edl         splicing_edl.csv
        --onset_threshold   0.35    # peak-pick threshold on the [0,1]
                                    # combined onset function
        --min_ioi_ms        80      # refractory period between onsets
        --onset_flux_weight 0.6     # flux vs dB-rise mix (1.0 = flux only)
        --spectral_bins     16      # linear bands used for flux
        --spectral_max_freq 5000    # top of the flux band range, Hz
        --gpr_ioi_weight     1.0    # GPR 2: IOI/rest proximity
        --gpr_pitch_weight   1.0    # GPR 3a: pitch-interval leaps
        --gpr_dynamic_weight 1.0    # GPR 3b: dynamic (dB) drops
        --gpr_timbre_weight  1.0    # GPR 3c: formant (timbre) shift
        --merge_weakest_fraction 0.5  # 0..1 — merge away this FRACTION of
                                    # the weakest boundaries (a quantile,
                                    # not a level)
        --target_retention 0.45     # 0..1 — cap on the fraction of the
                                    # original DURATION the montage keeps
        --w1 1.0   # pTSR head weight: duration
        --w2 1.0   # pTSR head weight: pitch stability
        --w3 1.0   # pTSR head weight: intensity peak
        --w4 0.5   # pTSR head weight: pitch variance (penalty)
        --level0_frac 0.15   # target share of segments as Primary Anchors
        --level1_frac 0.35   # target share of segments as Phrase Heads
        --level2_frac 0.30   # target share of the non-head remainder kept
                             # as Ornaments (rest becomes Artifact/Noise)
        --min_anchor_gap_s 0.40   # min spacing between Level 0 anchors
        --min_head_gap_s   0.15   # min spacing between Level 1 heads
        [--debug]

Architecture:
    A  — Load per-frame acoustic_features.csv (pandas)
    A2 — Onset detection (v1.1, moved here from Praat): banded spectral
         flux over the analysis WAV in numpy, mixed with the half-wave
         rectified dB derivative from the CSV, peak-picked with a
         refractory minimum IOI. Results are written back into
         acoustic_features.csv as spectral_flux / onset_flag / ioi_s.
    B  — Onset-bounded raw segmentation
    C  — Probabilistic GPR 2/3 boundary evaluation -> merge weak
         boundaries (this is the "Grouping_Macro" tier)
    D  — pTSR head-score per segment:
            P(Head) ~ w1*Duration + w2*PitchStability + w3*IntensityPeak
                       - w4*PitchVariance
    E  — MAP-style reduction: a weighted, minimum-spacing chart DP (a 1-D
         relative of Viterbi / weighted interval scheduling) picks the
         highest-scoring, well-spaced backbone of structural heads; a
         second DP pass *within that backbone* picks the Level 0 Primary
         Anchors, so anchors are a subset of heads by construction.
         Everything left over is ranked into Level 2 (Ornament) or
         Level 3 (Artifact/Noise) by score.
    F  — Write gttm_output.TextGrid (3 tiers) + splicing_edl.csv
         (Level 0 + Level 1 spans only, in time order).

Why the onset stage lives here (v1.1):
    v1.0 computed spectral flux in Praat by querying a Spectrogram once
    per band per frame — ~288,000 "Get power at" calls plus ~410,000
    indexed-variable writes for a 3-minute file, which is why Stage 1
    could appear to hang and never reach the CSV. The same computation
    is a chunked rfft here. Praat keeps what it is good at (Pitch,
    Formant, Intensity objects and orchestration); numpy gets the DSP.

Notes on "MAP" framing:
    A full PCFG/Inside-Outside parse over pGTTM's complete rule set is
    out of scope for a per-performance acoustic pass. What's implemented
    here is the acoustic-grammar-relevant core: probabilistic grouping
    boundaries (GPR) feeding a dynamic-programming head-selection pass
    that maximizes total structural-weight subject to a minimum-spacing
    constraint — the DP recurrence is the same shape as Viterbi /
    weighted interval scheduling, and the per-segment score functions as
    an unnormalized posterior over "is this segment structurally
    salient".

Dependencies: numpy, pandas. WAV reading uses the standard-library
`wave` module, so no soundfile/librosa/scipy requirement is introduced.
"""

import sys
import os
import argparse
import math
import wave

import numpy as np
import pandas as pd


# ─────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(description="Probabilistic GTTM acoustic-grammar engine")
    p.add_argument("--features", required=True)
    p.add_argument("--audio", default=None,
                   help="Analysis WAV written by Acoustic_Grammar_Reducer.praat. "
                        "If "
                        "omitted, onsets fall back to the intensity "
                        "derivative alone (or to existing CSV columns).")
    p.add_argument("--sound_name", required=True)
    p.add_argument("--duration", type=float, required=True)
    p.add_argument("--time_step", type=float, default=0.01)
    p.add_argument("--out_textgrid", required=True)
    p.add_argument("--out_edl", required=True)

    p.add_argument("--onset_threshold", type=float, default=0.35)
    p.add_argument("--min_ioi_ms", type=float, default=80.0)
    p.add_argument("--onset_flux_weight", type=float, default=0.6)
    p.add_argument("--onset_median_window_s", type=float, default=1.0,
                   help="Width of the local-median floor the onset function "
                        "must clear, in seconds. 0 uses a single global "
                        "threshold instead (the v1.1 behaviour).")
    p.add_argument("--onset_smooth_frames", type=int, default=3,
                   help="Moving-average width applied to the onset function "
                        "before peak-picking. Wider suits legato material, "
                        "where the useful peaks are broad; narrow suits "
                        "transient material, where they are one frame wide.")
    p.add_argument("--spectral_bins", type=int, default=16)
    p.add_argument("--spectral_max_freq", type=float, default=5000.0)

    p.add_argument("--gpr_ioi_weight", type=float, default=1.0)
    p.add_argument("--gpr_pitch_weight", type=float, default=1.0)
    p.add_argument("--gpr_dynamic_weight", type=float, default=1.0)
    p.add_argument("--gpr_timbre_weight", type=float, default=1.0)
    p.add_argument("--merge_weakest_fraction", type=float, default=0.5,
                   help="Fraction of the WEAKEST onset boundaries to merge "
                        "away, 0..1. A quantile, not a level: GPR strength is "
                        "an average of four normalized cues that peak at "
                        "different boundaries, so its distribution is crushed "
                        "toward zero (median ~0.17 on real material) and any "
                        "absolute level near 0.5 deletes almost every "
                        "boundary.")

    p.add_argument("--w1", type=float, default=1.0)
    p.add_argument("--w2", type=float, default=1.0)
    p.add_argument("--w3", type=float, default=1.0)
    p.add_argument("--w4", type=float, default=0.5)

    p.add_argument("--target_retention", type=float, default=0.45,
                   help="TARGET fraction of the ORIGINAL DURATION the montage "
                        "keeps. Not a hard cap: one head always survives, so a "
                        "file whose best single segment already exceeds the "
                        "budget will overshoot it, and the engine says so when "
                        "it happens. 1.0 disables the target. Counting "
                        "retention in segments does not bound it: the head "
                        "score rewards duration, so the selected segments are "
                        "the long ones and a half-of-segments montage can be "
                        "nearly the whole file.")
    p.add_argument("--level0_frac", type=float, default=0.15)
    p.add_argument("--level1_frac", type=float, default=0.35)
    p.add_argument("--level2_frac", type=float, default=0.30)
    p.add_argument("--min_anchor_gap_s", type=float, default=0.40)
    p.add_argument("--min_head_gap_s", type=float, default=0.15)

    p.add_argument("--out_trace", default=None,
                   help="Optional decimated onset-function trace for the "
                        "Praat figure. Written only if given.")
    p.add_argument("--out_segments", default=None,
                   help="Optional per-raw-segment table (boundary strengths, "
                        "group membership, levels, scores) for the Praat "
                        "figure. Written only if given.")
    p.add_argument("--trace_points", type=int, default=1200)

    p.add_argument("--debug", action="store_true")
    return p.parse_args()


def log(msg, debug_only=False, args=None):
    if debug_only and not (args and args.debug):
        return
    print(msg, file=sys.stderr)


def norm01(x):
    """Min-max normalize to [0, 1]; an all-flat vector becomes all zeros."""
    x = np.asarray(x, dtype=float)
    if x.size == 0:
        return x
    lo, hi = float(np.min(x)), float(np.max(x))
    if hi - lo < 1e-9:
        return np.zeros_like(x)
    return (x - lo) / (hi - lo)


def robust_norm(x, pct=95.0):
    """
    Normalize an onset cue against its `pct`-th percentile instead of its
    maximum, clipping the overshoot to 1.

    Min-max is wrong for onset functions specifically: a single loud
    transient becomes the ceiling and squashes every other peak toward
    zero, so Onset_threshold stops meaning anything stable. Measured on
    a 3-minute fixture, the min-max onset function had its 99th
    percentile at 0.38 and its maximum at 0.51 — the documented default
    of 0.35 sat on a cliff (0.35 -> 186 events, 0.50 -> 6), whereas
    percentile-normalized the same default sits on a plateau that
    recovers every event. Frames above the percentile all clip to 1;
    they are onsets either way, and only the local-maximum test
    distinguishes them.
    """
    x = np.asarray(x, dtype=float)
    if x.size == 0:
        return x
    lo = float(np.min(x))
    hi = float(np.percentile(x, pct))
    if hi - lo < 1e-9:
        return np.zeros_like(x)
    return np.clip((x - lo) / (hi - lo), 0.0, 1.0)


# ─────────────────────────────────────────────────────────────────────────────
# A — Load features
# ─────────────────────────────────────────────────────────────────────────────

def load_features(path):
    df = pd.read_csv(path)
    # Blank fields (unvoiced f0_cents, non-onset ioi_s) come in as NaN —
    # that's fine, they're only consulted where voiced/onset gates them.
    return df


# ─────────────────────────────────────────────────────────────────────────────
# A2 — Onset detection (moved out of Praat in v1.1)
# ─────────────────────────────────────────────────────────────────────────────
def rolling_median(x, width, chunk=8000):
    """
    Local median of `x` over a window of `width` samples, edge-padded.

    Computed in chunks: the strided view is (n x width) and materializing it
    whole for a ten-minute file at a two-second window is ~100 MB for a
    quantity that is only a threshold floor.
    """
    x = np.asarray(x, dtype=float)
    n = x.size
    if width < 3 or n == 0:
        return np.zeros(n, dtype=float)
    width = int(width) | 1          # odd, so the window is centred
    half = width // 2
    padded = np.pad(x, (half, half), mode="edge")
    out = np.empty(n, dtype=float)
    for s in range(0, n, chunk):
        e = min(n, s + chunk)
        view = np.lib.stride_tricks.sliding_window_view(padded[s:e + 2 * half], width)
        out[s:e] = np.median(view, axis=1)
    return out



def read_wav_mono(path):
    """
    Read a WAV as float32 in [-1, 1] using only the standard library.
    Praat's "Save as WAV file" writes 16-bit PCM, but 8/24/32-bit integer
    files are handled too so a hand-supplied WAV doesn't fail obscurely.
    """
    with wave.open(path, "rb") as w:
        n_ch = w.getnchannels()
        width = w.getsampwidth()
        sr = w.getframerate()
        raw = w.readframes(w.getnframes())

    if width == 1:
        x = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif width == 2:
        x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif width == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v & 0x800000, v - 0x1000000, v)
        x = v.astype(np.float32) / 8388608.0
    elif width == 4:
        x = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        raise ValueError("Unsupported WAV sample width: %d bytes" % width)

    if n_ch > 1:
        x = x.reshape(-1, n_ch).mean(axis=1)
    return np.ascontiguousarray(x, dtype=np.float32), sr


def banded_spectral_flux(x, sr, times, n_bands, max_freq, chunk=1024):
    """
    Half-wave-rectified banded spectral flux, evaluated at exactly the CSV
    frame times so the result drops straight into the existing frame grid.

    Windows are centred on each frame time (the signal is zero-padded by
    half a window), power is summed into `n_bands` linear bands up to
    `max_freq`, converted to log10, and the frame-to-frame increase is
    taken as an L2 norm over bands. Rectification is per band: onsets are
    energy/timbre *rises*, and letting a decaying band cancel a rising one
    is what blurs flux peaks on polyphonic material.

    Frames are processed in chunks so peak memory stays at
    chunk x win_len floats regardless of file length.
    """
    times = np.asarray(times, dtype=float)
    n_frames = times.size
    if n_frames == 0 or x.size == 0:
        return np.zeros(n_frames, dtype=float)

    # ~46 ms analysis window at the NEAREST power of two, not the next one up.
    # Rounding up made the window sample-rate dependent in a way that matters:
    # 46.4 ms at 44.1 kHz but 85.3 ms at 48, 96 and 192 kHz, because 0.046*sr
    # lands just above a power of two at those rates. That is nearly double the
    # temporal smearing on the most common professional rate, so the same
    # recording at 44.1 and 48 kHz would not get the same onsets. Nearest keeps
    # every supported rate within 42.7-46.4 ms.
    win_len = 1 << int(round(math.log2(max(64.0, 0.046 * sr))))
    win_len = min(win_len, 1 << 15)
    half = win_len // 2
    window = np.hanning(win_len).astype(np.float32)

    xp = np.pad(x, (half, half))
    # After padding by `half`, window start index == centre sample index.
    centres = np.rint(times * sr).astype(np.int64)
    centres = np.clip(centres, 0, max(0, xp.size - win_len))

    freqs = np.fft.rfftfreq(win_len, 1.0 / sr)
    edges = np.linspace(0.0, max_freq, n_bands + 1)
    band_of_bin = np.digitize(freqs, edges) - 1
    keep = (band_of_bin >= 0) & (band_of_bin < n_bands)
    # One-hot bin->band matrix; (n_bins x n_bands) is tiny, so the band
    # sum is a single small matmul per chunk.
    proj = np.zeros((freqs.size, n_bands), dtype=np.float32)
    proj[np.nonzero(keep)[0], band_of_bin[keep]] = 1.0

    offsets = np.arange(win_len, dtype=np.int64)
    bands = np.empty((n_frames, n_bands), dtype=np.float32)
    for s in range(0, n_frames, chunk):
        idx = centres[s:s + chunk]
        frames = xp[idx[:, None] + offsets[None, :]] * window
        power = np.abs(np.fft.rfft(frames, axis=1)) ** 2
        bands[s:s + chunk] = power.astype(np.float32) @ proj

    log_bands = np.log10(np.maximum(bands, 1e-12))
    diff = np.diff(log_bands, axis=0)
    np.maximum(diff, 0.0, out=diff)
    flux = np.zeros(n_frames, dtype=float)
    flux[1:] = np.sqrt((diff ** 2).sum(axis=1) / float(n_bands))
    return flux


def detect_onsets(df, args):
    """
    Combine banded spectral flux with the half-wave-rectified intensity
    derivative, then peak-pick: local maximum, above threshold, respecting
    a refractory minimum IOI so dense energy modulation doesn't fragment
    into a flood of onsets.

    Returns (flux, onset_flag, ioi_s, source_label, onset_function,
    threshold_curve).
    """
    n = len(df)
    times = df["time_s"].to_numpy(dtype=float)

    flux = np.zeros(n, dtype=float)
    source = "intensity-derivative only"
    if args.audio and os.path.isfile(args.audio):
        try:
            x, sr = read_wav_mono(args.audio)
            flux = banded_spectral_flux(x, sr, times,
                                        max(2, args.spectral_bins),
                                        args.spectral_max_freq)
            source = "spectral flux + intensity derivative"
            log("  audio: %d samples @ %d Hz" % (x.size, sr), debug_only=True, args=args)
        except Exception as exc:  # noqa: BLE001 — degrade, don't abort
            log("  WARNING: could not analyse %s (%s); falling back to the "
                "intensity derivative alone." % (args.audio, exc), args=args)
    elif args.audio:
        log("  WARNING: analysis WAV not found at %s; falling back to the "
            "intensity derivative alone." % args.audio, args=args)

    db = df["intensity_db"].to_numpy(dtype=float)
    d_db = np.zeros(n, dtype=float)
    if n > 1:
        d_db[1:] = np.maximum(np.diff(db), 0.0)

    w = float(np.clip(args.onset_flux_weight, 0.0, 1.0))
    if source.startswith("intensity"):
        w = 0.0
    onset_fn = w * robust_norm(flux) + (1.0 - w) * robust_norm(d_db)

    # Smoothing before peak-picking. Without it, single-frame jitter in the
    # flux curve creates spurious local maxima that survive the threshold and
    # eat the refractory budget of a real nearby onset. The width is material-
    # dependent, which is why it is a parameter: a plucked attack is one frame
    # wide and is blunted by a wide window, whereas a bowed or sung note change
    # is a broad ramp whose peak only becomes stable once smoothed.
    smooth = max(1, int(args.onset_smooth_frames))
    if smooth > 1 and n >= smooth:
        onset_fn = np.convolve(onset_fn, np.ones(smooth) / float(smooth), mode="same")

    min_ioi_frames = max(1, int(round((args.min_ioi_ms / 1000.0) / args.time_step)))

    # ADAPTIVE THRESHOLD. A single global level cannot serve both material
    # types. On struck material the onset function is spiky over a near-zero
    # background, so a global level works. On sustained material — bowed, sung,
    # blown, or any drone — there is no quiet background: vibrato and slow
    # timbral motion keep the function permanently high (measured on a slurred
    # 49-note fixture, the function's median sat at 0.50 against 0.08 for the
    # struck case), and a global level either fires on everything or nothing.
    # Requiring a peak to clear a LOCAL median by `onset_threshold` fixes this:
    # on that fixture it took the count from 297 to 48 against 49 real notes,
    # while leaving the struck fixture unchanged at 465 of 465.
    #
    # So onset_threshold now means "margin above the local median", not
    # "absolute level". Set onset_median_window_s to 0 for the old behaviour.
    med_frames = int(round(args.onset_median_window_s / max(args.time_step, 1e-6)))
    if med_frames >= 3:
        floor_curve = rolling_median(onset_fn, med_frames)
    else:
        floor_curve = np.zeros(n, dtype=float)
    thr_curve = floor_curve + float(args.onset_threshold)

    onset_flag = np.zeros(n, dtype=int)
    ioi_s = np.full(n, np.nan, dtype=float)
    last_idx = -10 ** 9
    prev_onset_time = None
    for i in range(n):
        if onset_fn[i] < thr_curve[i]:
            continue
        if i > 0 and onset_fn[i] < onset_fn[i - 1]:
            continue
        if i < n - 1 and onset_fn[i] < onset_fn[i + 1]:
            continue
        if (i - last_idx) < min_ioi_frames:
            continue
        onset_flag[i] = 1
        ioi_s[i] = 0.0 if prev_onset_time is None else times[i] - prev_onset_time
        prev_onset_time = times[i]
        last_idx = i

    # The first frame always anchors the first event, even if the onset
    # function never crosses threshold there — silence-to-sound entries are
    # common and shouldn't be lost, and Section B assumes a segment starts
    # at frame 0.
    if n and onset_flag[0] != 1:
        onset_flag[0] = 1
        ioi_s[0] = 0.0
        # The former first onset's IOI is now measured from frame 0.
        later = np.nonzero(onset_flag)[0]
        if later.size > 1:
            ioi_s[later[1]] = times[later[1]] - times[0]

    return flux, onset_flag, ioi_s, source, onset_fn, thr_curve


# ─────────────────────────────────────────────────────────────────────────────
# B — Onset-bounded raw segmentation
# ─────────────────────────────────────────────────────────────────────────────

def raw_segments_from_onsets(df, duration, time_step):
    """
    Group frames into raw segments delimited by onset_flag==1 rows.
    Each raw segment spans [start_time, end_time), where end_time is the
    next onset's time (or the file duration for the last segment).
    """
    onset_rows = df.index[df["onset_flag"] == 1].tolist()
    if not onset_rows or onset_rows[0] != 0:
        onset_rows = [0] + onset_rows

    segs = []
    for k, start_idx in enumerate(onset_rows):
        end_idx = onset_rows[k + 1] if k + 1 < len(onset_rows) else len(df)
        t_start = min(float(df.loc[start_idx, "time_s"]), duration)
        t_end = float(df.loc[end_idx, "time_s"]) if end_idx < len(df) else duration
        # Clamp, never extend. Praat clamps the last frame's time to the file
        # duration, so an onset accepted on that frame has t_start == duration
        # and the old "t_end = t_start + time_step" pushed a TextGrid interval
        # past the global xmax — an invalid TextGrid. The audio was safe
        # because Stage 3 clamps before cutting, so this failed silently in
        # the one artifact nothing downstream re-validates.
        t_end = min(t_end, duration)
        if t_end - t_start < 1e-9:
            continue
        segs.append({
            "start": t_start,
            "end": t_end,
            "frame_lo": start_idx,
            "frame_hi": end_idx,  # exclusive
        })

    if not segs:
        # Every candidate collapsed (a file whose only onset is its last
        # frame). One segment spanning the file keeps every downstream stage
        # defined rather than propagating an empty list.
        segs = [{"start": 0.0, "end": duration, "frame_lo": 0, "frame_hi": len(df)}]
    return segs


def segment_frame_stats(df, seg):
    """Aggregate per-segment acoustic stats used by GPR + pTSR."""
    lo, hi = seg["frame_lo"], seg["frame_hi"]
    sub = df.iloc[lo:hi]
    voiced = sub[sub["voiced"] == 1]

    f0_mean = float(voiced["f0_hz"].mean()) if len(voiced) else 0.0
    cents_mean = float(voiced["f0_cents"].mean()) if len(voiced) else 0.0
    # Pitch variability in CENTS, not Hz. In Hz the same musical wobble scores
    # as more variance the higher the register — a 10 Hz spread is a quarter
    # tone at 440 and a whole tone at 110 — so a Hz-based figure penalised
    # high material for nothing. f0_cents is already in the frame table.
    f0_std = float(voiced["f0_cents"].std()) if len(voiced) > 1 else 0.0

    intensity_peak = float(sub["intensity_db"].max()) if len(sub) else 0.0
    intensity_mean = float(sub["intensity_db"].mean()) if len(sub) else 0.0

    f1_mean = float(sub["f1_hz"].replace(0, np.nan).mean())
    f2_mean = float(sub["f2_hz"].replace(0, np.nan).mean())
    f1_mean = 0.0 if math.isnan(f1_mean) else f1_mean
    f2_mean = 0.0 if math.isnan(f2_mean) else f2_mean

    duration = seg["end"] - seg["start"]
    # First/last onset-frame IOI within the segment, for GPR2 proximity.
    ioi = seg.get("ioi", 0.0)

    return {
        "duration": duration,
        "f0_mean": f0_mean,
        "f0_std": f0_std,
        "cents_mean": cents_mean,
        "intensity_peak": intensity_peak,
        "intensity_mean": intensity_mean,
        "f1_mean": f1_mean,
        "f2_mean": f2_mean,
        "n_voiced": len(voiced),
        "ioi": ioi,
    }


# ─────────────────────────────────────────────────────────────────────────────
# C — Probabilistic GPR boundary evaluation + merge
# ─────────────────────────────────────────────────────────────────────────────

def gpr_boundary_strengths(segments, stats, args):
    """
    Score each boundary between consecutive raw segments using GPR 2/3
    evidence: IOI proximity, pitch-interval leap, dynamic (dB) drop, and
    timbre shift (delta F1/F2). Scores are min-max normalized to [0, 1]
    per component before weighting, so no single cue dominates purely
    because of its native units (Hz vs dB vs seconds).
    """
    n = len(segments)
    if n <= 1:
        return np.array([])

    ioi_raw = np.array([stats[i]["ioi"] for i in range(1, n)])
    pitch_leap_raw = np.array([
        abs(stats[i]["cents_mean"] - stats[i - 1]["cents_mean"])
        if stats[i]["n_voiced"] and stats[i - 1]["n_voiced"] else 0.0
        for i in range(1, n)
    ])
    dyn_drop_raw = np.array([
        max(0.0, stats[i - 1]["intensity_peak"] - stats[i]["intensity_mean"])
        for i in range(1, n)
    ])
    timbre_shift_raw = np.array([
        math.hypot(stats[i]["f1_mean"] - stats[i - 1]["f1_mean"],
                   stats[i]["f2_mean"] - stats[i - 1]["f2_mean"])
        for i in range(1, n)
    ])

    ioi_n = norm01(ioi_raw)
    pitch_n = norm01(pitch_leap_raw)
    dyn_n = norm01(dyn_drop_raw)
    timbre_n = norm01(timbre_shift_raw)

    w_sum = (args.gpr_ioi_weight + args.gpr_pitch_weight +
             args.gpr_dynamic_weight + args.gpr_timbre_weight)
    w_sum = w_sum if w_sum > 1e-9 else 1.0

    strength = (args.gpr_ioi_weight * ioi_n +
                args.gpr_pitch_weight * pitch_n +
                args.gpr_dynamic_weight * dyn_n +
                args.gpr_timbre_weight * timbre_n) / w_sum

    return strength


def resolve_merge_cut(strengths, weakest_fraction):
    """
    Turn "merge the weakest q of the boundaries" into the strength value that
    does it, and return both. Reported rather than hidden, because the figure
    draws this line and the user needs to see where it landed.
    """
    if len(strengths) == 0:
        return 0.0, 0
    q = float(np.clip(weakest_fraction, 0.0, 1.0))
    if q <= 0.0:
        return float(np.min(strengths)), int(len(strengths))
    cut = float(np.quantile(strengths, q))
    survivors = int((strengths >= cut).sum())
    # An all-flat strength vector (every boundary identical) would otherwise
    # merge everything or nothing depending on float luck. Keep them all: no
    # evidence to discriminate on is not evidence for deleting structure.
    if survivors == 0:
        return float(np.min(strengths)), int(len(strengths))
    return cut, survivors


def merge_weak_boundaries(segments, stats, strengths, cut):
    """
    Boundary i (between raw segment i and i+1) survives only if its
    probabilistic GPR strength clears `cut` (resolved from the requested
    quantile by resolve_merge_cut); otherwise the two segments merge into one (their union becomes the new segment, and
    frame ranges concatenate so later stats recompute cleanly).
    This is what turns raw onset-slicing into the "Grouping_Macro" tier.

    Returns (merged_segments, parent_index_per_raw_segment). The parent map
    is what lets the figure show which raw onsets were absorbed into which
    group rather than only showing the surviving boundaries.
    """
    if len(segments) <= 1:
        return segments, [0] * len(segments)

    merged = [dict(segments[0])]
    parent = [0]
    for i in range(1, len(segments)):
        keep_boundary = strengths[i - 1] >= cut if len(strengths) else True
        if keep_boundary:
            merged.append(dict(segments[i]))
        else:
            merged[-1]["end"] = segments[i]["end"]
            merged[-1]["frame_hi"] = segments[i]["frame_hi"]
        parent.append(len(merged) - 1)
    return merged, parent


# ─────────────────────────────────────────────────────────────────────────────
# D — pTSR head score
# ─────────────────────────────────────────────────────────────────────────────

def compute_head_scores(stats_list, args):
    dur = np.array([s["duration"] for s in stats_list])
    # Pitch stability: inverse of the cents spread (only meaningful where
    # voiced; unvoiced/percussive segments get stability 0 rather than an
    # artificially perfect score).
    #
    # Note that w2 (stability) and w4 (variance penalty) act on the SAME
    # statistic with opposite signs: 1/(1+x) against x, each min-max
    # normalized. They are not independent evidence, and raising w4 mostly
    # steepens what w2 already expresses rather than adding a new criterion.
    # Kept as two knobs because every preset is calibrated against them, but
    # they should not be read as separate musical claims.
    pitch_stab = np.array([
        1.0 / (1.0 + s["f0_std"] / 100.0) if s["n_voiced"] > 0 else 0.0
        for s in stats_list
    ])
    intensity_peak = np.array([s["intensity_peak"] for s in stats_list])
    pitch_var = np.array([s["f0_std"] if s["n_voiced"] > 0 else 0.0 for s in stats_list])

    dur_n = norm01(dur)
    stab_n = norm01(pitch_stab)
    peak_n = norm01(intensity_peak)
    var_n = norm01(pitch_var)

    raw_score = (args.w1 * dur_n + args.w2 * stab_n +
                 args.w3 * peak_n - args.w4 * var_n)
    # Renormalize the combined score to [0, 1] so it can double as a
    # posterior-probability-like head-salience value in stats/labels.
    lo, hi = float(np.min(raw_score)), float(np.max(raw_score))
    if hi - lo < 1e-9:
        score = np.full_like(raw_score, 0.5)
    else:
        score = (raw_score - lo) / (hi - lo)
    return score


# ─────────────────────────────────────────────────────────────────────────────
# E — MAP-style reduction: min-spacing weighted DP (Viterbi-shaped)
# ─────────────────────────────────────────────────────────────────────────────

def dp_select_heads(starts, scores, min_gap):
    """
    Classic weighted interval-scheduling DP: choose a subset of segment
    indices maximizing sum(score) such that any two chosen segments'
    start times differ by at least min_gap. Segments are already in
    time order, so for each i we find the latest j < i whose start is
    still >= min_gap away and take max(skip, score[i] + best[j]).
    This is the same recurrence shape as Viterbi decoding over a chain,
    with "compatible predecessor" playing the role of the allowed
    transition set.

    Indices returned are positions within `starts`, in time order.
    """
    starts = np.asarray(starts, dtype=float)
    scores = np.asarray(scores, dtype=float)
    n = starts.size
    if n == 0:
        return []

    best = np.zeros(n)
    choice = np.zeros(n, dtype=bool)
    back = np.full(n, -1, dtype=int)

    # For each i, find the latest predecessor j with
    # starts[j] <= starts[i] - min_gap. searchsorted instead of the old
    # backward scan: on dense material (thousands of segments, small
    # min_gap) that scan degenerates towards O(n^2).
    for i in range(n):
        target = starts[i] - min_gap
        j = int(np.searchsorted(starts, target, side="right")) - 1
        if j >= i:
            j = i - 1
        take = scores[i] + (best[j] if j >= 0 else 0.0)
        skip = best[i - 1] if i > 0 else 0.0
        if take >= skip:
            best[i] = take
            choice[i] = True
            back[i] = j
        else:
            best[i] = skip
            choice[i] = False
            back[i] = i - 1

    # Backtrack
    selected = []
    i = n - 1
    while i >= 0:
        if choice[i]:
            selected.append(i)
            i = back[i]
        else:
            i -= 1
    selected.reverse()
    return selected


def _trim_to_target(pool, scores, target_n):
    """
    Keep the `target_n` highest-scoring members of an already
    minimum-spaced pool. A subset of a spaced set is still spaced, so
    trimming can only ever satisfy the spacing constraint, never break it.

    target_n <= 0 means "no cap", not "select nothing": a level fraction
    left at 0 should fall back to whatever the spacing DP chose rather
    than silently hand Stage 3 an empty EDL.
    """
    if target_n <= 0 or len(pool) <= target_n:
        return sorted(pool)
    keep = sorted(pool, key=lambda i: scores[i], reverse=True)[:target_n]
    return sorted(keep)


def assign_levels(segments, stats_list, scores, args):
    """
    Two nested DP passes. The head pass runs over all segments at
    min_head_gap_s; the anchor pass runs *within the surviving heads* at
    min_anchor_gap_s, which makes Level 0 a subset of Level 1 by
    construction. v1.0 ran the two passes independently and intersected
    them afterwards — with different spacing constraints the two optima
    frequently disagreed, and the intersection could collapse to a
    handful of anchors (or none), which is one reason the EDL came out
    thinner than the Reduction_density preset implied.

    level0_frac / level1_frac now actually bind: they cap the pools. In
    v1.0 they were computed, logged as "targets", and never used — only
    the min-gap spacing decided the counts.
    """
    starts = np.array([s["start"] for s in segments], dtype=float)
    n = len(segments)
    if n == 0:
        return []

    # Combined structural backbone: Level 0 and Level 1 together.
    head_target = int(round((args.level0_frac + args.level1_frac) * n))
    head_pool = dp_select_heads(starts, scores, args.min_head_gap_s)
    head_pool = _trim_to_target(head_pool, scores, head_target)

    # DURATION BUDGET. The count caps above bound how MANY segments are kept,
    # which does not bound how much AUDIO is kept — the head score rewards
    # duration, so the segments it selects are the long ones. Measured on a
    # 10.7 s flute phrase, keeping 2 of 3 groups kept 97.5% of the file and
    # the montage was indistinguishable from the input. Heads are dropped
    # lowest-score-first until the retained span fits the budget.
    if 0 < args.target_retention < 1.0 and head_pool:
        total = float(sum(seg["end"] - seg["start"] for seg in segments))
        budget = args.target_retention * total
        ranked = sorted(head_pool, key=lambda i: scores[i], reverse=True)
        kept, used = [], 0.0
        for i in ranked:
            d = segments[i]["end"] - segments[i]["start"]
            if used + d <= budget or not kept:
                # `or not kept` guarantees at least one head survives: an
                # empty EDL means no audio at all, which is a worse failure
                # than overshooting the budget by one segment. This is the
                # single exception that makes target_retention a target and
                # not a cap, so it is recorded rather than left implicit —
                # otherwise a short file with one dominant segment silently
                # returns 80% against a 45% request.
                kept.append(i)
                used += d
        head_pool = sorted(kept)
        if used > budget:
            assign_levels.overshoot = (used, budget, total)

    # Anchors chosen among the heads only.
    anchor_target = int(round(args.level0_frac * n))
    if head_pool:
        sub_idx = np.array(head_pool, dtype=int)
        sub_sel = dp_select_heads(starts[sub_idx], scores[sub_idx], args.min_anchor_gap_s)
        anchor_pool = [int(sub_idx[k]) for k in sub_sel]
        anchor_pool = _trim_to_target(anchor_pool, scores, anchor_target)
    else:
        anchor_pool = []

    levels = ["L3"] * n
    for i in head_pool:
        levels[i] = "L1"
    for i in anchor_pool:
        levels[i] = "L0"

    # Remaining (non-head) segments get split into L2 (Ornament) vs L3
    # (Artifact/Noise) by score, using level2_frac of the remainder as
    # the Ornament share.
    remainder = [i for i in range(n) if levels[i] == "L3"]
    remainder_sorted = sorted(remainder, key=lambda i: scores[i], reverse=True)
    n_l2 = int(round(args.level2_frac * len(remainder_sorted)))
    for i in remainder_sorted[:n_l2]:
        levels[i] = "L2"

    return levels


# ─────────────────────────────────────────────────────────────────────────────
# F — Output writers
# ─────────────────────────────────────────────────────────────────────────────

def _tg_escape(text):
    return text.replace('"', '""')


def _clamped(segments, duration):
    """
    Segment spans clipped to [0, duration] for TextGrid emission, dropping
    anything that collapses. Praat rejects a tier whose intervals leave the
    object's own [xmin, xmax], so this is enforced at the point of writing as
    well as at the point of construction — the writer is the last place the
    invariant can still be checked.
    """
    out = []
    for seg in segments:
        a, b = max(0.0, float(seg["start"])), min(float(duration), float(seg["end"]))
        if b - a > 1e-9:
            out.append((a, b))
    return out


def write_textgrid(path, duration, segments, levels, sound_name):
    """
    Native Praat long TextGrid text format, 3 tiers:
      1. Grouping_Macro   (Interval) — the merged GPR segments
      2. TimeSpan_Heads   (Interval) — Level 0/1 spans labeled, rest blank
      3. Ornaments_Level2_3 (Point)  — one point per L2/L3 segment onset
    Interval tiers must tile [0, duration] with no gaps, so leading/
    trailing pad intervals are inserted where segments don't start at 0
    or don't reach duration.
    """
    n = len(segments)

    # ---- Tier 1 intervals: the segments themselves, gapless by construction ----
    tier1 = []
    if n and segments[0]["start"] > 1e-9:
        tier1.append((0.0, segments[0]["start"], ""))
    for i, seg in enumerate(segments):
        tier1.append((seg["start"], seg["end"], "Group_%d" % (i + 1)))
    if n and segments[-1]["end"] < duration - 1e-9:
        tier1.append((segments[-1]["end"], duration, ""))
    if not n:
        tier1.append((0.0, duration, ""))

    # ---- Tier 2 intervals: same spans, labeled only where L0/L1 ----
    tier2 = []
    if n and segments[0]["start"] > 1e-9:
        tier2.append((0.0, segments[0]["start"], ""))
    for i, seg in enumerate(segments):
        lab = ""
        if levels[i] == "L0":
            lab = "L0_Anchor"
        elif levels[i] == "L1":
            lab = "L1_Head"
        tier2.append((seg["start"], seg["end"], lab))
    if n and segments[-1]["end"] < duration - 1e-9:
        tier2.append((segments[-1]["end"], duration, ""))
    if not n:
        tier2.append((0.0, duration, ""))

    # ---- Tier 3 points: onset of every L2/L3 segment ----
    tier3 = []
    for i, seg in enumerate(segments):
        if levels[i] == "L2":
            tier3.append((seg["start"], "L2_Ornament"))
        elif levels[i] == "L3":
            tier3.append((seg["start"], "L3_Artifact"))
    tier3.sort(key=lambda p: p[0])

    lines = []
    lines.append('File type = "ooTextFile"')
    lines.append('Object class = "TextGrid"')
    lines.append("")
    lines.append("xmin = 0")
    lines.append("xmax = %.6f" % duration)
    lines.append("tiers? <exists>")
    lines.append("size = 3")
    lines.append("item []:")

    # Tier 1
    lines.append('    item [1]:')
    lines.append('        class = "IntervalTier"')
    lines.append('        name = "Grouping_Macro"')
    lines.append('        xmin = 0')
    lines.append('        xmax = %.6f' % duration)
    lines.append('        intervals: size = %d' % len(tier1))
    for k, (s, e, lab) in enumerate(tier1, start=1):
        lines.append('        intervals [%d]:' % k)
        lines.append('            xmin = %.6f' % s)
        lines.append('            xmax = %.6f' % e)
        lines.append('            text = "%s"' % _tg_escape(lab))

    # Tier 2
    lines.append('    item [2]:')
    lines.append('        class = "IntervalTier"')
    lines.append('        name = "TimeSpan_Heads"')
    lines.append('        xmin = 0')
    lines.append('        xmax = %.6f' % duration)
    lines.append('        intervals: size = %d' % len(tier2))
    for k, (s, e, lab) in enumerate(tier2, start=1):
        lines.append('        intervals [%d]:' % k)
        lines.append('            xmin = %.6f' % s)
        lines.append('            xmax = %.6f' % e)
        lines.append('            text = "%s"' % _tg_escape(lab))

    # Tier 3
    lines.append('    item [3]:')
    lines.append('        class = "TextTier"')
    lines.append('        name = "Ornaments_Level2_3"')
    lines.append('        xmin = 0')
    lines.append('        xmax = %.6f' % duration)
    lines.append('        points: size = %d' % len(tier3))
    for k, (t, lab) in enumerate(tier3, start=1):
        lines.append('        points [%d]:' % k)
        lines.append('            number = %.6f' % t)
        lines.append('            mark = "%s"' % _tg_escape(lab))

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def write_edl(path, segments, levels, scores):
    """
    splicing_edl.csv — retained Level 0 + Level 1 spans only, in time
    order, ready for Stage 3 (build_montage.praat) to slice + crossfade.
    """
    rows = []
    for i, seg in enumerate(segments):
        if levels[i] in ("L0", "L1"):
            rows.append((seg["start"], seg["end"], levels[i], float(scores[i])))
    rows.sort(key=lambda r: r[0])

    with open(path, "w", encoding="utf-8") as f:
        f.write("order,start_s,end_s,duration_s,level,score\n")
        for order, (s, e, lvl, sc) in enumerate(rows, start=1):
            f.write("%d,%.6f,%.6f,%.6f,%s,%.6f\n" % (order, s, e, e - s, lvl, sc))
    return len(rows)


def write_trace(path, times, onset_fn, thr_curve, flux, d_db, n_points):
    """
    Decimated onset-function trace for the Praat figure.

    Praat queries a Table one cell per call, so handing it 18,000 frames to
    plot across a seven-inch panel costs tens of thousands of calls for
    detail no printer can resolve. Buckets are max-pooled rather than
    averaged: the whole point of the panel is where the peaks are, and
    averaging is exactly the operation that hides them.
    """
    n = len(times)
    n_points = max(2, min(n_points, n))
    edges = np.linspace(0, n, n_points + 1).astype(int)
    rows = []
    fn_n = robust_norm(flux)
    db_n = robust_norm(d_db)
    for k in range(n_points):
        lo, hi = edges[k], max(edges[k] + 1, edges[k + 1])
        rows.append((float(times[lo:hi].mean()),
                     float(np.max(onset_fn[lo:hi])),
                     # The threshold is a curve, not a level, so the figure
                     # needs it sampled alongside the function. Mean, not max:
                     # this is the floor a peak had to clear, and max-pooling
                     # it would draw a threshold no peak actually faced.
                     float(np.mean(thr_curve[lo:hi])),
                     float(np.max(fn_n[lo:hi])),
                     float(np.max(db_n[lo:hi]))))
    with open(path, "w", encoding="utf-8") as f:
        f.write("time_s,onset_fn,thr_curve,flux_n,db_n\n")
        for t, o, th, fx, d in rows:
            f.write("%.6f,%.6f,%.6f,%.6f,%.6f\n" % (t, o, th, fx, d))
    return len(rows)


def write_segments(path, raw_segs, strengths, parent, merged, levels, scores):
    """
    One row per RAW (onset-bounded) segment, carrying both its own boundary
    evidence and the group it ended up in. This single table is enough to
    draw the onset ticks, the GPR boundary-strength panel, the head-score
    scatter and the reduction map, so the figure needs no second pass over
    the frame CSV.

    `level` is written as text for a human reading the file and as
    `level_id` for Praat, whose Table queries return numbers.
    """
    level_id = {"L0": 0, "L1": 1, "L2": 2, "L3": 3}
    with open(path, "w", encoding="utf-8") as f:
        f.write("raw_index,start_s,end_s,gpr_strength,boundary_kept,"
                "group_index,group_start_s,group_end_s,level,level_id,score\n")
        for i, seg in enumerate(raw_segs):
            g = parent[i]
            # Boundary strength belongs to the boundary at this segment's LEFT
            # edge; segment 0 has no left boundary, written as -1 so the figure
            # can skip it rather than plotting a fictitious zero.
            gs = float(strengths[i - 1]) if (i > 0 and len(strengths) >= i) else -1.0
            kept = 1 if (i == 0 or parent[i] != parent[i - 1]) else 0
            lvl = levels[g] if g < len(levels) else "L3"
            f.write("%d,%.6f,%.6f,%.6f,%d,%d,%.6f,%.6f,%s,%d,%.6f\n"
                    % (i + 1, seg["start"], seg["end"], gs, kept, g + 1,
                       merged[g]["start"], merged[g]["end"],
                       lvl, level_id.get(lvl, 3), float(scores[g])))
    return len(raw_segs)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()
    log("=== pGTTM Engine v1.4 — %s ===" % args.sound_name, args=args)

    df = load_features(args.features)
    log("Loaded %d frames" % len(df), args=args)
    if len(df) == 0:
        log("ERROR: acoustic_features.csv has no rows.", args=args)
        sys.exit(1)

    # ---- A2: onsets ----
    has_onsets = "onset_flag" in df.columns and df["onset_flag"].notna().any()
    onset_fn = None
    thr_curve = None
    if args.audio or not has_onsets:
        flux, onset_flag, ioi_s, src, onset_fn, thr_curve = detect_onsets(df, args)
        df["spectral_flux"] = flux
        df["onset_flag"] = onset_flag
        df["ioi_s"] = ioi_s
        # Write the completed frame table back, so acoustic_features.csv
        # stays the single inspectable record of the analysis.
        df.to_csv(args.features, index=False, float_format="%.6f")
        if args.onset_median_window_s > 0:
            thr_desc = "+%.2f over a %.1fs local median" % (args.onset_threshold,
                                                            args.onset_median_window_s)
        else:
            thr_desc = "global %.2f" % args.onset_threshold
        log("Onsets: %d detected (%s, thresh %s, min IOI=%.0f ms)"
            % (int(onset_flag.sum()), src, thr_desc, args.min_ioi_ms), args=args)
    else:
        log("Onsets: %d read from existing CSV columns"
            % int((df["onset_flag"] == 1).sum()), args=args)

    raw_segs = raw_segments_from_onsets(df, args.duration, args.time_step)
    log("Raw onset-bounded segments: %d" % len(raw_segs), args=args)

    raw_stats = [segment_frame_stats(df, s) for s in raw_segs]
    # IOI per raw segment: time since previous segment's start, for GPR2.
    for i, s in enumerate(raw_segs):
        raw_stats[i]["ioi"] = (s["start"] - raw_segs[i - 1]["start"]) if i > 0 else 0.0

    strengths = gpr_boundary_strengths(raw_segs, raw_stats, args)
    merge_cut, survivors = resolve_merge_cut(strengths, args.merge_weakest_fraction)
    segments, parent = merge_weak_boundaries(raw_segs, raw_stats, strengths,
                                             merge_cut)
    log("Merged (Grouping_Macro) segments: %d — kept %d of %d boundaries "
        "(weakest %.0f%% merged, cut at strength %.3f)"
        % (len(segments), survivors, len(strengths),
           100 * args.merge_weakest_fraction, merge_cut), args=args)

    stats_list = [segment_frame_stats(df, s) for s in segments]
    for i, s in enumerate(segments):
        stats_list[i]["ioi"] = (s["start"] - segments[i - 1]["start"]) if i > 0 else 0.0

    scores = compute_head_scores(stats_list, args)
    assign_levels.overshoot = None
    levels = assign_levels(segments, stats_list, scores, args)
    if getattr(assign_levels, "overshoot", None):
        used, budget, total = assign_levels.overshoot
        log("NOTE: retention target overshot — the highest-scoring segment "
            "alone runs %.2f s against a budget of %.2f s, and at least one "
            "head always survives. Keeping %.1f%% instead of the requested "
            "%.1f%%." % (used, budget, 100 * used / total,
                         100 * args.target_retention), args=args)

    n = len(segments)
    n_l0 = levels.count("L0")
    n_l1 = levels.count("L1")
    n_l2 = levels.count("L2")
    n_l3 = levels.count("L3")
    log("Levels — L0(Anchor)=%d L1(Head)=%d L2(Ornament)=%d L3(Artifact)=%d "
        "(targets were L0=%.2f L1=%.2f L2=%.2f, achieved L0=%.2f L1=%.2f L2=%.2f)"
        % (n_l0, n_l1, n_l2, n_l3, args.level0_frac, args.level1_frac, args.level2_frac,
           n_l0 / n if n else 0.0, n_l1 / n if n else 0.0, n_l2 / n if n else 0.0),
        args=args)

    # ---- Figure data (only when Praat asked for it) ----
    if args.out_trace:
        times = df["time_s"].to_numpy(dtype=float)
        flux = df["spectral_flux"].to_numpy(dtype=float) if "spectral_flux" in df.columns \
            else np.zeros(len(df))
        db = df["intensity_db"].to_numpy(dtype=float)
        d_db = np.zeros(len(df))
        if len(df) > 1:
            d_db[1:] = np.maximum(np.diff(db), 0.0)
        if onset_fn is None:
            # Onsets were read from the CSV, so the function that produced
            # them is gone. The normalized flux is the closest honest stand-in
            # and the figure labels it as such.
            onset_fn = robust_norm(flux)
        if thr_curve is None:
            thr_curve = np.full(len(df), float(args.onset_threshold))
        n_trace = write_trace(args.out_trace, times, onset_fn, thr_curve,
                              flux, d_db, args.trace_points)
        log("Wrote figure trace (%d points)" % n_trace, args=args)

    if args.out_segments:
        n_seg = write_segments(args.out_segments, raw_segs, strengths, parent,
                               segments, levels, scores)
        log("Wrote figure segment table (%d raw segments)" % n_seg, args=args)

    write_textgrid(args.out_textgrid, args.duration, segments, levels, args.sound_name)
    n_edl = write_edl(args.out_edl, segments, levels, scores)

    kept_dur = sum(seg["end"] - seg["start"]
                   for i, seg in enumerate(segments) if levels[i] in ("L0", "L1"))
    frac = kept_dur / args.duration if args.duration > 0 else 0.0
    log("Wrote gttm_output.TextGrid and splicing_edl.csv — %d spans, %.2f s of "
        "%.2f s (%.1f%% of the original retained)"
        % (n_edl, kept_dur, args.duration, 100 * frac), args=args)

    if n_edl == 0:
        log("WARNING: the EDL is empty — Stage 3 will have nothing to splice. "
            "Lower the onset margin, merge a smaller fraction of boundaries, "
            "or use a denser Reduction_density preset.", args=args)
    elif frac > 0.90:
        # The failure this guard exists for is silent: a montage that is
        # 97% of the input plays back as the input, and nothing else in the
        # pipeline notices.
        log("WARNING: %.1f%% of the original was retained — the montage will "
            "be close to the input. Lower Target_retention, or merge a "
            "smaller fraction of boundaries so there are more groups to "
            "choose between (currently %d groups from %d onsets)."
            % (100 * frac, len(segments), len(raw_segs)), args=args)


if __name__ == "__main__":
    main()
