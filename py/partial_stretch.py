#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - partial_stretch.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Backend for IRCAM_Partial_Stretch.praat. PM2 partial analysis ->
#   partial tracks -> one of five track operations -> additive
#   resynthesis -> automatic level balancing.
#
#   Modes (what they actually do):
#     spectral_stretch  tracks above the split frequency are time-stretched;
#                       they also get an AUTOMATIC amplitude boost (x1..x8,
#                       from the lower/upper RMS ratio) so they stay audible
#     band_stretch      three bands, each with its own time-stretch factor
#                       and an AUTOMATIC per-band boost (x1..x8)
#     freeze            the partials at one instant held as a drone
#     partial_thin      above a threshold, keep every N-th track
#                       (tracks ordered by mean frequency)
#     spectral_blur     moving average of each track's AMPLITUDE envelope;
#                       frequencies are untouched (amplitude-envelope
#                       smoothing, not a frequency blur)
#
#   Resynthesis: sum of sinusoids, phase obtained by integrating each
#   track's frequency from zero (PM2's measured phases are parsed but not
#   used — kept deliberately, see changelog). After synthesis an automatic
#   LEVEL BALANCING stage evens out 0.5 s blocks toward their median peak
#   (gain <= x10, 0.1 s smoothing), then peak-normalises to 0.9 and applies
#   Output gain (capped at 2) with hard clipping. Level balancing can be
#   switched off; peak normalisation always runs.
#
# Changelog v1.4:
#   - PM2 window: nearest power of two to the requested length (v1.3
#     rounded up: 46.44 ms at 48 kHz became 85 ms). Unchanged at 44.1 kHz.
#   - Sample rate taken from the input file (was fixed at 44.1 kHz): PM2
#     window/hop are now computed in the file's own samples, and the
#     output is written at the input rate. Output for 44.1 kHz input is
#     unchanged (verified sample-identical against v1.3).
#   - Parameters read from a key=value file (one path argument), like the
#     SuperVP bridge; the command-line form still works.
#   - Session-prefixed temporary files, removed on every exit path.
#   - Manifest with what the algorithm did: selected tracks per band,
#     group counts, stretch factors, automatic boosts, level-balancing gain
#     range, normalisation factor, clipped samples, durations, sample rate.
#   - Visualisation data: input and output partial tracks (decimated) and
#     the level-balancing gain curve.
#   - Level balancing switchable (default on = v1.3 behaviour).
#   - Clear errors instead of silent fixes: Thin every N < 2, non-positive
#     stretch factors, missing numpy/soundfile.
#   - Phase reconstruction NOT changed: PM2-phase-aware resynthesis would
#     change the sound and should be A/B tested as a separate option.
#
# Changelog v1.3: fixed track selection, dual sub-frames
# ============================================================

import argparse
import math
import os
import subprocess
import sys
import traceback

try:
    import numpy as np
    import soundfile as sf
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

VERSION = "1.4"
DEFAULT_PM2_DIR = r"C:\Users\User\Pm2\bin"
DEFAULT_SR = 44100          # only a fallback; the input file's rate is used


class PSError(Exception):
    pass


# =============================================================================
#  INFRASTRUCTURE
# =============================================================================

def safe_mkdir(path):
    if path and not os.path.isdir(path):
        os.makedirs(path, exist_ok=True)

def write_done(done_file, status):
    try:
        safe_mkdir(os.path.dirname(done_file))
        with open(done_file, "w", encoding="utf-8") as fh:
            fh.write(status + "\n")
    except OSError:
        pass

def append_log(log_path, text):
    if not log_path:
        return
    try:
        safe_mkdir(os.path.dirname(log_path))
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(text)
            if not text.endswith("\n"):
                fh.write("\n")
    except OSError:
        pass

def next_power_of_two(n):
    p = 1
    while p < n:
        p <<= 1
    return p

def resolve_pm2(pm2_dir):
    for name in ["pm2.exe", "Pm2.exe", "PM2.exe", "pm2"]:
        candidate = os.path.join(pm2_dir, name)
        if os.path.isfile(candidate):
            return candidate
    return os.path.join(pm2_dir, "pm2.exe")


# =============================================================================
#  PM2 ANALYSIS
# =============================================================================

