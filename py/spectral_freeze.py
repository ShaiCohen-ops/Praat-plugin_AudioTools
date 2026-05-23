"""
spectral_freeze.py  –  Spectral freeze via phase vocoder OLA

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

v3.1 — Phase mode: 'coherent' locks bin phases for a steady tonal
       freeze (vs 'random' diffuse). Fixed loop double-dwell at seam.

v3.0 — Multi-Freeze mode: captures spectra at multiple moments and
       crossfades between them, creating an evolving frozen texture.

Modes:
    single  — Original: freeze one moment (v2 behaviour)
    multi   — NEW: freeze N moments, crossfade between them in sequence

Usage (single):
    python spectral_freeze.py input.wav output.wav freeze_time_s duration_s
           window_ms shimmer fade_in_s fade_out_s single [phase_mode]

Usage (multi):
    python spectral_freeze.py input.wav output.wav freeze_times duration_s
           window_ms shimmer fade_in_s fade_out_s multi xfade_s dwell_s loop

    freeze_times:  comma-separated times in seconds (e.g. "0.3,1.2,2.5")
    xfade_s:       crossfade duration between waypoints (seconds)
    dwell_s:       hold time at each waypoint before crossfading (seconds)
    loop:          0 = one pass through waypoints, 1 = loop back to start
    phase_mode:    random (diffuse, default) | coherent (tonal, locked)
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


def _coherent_advance(audio, sr, freeze_time_s, wsize, hop, win):
    """Phase reference for a tonal (phase-locked) freeze.

    Returns (phase0, per_hop_advance): the captured phase and the
    per-hop phase increment for each bin, using the bin's TRUE
    frequency estimated from two analysis frames (phase-vocoder
    instantaneous frequency). Advancing by this keeps partials
    locked, so a frozen tone stays steady instead of beating.
    """
    import numpy as np
    n = wsize
    fs = int(np.clip(freeze_time_s * sr, 0, len(audio) - n))
    s0 = np.fft.rfft(audio[fs:fs + n] * win)
    phase0 = np.angle(s0).astype(np.float64)
    k = np.arange(s0.shape[0])
    fs2 = min(fs + hop, len(audio) - n)
    gap = fs2 - fs
    if gap >= 1:
        s1 = np.fft.rfft(audio[fs2:fs2 + n] * win)
        expected = 2.0 * np.pi * k * gap / n
        dev = np.angle(s1) - phase0 - expected
        dev = (dev + np.pi) % (2.0 * np.pi) - np.pi   # principal value
        per_hop = (expected + dev) / gap * hop
    else:
        per_hop = 2.0 * np.pi * k * hop / n            # bin-centre fallback
    return phase0, per_hop


# ─────────────────────────────────────────────────────────────────────────────
# Single freeze (v2 behaviour, unchanged)
# ─────────────────────────────────────────────────────────────────────────────

def spectral_freeze_single(audio, sr, freeze_time_s, duration_s,
                           window_ms, shimmer, fade_in_s, fade_out_s,
                           phase_mode="random"):
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

    # Phase-coherent synthesis: lock each bin to its TRUE frequency
    # (estimated from two analysis frames) so the freeze is a steady
    # tonal sustain rather than a diffuse random-phase texture.
    coherent = (phase_mode == "coherent")
    if coherent:
        running_phase, dphi = _coherent_advance(
            audio, sr, freeze_time_s, wsize, hop, win)
    else:
        running_phase, dphi = None, None

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

        if coherent:
            S_out = mag * np.exp(1j * running_phase)
            running_phase = running_phase + dphi
        else:
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
                          xfade_s, dwell_s, loop, phase_mode="random"):
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
            duration_s, window_ms, shimmer, fade_in_s, fade_out_s,
            phase_mode)

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

    # Timeline: dwell@wp0, xfade 0->1, dwell@wp1, ..., dwell@wp(n-1).
    # If loop, one extra xfade (n-1)->0 closes the cycle WITHOUT a
    # trailing dwell, so wp0 is not held twice at the seam.
    n_dwell = n_wp
    n_xfade = n_wp if loop else (n_wp - 1)
    one_pass_dur = n_dwell * dwell_s + n_xfade * xfade_s
    if one_pass_dur <= 0:
        one_pass_dur = duration_s

    print(f"  Waypoints: {n_wp}  |  One pass: {one_pass_dur:.2f}s  "
          f"|  Target: {duration_s:.2f}s  |  Loop: {loop}")

    # Coherent phase: lock partials to the first waypoint's TRUE bin
    # frequencies (see _coherent_advance); magnitudes still morph.
    coherent = (phase_mode == "coherent")
    if coherent:
        running_phase, dphi = _coherent_advance(
            audio, sr, freeze_times[0], wsize, hop, win)
    else:
        running_phase, dphi = None, None

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

        # Walk waypoints (dwell then xfade) to find where t_local falls
        cursor = 0.0
        mag_a_idx = 0
        mag_b_idx = 0
        blend = 0.0
        found = False

        for wp_i in range(n_wp):
            dwell_end = cursor + dwell_s
            if t_local < dwell_end:
                mag_a_idx = wp_i
                mag_b_idx = wp_i
                blend = 0.0
                found = True
                break
            cursor = dwell_end

            has_xfade = (wp_i < n_wp - 1) or loop
            if has_xfade:
                nxt = (wp_i + 1) % n_wp
                xfade_end = cursor + xfade_s
                if t_local < xfade_end:
                    mag_a_idx = wp_i
                    mag_b_idx = nxt
                    u = (t_local - cursor) / max(xfade_s, 1e-9)
                    # Cosine S-curve for smooth crossfade
                    blend = 0.5 - 0.5 * math.cos(math.pi * u)
                    found = True
                    break
                cursor = xfade_end

        if not found:
            # Past the end (non-loop): hold the last waypoint
            mag_a_idx = n_wp - 1
            mag_b_idx = n_wp - 1
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

        # Phase: coherent (locked) or random (diffuse)
        if coherent:
            S_out = mag * np.exp(1j * running_phase)
            running_phase = running_phase + dphi
        else:
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

    # Optional trailing phase_mode argument (random | coherent)
    phase_mode = "random"
    if mode == "multi" and len(args) >= 13:
        phase_mode = args[12].lower()
    elif mode == "single" and len(args) >= 10:
        phase_mode = args[9].lower()
    if phase_mode not in ("random", "coherent"):
        phase_mode = "random"

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
              f"|  Loop: {loop}  |  Phase: {phase_mode}")

        output = spectral_freeze_multi(
            audio, sr, freeze_times, duration_s,
            window_ms, shimmer, fade_in_s, fade_out_s,
            xfade_s, dwell_s, loop, phase_mode)
    else:
        freeze_time_s = float(times_str)
        print(f"  Mode: SINGLE freeze at {freeze_time_s:.3f}s  "
              f"(phase={phase_mode})")

        output = spectral_freeze_single(
            audio, sr, freeze_time_s, duration_s,
            window_ms, shimmer, fade_in_s, fade_out_s, phase_mode)

    sf.write(out_wav, output, sr)
    print(f"OK: wrote {out_wav}  ({len(output)/sr:.3f}s)")


if __name__ == "__main__":
    main()
