"""
spectral_freeze.py  –  Spectral freeze via phase vocoder OLA

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

v3.0 — Multi-Freeze mode: captures spectra at multiple moments and
       crossfades between them, creating an evolving frozen texture.

Modes:
    single  — Original: freeze one moment (v2 behaviour)
    multi   — NEW: freeze N moments, crossfade between them in sequence

Usage (single):
    python spectral_freeze.py input.wav output.wav freeze_time_s duration_s
           window_ms shimmer fade_in_s fade_out_s single

Usage (multi):
    python spectral_freeze.py input.wav output.wav freeze_times duration_s
           window_ms shimmer fade_in_s fade_out_s multi xfade_s dwell_s loop

    freeze_times:  comma-separated times in seconds (e.g. "0.3,1.2,2.5")
    xfade_s:       crossfade duration between waypoints (seconds)
    dwell_s:       hold time at each waypoint before crossfading (seconds)
    loop:          0 = one pass through waypoints, 1 = loop back to start
"""

import sys
import os
import math


def check_dependencies():
    """Verify required packages are installed with clear error messages."""
    missing = []
    try:
        import numpy  # noqa: F401
    except ImportError:
        missing.append("numpy")
    try:
        import soundfile  # noqa: F401
    except ImportError:
        missing.append("soundfile")

    if missing:
        print("ERROR: Missing required Python packages:", ", ".join(missing),
              file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing),
              file=sys.stderr)
        sys.exit(1)


def hann(n):
    """Classic Hann (raised cosine) window."""
    import numpy as np
    return (0.5 - 0.5 * np.cos(
        2.0 * np.pi * np.arange(n) / (n - 1)
    )).astype(np.float32)


def next_pow2(n):
    """Round up to nearest power of 2."""
    return 1 << int(math.ceil(math.log2(max(n, 1))))


# ─────────────────────────────────────────────────────────────────────────────
# Single freeze (v2 behaviour, unchanged)
# ─────────────────────────────────────────────────────────────────────────────

def spectral_freeze_single(audio, sr, freeze_time_s, duration_s,
                           window_ms, shimmer, fade_in_s, fade_out_s):
    """
    Freeze the spectrum at a single moment and sustain it.
    """
    import numpy as np

    if audio.ndim > 1:
        audio = audio[:, 0]
    audio = audio.astype(np.float32)

    wsize = next_pow2(int(window_ms / 1000 * sr))
    wsize = max(wsize, 64)
    hop = wsize // 4
    win = hann(wsize)
    win_sq = win ** 2

    freeze_sample = int(np.clip(freeze_time_s * sr, 0, len(audio) - wsize))

    frame = audio[freeze_sample:freeze_sample + wsize] * win
    spectrum = np.fft.rfft(frame)
    mag_freeze = np.abs(spectrum).astype(np.float32)

    print(f"  Freeze point: {freeze_time_s:.3f}s (sample {freeze_sample})")
    print(f"  Window: {wsize} samples ({window_ms:.0f}ms)  hop: {hop}")
    print(f"  Output duration: {duration_s:.2f}s  shimmer: {shimmer:.2f}")

    target_samples = int(duration_s * sr)
    out_len = target_samples + 2 * wsize
    y = np.zeros(out_len, dtype=np.float32)
    norm = np.zeros(out_len, dtype=np.float32)

    rng = np.random.default_rng()

    out_pos = 0
    while out_pos < target_samples + wsize:
        if shimmer > 0:
            jitter = 1.0 + shimmer * (
                rng.random(len(mag_freeze)).astype(np.float32) * 2 - 1)
            mag = mag_freeze * np.abs(jitter)
        else:
            mag = mag_freeze.copy()

        phase = rng.random(len(mag)) * 2.0 * np.pi
        S_out = mag * np.exp(1j * phase)

        frame_out = np.fft.irfft(S_out, n=wsize).real.astype(np.float32)
        frame_out *= win

        end = out_pos + wsize
        if end > len(y):
            y = np.pad(y, (0, end - len(y)))
            norm = np.pad(norm, (0, end - len(norm)))

        y[out_pos:end] += frame_out
        norm[out_pos:end] += win_sq
        out_pos += hop

    norm = np.maximum(norm, 1e-8)
    y /= norm
    y = y[wsize:wsize + target_samples]

    if fade_in_s > 0:
        n_fi = min(int(fade_in_s * sr), len(y))
        y[:n_fi] *= np.linspace(0, 1, n_fi).astype(np.float32)
    if fade_out_s > 0:
        n_fo = min(int(fade_out_s * sr), len(y))
        y[-n_fo:] *= np.linspace(1, 0, n_fo).astype(np.float32)

    peak = np.max(np.abs(y))
    if peak > 0:
        y /= max(1.0, peak / 0.95)

    return y


# ─────────────────────────────────────────────────────────────────────────────
# Multi-freeze (v3 new)
# ─────────────────────────────────────────────────────────────────────────────

