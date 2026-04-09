#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - supervp_transform.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SuperVP transform backend.
#   Receives: input WAV(s), F0 BPF, Intensity BPF (all from Praat).
#   Builds SuperVP parameter BPF files, runs supervp.exe, writes result.
#
#   Modes:
#     age            Voice aging / rejuvenation           --age_val <int>
#     gender         Male <-> female morph                --gender_dir male|female  --gender_amount 1-5
#     flatten_pitch  Normalise F0 to median or target Hz  --target_f0 <Hz>  (0 = use median)
#     time_stretch   F0-adaptive time dilation            --stretch_factor <float>  (or BPF file)
#     tremolo        Intensity-driven tremolo              --tremolo_freq <Hz>  --tremolo_depth <cents>
#     cross          Spectral cross-synthesis             --input_wav2 <path>  --cross_mix <0-1>
#     vibrato        Sinusoidal pitch modulation           --vibrato_freq <Hz>  --vibrato_depth <cents>
#     breathiness    Blend spectral noise (breathy/whisper) --breathiness_amount <0-1>
#     formant_shift  Shift vocal tract resonances          --formant_shift_cents <cents>
#     harmoniser     Add parallel voice at fixed interval  --harmoniser_interval <cents>  --harmoniser_mix <0-1>
#     denoise        Spectral gate via intensity-derived BPF --denoise_threshold_db <dB>
#     age_gender     Chain age then gender in two SVP passes (all age+gender params apply)
#
# Infrastructure improvements (v2.0):
#   --dry_run        Print the SuperVP command without executing it
#   --batch          Process a list of input WAVs (newline-separated file)
#   Log content is written to log_path; Praat script reads it back on failure.
#
# Dependencies:
#   pip install numpy soundfile
#   SuperVP.exe at path given by --supervp_exe
#
# Called from SuperVP_Transform.praat via runSystem.
# Writes done_file with "ok" or "error" when finished.
# ============================================================

import argparse
import math
import os
import subprocess
import sys
import tempfile

# ── Optional numpy / soundfile for waveform inspection ───────────────────────
try:
    import numpy as np
    import soundfile as sf
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False


# =============================================================================
#  BPF I/O
# =============================================================================

def read_bpf(path):
    """Return list of (time_sec, value) float pairs. Skip blank / comment lines."""
    pts = []
    if not os.path.isfile(path):
        return pts
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                try:
                    pts.append((float(parts[0]), float(parts[1])))
                except ValueError:
                    pass
    return pts


def write_bpf(path, pts):
    """Write (time_sec, value) pairs as a SuperVP-compatible BPF text file."""
    with open(path, "w", encoding="utf-8") as fh:
        for t, v in pts:
            fh.write(f"{t:.6f} {v:.6f}\n")


# =============================================================================
#  F0 BPF TRANSFORMS
# =============================================================================

