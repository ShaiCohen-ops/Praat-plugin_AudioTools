"""
paulstretch.py  –  Extreme time-stretching via spectral phase randomization

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage:
    python paulstretch.py input.wav output.wav stretch window_seconds [seed]

    stretch:        duration multiplier (>0; 1 = phase-smear at original duration)
    window_seconds: analysis window in seconds (typically 0.1-1.0)
    seed:           optional integer random seed for reproducible output

Example:
    python paulstretch.py in.wav out.wav 8 0.25
    python paulstretch.py in.wav out.wav 8 0.25 12345
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

    if missing:
        print("ERROR: Missing required Python packages:", ", ".join(missing),
              file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing),
              file=sys.stderr)
        sys.exit(1)


def hann_window(n):
    """Classic symmetric Hann (raised-cosine) window."""
    import numpy as np
    if n <= 1:
        return np.ones(max(1, n), dtype=np.float32)
    return (0.5 - 0.5 * np.cos(
        2.0 * np.pi * np.arange(n, dtype=np.float64) / (n - 1)
    )).astype(np.float32)


def _window_size_samples(sr, window_seconds):
    """Convert seconds to a near-exact size compatible with 4x overlap."""
    raw = max(16.0, float(window_seconds) * float(sr))
    # The processor uses hop = N/4, so a multiple of four keeps the overlap
    # exactly at 75% while changing the requested physical window by at most
    # two samples. This avoids the large inflation caused by power-of-two FFTs.
    return max(16, 4 * int(round(raw / 4.0)))


def _normalize_peak(audio, ceiling=0.99):
    """Apply one scalar peak normalization only when needed."""
    import numpy as np
    if audio.size == 0:
        return audio.astype(np.float32, copy=False)
    peak = float(np.max(np.abs(audio)))
    if peak > ceiling and peak > 0.0:
        audio = audio * (ceiling / peak)
    return audio.astype(np.float32, copy=False)


def _fade_output_end(y, sr, seconds=0.02):
    """Short cosine fade-out to prevent a hard cut at the requested target length."""
    import numpy as np
    n = min(len(y) // 2, int(round(seconds * sr)))
    if n <= 1:
        return y
    fade = 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, n, dtype=np.float64))
    y[-n:] *= fade.astype(np.float32)
    return y


def paulstretch_channel(x, sr, stretch, window_seconds, rng=None, normalize=True):
    """
    Paulstretch for a single channel.

    Randomizes FFT phases while preserving the magnitude spectrum of each
    analysis frame. The output duration is exactly round(input_length*stretch)
    samples; fractional analysis positions avoid hop-rounding drift.
    """
    import numpy as np

    if stretch <= 0:
        raise ValueError("stretch must be > 0")
    if window_seconds <= 0:
        raise ValueError("window_seconds must be > 0")
    if sr <= 0:
        raise ValueError("sample rate must be > 0")

    x = np.asarray(x, dtype=np.float32)
    if x.ndim != 1:
        raise ValueError("paulstretch_channel expects a mono 1-D signal")
    if len(x) == 0:
        return np.zeros(0, dtype=np.float32)

    if rng is None:
        rng = np.random.default_rng()

    # Keep the user's requested physical window duration (within two samples)
    # instead of silently inflating it to the next power of two.
    wsize = _window_size_samples(sr, window_seconds)
    hop_out = max(1, wsize // 4)  # smooth 4x Hann overlap
    hop_in = hop_out / float(stretch)  # fractional position: no ratio drift
    win = hann_window(wsize)

    target_len = max(1, int(round(len(x) * float(stretch))))
    # Extra tail is needed internally for the last overlap-add frames; it is
    # cropped to target_len below.
    y = np.zeros(target_len + wsize, dtype=np.float32)

    in_pos = 0.0
    out_pos = 0
    frame = np.zeros(wsize, dtype=np.float32)

    while out_pos < target_len:
        i0 = int(in_pos)  # same floor-style stepping as the reference code
        frame.fill(0.0)
        if i0 < len(x):
            ncopy = min(wsize, len(x) - i0)
            frame[:ncopy] = x[i0:i0 + ncopy]
        frame *= win

        spectrum = np.fft.rfft(frame)
        mag = np.abs(spectrum)

        phase = rng.uniform(0.0, 2.0 * np.pi, size=len(mag))
        # DC and Nyquist (for even FFT sizes) must remain real in an rFFT.
        # Keeping their phase at zero makes the "preserve magnitude" claim true
        # for these endpoint bins too.
        phase[0] = 0.0
        if wsize % 2 == 0:
            phase[-1] = 0.0
        new_spec = mag * np.exp(1j * phase)

        out_frame = np.fft.irfft(new_spec, n=wsize).astype(np.float32)
        out_frame *= win

        end = out_pos + wsize
        y[out_pos:end] += out_frame

        in_pos += hop_in
        out_pos += hop_out

    y = y[:target_len]
    y = _fade_output_end(y, sr)
    if normalize:
        y = _normalize_peak(y)
    return y


def paulstretch(audio, sr, stretch, window_seconds, seed=None):
    """Paulstretch for mono or multichannel audio, preserving channel count."""
    import numpy as np

    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim == 1:
        rng = np.random.default_rng(seed)
        return paulstretch_channel(
            audio, sr, stretch, window_seconds, rng=rng, normalize=True
        )
    if audio.ndim != 2:
        raise ValueError("audio must be 1-D mono or 2-D (samples, channels)")
    if audio.shape[1] < 1:
        raise ValueError("audio must contain at least one channel")

    # Independent phase realizations per channel are faithful to the reference
    # stereo implementation and create the characteristic diffuse stereo image.
    seed_seq = np.random.SeedSequence(seed)
    child_seeds = seed_seq.spawn(audio.shape[1])

    chans = []
    for ch in range(audio.shape[1]):
        print(f"  Processing channel {ch + 1}/{audio.shape[1]}...")
        rng = np.random.default_rng(child_seeds[ch])
        chans.append(
            paulstretch_channel(
                audio[:, ch], sr, stretch, window_seconds,
                rng=rng, normalize=False
            )
        )

    out = np.stack(chans, axis=1).astype(np.float32, copy=False)
    # One shared gain scalar preserves the relative balance between channels.
    return _normalize_peak(out)


def main():
    if len(sys.argv) not in (5, 6):
        print("Usage: python paulstretch.py input.wav output.wav "
              "stretch window_seconds [seed]")
        print("  stretch:        >0 (1 = same duration with Paulstretch smear)")
        print("  window_seconds: typically 0.1-1.0 (larger = smoother)")
        print("  seed:           optional integer for reproducible phase randomization")
        print("Example: python paulstretch.py in.wav out.wav 8 0.25")
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav = sys.argv[1]
    out_wav = sys.argv[2]
    try:
        stretch = float(sys.argv[3])
        window_seconds = float(sys.argv[4])
        seed = int(sys.argv[5]) if len(sys.argv) == 6 else None
    except ValueError as exc:
        print(f"ERROR: invalid numeric parameter: {exc}", file=sys.stderr)
        sys.exit(1)

    if stretch <= 0:
        print("ERROR: stretch must be > 0", file=sys.stderr)
        sys.exit(1)
    if window_seconds <= 0:
        print("ERROR: window_seconds must be > 0", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(in_wav):
        print(f"ERROR: Input file not found: {in_wav}", file=sys.stderr)
        sys.exit(1)

    out_dir = os.path.dirname(out_wav)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)

    dur_in = len(audio) / sr
    print(f"  Input: {in_wav}  ({dur_in:.2f}s  SR={sr})")
    print(f"  Stretch: {stretch}x | Window: {window_seconds}s")
    if seed is not None:
        print(f"  Seed: {seed}")
    print(f"  Expected output: {dur_in * stretch:.6f}s")

    out = paulstretch(audio, sr, stretch, window_seconds, seed=seed)

    # Float WAV avoids a second 16-bit quantization stage before Praat re-imports
    # the processed result.
    sf.write(out_wav, out, sr, subtype="FLOAT")
    dur_out = len(out) / sr
    print(f"OK: wrote {out_wav}  ({dur_out:.6f}s, WAV FLOAT)")


if __name__ == "__main__":
    main()
