"""
spectral_morph.py  –  CDP-style spectral morphing via phase vocoder

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage:
    python spectral_morph.py soundA.wav soundB.wav output.wav
           window_s start_morph_s end_morph_s morph_mode curve_type [mix_amount]

    morph_mode : 1 = log-magnitude (A phase)
                 2 = full complex (blend phase)
                 3 = spectral envelope / formant morph (cepstral)
    curve_type : 1 = linear   2 = cosine S-curve   3 = full mix (fixed ratio)
    mix_amount : 0.0-1.0 (only used with curve_type 3, default 0.5)
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


# ------------------------------------------------------------------ helpers --

def hann(n):
    """Classic Hann (raised cosine) window."""
    import numpy as np
    return (0.5 - 0.5 * np.cos(
        2.0 * np.pi * np.arange(n) / (n - 1)
    )).astype(np.float32)


def next_pow2(n):
    """Round up to nearest power of 2."""
    return 1 << int(math.ceil(math.log2(max(n, 1))))


def resample_linear(x, new_len):
    """Simple linear interpolation resample to new_len samples."""
    import numpy as np
    if len(x) == new_len:
        return x
    old_idx = np.linspace(0, len(x) - 1, new_len)
    return np.interp(old_idx, np.arange(len(x)), x).astype(np.float32)


def morph_curve(t, t0, t1, curve_type, mix_amount=0.5):
    """Return morph factor 0..1 at time t given region [t0, t1]."""
    if curve_type == 3:  # full mix — fixed ratio throughout
        return max(0.0, min(1.0, mix_amount))
    if t1 <= t0:
        return 1.0
    u = (t - t0) / (t1 - t0)
    u = max(0.0, min(1.0, u))
    if curve_type == 2:  # cosine S-curve
        return 0.5 - 0.5 * math.cos(math.pi * u)
    return u  # linear


# ----------------------------------------------------------------- cepstral --

def spectral_envelope(mag, order=60):
    """
    Estimate spectral envelope via real cepstrum liftering.
    Returns a smooth envelope of the same length as mag.
    """
    import numpy as np
    log_mag = np.log(mag + 1e-8)
    cep = np.fft.irfft(log_mag)  # real cepstrum
    # lifter: keep only low quefrency
    win = np.zeros_like(cep)
    win[0] = 1.0
    win[1:order] = 2.0
    env_log = np.fft.rfft(cep * win).real
    return np.exp(env_log).astype(np.float32)


# ---------------------------------------------------------------- main morph -

def spectral_morph_channel(a, b, sr, window_s, start_morph_s, end_morph_s,
                           morph_mode, curve_type, mix_amount=0.5):
    """
    Morph a single channel from sound A to sound B.

    Parameters
    ----------
    a, b : np.ndarray
        Mono float32 signals.
    sr : int
        Sample rate.
    window_s : float
        Analysis window in seconds.
    start_morph_s, end_morph_s : float
        Morph region boundaries.
    morph_mode : int
        1=log-magnitude, 2=full-complex, 3=formant/envelope.
    curve_type : int
        1=linear, 2=cosine, 3=full-mix.
    mix_amount : float
        Fixed blend ratio for curve_type 3.

    Returns
    -------
    np.ndarray
        Morphed signal (float32).
    """
    import numpy as np

    wsize = next_pow2(int(window_s * sr))
    wsize = max(wsize, 64)
    hop = wsize // 4

    # Time-align: map shorter signal onto longer
    len_out = max(len(a), len(b))
    a = resample_linear(a, len_out)
    b = resample_linear(b, len_out)

    win = hann(wsize)
    win_sq = win ** 2

    # OLA buffers
    norm = np.zeros(len_out + wsize * 2, dtype=np.float32)
    y = np.zeros(len_out + wsize * 2, dtype=np.float32)

    a_pad = np.pad(a, (wsize // 2, wsize), mode="constant")
    b_pad = np.pad(b, (wsize // 2, wsize), mode="constant")

    frame_idx = 0
    while True:
        in_pos = frame_idx * hop
        if in_pos + wsize > len(a_pad):
            break

        t_mid = (in_pos + wsize / 2 - wsize // 2) / sr
        m = morph_curve(t_mid, start_morph_s, end_morph_s,
                        curve_type, mix_amount)

        fa = a_pad[in_pos:in_pos + wsize] * win
        fb = b_pad[in_pos:in_pos + wsize] * win

        Sa = np.fft.rfft(fa)
        Sb = np.fft.rfft(fb)

        mag_a = np.abs(Sa).astype(np.float32)
        mag_b = np.abs(Sb).astype(np.float32)
        pha_a = np.angle(Sa).astype(np.float32)
        pha_b = np.angle(Sb).astype(np.float32)

        if morph_mode == 1:
            # --- log-magnitude interpolation, keep A phase ---
            log_a = np.log(mag_a + 1e-8)
            log_b = np.log(mag_b + 1e-8)
            mag_out = np.exp((1 - m) * log_a + m * log_b)
            pha_out = pha_a

        elif morph_mode == 2:
            # --- full complex interpolation ---
            mag_out = (1 - m) * mag_a + m * mag_b
            pha_out = pha_a + m * np.angle(
                np.exp(1j * (pha_b - pha_a).astype(np.float64))
            ).astype(np.float32)

        else:
            # --- spectral envelope / formant morph (CDP-style) ---
            env_a = spectral_envelope(mag_a)
            env_b = spectral_envelope(mag_b)
            fine_a = mag_a / (env_a + 1e-8)

            log_env_a = np.log(env_a + 1e-8)
            log_env_b = np.log(env_b + 1e-8)
            env_out = np.exp((1 - m) * log_env_a + m * log_env_b)

            mag_out = fine_a * env_out
            pha_out = pha_a

        # Reconstruct
        S_out = mag_out * np.exp(1j * pha_out.astype(np.float64))
        frame_out = np.fft.irfft(S_out, n=wsize).real.astype(np.float32)
        frame_out *= win

        out_pos = in_pos
        end_pos = out_pos + wsize
        y[out_pos:end_pos] += frame_out
        norm[out_pos:end_pos] += win_sq

        frame_idx += 1

    # OLA normalise
    norm = np.maximum(norm, 1e-8)
    y /= norm

    # Trim
    y = y[wsize // 2:wsize // 2 + len_out]

    # Normalise peak
    peak = np.max(np.abs(y))
    if peak > 0:
        y /= max(1.0, peak * 1.01)

    return y


def spectral_morph(audio_a, audio_b, sr, window_s, start_morph_s,
                   end_morph_s, morph_mode, curve_type, mix_amount=0.5):
    """Handle mono or stereo (process each channel)."""
    import numpy as np

    def to_mono_channels(x):
        if x.ndim == 1:
            return [x]
        return [x[:, ch] for ch in range(x.shape[1])]

    chs_a = to_mono_channels(audio_a)
    chs_b = to_mono_channels(audio_b)

    # Match channel count
    n_ch = max(len(chs_a), len(chs_b))
    while len(chs_a) < n_ch:
        chs_a.append(chs_a[-1])
    while len(chs_b) < n_ch:
        chs_b.append(chs_b[-1])

    out_chs = []
    for ch in range(n_ch):
        print(f"  Processing channel {ch + 1}/{n_ch}...")
        out_chs.append(spectral_morph_channel(
            chs_a[ch].astype(np.float32),
            chs_b[ch].astype(np.float32),
            sr, window_s, start_morph_s, end_morph_s,
            morph_mode, curve_type, mix_amount,
        ))

    if n_ch == 1:
        return out_chs[0]

    max_len = max(len(c) for c in out_chs)
    result = np.zeros((max_len, n_ch), dtype=np.float32)
    for i, c in enumerate(out_chs):
        result[:len(c), i] = c
    return result


# --------------------------------------------------------------------- CLI --

def main():
    if len(sys.argv) not in (9, 10):
        print("Usage: python spectral_morph.py soundA.wav soundB.wav output.wav "
              "window_s start_morph_s end_morph_s morph_mode curve_type [mix_amount]")
        print("  morph_mode: 1=log-mag  2=full-complex  3=formant/envelope")
        print("  curve_type: 1=linear   2=cosine   3=full-mix (needs mix_amount 0-1)")
        sys.exit(1)

    # Check dependencies before heavy imports
    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_a = sys.argv[1]
    in_b = sys.argv[2]
    out_wav = sys.argv[3]
    window_s = float(sys.argv[4])
    start_s = float(sys.argv[5])
    end_s = float(sys.argv[6])
    morph_mode = int(sys.argv[7])
    curve_type = int(sys.argv[8])
    mix_amount = float(sys.argv[9]) if len(sys.argv) == 10 else 0.5

    # Validate input files
    for path, label in [(in_a, "A"), (in_b, "B")]:
        if not os.path.isfile(path):
            print(f"ERROR: Input file {label} not found: {path}",
                  file=sys.stderr)
            sys.exit(1)

    # Validate parameters
    if morph_mode not in (1, 2, 3):
        print("ERROR: morph_mode must be 1, 2, or 3", file=sys.stderr)
        sys.exit(1)
    if curve_type not in (1, 2, 3):
        print("ERROR: curve_type must be 1, 2, or 3", file=sys.stderr)
        sys.exit(1)
    mix_amount = max(0.0, min(1.0, mix_amount))
    if window_s <= 0:
        print("ERROR: window_s must be > 0", file=sys.stderr)
        sys.exit(1)

    # Ensure output directory exists
    out_dir = os.path.dirname(out_wav)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    audio_a, sr_a = sf.read(in_a, always_2d=False)
    audio_b, sr_b = sf.read(in_b, always_2d=False)

    print(f"  A: {in_a}  ({len(audio_a)/sr_a:.2f}s  SR={sr_a})")
    print(f"  B: {in_b}  ({len(audio_b)/sr_b:.2f}s  SR={sr_b})")

    # Resample B to A's sample rate if needed
    if sr_b != sr_a:
        print(f"  Resampling B from {sr_b} to {sr_a} Hz...")
        try:
            from scipy.signal import resample_poly
            from fractions import Fraction
            r = Fraction(sr_a, sr_b).limit_denominator(100)
            if audio_b.ndim == 1:
                audio_b = resample_poly(
                    audio_b, r.numerator, r.denominator
                ).astype(np.float32)
            else:
                audio_b = np.stack([
                    resample_poly(
                        audio_b[:, ch], r.numerator, r.denominator
                    ).astype(np.float32)
                    for ch in range(audio_b.shape[1])
                ], axis=1)
        except ImportError:
            print("ERROR: scipy required for sample rate conversion "
                  "(pip install scipy)", file=sys.stderr)
            sys.exit(1)

    audio_a = np.asarray(audio_a, dtype=np.float32)
    audio_b = np.asarray(audio_b, dtype=np.float32)

    mode_names = {1: "log-magnitude", 2: "full-complex", 3: "formant/envelope"}
    curve_names = {1: "linear", 2: "cosine", 3: f"full-mix({mix_amount:.2f})"}
    print(f"  Mode: {mode_names.get(morph_mode, '?')} | "
          f"Curve: {curve_names.get(curve_type, '?')} | "
          f"Window: {window_s*1000:.0f}ms")

    out = spectral_morph(audio_a, audio_b, sr_a,
                         window_s, start_s, end_s,
                         morph_mode, curve_type, mix_amount)

    sf.write(out_wav, out, sr_a)
    dur_out = len(out) / sr_a if out.ndim == 1 else len(out) / sr_a
    print(f"OK: wrote {out_wav}  ({dur_out:.2f}s)")


if __name__ == "__main__":
    main()
