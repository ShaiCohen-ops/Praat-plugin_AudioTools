"""
waveset_distortion.py  –  CDP-style waveset distortion via numpy

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Segments audio at zero crossings and applies per-waveset transformations.

Usage:
    python waveset_distortion.py input.wav output.wav type amount preserve_length

    type:   1=Repeat  2=Skip  3=Reverse  4=Stretch  5=Compress
            6=Randomize  7=Amplitude
    amount: float, meaning depends on type
    preserve_length: 0 or 1
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


# ------------------------------------------------------------------ helpers --

def find_zero_crossings(samples):
    """Return indices where signal crosses zero (sign changes)."""
    import numpy as np
    signs = np.sign(samples)
    signs[signs == 0] = 1  # treat exact zero as positive
    crossings = np.where(np.diff(signs) != 0)[0] + 1
    return crossings


def get_wavesets(crossings):
    """Return list of (start, end) index pairs for each waveset."""
    return [(crossings[i], crossings[i + 1])
            for i in range(len(crossings) - 1)]


def micro_fade(chunk, fade_samples=4):
    """
    Apply a tiny linear fade-in and fade-out to a waveset chunk.
    This eliminates clicks at boundaries caused by non-zero
    sample values at zero crossing points.
    """
    import numpy as np
    n = len(chunk)
    if n < fade_samples * 2:
        return chunk
    chunk = chunk.copy()
    fade = np.linspace(0.0, 1.0, fade_samples)
    chunk[:fade_samples]  *= fade          # fade in
    chunk[-fade_samples:] *= fade[::-1]    # fade out
    return chunk


def resample_waveset(samples, new_length):
    """Linear interpolation resample of a waveset to new_length samples."""
    import numpy as np
    if len(samples) == new_length:
        return samples
    old_idx = np.linspace(0, len(samples) - 1, new_length)
    return np.interp(old_idx, np.arange(len(samples)), samples).astype(
        np.float64)


# ---------------------------------------------------------------- distortion -

def process_wavesets(samples, sr, dist_type, amount, preserve_length):
    """
    Apply waveset distortion.

    Parameters
    ----------
    samples : np.ndarray
        Mono float32 signal.
    sr : int
        Sample rate.
    dist_type : int
        1=Repeat 2=Skip 3=Reverse 4=Stretch 5=Compress 6=Randomize 7=Amplitude.
    amount : float
        Effect intensity (meaning varies by type).
    preserve_length : bool
        If True, resample output to match input length.

    Returns
    -------
    np.ndarray
        Processed signal (float32).
    """
    import numpy as np

    crossings = find_zero_crossings(samples)
    if len(crossings) < 2:
        raise ValueError("Not enough zero crossings found.")

    wavesets = get_wavesets(crossings)
    n = len(wavesets)
    print(f"  Zero crossings: {len(crossings)}  |  Wavesets: {n}")

    chunks = []

    # ---- 1: REPEAT ----
    if dist_type == 1:
        reps = max(1, round(amount))
        for start, end in wavesets:
            ws = samples[start:end]
            chunks.append(micro_fade(ws))
            for r in range(1, reps):
                chunks.append(micro_fade(ws * (0.8 ** r)))

    # ---- 2: SKIP ----
    elif dist_type == 2:
        rng = np.random.default_rng()
        skipped = 0
        for start, end in wavesets:
            if rng.random() > (1.0 / max(amount, 1.0)):
                chunks.append(micro_fade(samples[start:end]))
            else:
                skipped += 1
        print(f"  Skipped: {skipped} wavesets")

    # ---- 3: REVERSE ----
    elif dist_type == 3:
        for start, end in wavesets:
            chunks.append(micro_fade(samples[start:end][::-1].copy()))

    # ---- 4: STRETCH ----
    elif dist_type == 4:
        for start, end in wavesets:
            ws = samples[start:end]
            new_len = max(2, round(len(ws) * amount))
            chunks.append(micro_fade(resample_waveset(ws, new_len)))

    # ---- 5: COMPRESS ----
    elif dist_type == 5:
        for start, end in wavesets:
            ws = samples[start:end]
            new_len = max(2, round(len(ws) / max(amount, 1e-6)))
            chunks.append(micro_fade(resample_waveset(ws, new_len)))

    # ---- 6: RANDOMIZE ----
    elif dist_type == 6:
        indices = list(range(n))
        n_shuffle = min(n, round(n * amount))
        rng = np.random.default_rng()
        for _ in range(n_shuffle):
            i, j = rng.integers(0, n, size=2)
            indices[i], indices[j] = indices[j], indices[i]
        for idx in indices:
            start, end = wavesets[idx]
            chunks.append(micro_fade(samples[start:end]))

    # ---- 7: AMPLITUDE alternating ----
    elif dist_type == 7:
        for i, (start, end) in enumerate(wavesets):
            scale = amount if i % 2 == 0 else 1.0 / max(amount, 1e-6)
            chunks.append(micro_fade(samples[start:end] * scale))

    else:
        raise ValueError(f"Unknown distortion type: {dist_type}")

    if not chunks:
        raise ValueError("No output samples generated.")

    output = np.concatenate(chunks).astype(np.float64)

    # ---- Preserve length ----
    if preserve_length and len(output) != len(samples):
        print(f"  Resampling to preserve length "
              f"({len(output)} → {len(samples)} samples)...")
        output = resample_waveset(output, len(samples))

    # ---- Normalize to 0.95 peak (matches Praat's Scale peak: 0.95) ----
    peak = np.max(np.abs(output))
    if peak > 0:
        output = output * (0.95 / peak)

    return output.astype(np.float32)


# --------------------------------------------------------------------- CLI --

def main():
    if len(sys.argv) != 6:
        print("Usage: python waveset_distortion.py input.wav output.wav "
              "type amount preserve_length")
        print("  type: 1=Repeat 2=Skip 3=Reverse 4=Stretch "
              "5=Compress 6=Randomize 7=Amplitude")
        print("  amount: effect intensity (float)")
        print("  preserve_length: 0 or 1")
        sys.exit(1)

    # Check dependencies before heavy imports
    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav = sys.argv[1]
    out_wav = sys.argv[2]
    dist_type = int(sys.argv[3])
    amount = float(sys.argv[4])
    preserve_len = bool(int(sys.argv[5]))

    # Validate input file
    if not os.path.isfile(in_wav):
        print(f"ERROR: Input file not found: {in_wav}", file=sys.stderr)
        sys.exit(1)

    # Validate parameters
    if dist_type not in range(1, 8):
        print(f"ERROR: type must be 1-7, got {dist_type}", file=sys.stderr)
        sys.exit(1)
    if amount <= 0:
        print("ERROR: amount must be > 0", file=sys.stderr)
        sys.exit(1)

    # Ensure output directory exists
    out_dir = os.path.dirname(out_wav)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    audio, sr = sf.read(in_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)

    # Mono only — take first channel if stereo
    if audio.ndim > 1:
        print("  Stereo input — processing left channel only.")
        mono = audio[:, 0].astype(np.float64)
    else:
        mono = audio.astype(np.float64)

    type_names = {
        1: "Repeat", 2: "Skip", 3: "Reverse", 4: "Stretch",
        5: "Compress", 6: "Randomize", 7: "Amplitude"
    }
    print(f"  Samples: {len(mono)}  |  SR: {sr}  |  "
          f"Type: {type_names.get(dist_type, '?')}  |  Amount: {amount}")

    output = process_wavesets(mono, sr, dist_type, amount, preserve_len)

    sf.write(out_wav, output, sr)
    print(f"OK: wrote {out_wav}  ({len(output)/sr:.3f}s)")


if __name__ == "__main__":
    main()