def f0_median(f0_pts):
    """Return median of voiced F0 values (Hz)."""
    vals = sorted(v for _, v in f0_pts if v > 0)
    if not vals:
        return None
    return vals[len(vals) // 2]


def f0_range_cents(f0_pts):
    """Return (min_hz, max_hz, range_cents) for voiced frames."""
    vals = [v for _, v in f0_pts if v > 0]
    if len(vals) < 2:
        return None, None, 0.0
    lo, hi = min(vals), max(vals)
    return lo, hi, 1200.0 * math.log2(hi / lo) if lo > 0 else 0.0


def duration_from_bpf(f0_pts):
    """Estimate total duration from the last time point in the BPF."""
    if not f0_pts:
        return 1.0
    return f0_pts[-1][0]


def compute_flatten_bpf(f0_pts, target_hz=None):
    """
    Transposition BPF that moves every voiced frame to target_hz (or median if None).
    Unvoiced gaps are bridged by linear interpolation between flanking points.
    Returns list of (time, cents) for use with supervp -transke.
    """
    target = target_hz if (target_hz and target_hz > 0) else f0_median(f0_pts)
    if target is None or target <= 0:
        return []
    bpf = []
    for t, f0 in f0_pts:
        if f0 > 0:
            cents = 1200.0 * math.log2(target / f0)
            bpf.append((t, cents))
    if len(bpf) < 2:
        return bpf
    filled = [bpf[0]]
    for i in range(1, len(bpf)):
        t0, c0 = filled[-1]
        t1, c1 = bpf[i]
        gap = t1 - t0
        if gap > 0.04:
            mid_t = (t0 + t1) / 2.0
            mid_c = (c0 + c1) / 2.0
            filled.append((mid_t, mid_c))
        filled.append((t1, c1))
    return filled


def compute_exaggerate_bpf(f0_pts, factor=2.0):
    """
    Amplify pitch deviations around the median by <factor>.
    Returns list of (time, cents) for supervp -transke.
    """
    med = f0_median(f0_pts)
    if med is None or med <= 0:
        return []
    bpf = []
    for t, f0 in f0_pts:
        if f0 > 0:
            cents_from_median = 1200.0 * math.log2(f0 / med)
            bpf.append((t, cents_from_median * (factor - 1.0)))
    return bpf


def intensity_to_gain_bpf(int_pts, mode="linear"):
    """
    Convert dB intensity BPF to linear gain BPF for supervp -ggain.
    mode='linear'  : gain = 10^((dB - peak_dB) / 20)  (range 0..1)
    mode='compress' : light dynamic compression
    """
    if not int_pts:
        return []
    db_vals = [v for _, v in int_pts]
    peak_db = max(db_vals)
    floor_db = peak_db - 60.0   # 60 dB dynamic range floor
    bpf = []
    for t, db in int_pts:
        if mode == "compress":
            compressed = peak_db + (db - peak_db) * 0.5
            gain = 10.0 ** ((compressed - peak_db) / 20.0)
        else:
            db_clipped = max(db, floor_db)
            gain = 10.0 ** ((db_clipped - peak_db) / 20.0)
        bpf.append((t, max(0.0, gain)))
    return bpf


def compute_sinusoidal_cents_bpf(duration, freq_hz, depth_cents, step=0.005):
    """
    Build a time-varying transposition BPF with a sinusoidal modulation.
    Used by vibrato: cents(t) = depth * sin(2π * freq * t).
    step: time resolution in seconds (default 5 ms).
    Returns list of (time, cents).
    """
    bpf = []
    t = 0.0
    omega = 2.0 * math.pi * freq_hz
    while t <= duration + step:
        c = depth_cents * math.sin(omega * t)
        bpf.append((min(t, duration), c))
        t += step
    return bpf


def compute_denoise_gate_bpf(int_pts, threshold_db):
    """
    Build a gain BPF that gates spectral content: frames below threshold_db
    (relative to peak) are attenuated smoothly to near zero.
    Returns list of (time, gain) for supervp -ggain.
    """
    if not int_pts:
        return []
    db_vals = [v for _, v in int_pts]
    peak_db = max(db_vals)
    floor_db = peak_db - threshold_db   # absolute dB gate floor
    bpf = []
    for t, db in int_pts:
        if db >= floor_db:
            gain = 1.0
        else:
            # Smooth transition: 6 dB/dB slope below the gate
            gain = max(0.0, 10.0 ** ((db - floor_db) / 6.0))
        bpf.append((t, gain))
    return bpf


# =============================================================================
#  SUPERVP RUNNER
# =============================================================================

def run_supervp(supervp_exe, args_list, log_path=None, verbose=True, dry_run=False):
    """
    Run supervp.exe with the given argument list.
    If dry_run is True, print the command and return (0, "") without executing.
    Returns (returncode, stdout+stderr combined).
    """
    cmd = [supervp_exe] + args_list
    cmd_str = " ".join(f'"{a}"' if " " in a else a for a in cmd)
    if verbose:
        print("CMD: " + cmd_str, flush=True)
    if dry_run:
        print("[DRY RUN] Command NOT executed.", flush=True)
        if log_path:
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write(f"\n--- DRY RUN CMD ---\n{cmd_str}\n")
        return 0, ""
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )
    combined = result.stdout or ""
    if verbose and combined.strip():
        print(combined, flush=True)
    if log_path:
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(f"\n--- CMD ---\n{cmd_str}\n")
            fh.write(combined)
    return result.returncode, combined


# =============================================================================
#  MODE HANDLERS
# =============================================================================

def mode_age(args, tmp_dir, supervp_exe, log_path):
    """supervp -age <years> : voice aging (+) or rejuvenation (-)"""
    print(f"  Mode: age  value={args.age_val}", flush=True)
    svp_args = [
        "-S", args.input_wav1,
        "-A", "-Z",
        "-age", str(args.age_val),
        args.result_wav
    ]
    rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)
    return rc


