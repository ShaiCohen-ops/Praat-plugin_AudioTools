"""
dereverberation.py  –  Blind dereverberation using WPE (nara_wpe)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage:
    python dereverberation.py input.wav output.wav iterations delay filter_length

    iterations:    number of WPE iterations (5-20, more = stronger, default 10)
    delay:         delay in frames (2-5, default 3)
    filter_length: prediction filter length (10-30, default 15)
"""

import sys
import os


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
    try:
        import nara_wpe  # noqa: F401
    except ImportError:
        missing.append("nara_wpe")

    if missing:
        print("ERROR: Missing required Python packages:", ", ".join(missing),
              file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing),
              file=sys.stderr)
        sys.exit(1)


def dereverb(audio, sr, iterations, delay, filter_length):
    """
    Apply WPE blind dereverberation.

    Parameters
    ----------
    audio : np.ndarray
        Input audio, 1-D (mono) or 2-D (samples, channels).
    sr : int
        Sample rate.
    iterations : int
        WPE iterations (5-20).
    delay : int
        WPE frame delay (2-5).
    filter_length : int
        Prediction filter taps (10-30).

    Returns
    -------
    np.ndarray
        Dereverberated audio (float32), same shape as input.
    """
    import numpy as np
    from nara_wpe.wpe import wpe
    from nara_wpe.utils import stft, istft

    # WPE works best on float64
    audio = audio.astype(np.float64)
    mono_input = audio.ndim == 1

    # Always work in (channels, samples) shape
    if mono_input:
        audio = audio[np.newaxis, :]   # (1, samples)
    elif audio.ndim == 2:
        audio = audio.T               # (channels, samples)

    n_ch, n_samples = audio.shape

    # STFT parameters
    size  = 512
    shift = 256

    print(f"  Channels: {n_ch}  |  Samples: {n_samples}  |  SR: {sr}")
    print(f"  STFT size: {size}  shift: {shift}")
    print(f"  WPE — iterations: {iterations}  delay: {delay}  "
          f"filter_length: {filter_length}")

    # STFT  →  (freq_bins, frames, channels)
    Y = np.stack(
        [stft(audio[ch], size=size, shift=shift) for ch in range(n_ch)],
        axis=-1
    )

    # Limit processing to 8 kHz — reverb is mostly low/mid frequency
    max_freq_hz = 8000
    max_bin = min(Y.shape[0], int(max_freq_hz / (sr / size)) + 1)
    Y_low  = Y[:max_bin, :, :]
    Y_high = Y[max_bin:, :, :]

    print(f"  Processing {max_bin}/{Y.shape[0]} frequency bins "
          f"(up to {max_freq_hz} Hz)...")

    # WPE expects (freq_bins, channels, frames)
    Y_wpe = Y_low.transpose(0, 2, 1)

    X_wpe = wpe(
        Y_wpe,
        taps=filter_length,
        delay=delay,
        iterations=iterations,
        statistics_mode='full'
    )

    # Reassemble full spectrum — high bins unchanged
    X_low = X_wpe.transpose(0, 2, 1)
    X = np.concatenate([X_low, Y_high], axis=0)

    # iSTFT per channel
    out_channels = []
    for ch in range(n_ch):
        x = istft(X[:, :, ch], size=size, shift=shift)
        # Match length to input
        if len(x) > n_samples:
            x = x[:n_samples]
        elif len(x) < n_samples:
            x = np.pad(x, (0, n_samples - len(x)))
        out_channels.append(x)

    output = np.stack(out_channels, axis=0)  # (channels, samples)

    # Normalize — only attenuate if peak exceeds 0.95 (preserve dynamics)
    peak = np.max(np.abs(output))
    if peak > 0:
        output = output / max(1.0, peak / 0.95)

    # Back to original shape
    if mono_input:
        return output[0].astype(np.float32)
    else:
        return output.T.astype(np.float32)  # (samples, channels)


def main():
    if len(sys.argv) != 6:
        print("Usage: python dereverberation.py input.wav output.wav "
              "iterations delay filter_length")
        print("  iterations:    5-20  (default 10, more = stronger)")
        print("  delay:         2-5   (default 3)")
        print("  filter_length: 10-30 (default 15, longer = more removal)")
        sys.exit(1)

    # Check dependencies before doing anything
    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav        = sys.argv[1]
    out_wav       = sys.argv[2]
    iterations    = int(sys.argv[3])
    delay         = int(sys.argv[4])
    filter_length = int(sys.argv[5])

    # Validate parameters
    iterations    = max(1, min(50, iterations))
    delay         = max(1, min(10, delay))
    filter_length = max(5, min(60, filter_length))

    # Validate input file
    if not os.path.isfile(in_wav):
        print(f"ERROR: Input file not found: {in_wav}", file=sys.stderr)
        sys.exit(1)

    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)

    print(f"  Input: {in_wav}  ({len(audio)/sr:.2f}s  SR={sr})")

    output = dereverb(audio, sr, iterations, delay, filter_length)

    sf.write(out_wav, output, sr)
    print(f"OK: wrote {out_wav}")


if __name__ == "__main__":
    main()