def _capture_magnitude(audio, sr, freeze_time_s, wsize, win):
    """Capture the magnitude spectrum at a given time."""
    import numpy as np
    freeze_sample = int(np.clip(freeze_time_s * sr, 0, len(audio) - wsize))
    frame = audio[freeze_sample:freeze_sample + wsize] * win
    return np.abs(np.fft.rfft(frame)).astype(np.float32)


def spectral_freeze_multi(audio, sr, freeze_times, duration_s,
                          window_ms, shimmer, fade_in_s, fade_out_s,
                          xfade_s, dwell_s, loop):
    """
    Multi-freeze: capture spectra at multiple moments and crossfade
    between them, creating an evolving frozen texture.

    The output timeline is structured as a sequence of waypoints:
        [dwell @ wp0] → [xfade wp0→wp1] → [dwell @ wp1] → [xfade wp1→wp2] → ...

    If loop=True, after the last waypoint, crossfade back to the first.
    The total sequence is time-stretched or repeated to fill duration_s.

    Parameters
    ----------
    freeze_times : list of float
        Times in seconds to capture frozen spectra.
    xfade_s : float
        Crossfade duration between adjacent waypoints.
    dwell_s : float
        Hold time at each waypoint before crossfading.
    loop : bool
        If True, loop the waypoint sequence to fill duration.
    """
    import numpy as np

    if audio.ndim > 1:
        audio = audio[:, 0]
    audio = audio.astype(np.float32)

    n_wp = len(freeze_times)
    if n_wp < 2:
        # Fall back to single freeze
        print("  Multi-freeze needs >=2 points, falling back to single.")
        return spectral_freeze_single(
            audio, sr, freeze_times[0] if freeze_times else 0.5,
            duration_s, window_ms, shimmer, fade_in_s, fade_out_s)

    wsize = next_pow2(int(window_ms / 1000 * sr))
    wsize = max(wsize, 64)
    hop = wsize // 4
    win = hann(wsize)
    win_sq = win ** 2

    # Capture magnitude at each waypoint
    mags = []
    for i, ft in enumerate(freeze_times):
        mag = _capture_magnitude(audio, sr, ft, wsize, win)
        mags.append(mag)
        print(f"  Waypoint {i + 1}/{n_wp}: {ft:.3f}s  "
              f"(energy={float(np.sum(mag ** 2)):.1f})")

    # Build the waypoint sequence
    # Each segment: dwell_s of pure waypoint, then xfade_s to the next
    if loop:
        # Add first waypoint at the end to close the loop
        wp_indices = list(range(n_wp)) + [0]
    else:
        wp_indices = list(range(n_wp))

    n_segs = len(wp_indices)

    # One pass duration: dwell at each + xfade between each pair
    n_transitions = n_segs - 1
    one_pass_dur = n_segs * dwell_s + n_transitions * xfade_s

    if one_pass_dur <= 0:
        one_pass_dur = duration_s

    print(f"  Waypoints: {n_segs}  |  One pass: {one_pass_dur:.2f}s  "
          f"|  Target: {duration_s:.2f}s  |  Loop: {loop}")

    # Build a timeline function: for any time t, return (mag_interp, phase_random)
    # by figuring out which segment we're in and the blend factor

    target_samples = int(duration_s * sr)
    out_len = target_samples + 2 * wsize
    y = np.zeros(out_len, dtype=np.float32)
    norm = np.zeros(out_len, dtype=np.float32)

    rng = np.random.default_rng()
    n_bins = len(mags[0])

    out_pos = 0
    while out_pos < target_samples + wsize:
        # Current time in seconds
        t = out_pos / sr

        # Map t into the waypoint sequence (with looping if needed)
        if one_pass_dur > 0:
            t_local = t % one_pass_dur if loop else min(t, one_pass_dur)
        else:
            t_local = 0.0

        # Walk through segments to find where t_local falls
        cursor = 0.0
        mag_a_idx = wp_indices[0]
        mag_b_idx = wp_indices[0]
        blend = 0.0

        for seg_i in range(n_segs):
            wp_i = wp_indices[seg_i]

            # Dwell phase at this waypoint
            dwell_end = cursor + dwell_s
            if t_local < dwell_end:
                # In the dwell phase of waypoint seg_i
                mag_a_idx = wp_i
                mag_b_idx = wp_i
                blend = 0.0
                break
            cursor = dwell_end

            # Crossfade to next waypoint (if not the last)
            if seg_i < n_segs - 1:
                xfade_end = cursor + xfade_s
                if t_local < xfade_end:
                    # In the crossfade between seg_i and seg_i+1
                    mag_a_idx = wp_i
                    mag_b_idx = wp_indices[seg_i + 1]
                    u = (t_local - cursor) / max(xfade_s, 1e-9)
                    # Cosine S-curve for smooth crossfade
                    blend = 0.5 - 0.5 * math.cos(math.pi * u)
                    break
                cursor = xfade_end
        else:
            # Past the end of the sequence — hold last waypoint
            mag_a_idx = wp_indices[-1]
            mag_b_idx = wp_indices[-1]
            blend = 0.0

        # Interpolate magnitudes in log domain
        mag_a = mags[mag_a_idx]
        mag_b = mags[mag_b_idx]
        if blend < 0.001:
            mag = mag_a.copy()
        elif blend > 0.999:
            mag = mag_b.copy()
        else:
            log_a = np.log(mag_a + 1e-8)
            log_b = np.log(mag_b + 1e-8)
            mag = np.exp((1.0 - blend) * log_a + blend * log_b)

        # Shimmer
        if shimmer > 0:
            jitter = 1.0 + shimmer * (
                rng.random(n_bins).astype(np.float32) * 2 - 1)
            mag = mag * np.abs(jitter)

        # Random phase
        phase = rng.random(n_bins) * 2.0 * np.pi
        S_out = mag * np.exp(1j * phase)

        frame_out = np.fft.irfft(S_out, n=wsize).real.astype(np.float32)
        frame_out *= win

        end = out_pos + wsize
        if end > len(y):
            y = np.pad(y, (0, end - len(y)))
            norm = np.pad(norm, (0, end - len(norm)))

        y[out_pos:end] += frame_out
        norm[out_pos:end] += win_sq
        out_pos += hop

    # OLA normalize and trim
    norm = np.maximum(norm, 1e-8)
    y /= norm
    y = y[wsize:wsize + target_samples]

    # Fades
    if fade_in_s > 0:
        n_fi = min(int(fade_in_s * sr), len(y))
        y[:n_fi] *= np.linspace(0, 1, n_fi).astype(np.float32)
    if fade_out_s > 0:
        n_fo = min(int(fade_out_s * sr), len(y))
        y[-n_fo:] *= np.linspace(1, 0, n_fo).astype(np.float32)

    # Peak normalize
    peak = np.max(np.abs(y))
    if peak > 0:
        y /= max(1.0, peak / 0.95)

    return y


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def main():
    # Determine mode from last positional-ish argument
    args = sys.argv[1:]

    if len(args) < 8:
        print("Usage (single):")
        print("  python spectral_freeze.py input.wav output.wav freeze_time_s")
        print("    duration_s window_ms shimmer fade_in_s fade_out_s [single]")
        print("")
        print("Usage (multi):")
        print("  python spectral_freeze.py input.wav output.wav freeze_times")
        print("    duration_s window_ms shimmer fade_in_s fade_out_s")
        print("    multi xfade_s dwell_s loop")
        print("")
        print("  freeze_times: comma-separated (e.g. 0.3,1.2,2.5)")
        print("  xfade_s:      crossfade between waypoints (seconds)")
        print("  dwell_s:      hold time at each waypoint (seconds)")
        print("  loop:         0 or 1")
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav     = args[0]
    out_wav    = args[1]
    times_str  = args[2]
    duration_s = float(args[3])
    window_ms  = float(args[4])
    shimmer    = max(0.0, min(1.0, float(args[5])))
    fade_in_s  = max(0.0, float(args[6]))
    fade_out_s = max(0.0, float(args[7]))

    # Detect mode
    mode = "single"
    xfade_s = 2.0
    dwell_s = 1.0
    loop = False

    if len(args) >= 9 and args[8].lower() == "multi":
        mode = "multi"
        if len(args) >= 10:
            xfade_s = max(0.1, float(args[9]))
        if len(args) >= 11:
            dwell_s = max(0.0, float(args[10]))
        if len(args) >= 12:
            loop = int(args[11]) != 0

    if not os.path.isfile(in_wav):
        print(f"ERROR: Input file not found: {in_wav}", file=sys.stderr)
        sys.exit(1)
    if duration_s <= 0:
        print("ERROR: duration_s must be > 0", file=sys.stderr)
        sys.exit(1)

    out_dir = os.path.dirname(out_wav)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    print(f"  Input: {in_wav}  ({len(audio)/sr:.3f}s  SR={sr})")

    if mode == "multi":
        # Parse comma-separated freeze times
        freeze_times = [float(t.strip()) for t in times_str.split(",")
                        if t.strip()]
        print(f"  Mode: MULTI-FREEZE  |  {len(freeze_times)} waypoints")
        print(f"  Dwell: {dwell_s:.2f}s  |  Xfade: {xfade_s:.2f}s  "
              f"|  Loop: {loop}")

        output = spectral_freeze_multi(
            audio, sr, freeze_times, duration_s,
            window_ms, shimmer, fade_in_s, fade_out_s,
            xfade_s, dwell_s, loop)
    else:
        freeze_time_s = float(times_str)
        print(f"  Mode: SINGLE freeze at {freeze_time_s:.3f}s")

        output = spectral_freeze_single(
            audio, sr, freeze_time_s, duration_s,
            window_ms, shimmer, fade_in_s, fade_out_s)

    sf.write(out_wav, output, sr)
    print(f"OK: wrote {out_wav}  ({len(output)/sr:.3f}s)")


if __name__ == "__main__":
    main()