def mode_gender(args, tmp_dir, supervp_exe, log_path):
    """
    Stronger gender morph.

    Pass 1: IRCAM's built-in -male / -female transform with shape-invariant mode.
    Pass 2: an additional spectral-envelope (formant) shift via -transenv.

    Why two passes?
    The plain gender switch can be fairly subtle on some voices. Perceived
    vocal gender depends strongly on vocal-tract resonances (formants), so a
    moderate envelope shift usually makes the result much more obvious without
    forcing an unnatural pitch jump.

    The envelope shift is chosen heuristically from gender_amount:
        1 -> 120 cents
        2 -> 180 cents
        3 -> 260 cents
        4 -> 340 cents
        5 -> 420 cents
    Female direction shifts formants up; male shifts them down.
    """
    print(f"  Mode: gender  dir={args.gender_dir}  amount={args.gender_amount}",
          flush=True)

    flag = "-female" if args.gender_dir == "female" else "-male"
    amount = max(1, min(5, int(args.gender_amount)))
    auto_formant = {1: 120, 2: 180, 3: 260, 4: 340, 5: 420}[amount]
    if args.gender_dir == "male":
        auto_formant = -auto_formant

    inter_wav = os.path.join(tmp_dir, "svp_gender_inter.wav")

    # Pass 1 — built-in gender transform
    svp_args_1 = [
        "-S", args.input_wav1,
        "-A", "-Z",
        "-shape", "1",
        flag, str(amount),
        inter_wav
    ]
    print(f"  Pass 1 — {flag} {amount} with shape-invariant synthesis", flush=True)
    rc, _ = run_supervp(supervp_exe, svp_args_1, log_path, dry_run=args.dry_run)
    if rc != 0 and not args.dry_run:
        print("  ERROR: gender pass failed", flush=True)
        return rc

    # Pass 2 — extra formant movement for a clearer perceived gender shift
    src = inter_wav if (os.path.isfile(inter_wav) or args.dry_run) else args.input_wav1
    svp_args_2 = [
        "-S", src,
        "-A", "-Z",
        "-transenv", str(auto_formant),
        args.result_wav
    ]
    print(f"  Pass 2 — formant shift {auto_formant:+d} cents", flush=True)
    rc, _ = run_supervp(supervp_exe, svp_args_2, log_path, dry_run=args.dry_run)

    if os.path.isfile(inter_wav) and not args.dry_run:
        try:
            os.remove(inter_wav)
        except OSError:
            pass

    return rc


def mode_flatten_pitch(args, tmp_dir, supervp_exe, log_path):
    """
    Read F0 BPF from Praat, compute per-frame transposition to a target F0.
    Target is args.target_f0 Hz if > 0, otherwise the median of voiced frames.
    Applies with supervp -transke (preserves spectral envelope / timbre).
    Requires -Afft for envelope estimation.
    """
    print("  Mode: flatten_pitch", flush=True)
    f0_pts = read_bpf(args.f0_file)
    if not f0_pts:
        print("  WARNING: no voiced frames found — writing silence-free copy",
              flush=True)
        svp_args = ["-S", args.input_wav1, "-A", "-Z", args.result_wav]
        rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)
        return rc

    target_hz = args.target_f0 if args.target_f0 > 0 else None
    med = f0_median(f0_pts)
    lo, hi, rng = f0_range_cents(f0_pts)
    effective_target = target_hz if target_hz else med
    print(f"  F0: median={med:.1f} Hz  range={rng:.0f} cents  "
          f"target={effective_target:.1f} Hz", flush=True)

    trans_bpf = compute_flatten_bpf(f0_pts, target_hz=target_hz)
    trans_path = os.path.join(tmp_dir, "svp_trans.bpf")
    write_bpf(trans_path, trans_bpf)
    print(f"  Transposition BPF: {len(trans_bpf)} points → {trans_path}", flush=True)

    svp_args = [
        "-S", args.input_wav1,
        "-F0", args.f0_file,
        "-Mauto",
        "-A", "-Afft",
        "-Z", "-P1",
        "-transke", trans_path,
        args.result_wav
    ]
    rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)
    return rc


def mode_time_stretch(args, tmp_dir, supervp_exe, log_path):
    """
    F0-adaptive time stretch: uses -Mauto (F0-driven window) + -D factor (or BPF).
    If --stretch_bpf_file is given, it is passed directly to SuperVP's -D argument
    as a breakpoint function, enabling region-specific time scaling.
    Phase synchronisation and transient preservation enabled (-P1).
    """
    print(f"  Mode: time_stretch  factor={args.stretch_factor:.3f}", flush=True)
    f0_pts = read_bpf(args.f0_file)

    svp_args = ["-S", args.input_wav1]

    if f0_pts:
        svp_args += ["-F0", args.f0_file, "-Mauto"]
        print(f"  Using F0-adaptive window ({len(f0_pts)} voiced frames)", flush=True)
    else:
        print("  No F0 data — using fixed window", flush=True)

    svp_args += ["-A", "-Z", "-P1"]

    # Support BPF-based stretch (region-specific time scaling)
    if args.stretch_bpf_file and os.path.isfile(args.stretch_bpf_file):
        print(f"  BPF stretch file: {args.stretch_bpf_file}", flush=True)
        svp_args += ["-D", args.stretch_bpf_file]
    else:
        svp_args += [f"-D{args.stretch_factor:.6f}"]

    svp_args.append(args.result_wav)
    rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)
    return rc


def mode_tremolo(args, tmp_dir, supervp_exe, log_path):
    """
    Amplitude tremolo: -trmdle modulates the spectral envelope (not pitch).
    Modulation rate and depth come from --tremolo_freq / --tremolo_depth.
    Intensity BPF gates the effect to avoid pumping artifacts in quiet regions.
    """
    print(f"  Mode: tremolo  freq={args.tremolo_freq:.2f} Hz  "
          f"depth={args.tremolo_depth:.0f} cents", flush=True)

    int_pts = read_bpf(args.intensity_file)

    if int_pts:
        db_vals = [v for _, v in int_pts]
        db_med  = sorted(db_vals)[len(db_vals) // 2]
        rel_vals = [max(0.0, min(1.0, (db - (db_med - 20)) / 20.0))
                    for _, db in int_pts]
        mean_rel = sum(rel_vals) / len(rel_vals)
        effective_depth = args.tremolo_depth * mean_rel
        print(f"  Intensity-scaled depth: {effective_depth:.1f} cents "
              f"(mean rel={mean_rel:.2f})", flush=True)
    else:
        effective_depth = args.tremolo_depth
        print("  Constant tremolo depth (no intensity data)", flush=True)

    trem_arg = f"{args.tremolo_freq:.2f},{effective_depth:.2f}"

    svp_args = [
        "-S", args.input_wav1,
        "-A", "-Afft",
        "-Z",
        "-trmdle", trem_arg,
        args.result_wav
    ]
    rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)
    return rc


