"""
spectral_freeze.py  –  Spectral freeze via phase vocoder OLA

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

v3.3 — Robust capture, multichannel preservation, energy-stable multi-freeze.

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

VERSION = "3.3"


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


def _centered_window(audio, center_sample, wsize, win):
    """Return a windowed frame centred on center_sample, zero-padding at edges."""
    import numpy as np
    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim != 1:
        raise ValueError("_centered_window expects a mono channel")
    if len(audio) == 0:
        raise ValueError("Input audio is empty")

    center = int(np.clip(center_sample, 0, len(audio) - 1))
    start = center - wsize // 2
    end = start + wsize
    frame = np.zeros(wsize, dtype=np.float32)
    src0 = max(0, start)
    src1 = min(len(audio), end)
    if src1 > src0:
        dst0 = src0 - start
        frame[dst0:dst0 + (src1 - src0)] = audio[src0:src1]
    return frame * win


def _capture_state(audio, sr, freeze_time_s, wsize, hop, win):
    """Capture magnitude, phase and true-frequency phase advance at one moment.

    freeze_time_s is interpreted as the CENTER of the analysis frame.  A second
    frame one hop later is preferred for the instantaneous-frequency estimate;
    near the end of the file a preceding frame is used instead.  Edge frames
    are zero padded, so even sounds shorter than the FFT window are valid.
    """
    import numpy as np
    if len(audio) == 0:
        raise ValueError("Input audio is empty")

    n = wsize
    center0 = int(round(float(freeze_time_s) * sr))
    center0 = int(np.clip(center0, 0, len(audio) - 1))
    f0 = _centered_window(audio, center0, n, win)
    s0 = np.fft.rfft(f0)
    mag = np.abs(s0).astype(np.float32)
    phase0 = np.angle(s0).astype(np.float64)

    if len(audio) >= 2:
        if center0 + hop <= len(audio) - 1:
            center1 = center0 + hop
        elif center0 - hop >= 0:
            center1 = center0 - hop
        else:
            center1 = len(audio) - 1 if center0 == 0 else 0
        gap = center1 - center0
    else:
        center1 = center0
        gap = 0

    k = np.arange(s0.shape[0], dtype=np.float64)
    if gap != 0:
        f1 = _centered_window(audio, center1, n, win)
        s1 = np.fft.rfft(f1)
        expected = 2.0 * np.pi * k * gap / n
        dev = np.angle(s1) - phase0 - expected
        dev = (dev + np.pi) % (2.0 * np.pi) - np.pi
        per_hop = (expected + dev) / float(gap) * hop
    else:
        per_hop = 2.0 * np.pi * k * hop / n

    return mag, phase0, per_hop.astype(np.float64)


def _apply_fades(y, sr, fade_in_s, fade_out_s):
    import numpy as np
    if fade_in_s > 0:
        n_fi = min(int(round(fade_in_s * sr)), len(y))
        if n_fi > 0:
            y[:n_fi] *= np.linspace(0.0, 1.0, n_fi, dtype=np.float32)
    if fade_out_s > 0:
        n_fo = min(int(round(fade_out_s * sr)), len(y))
        if n_fo > 0:
            y[-n_fo:] *= np.linspace(1.0, 0.0, n_fo, dtype=np.float32)
    return y


def _global_peak_safety(y, ceiling=0.95):
    """Attenuation only, with one scalar for all channels."""
    import numpy as np
    peak = float(np.max(np.abs(y))) if np.size(y) else 0.0
    if peak > ceiling and peak > 0.0:
        y = y * np.float32(ceiling / peak)
    return y.astype(np.float32)

# ─────────────────────────────────────────────────────────────────────────────
# Single freeze (v2 behaviour, unchanged)
# ─────────────────────────────────────────────────────────────────────────────

def _spectral_freeze_single_channel(audio, sr, freeze_time_s, duration_s,
                                    window_ms, shimmer, fade_in_s, fade_out_s,
                                    phase_mode="random", rng=None):
    """Freeze one mono channel."""
    import numpy as np
    audio = np.asarray(audio, dtype=np.float32)
    if len(audio) == 0:
        raise ValueError("Input audio is empty")

    wsize = next_pow2(max(1, int(round(window_ms / 1000.0 * sr))))
    wsize = max(wsize, 64)
    hop = max(1, wsize // 4)
    win = hann(wsize)
    win_sq = win ** 2

    mag_freeze, phase0, dphi = _capture_state(
        audio, sr, freeze_time_s, wsize, hop, win)

    coherent = (phase_mode == "coherent")
    running_phase = phase0.copy() if coherent else None
    if rng is None:
        rng = np.random.default_rng()

    target_samples = max(1, int(round(duration_s * sr)))
    out_len = target_samples + 2 * wsize
    y = np.zeros(out_len, dtype=np.float64)
    norm = np.zeros(out_len, dtype=np.float64)

    out_pos = 0
    frame_idx = 0
    while out_pos < target_samples + wsize:
        if shimmer > 0:
            jitter = 1.0 + shimmer * (
                rng.random(len(mag_freeze)).astype(np.float32) * 2.0 - 1.0)
            mag = mag_freeze * np.abs(jitter)
        else:
            mag = mag_freeze

        if coherent:
            S_out = mag * np.exp(1j * running_phase)
            running_phase = running_phase + dphi
        else:
            phase = rng.random(len(mag)) * 2.0 * np.pi
            S_out = mag * np.exp(1j * phase)

        frame_out = np.fft.irfft(S_out, n=wsize).real
        frame_out *= win
        end = out_pos + wsize
        y[out_pos:end] += frame_out
        norm[out_pos:end] += win_sq
        out_pos += hop
        frame_idx += 1

    safe = norm > 1e-8
    y[safe] /= norm[safe]
    y[~safe] = 0.0
    y = y[wsize:wsize + target_samples].astype(np.float32)
    return _apply_fades(y, sr, fade_in_s, fade_out_s)


def spectral_freeze_single(audio, sr, freeze_time_s, duration_s,
                           window_ms, shimmer, fade_in_s, fade_out_s,
                           phase_mode="random"):
    """Freeze one moment while preserving the input channel layout."""
    import numpy as np
    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim == 1:
        channels = [audio]
    elif audio.ndim == 2:
        channels = [audio[:, ch] for ch in range(audio.shape[1])]
    else:
        raise ValueError("Audio must be mono or multichannel (samples x channels)")

    wsize = next_pow2(max(1, int(round(window_ms / 1000.0 * sr))))
    wsize = max(wsize, 64)
    print(f"  Freeze point: {freeze_time_s:.3f}s (frame centred on requested time)")
    print(f"  Window: {wsize} samples ({1000*wsize/sr:.1f}ms effective)  hop: {wsize//4}")
    print(f"  Output duration: {duration_s:.2f}s  shimmer: {shimmer:.2f}  channels: {len(channels)}")

    # Independent random streams prevent cloned stereo random-phase textures.
    rng_master = np.random.default_rng()
    outs = []
    for ch in channels:
        rng = np.random.default_rng(int(rng_master.integers(0, 2**63 - 1)))
        outs.append(_spectral_freeze_single_channel(
            ch, sr, freeze_time_s, duration_s, window_ms, shimmer,
            fade_in_s, fade_out_s, phase_mode, rng))

    y = outs[0] if len(outs) == 1 else np.column_stack(outs)
    return _global_peak_safety(y)

# ─────────────────────────────────────────────────────────────────────────────
# Multi-freeze (v3 new)
# ─────────────────────────────────────────────────────────────────────────────

def _power_crossfade_magnitude(mag_a, mag_b, blend):
    """Energy-stable spectral crossfade.

    A cosine time curve supplies blend in [0,1].  Interpolating spectral POWER
    rather than log magnitude avoids the deep level hole produced when two
    waypoints occupy different bins (e.g. one pitched note morphing to another).
    Endpoints and identical spectra are exact.
    """
    import numpy as np
    b = float(np.clip(blend, 0.0, 1.0))
    if b <= 0.0:
        return mag_a.copy()
    if b >= 1.0:
        return mag_b.copy()
    return np.sqrt((1.0 - b) * (mag_a.astype(np.float64) ** 2) +
                   b * (mag_b.astype(np.float64) ** 2)).astype(np.float32)


def _spectral_freeze_multi_channel(audio, sr, freeze_times, duration_s,
                                   window_ms, shimmer, fade_in_s, fade_out_s,
                                   xfade_s, dwell_s, loop,
                                   phase_mode="random", rng=None):
    import numpy as np
    audio = np.asarray(audio, dtype=np.float32)
    if len(audio) == 0:
        raise ValueError("Input audio is empty")

    n_wp = len(freeze_times)
    if n_wp < 2:
        return _spectral_freeze_single_channel(
            audio, sr, freeze_times[0] if freeze_times else 0.5,
            duration_s, window_ms, shimmer, fade_in_s, fade_out_s,
            phase_mode, rng)

    wsize = next_pow2(max(1, int(round(window_ms / 1000.0 * sr))))
    wsize = max(wsize, 64)
    hop = max(1, wsize // 4)
    win = hann(wsize)
    win_sq = win ** 2

    states = [_capture_state(audio, sr, ft, wsize, hop, win)
              for ft in freeze_times]
    mags = [st[0] for st in states]
    phases = [st[1] for st in states]
    dphis = [st[2] for st in states]

    n_dwell = n_wp
    n_xfade = n_wp if loop else (n_wp - 1)
    one_pass_dur = n_dwell * dwell_s + n_xfade * xfade_s
    if one_pass_dur <= 0:
        one_pass_dur = duration_s

    coherent = (phase_mode == "coherent")
    if rng is None:
        rng = np.random.default_rng()

    target_samples = max(1, int(round(duration_s * sr)))
    out_len = target_samples + 2 * wsize
    y = np.zeros(out_len, dtype=np.float64)
    norm = np.zeros(out_len, dtype=np.float64)
    n_bins = len(mags[0])

    out_pos = 0
    frame_idx = 0
    while out_pos < target_samples + wsize:
        t = out_pos / float(sr)
        t_local = t % one_pass_dur if loop else min(t, one_pass_dur)

        cursor = 0.0
        mag_a_idx = mag_b_idx = 0
        blend = 0.0
        found = False
        for wp_i in range(n_wp):
            dwell_end = cursor + dwell_s
            if t_local < dwell_end:
                mag_a_idx = mag_b_idx = wp_i
                blend = 0.0
                found = True
                break
            cursor = dwell_end

            has_xfade = (wp_i < n_wp - 1) or loop
            if has_xfade:
                nxt = (wp_i + 1) % n_wp
                xfade_end = cursor + xfade_s
                if t_local < xfade_end:
                    mag_a_idx, mag_b_idx = wp_i, nxt
                    u = (t_local - cursor) / max(xfade_s, 1e-9)
                    blend = 0.5 - 0.5 * math.cos(math.pi * u)
                    found = True
                    break
                cursor = xfade_end

        if not found:
            mag_a_idx = mag_b_idx = n_wp - 1
            blend = 0.0

        mag = _power_crossfade_magnitude(
            mags[mag_a_idx], mags[mag_b_idx], blend)

        jitter = None
        if shimmer > 0:
            jitter = np.abs(1.0 + shimmer * (
                rng.random(n_bins).astype(np.float32) * 2.0 - 1.0))
            mag = mag * jitter

        if coherent:
            # Each waypoint is a coherent virtual freeze stream with its own
            # captured phase and true-frequency advance.  Crossfade the two
            # complex streams with equal-power weights.  This preserves each
            # waypoint's internal phase relationships and avoids the amplitude
            # collapse that occurs when later magnitudes inherit waypoint 1's
            # unrelated phase trajectory.
            phase_a = phases[mag_a_idx] + frame_idx * dphis[mag_a_idx]
            mag_a_coh = mags[mag_a_idx] if jitter is None else mags[mag_a_idx] * jitter
            S_a = mag_a_coh * np.exp(1j * phase_a)
            if mag_a_idx == mag_b_idx or blend <= 0.0:
                S_out = S_a
            elif blend >= 1.0:
                phase_b = phases[mag_b_idx] + frame_idx * dphis[mag_b_idx]
                mag_b_coh = mags[mag_b_idx] if jitter is None else mags[mag_b_idx] * jitter
                S_out = mag_b_coh * np.exp(1j * phase_b)
            else:
                phase_b = phases[mag_b_idx] + frame_idx * dphis[mag_b_idx]
                mag_b_coh = mags[mag_b_idx] if jitter is None else mags[mag_b_idx] * jitter
                S_b = mag_b_coh * np.exp(1j * phase_b)
                S_out = math.sqrt(1.0 - blend) * S_a + math.sqrt(blend) * S_b
        else:
            phase = rng.random(n_bins) * 2.0 * np.pi
            S_out = mag * np.exp(1j * phase)

        frame_out = np.fft.irfft(S_out, n=wsize).real
        frame_out *= win
        end = out_pos + wsize
        y[out_pos:end] += frame_out
        norm[out_pos:end] += win_sq
        out_pos += hop
        frame_idx += 1

    safe = norm > 1e-8
    y[safe] /= norm[safe]
    y[~safe] = 0.0
    y = y[wsize:wsize + target_samples].astype(np.float32)
    return _apply_fades(y, sr, fade_in_s, fade_out_s)


def spectral_freeze_multi(audio, sr, freeze_times, duration_s,
                          window_ms, shimmer, fade_in_s, fade_out_s,
                          xfade_s, dwell_s, loop, phase_mode="random"):
    """Evolving freeze through multiple spectral waypoints.

    Non-loop runs traverse the sequence once and then hold the final waypoint.
    Loop runs crossfade last->first and repeat without a duplicated seam dwell.
    Input channel layout is preserved.
    """
    import numpy as np
    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim == 1:
        channels = [audio]
    elif audio.ndim == 2:
        channels = [audio[:, ch] for ch in range(audio.shape[1])]
    else:
        raise ValueError("Audio must be mono or multichannel (samples x channels)")

    n_wp = len(freeze_times)
    if n_wp < 2:
        print("  Multi-freeze needs >=2 points, falling back to single.")
        return spectral_freeze_single(
            audio, sr, freeze_times[0] if freeze_times else 0.5,
            duration_s, window_ms, shimmer, fade_in_s, fade_out_s,
            phase_mode)

    wsize = next_pow2(max(1, int(round(window_ms / 1000.0 * sr))))
    wsize = max(wsize, 64)
    for i, ft in enumerate(freeze_times):
        print(f"  Waypoint {i + 1}/{n_wp}: {ft:.3f}s")
    n_xfade = n_wp if loop else n_wp - 1
    one_pass_dur = n_wp * dwell_s + n_xfade * xfade_s
    if one_pass_dur <= 0:
        one_pass_dur = duration_s
    print(f"  Waypoints: {n_wp}  |  One pass: {one_pass_dur:.2f}s  "
          f"|  Target: {duration_s:.2f}s  |  Loop: {loop}  |  channels: {len(channels)}")
    print(f"  Window: {wsize} samples ({1000*wsize/sr:.1f}ms effective)  hop: {wsize//4}")

    rng_master = np.random.default_rng()
    outs = []
    for ch in channels:
        rng = np.random.default_rng(int(rng_master.integers(0, 2**63 - 1)))
        outs.append(_spectral_freeze_multi_channel(
            ch, sr, freeze_times, duration_s, window_ms, shimmer,
            fade_in_s, fade_out_s, xfade_s, dwell_s, loop, phase_mode, rng))

    y = outs[0] if len(outs) == 1 else np.column_stack(outs)
    return _global_peak_safety(y)

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
    if window_ms <= 0:
        print("ERROR: window_ms must be > 0", file=sys.stderr)
        sys.exit(1)

    out_dir = os.path.dirname(out_wav)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    print(f"=== Spectral Freeze v{VERSION} ===")
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

    sf.write(out_wav, output, sr, subtype="FLOAT")
    print(f"OK: wrote {out_wav}  ({len(output)/sr:.3f}s)")


if __name__ == "__main__":
    main()
