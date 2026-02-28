"""
paulstretch.py  –  Extreme time-stretching via spectral phase randomization

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage:
    python paulstretch.py input.wav output.wav stretch window_seconds

    stretch:        duration multiplier (>1.0, e.g. 8 = 8x longer)
    window_seconds: analysis window in seconds (0.1-1.0, larger = smoother)

Example:
    python paulstretch.py in.wav out.wav 8 0.25
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


def hann_window(n):
    """Classic Hann (raised cosine) window."""
    import numpy as np
    return 0.5 - 0.5 * np.cos(
        2.0 * np.pi * np.arange(n, dtype=np.float32) / (n - 1)
    )


def paulstretch_channel(x, sr, stretch, window_seconds):
    """
    Paulstretch for a single channel.

    Randomizes FFT phases while preserving magnitudes, producing
    smooth, evolving textures from any source material.

    Parameters
    ----------
    x : np.ndarray
        Mono float32 signal.
    sr : int
        Sample rate.
    stretch : float
        Duration multiplier (>1.0).
    window_seconds : float
        Analysis window length in seconds.

    Returns
    -------
    np.ndarray
        Stretched signal (float32).
    """
    import numpy as np

    if stretch <= 0:
        raise ValueError("stretch must be > 0")
    if window_seconds <= 0:
        raise ValueError("window_seconds must be > 0")

    # Window size as power of 2
    wsize = int(window_seconds * sr)
    wsize = max(wsize, 16)
    wsize = 1 << int(math.ceil(math.log2(wsize)))

    # Synthesis hop fixed (COLA with Hann); analysis hop shrinks with stretch
    hop_out = wsize // 4
    hop_in = max(1, int(hop_out / stretch))

    win = hann_window(wsize)

    # Pad input to avoid boundary issues
    x = x.astype(np.float32)
    xpad = np.pad(x, (wsize, wsize), mode="constant")

    # Output buffer
    out_len = int(len(x) * stretch) + 2 * wsize
    y = np.zeros(out_len, dtype=np.float32)

    in_pos = 0
    out_pos = 0
    frame = np.zeros(wsize, dtype=np.float32)

    while in_pos + wsize <= len(xpad):
        frame[:] = xpad[in_pos:in_pos + wsize]
        frame *= win

        # FFT → preserve magnitudes, randomize phases
        spectrum = np.fft.rfft(frame)
        mag = np.abs(spectrum).astype(np.float32)
        rand_phase = np.exp(
            1j * (2.0 * np.pi * np.random.random(len(mag)))
        ).astype(np.complex64)
        new_spec = mag * rand_phase

        # iFFT → window → overlap-add
        out_frame = np.fft.irfft(new_spec, n=wsize).astype(np.float32)
        out_frame *= win

        end = out_pos + wsize
        if end > len(y):
            y = np.pad(y, (0, end - len(y)), mode="constant")
        y[out_pos:end] += out_frame

        in_pos += hop_in
        out_pos += hop_out

    # Trim padding, normalize to prevent clipping
    y = y[wsize:out_pos + wsize]
    peak = np.max(np.abs(y)) if len(y) else 1.0
    if peak > 0:
        y = y / max(1.0, peak * 1.01)

    return y


def paulstretch(audio, sr, stretch, window_seconds):
    """
    Paulstretch for mono or multichannel audio.

    Parameters
    ----------
    audio : np.ndarray
        1-D (mono) or 2-D (samples, channels).
    sr : int
        Sample rate.
    stretch : float
        Duration multiplier.
    window_seconds : float
        Analysis window in seconds.

    Returns
    -------
    np.ndarray
        Stretched audio (float32), same channel count as input.
    """
    import numpy as np

    if audio.ndim == 1:
        return paulstretch_channel(audio, sr, stretch, window_seconds)

    # Multi-channel: process each channel separately
    chans = []
    for ch in range(audio.shape[1]):
        print(f"  Processing channel {ch + 1}/{audio.shape[1]}...")
        chans.append(
            paulstretch_channel(audio[:, ch], sr, stretch, window_seconds)
        )

    # Align to equal length
    maxlen = max(len(c) for c in chans)
    out = np.zeros((maxlen, len(chans)), dtype=np.float32)
    for i, c in enumerate(chans):
        out[:len(c), i] = c
    return out


def main():
    if len(sys.argv) != 5:
        print("Usage: python paulstretch.py input.wav output.wav "
              "stretch window_seconds")
        print("  stretch:        >1.0 (e.g. 8 = 8x longer)")
        print("  window_seconds: 0.1-1.0 (larger = smoother)")
        print("Example: python paulstretch.py in.wav out.wav 8 0.25")
        sys.exit(1)

    # Check dependencies before doing anything
    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav = sys.argv[1]
    out_wav = sys.argv[2]
    stretch = float(sys.argv[3])
    window_seconds = float(sys.argv[4])

    # Validate parameters
    if stretch <= 0:
        print("ERROR: stretch must be > 0", file=sys.stderr)
        sys.exit(1)
    if window_seconds <= 0:
        print("ERROR: window_seconds must be > 0", file=sys.stderr)
        sys.exit(1)

    # Validate input file
    if not os.path.isfile(in_wav):
        print(f"ERROR: Input file not found: {in_wav}", file=sys.stderr)
        sys.exit(1)

    # Ensure output directory exists
    out_dir = os.path.dirname(out_wav)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)

    dur_in = len(audio) / sr
    print(f"  Input: {in_wav}  ({dur_in:.2f}s  SR={sr})")
    print(f"  Stretch: {stretch}x | Window: {window_seconds}s")
    print(f"  Expected output: ~{dur_in * stretch:.1f}s")

    out = paulstretch(audio, sr, stretch, window_seconds)

    sf.write(out_wav, out, sr)
    dur_out = len(out) / sr
    print(f"OK: wrote {out_wav}  ({dur_out:.2f}s)")


if __name__ == "__main__":
    main()