def mode_cross(args, tmp_dir, supervp_exe, log_path):
    """
    Spectral cross-synthesis: -Gcross blends amplitude of sound1 with
    frequency (pitch) of sound2 (or vice versa) according to --cross_mix.
    """
    if not args.input_wav2 or not os.path.isfile(args.input_wav2):
        print("  ERROR: cross mode requires --input_wav2", flush=True)
        return 1

    mix = max(0.0, min(1.0, args.cross_mix))
    print(f"  Mode: cross  mix={mix:.3f}  "
          f"(amp: {1-mix:.2f}×snd1 + {mix:.2f}×snd2 | "
          f"freq: {1-mix:.2f}×snd1 + {mix:.2f}×snd2)", flush=True)

    svp_args = [
        "-S", args.input_wav1,
        "-s", args.input_wav2,
        "-A", "-a", "-Z",
        "-Gcross",
        f"-X{1.0 - mix:.4f}",
        f"-x{mix:.4f}",
        f"-Y{1.0 - mix:.4f}",
        f"-y{mix:.4f}",
        args.result_wav
    ]
    rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)
    return rc


# ─── NEW MODE: VIBRATO ────────────────────────────────────────────────────────

def mode_vibrato(args, tmp_dir, supervp_exe, log_path):
    """
    Pitch vibrato: sinusoidal pitch modulation via a time-varying transposition BPF
    fed to supervp -transke.  Analogous to tremolo but on pitch instead of amplitude.

    Uses -Afft and -F0/-Mauto when F0 data is available so that the spectral
    envelope is preserved during the transposition.

    Parameters:
        --vibrato_freq   modulation rate in Hz (default 5.5 Hz)
        --vibrato_depth  peak deviation in cents (default 50 cents, ≈ a semitone)
    """
    print(f"  Mode: vibrato  freq={args.vibrato_freq:.2f} Hz  "
          f"depth={args.vibrato_depth:.0f} cents", flush=True)

    f0_pts = read_bpf(args.f0_file)
    duration = duration_from_bpf(f0_pts) if f0_pts else None

    # Fall back to intensity BPF for duration if no F0
    if duration is None:
        int_pts = read_bpf(args.intensity_file)
        duration = duration_from_bpf(int_pts) if int_pts else 5.0

    vib_bpf = compute_sinusoidal_cents_bpf(
        duration, args.vibrato_freq, args.vibrato_depth
    )
    vib_path = os.path.join(tmp_dir, "svp_vibrato.bpf")
    write_bpf(vib_path, vib_bpf)
    print(f"  Vibrato BPF: {len(vib_bpf)} points  dur={duration:.3f} s → {vib_path}",
          flush=True)

    svp_args = ["-S", args.input_wav1]
    if f0_pts:
        svp_args += ["-F0", args.f0_file, "-Mauto"]
    svp_args += [
        "-A", "-Afft",
        "-Z", "-P1",
        "-transke", vib_path,
        args.result_wav
    ]
    rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)
    return rc


# ─── NEW MODE: BREATHINESS ────────────────────────────────────────────────────