def run_pm2_analysis(pm2_exe, input_wav, output_txt, args, log_path, sr):
    raw_win = max(16, round(args.analysis_window_ms * sr / 1000.0))
    # nearest power of two (v1.3 rounded UP, which nearly doubled the window
    # at 48 kHz: 2229 -> 4096 samples). Identical at 44.1 kHz (2048 exact).
    up = next_power_of_two(raw_win)
    down = max(16, up // 2)
    win_samples = up if (up / raw_win) <= (raw_win / down) else down
    hop_samples = max(1, round(args.hop_ms * sr / 1000.0))

    sdif_base = output_txt
    if sdif_base.endswith(".txt"):
        sdif_base = sdif_base[:-4]

    cmd = [
        pm2_exe, "-Apar",
        f"-S{input_wav}",
        f"-q{args.max_partials}",
        f"-M{win_samples}",
        f"-N{win_samples}",
        f"-I{hop_samples}",
        "-Oa", sdif_base + ".txt"
    ]
    cmd_str = " ".join(f'"{a}"' if " " in str(a) else str(a) for a in cmd)
    print(f"  PM2 CMD: {cmd_str}", flush=True)
    append_log(log_path, f"PM2 CMD: {cmd_str}\n")
    STATS["pm2_cmd"] = cmd_str
    STATS["pm2_window"] = f"{win_samples} samples ({1000.0 * win_samples / sr:.2f} ms at {sr} Hz)"
    STATS["pm2_hop"] = f"{hop_samples} samples ({1000.0 * hop_samples / sr:.2f} ms)"

    if args.dry_run:
        return 0

    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        combined = result.stdout or ""
        if combined.strip():
            print(combined, flush=True)
        append_log(log_path, combined)
        return result.returncode
    except Exception as exc:
        msg = f"Error launching PM2: {exc}"
        print(f"  ERROR: {msg}", flush=True)
        append_log(log_path, msg + "\n")
        return 1


# =============================================================================
#  PARTIAL TRACK
# =============================================================================

class PartialTrack:
    __slots__ = ("track_id", "times", "freqs", "amps", "phases")

    def __init__(self, track_id):
        self.track_id = track_id
        self.times = []
        self.freqs = []
        self.amps = []
        self.phases = []

    def append(self, t, f, a, p):
        self.times.append(t)
        self.freqs.append(f)
        self.amps.append(a)
        self.phases.append(p)

    def mean_freq(self):
        active = [f for f, a in zip(self.freqs, self.amps) if a > 1e-7 and f > 0]
        return sum(active) / len(active) if active else 0.0

    def max_amp(self):
        return max(self.amps) if self.amps else 0.0

    def rms_amp(self):
        if not self.amps:
            return 0.0
        return math.sqrt(sum(a * a for a in self.amps) / len(self.amps))

    def duration(self):
        if len(self.times) < 2:
            return 0.0
        return self.times[-1] - self.times[0]

    def time_stretch(self, factor):
        new = PartialTrack(self.track_id)
        for t, f, a, p in zip(self.times, self.freqs, self.amps, self.phases):
            new.append(t * factor, f, a, p)
        return new

    def copy(self):
        new = PartialTrack(self.track_id)
        new.times = list(self.times)
        new.freqs = list(self.freqs)
        new.amps = list(self.amps)
        new.phases = list(self.phases)
        return new


# =============================================================================
#  PARSING — handles PM2 dual sub-frames
# =============================================================================

def parse_to_tracks(txt_path, max_partials=80, log_path=None):
    """
    Parse PM2 text output into PartialTrack objects.
    
    PM2 outputs TWO sub-frames per time step (both sinusoidal track groups
    with non-overlapping track IDs). Both are merged per time, then the
    top tracks by max amplitude are selected (not by ID number).
    """
    if not os.path.isfile(txt_path):
        print(f"  ERROR: File not found: {txt_path}", flush=True)
        return [], 0.0

    with open(txt_path, "r", encoding="utf-8") as fh:
        lines = fh.readlines()

    print(f"  File: {len(lines)} lines", flush=True)

    # Pass 1: parse all frames (merge sub-frames at same time)
    frames_by_time = {}
    current_time = None
    rows_remaining = 0

    for raw in lines:
        parts = raw.strip().split()
        if not parts:
            continue

        # Frame header: <count> <time>
        if len(parts) == 2:
            try:
                rows_remaining = int(float(parts[0]))
                current_time = float(parts[1])
                if current_time not in frames_by_time:
                    frames_by_time[current_time] = {}
                # Don't reset — second sub-frame merges into same dict
            except ValueError:
                pass
            continue

        # Partial data: <idx> <freq> <amp> <phase>
        if len(parts) >= 4 and current_time is not None and rows_remaining > 0:
            try:
                track_idx = int(float(parts[0]))
                freq = float(parts[1])
                amp = float(parts[2])
                phase = float(parts[3])
                frames_by_time[current_time][track_idx] = (freq, amp, phase)
                rows_remaining -= 1
            except ValueError:
                pass

    if not frames_by_time:
        print("  ERROR: No frames parsed.", flush=True)
        return [], 0.0

    sorted_times = sorted(frames_by_time.keys())
    all_ids = sorted({idx for fd in frames_by_time.values() for idx in fd})

    print(f"  Parsed: {len(sorted_times)} time steps, {len(all_ids)} unique track IDs", flush=True)
    print(f"  Time range: {sorted_times[0]:.4f} - {sorted_times[-1]:.4f} s", flush=True)

    # Pass 2: compute per-track stats in one pass
    track_max_amp = {}
    track_freq_sum = {}
    track_freq_n = {}
    for fd in frames_by_time.values():
        for tid, (freq, amp, phase) in fd.items():
            if tid not in track_max_amp or amp > track_max_amp[tid]:
                track_max_amp[tid] = amp
            if amp > 1e-7 and freq > 0:
                track_freq_sum[tid] = track_freq_sum.get(tid, 0.0) + freq
                track_freq_n[tid] = track_freq_n.get(tid, 0) + 1

    track_mean_freq = {}
    for tid in all_ids:
        n = track_freq_n.get(tid, 0)
        track_mean_freq[tid] = track_freq_sum.get(tid, 0.0) / n if n > 0 else 0.0

    # Stratified selection: pick top tracks from each frequency band
    # to guarantee upper-partial coverage (pure amplitude ranking
    # selects only the loudest low-frequency partials).
    bands = [(0, 300), (300, 600), (600, 1000), (1000, 2000),
             (2000, 4000), (4000, 8000), (8000, 20000)]
    per_band = max(5, max_partials // len(bands))
    selected_ids = set()

    for lo, hi in bands:
        band_tracks = [(tid, track_max_amp.get(tid, 0)) for tid in all_ids
                       if lo <= track_mean_freq.get(tid, 0) < hi
                       and track_max_amp.get(tid, 0) > 1e-8]
        band_tracks.sort(key=lambda x: x[1], reverse=True)
        for tid, _ in band_tracks[:per_band]:
            selected_ids.add(tid)

    # Fill remaining slots with next-loudest from any band
    remaining = max_partials - len(selected_ids)
    if remaining > 0:
        leftovers = [(tid, track_max_amp.get(tid, 0)) for tid in all_ids
                     if tid not in selected_ids and track_max_amp.get(tid, 0) > 1e-8]
        leftovers.sort(key=lambda x: x[1], reverse=True)
        for tid, _ in leftovers[:remaining]:
            selected_ids.add(tid)

    selected_ids = sorted(selected_ids)

    band_counts = {}
    for tid in selected_ids:
        mf = track_mean_freq.get(tid, 0)
        for lo, hi in bands:
            if lo <= mf < hi:
                band_counts[f"{lo}-{hi}"] = band_counts.get(f"{lo}-{hi}", 0) + 1
                break
    print(f"  Selected {len(selected_ids)} tracks (stratified by freq band)", flush=True)
    print(f"  Per band: {band_counts}", flush=True)
    STATS["tracks_found"] = len(all_ids)
    STATS["tracks_selected"] = len(selected_ids)
    STATS["time_steps"] = len(sorted_times)
    STATS["selected_per_band"] = "  ".join(f"{lo}-{hi}: {band_counts.get(f'{lo}-{hi}', 0)}"
                                           for lo, hi in bands)

    # Pass 3: build tracks
    tracks = {}
    for tid in selected_ids:
        tracks[tid] = PartialTrack(tid)

    for t in sorted_times:
        fd = frames_by_time[t]
        for tid in selected_ids:
            if tid in fd:
                freq, amp, phase = fd[tid]
                tracks[tid].append(t, freq, amp, phase)
            else:
                tracks[tid].append(t, 0.0, 0.0, 0.0)

    track_list = list(tracks.values())
    total_dur = sorted_times[-1] if sorted_times else 0.0

    # Diagnostics
    active_tracks = [t for t in track_list if t.max_amp() > 1e-8]
    print(f"  Active tracks: {len(active_tracks)} / {len(track_list)}", flush=True)

    by_amp = sorted(active_tracks, key=lambda t: t.max_amp(), reverse=True)
    print(f"  Top 5 tracks:", flush=True)
    for tr in by_amp[:5]:
        print(f"    #{tr.track_id:4d}  freq={tr.mean_freq():8.1f} Hz  "
              f"max_amp={tr.max_amp():.6f}  rms={tr.rms_amp():.6f}  "
              f"dur={tr.duration():.3f}s", flush=True)

    return track_list, total_dur


# =============================================================================
#  ADDITIVE RESYNTHESIS — block-normalised
# =============================================================================

def resynthesize(tracks, sr=DEFAULT_SR, output_gain=1.0, level_balance=True):
    if not tracks:
        return np.zeros(sr, dtype=np.float32), sr

    max_time = 0.0
    for t in tracks:
        if t.times and t.times[-1] > max_time:
            max_time = t.times[-1]

    if max_time <= 0:
        return np.zeros(sr, dtype=np.float32), sr

    n_samples = int(round((max_time + 0.1) * sr))
    audio = np.zeros(n_samples, dtype=np.float64)

    for track in tracks:
        n_pts = len(track.times)
        if n_pts < 2 or track.max_amp() < 1e-8:
            continue

        phase = 0.0

        for fi in range(n_pts - 1):
            t0, t1 = track.times[fi], track.times[fi + 1]
            f0, f1 = track.freqs[fi], track.freqs[fi + 1]
            a0, a1 = track.amps[fi], track.amps[fi + 1]

            s0 = max(0, int(round(t0 * sr)))
            s1 = min(n_samples, int(round(t1 * sr)))
            if s0 >= s1:
                if f0 > 0:
                    phase = (phase + 2.0 * math.pi * f0 * max(0.0, t1 - t0)) % (2.0 * math.pi)
                continue

            hop_n = s1 - s0

            # Birth / death frequency continuity
            if a0 <= 1e-8 and a1 > 1e-8:
                f0 = f1
            if a1 <= 1e-8 and a0 > 1e-8:
                f1 = f0
            if f0 <= 0 and f1 <= 0:
                continue
            if f0 <= 0:
                f0 = f1
            if f1 <= 0:
                f1 = f0
            if a0 <= 1e-8 and a1 <= 1e-8:
                phase = (phase + 2.0 * math.pi * f0 * hop_n / sr) % (2.0 * math.pi)
                continue

            freq_env = np.linspace(f0, f1, hop_n, endpoint=False)
            amp_env = np.linspace(a0, a1, hop_n, endpoint=False)
            phase_inc = 2.0 * math.pi * freq_env / sr
            inst_phase = phase + np.cumsum(phase_inc)

            audio[s0:s1] += amp_env * np.sin(inst_phase)
            phase = inst_phase[-1] % (2.0 * math.pi)

    raw_peak = float(np.max(np.abs(audio)))
    gain_env = np.ones(n_samples, dtype=np.float64)
    if level_balance:
        gain_env = block_balance_gain(audio, sr, n_samples)
        audio *= gain_env

    peak = np.max(np.abs(audio))
    norm = 0.9 / peak if peak > 1e-10 else 1.0
    audio = audio * norm
    g = min(output_gain, 2.0)
    audio *= g
    n_clip = int(np.sum(np.abs(audio) > 1.0))
    np.clip(audio, -1.0, 1.0, out=audio)

    final_peak = float(np.max(np.abs(audio)))
    final_rms = float(np.sqrt(np.mean(audio ** 2)))
    n_silent = int(np.sum(np.abs(audio) < 1e-6))
    print(f"  Resynth: {n_samples/sr:.2f}s  peak={final_peak:.4f}  rms={final_rms:.6f}  "
          f"silent={100*n_silent/max(1,n_samples):.1f}%", flush=True)

    STATS["sample_rate"] = sr
    STATS["output_duration"] = round(n_samples / sr, 4)
    STATS["level_balance"] = "on" if level_balance else "off"
    if level_balance:
        STATS["balance_gain_range"] = f"{gain_env.min():.2f}..{gain_env.max():.2f}"
    STATS["peak_after_synthesis"] = round(raw_peak, 6)
    STATS["peak_before_norm"] = round(float(peak), 6)
    STATS["normalise_factor"] = round(norm, 6)
    STATS["output_gain_applied"] = g
    STATS["clipped_samples"] = n_clip
    STATS["output_peak"] = round(final_peak, 4)
    STATS["output_rms"] = round(final_rms, 6)
    total = gain_env * norm * g                         # overall gain curve after synthesis
    step = max(1, n_samples // 1500)
    VIZ["gain"] = [(i / sr, float(total[i])) for i in range(0, n_samples, step)]
    return audio.astype(np.float32), sr


def block_balance_gain(audio, sr, n_samples):
    """Automatic level balancing (v1.3 behaviour, unchanged): gain per 0.5 s
    block toward the median non-silent block peak, at most x10, smoothed
    over 0.1 s."""
    block_dur = 0.5
    block_len = int(block_dur * sr)
    n_blocks = max(1, int(math.ceil(n_samples / block_len)))

    block_peaks = np.zeros(n_blocks)
    for bi in range(n_blocks):
        b0 = bi * block_len
        b1 = min(b0 + block_len, n_samples)
        block_peaks[bi] = np.max(np.abs(audio[b0:b1])) + 1e-12

    non_silent = block_peaks[block_peaks > 1e-6]
    target = float(np.median(non_silent)) if len(non_silent) > 0 else 1e-6

    gain_env = np.ones(n_samples, dtype=np.float64)
    for bi in range(n_blocks):
        b0 = bi * block_len
        b1 = min(b0 + block_len, n_samples)
        if block_peaks[bi] > 1e-8:
            gain_env[b0:b1] = min(target / block_peaks[bi], 10.0)

    smooth_len = int(0.1 * sr)
    if smooth_len > 1 and len(gain_env) > smooth_len:
        kernel = np.ones(smooth_len) / smooth_len
        gain_env = np.convolve(gain_env, kernel, mode="same")
    return gain_env


# =============================================================================
#  MODES
# =============================================================================

def mode_spectral_stretch(tracks, total_dur, args, log_path):
    split = args.split_freq_hz
    hi_factor = args.upper_stretch_factor
    print(f"  Mode: spectral_stretch  split={split:.0f} Hz  upper={hi_factor:.2f}x", flush=True)

    lo_rms_sum = hi_rms_sum = 0.0
    n_lo = n_hi = 0
    for track in tracks:
        mf = track.mean_freq()
        if mf <= 0:
            continue
        rms = track.rms_amp()
        if mf < split:
            lo_rms_sum += rms; n_lo += 1
        else:
            hi_rms_sum += rms; n_hi += 1

    boost = 2.0
    if n_lo > 0 and n_hi > 0 and hi_rms_sum > 1e-10:
        lo_avg = lo_rms_sum / n_lo
        hi_avg = hi_rms_sum / n_hi
        boost = max(1.0, min(8.0, lo_avg / hi_avg * 0.7))

    print(f"  Lower: {n_lo}  Upper: {n_hi}  Boost: {boost:.2f}x", flush=True)
    STATS["groups"] = f"below {split:.0f} Hz: {n_lo} tracks x1.00 time, gain x1.00 | " \
                      f"above: {n_hi} tracks x{hi_factor:.2f} time, AUTO gain x{boost:.2f}"
    STATS["auto_boost"] = round(boost, 3)
    GROUP_OF.update({t.track_id: (0 if t.mean_freq() < split else 1) for t in tracks if t.mean_freq() > 0})

    new_tracks = []
    for track in tracks:
        mf = track.mean_freq()
        if mf <= 0:
            continue
        if mf < split:
            new_tracks.append(track.copy())
        else:
            stretched = track.time_stretch(hi_factor)
            stretched.amps = [a * boost for a in stretched.amps]
            new_tracks.append(stretched)

    return new_tracks


def mode_band_stretch(tracks, total_dur, args, log_path):
    lo_hi = args.band_lo_hz
    mid_hi = args.band_mid_hz
    lo_f, mid_f, hi_f = args.band_lo_stretch, args.band_mid_stretch, args.band_hi_stretch
    print(f"  Mode: band_stretch  0-{lo_hi:.0f}({lo_f:.1f}x)  "
          f"{lo_hi:.0f}-{mid_hi:.0f}({mid_f:.1f}x)  {mid_hi:.0f}+({hi_f:.1f}x)", flush=True)

    band_rms = [0.0, 0.0, 0.0]
    band_n = [0, 0, 0]
    for track in tracks:
        mf = track.mean_freq()
        if mf <= 0: continue
        rms = track.rms_amp()
        bi = 0 if mf < lo_hi else (1 if mf < mid_hi else 2)
        band_rms[bi] += rms; band_n[bi] += 1

    band_avg = [band_rms[i] / max(1, band_n[i]) for i in range(3)]
    ref = max(band_avg) if max(band_avg) > 1e-10 else 1.0
    boosts = [min(8.0, max(1.0, ref / ba * 0.5)) if ba > 1e-10 else 1.0 for ba in band_avg]
    factors = [lo_f, mid_f, hi_f]

    new_tracks = []
    for track in tracks:
        mf = track.mean_freq()
        if mf <= 0: continue
        bi = 0 if mf < lo_hi else (1 if mf < mid_hi else 2)
        stretched = track.time_stretch(factors[bi])
        if boosts[bi] > 1.01:
            stretched.amps = [a * boosts[bi] for a in stretched.amps]
        new_tracks.append(stretched)

    print(f"  Tracks: {band_n}  Boosts: [{boosts[0]:.2f}, {boosts[1]:.2f}, {boosts[2]:.2f}]", flush=True)
    names = [f"0-{lo_hi:.0f} Hz", f"{lo_hi:.0f}-{mid_hi:.0f} Hz", f"above {mid_hi:.0f} Hz"]
    STATS["groups"] = " | ".join(f"{names[i]}: {band_n[i]} tracks x{factors[i]:.2f} time, "
                                 f"AUTO gain x{boosts[i] if boosts[i] > 1.01 else 1.0:.2f}" for i in range(3))
    STATS["auto_boost"] = " ".join(f"{(b if b > 1.01 else 1.0):.3f}" for b in boosts)
    for t in tracks:
        mf = t.mean_freq()
        if mf > 0:
            GROUP_OF[t.track_id] = 0 if mf < lo_hi else (1 if mf < mid_hi else 2)
    return new_tracks


def mode_freeze(tracks, total_dur, args, log_path):
    freeze_pos = max(0.0, min(1.0, args.freeze_time))
    freeze_t = freeze_pos * total_dur
    freeze_dur = args.freeze_duration
    print(f"  Mode: freeze  t={freeze_t:.3f}s  dur={freeze_dur:.2f}s", flush=True)

    new_tracks = []
    hop = 0.005
    fade = min(0.03, freeze_dur * 0.05)

    for track in tracks:
        if not track.times: continue
        best_i = min(range(len(track.times)), key=lambda i: abs(track.times[i] - freeze_t))
        ff, fa = track.freqs[best_i], track.amps[best_i]
        if fa < 1e-7 or ff <= 0: continue

        new = PartialTrack(track.track_id)
        t = 0.0
        while t <= freeze_dur:
            env = 1.0
            if t < fade: env = t / fade
            elif t > freeze_dur - fade: env = max(0.0, (freeze_dur - t) / fade)
            new.append(t, ff, fa * env, 0.0)
            t += hop
        new_tracks.append(new)

    print(f"  Frozen: {len(new_tracks)} tracks", flush=True)
    STATS["groups"] = f"{len(new_tracks)} partials frozen at {freeze_t:.3f} s, held {freeze_dur:.2f} s " \
                      f"(fade {fade * 1000:.0f} ms)"
    STATS["freeze_time_s"] = round(freeze_t, 4)
    GROUP_OF.update({t.track_id: 0 for t in tracks})
    return new_tracks


def mode_partial_thin(tracks, total_dur, args, log_path):
    threshold = args.thin_above_hz
    if args.thin_every_n < 2:
        raise PSError(f"Thin every N must be >= 2 (got {args.thin_every_n}); 1 would keep everything")
    keep_every = args.thin_every_n
    print(f"  Mode: partial_thin  above={threshold:.0f} Hz  keep 1/{keep_every}", flush=True)

    sortable = sorted([(t, t.mean_freq()) for t in tracks], key=lambda x: x[1])
    new_tracks = []
    above_idx = 0
    for track, mf in sortable:
        if mf <= 0: continue
        if mf < threshold:
            new_tracks.append(track.copy())
        else:
            above_idx += 1
            if (above_idx % keep_every) == 1:
                new_tracks.append(track.copy())

    print(f"  Kept: {len(new_tracks)} / {len(tracks)}", flush=True)
    kept = {t.track_id for t in new_tracks}
    n_below = sum(1 for t, mf in sortable if 0 < mf < threshold)
    n_above = sum(1 for t, mf in sortable if mf >= threshold)
    STATS["groups"] = f"below {threshold:.0f} Hz: {n_below} kept | above: {len(new_tracks) - n_below} " \
                      f"of {n_above} kept (1/{keep_every})"
    for t, mf in sortable:
        if mf > 0:
            GROUP_OF[t.track_id] = 0 if mf < threshold else (1 if t.track_id in kept else 2)
    return new_tracks


def mode_spectral_blur(tracks, total_dur, args, log_path):
    blur_ms = args.blur_window_ms
    hop_ms = args.hop_ms if args.hop_ms > 0 else 5.0
    blur_frames = max(3, int(blur_ms / hop_ms))
    print(f"  Mode: spectral_blur  window={blur_ms:.0f} ms (~{blur_frames} frames)", flush=True)

    new_tracks = []
    for track in tracks:
        if len(track.amps) < 3:
            new_tracks.append(track.copy())
            continue
        amps_arr = np.array(track.amps, dtype=np.float64)
        ks = min(blur_frames, len(amps_arr))
        if ks < 2:
            new_tracks.append(track.copy())
            continue
        kernel = np.ones(ks) / ks
        smoothed = np.convolve(amps_arr, kernel, mode="same")
        new = PartialTrack(track.track_id)
        for i in range(len(track.times)):
            new.append(track.times[i], track.freqs[i], float(smoothed[i]), track.phases[i])
        new_tracks.append(new)

    print(f"  Blurred: {len(new_tracks)} tracks", flush=True)
    STATS["groups"] = f"{len(new_tracks)} tracks, amplitude envelopes smoothed over {blur_frames} frames " \
                      f"({blur_frames * hop_ms:.0f} ms); frequencies unchanged"
    GROUP_OF.update({t.track_id: 0 for t in tracks})
    return new_tracks


MODES = {
    "spectral_stretch": mode_spectral_stretch,
    "band_stretch":     mode_band_stretch,
    "freeze":           mode_freeze,
    "partial_thin":     mode_partial_thin,
    "spectral_blur":    mode_spectral_blur,
}


# =============================================================================
#  MAIN
# =============================================================================

STATS = {}
VIZ = {}
GROUP_OF = {}
POSITIONAL = ["input_wav", "done_file"]


def params_to_argv(path):
    d = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\r\n")
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    argv = [d.pop(k, "") for k in POSITIONAL]
    for k, v in d.items():
        if v == "":
            continue
        if k == "dry_run":
            if v not in ("0", "no", "false"):
                argv.append("--dry_run")
            continue
        argv += ["--" + k, v]
    return argv


def track_points(tracks, max_points=20000):
    """(tid, time, freq, amp) rows, decimated in time so the figure stays fast."""
    n = sum(len(t.times) for t in tracks)
    stride = max(1, int(math.ceil(n / max_points)))
    rows = []
    for t in tracks:
        for i in range(0, len(t.times), stride):
            rows.append((t.track_id, t.times[i], t.freqs[i], t.amps[i]))
    return rows


def write_viz(prefix, in_tracks, out_tracks):
    def dump(path, rows):
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            for tid, tt, f, a in rows:
                fh.write(f"{tid} {GROUP_OF.get(tid, 0)} {tt:.5f} {f:.2f} {a:.7f}\n")
    dump(prefix + "tracks_in.txt", track_points(in_tracks))
    dump(prefix + "tracks_out.txt", track_points(out_tracks))
    with open(prefix + "gain.txt", "w", encoding="utf-8", newline="\n") as fh:
        for tt, g in VIZ.get("gain", []):
            fh.write(f"{tt:.5f} {g:.6f}\n")


def main():
    class _Parser(argparse.ArgumentParser):
        def error(self, message):
            raise PSError("invalid parameter - " + message)

    ap = _Parser(description=f"Partial Stretch v{VERSION}")
    ap.add_argument("input_wav", type=str)
    ap.add_argument("done_file", type=str)
    ap.add_argument("--pm2_dir", type=str, default=DEFAULT_PM2_DIR)
    ap.add_argument("--result_wav", type=str, default="")
    ap.add_argument("--log_path", type=str, default="")
    ap.add_argument("--tmp_prefix", type=str, default="")
    ap.add_argument("--manifest", type=str, default="")
    ap.add_argument("--mode", type=str, default="spectral_stretch", choices=list(MODES))
    ap.add_argument("--dry_run", action="store_true")
    ap.add_argument("--max_partials", type=int, default=200)
    ap.add_argument("--analysis_window_ms", type=float, default=46.44)
    ap.add_argument("--hop_ms", type=float, default=5.0)
    ap.add_argument("--split_freq_hz", type=float, default=1000.0)
    ap.add_argument("--upper_stretch_factor", type=float, default=3.0)
    ap.add_argument("--band_lo_hz", type=float, default=500.0)
    ap.add_argument("--band_mid_hz", type=float, default=2000.0)
    ap.add_argument("--band_lo_stretch", type=float, default=1.0)
    ap.add_argument("--band_mid_stretch", type=float, default=2.0)
    ap.add_argument("--band_hi_stretch", type=float, default=4.0)
    ap.add_argument("--freeze_time", type=float, default=0.5)
    ap.add_argument("--freeze_duration", type=float, default=5.0)
    ap.add_argument("--thin_above_hz", type=float, default=1000.0)
    ap.add_argument("--thin_every_n", type=int, default=2)
    ap.add_argument("--blur_window_ms", type=float, default=100.0)
    ap.add_argument("--output_gain", type=float, default=1.0)
    ap.add_argument("--level_balance", type=int, default=1)

    argv = sys.argv[1:]
    if len(argv) == 1 and os.path.isfile(argv[0]):
        argv = params_to_argv(argv[0])
    done_guess = argv[1] if len(argv) > 1 else ""
    try:
        args = ap.parse_args(argv)
    except PSError as e:
        if done_guess:
            append_log(os.path.join(os.path.dirname(done_guess), "ps_log.txt"), "ERROR: " + str(e))
            write_done(done_guess, "error")
        print("ERROR: " + str(e), flush=True)
        return

    if not args.result_wav:
        base, _ = os.path.splitext(args.input_wav)
        args.result_wav = f"{base}_ps_{args.mode}.wav"
    tmp_dir = os.path.dirname(args.done_file)
    prefix = args.tmp_prefix or os.path.join(tmp_dir, "ps_")
    log_path = args.log_path or prefix + "log.txt"
    manifest = args.manifest or prefix + "manifest.txt"
    if os.path.isfile(log_path):
        os.remove(log_path)

    print(f"=== Partial Stretch v{VERSION} ===", flush=True)
    print(f"Mode:    {args.mode}", flush=True)
    print(f"Input:   {args.input_wav}", flush=True)

    pm2_exe = resolve_pm2(args.pm2_dir)
    analysis_txt = prefix + "analysis.sdif.txt"
    analysis_sdif = prefix + "analysis.sdif"

    def log(msg):
        print(msg, flush=True)
        append_log(log_path, msg)

    try:
        if not HAS_NUMPY:
            raise PSError("numpy and soundfile are required (pip install numpy soundfile)")
        for name in ("upper_stretch_factor", "band_lo_stretch", "band_mid_stretch", "band_hi_stretch",
                     "freeze_duration", "blur_window_ms", "analysis_window_ms", "hop_ms"):
            if getattr(args, name) <= 0:
                raise PSError(f"{name} must be > 0 (got {getattr(args, name)})")
        if args.band_lo_hz >= args.band_mid_hz:
            raise PSError("Band low edge must be below the band mid edge")
        if not os.path.isfile(pm2_exe):
            raise PSError(f"PM2 binary not found: {pm2_exe}")
        info = sf.info(args.input_wav)
        sr = int(info.samplerate)
        STATS["input_duration"] = round(info.duration, 4)
        STATS["input_sample_rate"] = sr

        log("[1/3] Analysing with PM2...")
        rc = run_pm2_analysis(pm2_exe, args.input_wav, analysis_txt, args, log_path, sr)
        if args.dry_run:
            write_manifest(manifest, args)
            write_done(args.done_file, "ok")
            return
        if rc != 0:
            raise PSError(f"PM2 returned code {rc} (see log)")

        log("[2/3] Processing partials...")
        tracks, total_dur = parse_to_tracks(analysis_txt, args.max_partials, log_path)
        if not tracks:
            raise PSError("PM2 produced no partial tracks")
        active = [t for t in tracks if t.max_amp() > 1e-8]
        if not active:
            raise PSError("all partial tracks are silent")

        processed = MODES[args.mode](active, total_dur, args, log_path)
        if not processed:
            raise PSError("0 tracks after processing")

        log("[3/3] Resynthesizing...")
        audio, out_sr = resynthesize(processed, sr=sr, output_gain=args.output_gain,
                                     level_balance=bool(args.level_balance))
        sf.write(args.result_wav, audio, out_sr)
        log(f"  Written: {args.result_wav}")
        STATS["tracks_processed"] = len(processed)
        write_viz(prefix, active, processed)
        write_manifest(manifest, args)
        write_done(args.done_file, "ok")
        print("OK: done.", flush=True)

    except PSError as e:
        log("ERROR: " + str(e))
        STATS["error"] = str(e)
        write_manifest(manifest, args)
        write_done(args.done_file, "error")
    except Exception:
        msg = traceback.format_exc()
        log("ERROR (internal):\n" + msg)
        write_done(args.done_file, "error")
    finally:
        for p in [analysis_txt, analysis_sdif]:
            if os.path.isfile(p):
                try:
                    os.remove(p)
                except OSError:
                    pass


def write_manifest(path, args):
    try:
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(f"version={VERSION}\nmode={args.mode}\n")
            for k, v in STATS.items():
                fh.write(f"{k}={v}\n")
    except OSError:
        pass


if __name__ == "__main__":
    main()
