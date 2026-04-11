#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - partial_stretch.py
# Author: Shai Cohen
# Version: 1.3 (2026) - Fixed track selection, dual sub-frames
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

VERSION = "1.3"
DEFAULT_PM2_DIR = r"C:\Users\User\Pm2\bin"
DEFAULT_SR = 44100


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

def run_pm2_analysis(pm2_exe, input_wav, output_txt, args, log_path):
    sr = DEFAULT_SR
    raw_win = max(16, round(args.analysis_window_ms * sr / 1000.0))
    win_samples = next_power_of_two(raw_win)
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

def resynthesize(tracks, sr=DEFAULT_SR, output_gain=1.0):
    if not HAS_NUMPY or not tracks:
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

    # Block normalization
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

    audio *= gain_env

    peak = np.max(np.abs(audio))
    if peak > 1e-10:
        audio = audio / peak * 0.9
    audio *= min(output_gain, 2.0)
    np.clip(audio, -1.0, 1.0, out=audio)

    final_peak = float(np.max(np.abs(audio)))
    final_rms = float(np.sqrt(np.mean(audio ** 2)))
    n_silent = int(np.sum(np.abs(audio) < 1e-6))
    print(f"  Resynth: {n_samples/sr:.2f}s  peak={final_peak:.4f}  rms={final_rms:.6f}  "
          f"silent={100*n_silent/max(1,n_samples):.1f}%", flush=True)

    return audio.astype(np.float32), sr


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
    return new_tracks


def mode_partial_thin(tracks, total_dur, args, log_path):
    threshold = args.thin_above_hz
    keep_every = max(2, args.thin_every_n)
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

def main():
    ap = argparse.ArgumentParser(description=f"Partial Stretch v{VERSION}")
    ap.add_argument("input_wav", type=str)
    ap.add_argument("done_file", type=str)
    ap.add_argument("--pm2_dir", type=str, default=DEFAULT_PM2_DIR)
    ap.add_argument("--result_wav", type=str, default="")
    ap.add_argument("--log_path", type=str, default="")
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
    args = ap.parse_args()

    if not args.result_wav:
        base, _ = os.path.splitext(args.input_wav)
        args.result_wav = f"{base}_ps_{args.mode}.wav"

    log_path = args.log_path or os.path.join(os.path.dirname(args.done_file), "ps_log.txt")
    if os.path.isfile(log_path):
        os.remove(log_path)

    print(f"=== Partial Stretch v{VERSION} ===", flush=True)
    print(f"Mode:    {args.mode}", flush=True)
    print(f"Input:   {args.input_wav}", flush=True)

    pm2_exe = resolve_pm2(args.pm2_dir)
    tmp_dir = os.path.dirname(args.done_file)

    try:
        print("[1/3] Analysing with PM2...", flush=True)
        analysis_txt = os.path.join(tmp_dir, "ps_analysis.sdif.txt")
        analysis_sdif = os.path.join(tmp_dir, "ps_analysis.sdif")

        rc = run_pm2_analysis(pm2_exe, args.input_wav, analysis_txt, args, log_path)
        if rc != 0 and not args.dry_run:
            write_done(args.done_file, "error")
            return
        if args.dry_run:
            write_done(args.done_file, "ok")
            return

        print("[2/3] Processing partials...", flush=True)
        tracks, total_dur = parse_to_tracks(analysis_txt, args.max_partials, log_path)
        if not tracks:
            write_done(args.done_file, "error")
            return

        active = [t for t in tracks if t.max_amp() > 1e-8]
        if not active:
            print("  ERROR: All tracks silent.", flush=True)
            write_done(args.done_file, "error")
            return

        processed = MODES[args.mode](active, total_dur, args, log_path)
        if not processed:
            print("  ERROR: 0 tracks after processing.", flush=True)
            write_done(args.done_file, "error")
            return

        print("[3/3] Resynthesizing...", flush=True)
        audio, out_sr = resynthesize(processed, output_gain=args.output_gain)
        sf.write(args.result_wav, audio, out_sr)
        print(f"  Written: {args.result_wav}", flush=True)

        for p in [analysis_txt, analysis_sdif]:
            if os.path.isfile(p):
                try: os.remove(p)
                except OSError: pass

        write_done(args.done_file, "ok")
        print("OK: done.", flush=True)

    except Exception:
        msg = traceback.format_exc()
        print(f"ERROR: {msg}", flush=True)
        append_log(log_path, msg)
        write_done(args.done_file, "error")


if __name__ == "__main__":
    main()