def mode_breathiness(args, tmp_dir, supervp_exe, log_path):
    """
    Breathiness / whispery voice: blend spectral noise into the signal using
    supervp -Gnoise (or -ggain on a noise source when -Gnoise is unavailable).

    Strategy:
        1. Build a flat gain BPF scaled by args.breathiness_amount (0–1).
        2. Pass it to -ggain so that the noise source is mixed at that level.
           SuperVP's -Gnoise adds a noise component directly; -ggain scales it.

    If -Gnoise is not available in your SuperVP build, the command falls back to
    using only the gain BPF on the main signal (reduces voiced quality instead).

    Parameters:
        --breathiness_amount  0 = no noise, 1 = full noise (default 0.4)
    """
    amount = max(0.0, min(1.0, args.breathiness_amount))
    print(f"  Mode: breathiness  amount={amount:.2f}", flush=True)

    int_pts = read_bpf(args.intensity_file)
    duration = duration_from_bpf(int_pts) if int_pts else 5.0

    # Build a flat gain BPF at the chosen noise level
    step = 0.01
    t = 0.0
    noise_gain_bpf = []
    while t <= duration + step:
        noise_gain_bpf.append((min(t, duration), amount))
        t += step
    noise_path = os.path.join(tmp_dir, "svp_noise_gain.bpf")
    write_bpf(noise_path, noise_gain_bpf)
    print(f"  Noise gain BPF: {len(noise_gain_bpf)} points → {noise_path}", flush=True)

    # Primary command: use -Gnoise if the build supports it
    svp_args = [
        "-S", args.input_wav1,
        "-A", "-Afft",
        "-Z",
        "-Gnoise",
        "-ggain", noise_path,
        args.result_wav
    ]
    rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)

    if rc != 0 and not args.dry_run:
        # Fallback: scale voiced signal gain without explicit noise source
        print("  WARNING: -Gnoise failed, falling back to gain reduction", flush=True)
        # Reduce voiced gain inversely to simulate breathiness
        fallback_bpf = [(t, max(0.05, 1.0 - amount * 0.8)) for t, _ in noise_gain_bpf]
        fallback_path = os.path.join(tmp_dir, "svp_breath_fb.bpf")
        write_bpf(fallback_path, fallback_bpf)
        svp_args_fb = [
            "-S", args.input_wav1,
            "-A", "-Afft",
            "-Z",
            "-ggain", fallback_path,
            args.result_wav
        ]
        rc, _ = run_supervp(supervp_exe, svp_args_fb, log_path, dry_run=args.dry_run)

    return rc


# ─── MODE: FORMANT SHIFT ──────────────────────────────────────────────

def mode_formant_shift(args, tmp_dir, supervp_exe, log_path):
    """
    Formant shift: moves vocal-tract resonances independently of pitch.
    Stripped down to minimal flags to prevent SuperVP bypass errors.
    """
    cents = int(args.formant_shift_cents)
    print(f"  Mode: formant_shift  {cents:+.0f} cents", flush=True)

    if args.dry_run:
        return 0

    # Minimal, proven syntax from the naked test
    svp_args = [
        "-S", args.input_wav1,
        "-A", 
        "-Z", 
        "-transenv", str(cents),
        args.result_wav
    ]
    
    rc, _ = run_supervp(supervp_exe, svp_args, log_path=log_path, verbose=False, dry_run=args.dry_run)
    return rc


# ─── NEW MODE: HARMONISER ─────────────────────────────────────────────────────

def mode_harmoniser(args, tmp_dir, supervp_exe, log_path):
    """
    Harmoniser: add a parallel voice at a fixed interval (in cents) above or
    below the original.

    Strategy:
        Pass 1 — transpose by --harmoniser_interval cents → harmony_tmp.wav
        Pass 2 — mix harmony_tmp.wav with the original using Praat's Mix command
                  via a second SuperVP cross-synthesis at the desired blend level.

    Because Praat handles mixing natively, we write a small helper WAV mix in
    Python (using soundfile + numpy) when available; otherwise we do a naive
    SuperVP cross-synthesis at 50/50 and instruct the caller to mix in Praat.

    Parameters:
        --harmoniser_interval  interval in cents (e.g. 700 = perfect fifth)
        --harmoniser_mix       0 = original only, 1 = harmony only (default 0.3)
    """
    interval = args.harmoniser_interval
    mix      = max(0.0, min(1.0, args.harmoniser_mix))
    print(f"  Mode: harmoniser  interval={interval:+.0f} cents  mix={mix:.2f}",
          flush=True)

    f0_pts = read_bpf(args.f0_file)

    # ── Pass 1: build flat transposition BPF at constant interval ────────────
    duration = duration_from_bpf(f0_pts) if f0_pts else 5.0
    step = 0.01
    t = 0.0
    harm_bpf = []
    while t <= duration + step:
        harm_bpf.append((min(t, duration), float(interval)))
        t += step
    harm_path = os.path.join(tmp_dir, "svp_harm.bpf")
    write_bpf(harm_path, harm_bpf)

    harmony_wav = os.path.join(tmp_dir, "svp_harmony_tmp.wav")

    svp_args_1 = ["-S", args.input_wav1]
    if f0_pts:
        svp_args_1 += ["-F0", args.f0_file, "-Mauto"]
    svp_args_1 += [
        "-A", "-Afft",
        "-Z", "-P1",
        "-transke", harm_path,
        harmony_wav
    ]
    print(f"  Pass 1 — transposing by {interval:+.0f} cents → {harmony_wav}", flush=True)
    rc, _ = run_supervp(supervp_exe, svp_args_1, log_path, dry_run=args.dry_run)
    if rc != 0 and not args.dry_run:
        print("  ERROR: harmoniser pass 1 failed", flush=True)
        return rc

    # ── Pass 2: mix original + harmony ──────────────────────────────────────
    if HAS_NUMPY and not args.dry_run and os.path.isfile(harmony_wav):
        orig, sr_o  = sf.read(args.input_wav1)
        harm, sr_h  = sf.read(harmony_wav)
        if sr_o != sr_h:
            print(f"  WARNING: SR mismatch ({sr_o} vs {sr_h}); truncating to shorter",
                  flush=True)
        n = min(len(orig), len(harm))
        mixed = (1.0 - mix) * orig[:n] + mix * harm[:n]
        sf.write(args.result_wav, mixed, sr_o)
        print(f"  Pass 2 — numpy mix written → {args.result_wav}", flush=True)
        rc = 0
    else:
        # Fallback: use SuperVP cross-synthesis to blend
        print(f"  Pass 2 — SuperVP cross-synthesis mix (numpy unavailable or dry-run)",
              flush=True)
        svp_args_2 = [
            "-S", args.input_wav1,
            "-s", harmony_wav,
            "-A", "-a", "-Z",
            "-Gcross",
            f"-X{1.0 - mix:.4f}",
            f"-x{mix:.4f}",
            f"-Y{1.0 - mix:.4f}",
            f"-y{mix:.4f}",
            args.result_wav
        ]
        rc, _ = run_supervp(supervp_exe, svp_args_2, log_path, dry_run=args.dry_run)

    # Cleanup harmony tmp
    if os.path.isfile(harmony_wav) and not args.dry_run:
        try:
            os.remove(harmony_wav)
        except OSError:
            pass

    return rc


