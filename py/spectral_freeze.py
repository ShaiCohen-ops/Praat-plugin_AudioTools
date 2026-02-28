"""
spectral_freeze.py  –  Spectral freeze via phase vocoder OLA

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Captures the magnitude spectrum at a chosen moment and sustains it
indefinitely via per-frame phase randomization with overlap-add.

Usage:
    python spectral_freeze.py input.wav output.wav freeze_time_s duration_s
           window_ms shimmer fade_in_s fade_out_s

    freeze_time_s:  time in seconds to capture the frozen frame
    duration_s:     total output duration in seconds
    window_ms:      analysis window in ms (40-200, default 80)
    shimmer:        0.0-1.0 magnitude jitter per frame (0=static, 0.2=alive)
    fade_in_s:      fade in duration in seconds (0 = no fade)
    fade_out_s:     fade out duration in seconds (0 = no fade)
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


def spectral_freeze(audio, sr, freeze_time_s, duration_s,
                    window_ms, shimmer, fade_in_s, fade_out_s):
    """
    Freeze the spectrum at a single moment and sustain it.

    Parameters
    ----------
    audio : np.ndarray
        Input audio (mono or multi-channel, uses first channel).
    sr : int
        Sample rate.
    freeze_time_s : float
        Time in seconds to capture the frozen frame.
    duration_s : float
        Output duration in seconds.
    window_ms : float
        Analysis window in milliseconds.
    shimmer : float
        Magnitude randomization per frame (0.0-1.0).
    fade_in_s : float
        Fade in duration in seconds.
    fade_out_s : float
        Fade out duration in seconds.

    Returns
    -------
    np.ndarray
        Frozen output signal (float32, mono).
    """
    import numpy as np

    # Mono
    if audio.ndim > 1:
        audio = audio[:, 0]
    audio = audio.astype(np.float32)

    wsize = next_pow2(int(window_ms / 1000 * sr))
    wsize = max(wsize, 64)
    hop = wsize // 4
    win = hann(wsize)
    win_sq = win ** 2

    # Clamp freeze time
    freeze_sample = int(np.clip(freeze_time_s * sr, 0, len(audio) - wsize))

    # Extract and window the freeze frame
    frame = audio[freeze_sample:freeze_sample + wsize] * win
    spectrum = np.fft.rfft(frame)
    mag_freeze = np.abs(spectrum).astype(np.float32)

    print(f"  Freeze point: {freeze_time_s:.3f}s (sample {freeze_sample})")
    print(f"  Window: {wsize} samples ({window_ms:.0f}ms)  hop: {hop}")
    print(f"  Output duration: {duration_s:.2f}s  shimmer: {shimmer:.2f}")

    # Pad start by wsize so the OLA buildup region can be trimmed
    # (avoids click from dividing near-zero norm at boundaries)
    target_samples = int(duration_s * sr)
    out_len = target_samples + 2 * wsize
    y = np.zeros(out_len, dtype=np.float32)
    norm = np.zeros(out_len, dtype=np.float32)

    rng = np.random.default_rng()

    out_pos = 0
    # Generate enough to cover wsize padding + target duration
    while out_pos < target_samples + wsize:
        # Optional shimmer — slightly randomize magnitudes each frame
        if shimmer > 0:
            jitter = 1.0 + shimmer * (
                rng.random(len(mag_freeze)).astype(np.float32) * 2 - 1
            )
            mag = mag_freeze * np.abs(jitter)
        else:
            mag = mag_freeze.copy()

        # Random phase every frame — makes it breathe
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

    # OLA normalize — trim the buildup region at both ends
    norm = np.maximum(norm, 1e-8)
    y /= norm
    y = y[wsize:wsize + target_samples]

    # Fade in
    if fade_in_s > 0:
        fade_in_samples = min(int(fade_in_s * sr), len(y))
        y[:fade_in_samples] *= np.linspace(
            0, 1, fade_in_samples
        ).astype(np.float32)

    # Fade out
    if fade_out_s > 0:
        fade_out_samples = min(int(fade_out_s * sr), len(y))
        y[-fade_out_samples:] *= np.linspace(
            1, 0, fade_out_samples
        ).astype(np.float32)

    # Normalize peak
    peak = np.max(np.abs(y))
    if peak > 0:
        y /= max(1.0, peak / 0.95)

    return y


def main():
    if len(sys.argv) != 9:
        print("Usage: python spectral_freeze.py input.wav output.wav "
              "freeze_time_s duration_s window_ms shimmer fade_in_s fade_out_s")
        print("  freeze_time_s:  capture time (seconds)")
        print("  duration_s:     output length (seconds)")
        print("  window_ms:      analysis window (40-200, default 80)")
        print("  shimmer:        0.0-1.0 (0=static, 0.2=alive)")
        print("  fade_in_s:      fade in (seconds, 0=none)")
        print("  fade_out_s:     fade out (seconds, 0=none)")
        sys.exit(1)

    # Check dependencies before heavy imports
    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav = sys.argv[1]
    out_wav = sys.argv[2]
    freeze_time_s = float(sys.argv[3])
    duration_s = float(sys.argv[4])
    window_ms = float(sys.argv[5])
    shimmer = float(sys.argv[6])
    fade_in_s = float(sys.argv[7])
    fade_out_s = float(sys.argv[8])

    # Validate input file
    if not os.path.isfile(in_wav):
        print(f"ERROR: Input file not found: {in_wav}", file=sys.stderr)
        sys.exit(1)

    # Validate parameters
    if duration_s <= 0:
        print("ERROR: duration_s must be > 0", file=sys.stderr)
        sys.exit(1)
    if window_ms <= 0:
        print("ERROR: window_ms must be > 0", file=sys.stderr)
        sys.exit(1)
    shimmer = max(0.0, min(1.0, shimmer))
    fade_in_s = max(0.0, fade_in_s)
    fade_out_s = max(0.0, fade_out_s)

    # Ensure output directory exists
    out_dir = os.path.dirname(out_wav)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)

    print(f"  Input: {in_wav}  ({len(audio)/sr:.3f}s  SR={sr})")

    output = spectral_freeze(audio, sr, freeze_time_s, duration_s,
                             window_ms, shimmer, fade_in_s, fade_out_s)

    sf.write(out_wav, output, sr)
    print(f"OK: wrote {out_wav}  ({len(output)/sr:.3f}s)")


if __name__ == "__main__":
    main()