# ─── NEW MODE: DENOISE / SPECTRAL GATE ───────────────────────────────────────

def mode_denoise(args, tmp_dir, supervp_exe, log_path):
    """
    Spectral gate / de-noise: suppress low-energy spectral bins below an
    intensity-derived threshold using supervp -ggain with a gate BPF.

    Frames whose intensity falls more than --denoise_threshold_db dB below the
    peak are progressively attenuated (6 dB per dB below the gate).

    Parameters:
        --denoise_threshold_db  gate depth in dB below peak (default 30 dB)
    """
    threshold = args.denoise_threshold_db
    print(f"  Mode: denoise  threshold={threshold:.0f} dB below peak", flush=True)

    int_pts = read_bpf(args.intensity_file)
    if not int_pts:
        print("  WARNING: no intensity data — passing through unchanged", flush=True)
        svp_args = ["-S", args.input_wav1, "-A", "-Z", args.result_wav]
        rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)
        return rc

    gate_bpf = compute_denoise_gate_bpf(int_pts, threshold)
    gate_path = os.path.join(tmp_dir, "svp_gate.bpf")
    write_bpf(gate_path, gate_bpf)

    db_vals = [v for _, v in int_pts]
    peak_db  = max(db_vals)
    gate_abs = peak_db - threshold
    n_gated  = sum(1 for _, g in gate_bpf if g < 0.99)
    print(f"  Gate: peak={peak_db:.1f} dB  gate floor={gate_abs:.1f} dB  "
          f"frames suppressed: {n_gated}/{len(gate_bpf)}", flush=True)

    svp_args = [
        "-S", args.input_wav1,
        "-A", "-Afft",
        "-Z",
        "-ggain", gate_path,
        args.result_wav
    ]
    rc, _ = run_supervp(supervp_exe, svp_args, log_path, dry_run=args.dry_run)
    return rc


# ─── IMPROVED MODE: AGE + GENDER CHAIN ────────────────────────────────────────

def mode_age_gender(args, tmp_dir, supervp_exe, log_path):
    """
    Chain age transform then gender transform in two SuperVP passes.
    Pass 1: age → intermediate WAV
    Pass 2: gender on intermediate → final result WAV
    All age and gender parameters are re-used from the standard flags.
    """
    print(f"  Mode: age_gender  age={args.age_val}  "
          f"dir={args.gender_dir}  amount={args.gender_amount}", flush=True)

    inter_wav = os.path.join(tmp_dir, "svp_age_inter.wav")

    # Pass 1 — age
    svp_args_1 = [
        "-S", args.input_wav1,
        "-A", "-Z",
        "-age", str(args.age_val),
        inter_wav
    ]
    print("  Pass 1 — age transform", flush=True)
    rc, _ = run_supervp(supervp_exe, svp_args_1, log_path, dry_run=args.dry_run)
    if rc != 0 and not args.dry_run:
        print("  ERROR: age pass failed", flush=True)
        return rc

    # Pass 2 — gender (on intermediate)
    flag = "-female" if args.gender_dir == "female" else "-male"
    src  = inter_wav if (os.path.isfile(inter_wav) or args.dry_run) else args.input_wav1
    svp_args_2 = [
        "-S", src,
        "-A", "-Z",
        flag, str(args.gender_amount),
        args.result_wav
    ]
    print("  Pass 2 — gender transform", flush=True)
    rc, _ = run_supervp(supervp_exe, svp_args_2, log_path, dry_run=args.dry_run)

    if os.path.isfile(inter_wav) and not args.dry_run:
        try:
            os.remove(inter_wav)
        except OSError:
            pass

    return rc


# =============================================================================
#  BATCH PROCESSING
# =============================================================================

def run_batch(args, supervp_exe, log_path):
    """
    Process a list of WAV files found in args.batch_file (one path per line).
    For each file, sets args.input_wav1 and args.result_wav, then calls the
    appropriate mode handler.  Results are written as
      <original_basename>_svp_<mode>_<N>.wav
    in the same directory as the original file.

    F0 and intensity BPFs are extracted by the Praat side before this call; in
    batch mode those BPFs correspond to the first file only.  For full batch
    analysis, call the Praat script once per Sound.
    """
    if not args.batch_file or not os.path.isfile(args.batch_file):
        print("ERROR: --batch requires a readable --batch_file", flush=True)
        return 1

    with open(args.batch_file, "r", encoding="utf-8") as fh:
        paths = [ln.strip() for ln in fh if ln.strip() and not ln.startswith("#")]

    print(f"  Batch mode: {len(paths)} files", flush=True)
    tmp_dir = os.path.dirname(args.done_file)
    handler = MODES[args.mode]
    any_error = False

    for idx, wav_path in enumerate(paths, start=1):
        if not os.path.isfile(wav_path):
            print(f"  [{idx}/{len(paths)}] SKIP (not found): {wav_path}", flush=True)
            any_error = True
            continue

        base, _ = os.path.splitext(wav_path)
        args.input_wav1 = wav_path
        args.result_wav  = f"{base}_svp_{args.mode}_{idx:03d}.wav"
        print(f"  [{idx}/{len(paths)}] {wav_path} → {args.result_wav}", flush=True)

        rc = handler(args, tmp_dir, supervp_exe, log_path)
        if rc != 0:
            print(f"  [{idx}/{len(paths)}] ERROR (rc={rc})", flush=True)
            any_error = True
        else:
            print(f"  [{idx}/{len(paths)}] OK", flush=True)

    return 1 if any_error else 0


# =============================================================================
#  MODE REGISTRY
# =============================================================================

MODES = {
    "age":            mode_age,
    "gender":         mode_gender,
    "flatten_pitch":  mode_flatten_pitch,
    "time_stretch":   mode_time_stretch,
    "tremolo":        mode_tremolo,
    "cross":          mode_cross,
    # ── new modes ────────────────────────
    "vibrato":        mode_vibrato,
    "breathiness":    mode_breathiness,
    "formant_shift":  mode_formant_shift,
    "harmoniser":     mode_harmoniser,
    "denoise":        mode_denoise,
    "age_gender":     mode_age_gender,
}


# =============================================================================
#  MAIN
# =============================================================================

def main():
    ap = argparse.ArgumentParser(description="SuperVP Transform backend v2.0")

    # ── Positional (match Praat call order) ──────────────────────────────────
    ap.add_argument("input_wav1",      type=str, help="Primary input WAV")
    ap.add_argument("f0_file",         type=str, help="F0 BPF from Praat (time Hz)")
    ap.add_argument("intensity_file",  type=str, help="Intensity BPF from Praat (time dB)")
    ap.add_argument("done_file",       type=str, help="Written when finished (ok / error)")

    # ── Named — infrastructure ────────────────────────────────────────────────
    ap.add_argument("--supervp_exe",    type=str,
                    default=r"C:\Users\User\SuperVP\bin\supervp.exe")
    ap.add_argument("--result_wav",     type=str, default="")
    ap.add_argument("--mode",           type=str, default="age",
                    choices=list(MODES))
    ap.add_argument("--dry_run",        action="store_true",
                    help="Print SuperVP command(s) without executing them")
    ap.add_argument("--batch",          action="store_true",
                    help="Process all WAV paths listed in --batch_file")
    ap.add_argument("--batch_file",     type=str, default="",
                    help="Newline-separated list of WAV paths for --batch mode")

    # ── Named — existing mode parameters ─────────────────────────────────────
    ap.add_argument("--age_val",        type=int,   default=20)
    ap.add_argument("--gender_dir",     type=str,   default="female",
                    choices=["female", "male"])
    ap.add_argument("--gender_amount",  type=int,   default=3)
    ap.add_argument("--target_f0",      type=float, default=0.0,
                    help="flatten_pitch: target F0 in Hz (0 = use median)")
    ap.add_argument("--stretch_factor", type=float, default=1.5)
    ap.add_argument("--stretch_bpf_file", type=str, default="",
                    help="time_stretch: path to BPF file for region-specific stretch")
    ap.add_argument("--tremolo_freq",   type=float, default=5.0)
    ap.add_argument("--tremolo_depth",  type=float, default=30.0)
    ap.add_argument("--cross_mix",      type=float, default=0.5)
    ap.add_argument("--input_wav2",     type=str,   default="")

    # ── Named — new mode parameters ───────────────────────────────────────────
    ap.add_argument("--vibrato_freq",   type=float, default=5.5,
                    help="vibrato: modulation rate in Hz")
    ap.add_argument("--vibrato_depth",  type=float, default=50.0,
                    help="vibrato: peak deviation in cents")
    ap.add_argument("--breathiness_amount", type=float, default=0.4,
                    help="breathiness: noise blend 0 (clean) – 1 (full noise)")
    ap.add_argument("--formant_shift_cents", type=float, default=200.0,
                    help="formant_shift: shift in cents (+ = up, - = down)")
    ap.add_argument("--harmoniser_interval", type=float, default=700.0,
                    help="harmoniser: parallel voice interval in cents (700 = P5)")
    ap.add_argument("--harmoniser_mix",  type=float, default=0.3,
                    help="harmoniser: harmony level 0 (original only) – 1 (harmony only)")
    ap.add_argument("--denoise_threshold_db", type=float, default=30.0,
                    help="denoise: gate depth in dB below peak (default 30)")

    args = ap.parse_args()

    # ── Resolve result path ───────────────────────────────────────────────────
    if not args.result_wav:
        base, _ = os.path.splitext(args.input_wav1)
        args.result_wav = f"{base}_svp_{args.mode}.wav"

    # ── Log file lives next to the done file ──────────────────────────────────
    log_path = args.done_file.replace("svp_done.txt", "svp_log.txt")

    print("=== SuperVP Transform v2.0 ===", flush=True)
    print(f"Mode:       {args.mode}", flush=True)
    print(f"Input:      {args.input_wav1}", flush=True)
    print(f"Result:     {args.result_wav}", flush=True)
    print(f"SuperVP:    {args.supervp_exe}", flush=True)
    if args.dry_run:
        print("*** DRY RUN — no SuperVP calls will be executed ***", flush=True)
    if args.batch:
        print(f"Batch file: {args.batch_file}", flush=True)

    # ── Validate SuperVP executable (skip in dry_run) ────────────────────────
    if not args.dry_run and not os.path.isfile(args.supervp_exe):
        msg = f"SuperVP not found: {args.supervp_exe}"
        print(f"ERROR: {msg}", flush=True)
        with open(log_path,       "w", encoding="utf-8") as fh: fh.write(msg + "\n")
        with open(args.done_file, "w", encoding="utf-8") as fh: fh.write("error\n")
        sys.exit(0)

    # ── Validate primary input ────────────────────────────────────────────────
    if not args.dry_run and not os.path.isfile(args.input_wav1):
        msg = f"Input WAV not found: {args.input_wav1}"
        print(f"ERROR: {msg}", flush=True)
        with open(log_path,       "w", encoding="utf-8") as fh: fh.write(msg + "\n")
        with open(args.done_file, "w", encoding="utf-8") as fh: fh.write("error\n")
        sys.exit(0)

    tmp_dir = os.path.dirname(args.done_file)

    try:
        if args.batch:
            rc = run_batch(args, args.supervp_exe, log_path)
        else:
            handler = MODES[args.mode]
            rc = handler(args, tmp_dir, args.supervp_exe, log_path)
    except Exception as exc:
        import traceback
        msg = traceback.format_exc()
        print(f"ERROR: {msg}", flush=True)
        with open(log_path,       "w", encoding="utf-8") as fh: fh.write(msg)
        with open(args.done_file, "w", encoding="utf-8") as fh: fh.write("error\n")
        sys.exit(0)

    # ── In dry_run, skip result-file check ───────────────────────────────────
    if not args.dry_run and not args.batch:
        if rc != 0 or not os.path.isfile(args.result_wav):
            msg = (f"SuperVP returned code {rc}. "
                   f"Result {'found' if os.path.isfile(args.result_wav) else 'MISSING'}.")
            print(f"ERROR: {msg}", flush=True)
            # Surface log content so Praat can display it in the info window
            if os.path.isfile(log_path):
                with open(log_path, "r", encoding="utf-8") as fh:
                    print("=== LOG ===\n" + fh.read(), flush=True)
            with open(log_path,       "a", encoding="utf-8") as fh: fh.write(msg + "\n")
            with open(args.done_file, "w", encoding="utf-8") as fh: fh.write("error\n")
            sys.exit(0)

    # ── Cleanup tmp BPF / WAV files ──────────────────────────────────────────
    cleanup_paths = [
        args.f0_file,
        args.intensity_file,
        args.input_wav2 if args.input_wav2 else None,
        os.path.join(tmp_dir, "svp_trans.bpf"),
        os.path.join(tmp_dir, "svp_vibrato.bpf"),
        os.path.join(tmp_dir, "svp_noise_gain.bpf"),
        os.path.join(tmp_dir, "svp_breath_fb.bpf"),
        os.path.join(tmp_dir, "svp_gate.bpf"),
        os.path.join(tmp_dir, "svp_harm.bpf"),
    ]
    # Keep input_wav1 only if it is a batch source (managed by run_batch)
    if not args.batch:
        cleanup_paths.insert(0, args.input_wav1)

    for p in cleanup_paths:
        if p and os.path.isfile(p):
            try:
                os.remove(p)
            except OSError as e:
                print(f"  Warning: could not delete {p}: {e}", flush=True)

    print("OK: SuperVP transform done", flush=True)
    with open(args.done_file, "w", encoding="utf-8") as fh:
        fh.write("ok\n")


if __name__ == "__main__":
    main()