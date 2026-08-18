#!/usr/bin/env python3
"""
stretch.py — HPSS + Phase Vocoder Time-Stretching  v2.3

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Pipeline:
    1. Load audio
    2. High-resolution STFT  (N=4096, hop=N//8)
    3. HPSS — split into harmonic (H) and percussive (P) spectrograms
    4. Harmonic: phase-vocoder stretch → ISTFT  (pitch-preserving)
    5. Percussive: WSOLA waveform-similarity overlap-add stretch
       (pitch- and transient-preserving — no rate-change detuning)
    6. Recombine H + P waveforms
    7. Write output WAV + stats

Changelog v2.3:
    - Stereo/multichannel percussive stretching now uses one linked WSOLA
      alignment path for all channels, preventing independent channel offset
      choices from destabilising the stereo image at stronger stretch factors.
    - Very short percussive inputs (<128 samples) use a safe pad/trim path
      instead of entering a 128-sample WSOLA window and crashing.

Changelog v2.2:
    - Percussive band now stretched with WSOLA instead of resample().
      Resampling changed playback rate, which slowed attacks and pitched
      the percussion DOWN by the stretch factor (so it drifted out of tune
      with the pitch-preserved harmonic layer). WSOLA changes duration only.
    - n_fft is now forced even; odd values broke the forward/inverse STFT
      window-size round-trip ((n_bins-1)*2 != n_fft for odd n_fft).

Dependencies: numpy scipy soundfile  (no librosa)
"""

import sys
import os
import math


def check_dependencies():
    missing = []
    for pkg in ["numpy", "scipy", "soundfile"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing),
              file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing),
              file=sys.stderr)
        sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════
# STFT / ISTFT  (pure numpy, Hann window, OLA)
# ═══════════════════════════════════════════════════════════════════════════

def _hann(n):
    import numpy as np
    return (0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(n) / (n - 1))
            ).astype(np.float64)


def forward_stft(y, n_fft, hop):
    """Forward STFT. Returns complex array (n_bins, n_frames)."""
    import numpy as np
    win   = _hann(n_fft)
    n_pad = n_fft // 2
    y_pad = np.concatenate([np.zeros(n_pad), y, np.zeros(n_pad + n_fft)])
    n_frames = max(1, (len(y_pad) - n_fft) // hop + 1)
    n_bins   = n_fft // 2 + 1
    S = np.zeros((n_bins, n_frames), dtype=np.complex128)
    for fi in range(n_frames):
        st = fi * hop
        S[:, fi] = np.fft.rfft(y_pad[st:st + n_fft] * win)
    return S


def inverse_stft(S, hop, target_len=None):
    """Inverse STFT with OLA normalisation. Returns float64 array."""
    import numpy as np
    n_bins, n_frames = S.shape
    n_fft = (n_bins - 1) * 2
    win    = _hann(n_fft)
    win_sq = win ** 2
    n_pad  = n_fft // 2

    buf_len  = n_frames * hop + n_fft
    out_buf  = np.zeros(buf_len, dtype=np.float64)
    norm_buf = np.zeros(buf_len, dtype=np.float64)

    for fi in range(n_frames):
        st = fi * hop
        frame = np.fft.irfft(S[:, fi], n=n_fft).real * win
        out_buf[st:st + n_fft]  += frame
        norm_buf[st:st + n_fft] += win_sq

    norm_buf = np.maximum(norm_buf, 1e-10)
    out = (out_buf / norm_buf)[n_pad:]

    if target_len is not None:
        if len(out) >= target_len:
            out = out[:target_len]
        else:
            out = np.concatenate([out, np.zeros(target_len - len(out))])
    return out.astype(np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# HPSS  (median filtering on magnitude spectrogram)
# ═══════════════════════════════════════════════════════════════════════════

def hpss_complex(S, margin=3.0, kernel_h=31, kernel_p=31):
    """
    Harmonic-Percussive Source Separation on complex STFT.
    Returns (S_harmonic, S_percussive) as complex spectrograms.

    margin controls mask hardness (higher = more separation).
    """
    import numpy as np
    from scipy.ndimage import median_filter

    mag = np.abs(S)

    # Harmonic enhanced: median along time axis (horizontal)
    H_mag = median_filter(mag, size=(1, kernel_h)).astype(np.float64)
    # Percussive enhanced: median along frequency axis (vertical)
    P_mag = median_filter(mag, size=(kernel_p, 1)).astype(np.float64)

    # Soft Wiener-type masks with margin exponent
    p = margin
    H_p = H_mag ** p
    P_p = P_mag ** p
    total = H_p + P_p + 1e-10
    mask_H = H_p / total
    mask_P = P_p / total

    return S * mask_H, S * mask_P


# ═══════════════════════════════════════════════════════════════════════════
# Phase Vocoder  (stretch harmonic component)
# ═══════════════════════════════════════════════════════════════════════════

def phase_vocoder_stretch(S, stretch_factor, hop):
    """
    Phase vocoder time-stretch of complex STFT.
    stretch_factor > 1 → longer, < 1 → shorter.
    Returns stretched complex STFT.
    """
    import numpy as np

    n_bins, n_frames_in = S.shape
    n_fft = (n_bins - 1) * 2
    n_frames_out = max(1, int(math.ceil(n_frames_in * stretch_factor)))

    mag   = np.abs(S)
    phase = np.angle(S)

    # Expected phase advance per hop for each bin
    omega = 2.0 * np.pi * np.arange(n_bins) / n_fft * hop

    # Pre-compute instantaneous frequencies from input phase
    dp = np.diff(phase, axis=1)
    dp = dp - omega[:, np.newaxis]
    dp = dp - 2.0 * np.pi * np.round(dp / (2.0 * np.pi))
    inst_freq = omega[:, np.newaxis] + dp  # (n_bins, n_frames_in-1)

    # Synthesis
    S_out = np.zeros((n_bins, n_frames_out), dtype=np.complex128)
    ph_acc = phase[:, 0].copy()

    for fo in range(n_frames_out):
        # Fractional input frame position
        fi_f  = fo / stretch_factor
        fi_lo = min(int(fi_f), n_frames_in - 1)
        fi_hi = min(fi_lo + 1, n_frames_in - 1)
        alpha = fi_f - fi_lo

        # Interpolate magnitude
        m = (1.0 - alpha) * mag[:, fi_lo] + alpha * mag[:, fi_hi]

        S_out[:, fo] = m * np.exp(1j * ph_acc)

        # Advance phase accumulator using instantaneous frequency
        if fi_lo < inst_freq.shape[1]:
            ifreq = (1.0 - alpha) * inst_freq[:, fi_lo]
            if fi_hi < inst_freq.shape[1]:
                ifreq += alpha * inst_freq[:, fi_hi]
            ph_acc += ifreq
        else:
            ph_acc += omega

    return S_out


# ═══════════════════════════════════════════════════════════════════════════
# Percussive stretch (WSOLA — preserves pitch AND transient sharpness)
# ═══════════════════════════════════════════════════════════════════════════

def stretch_percussive(y_P, stretch_factor, target_len):
    """
    WSOLA (waveform-similarity overlap-add) time-stretch of the percussive
    band. This changes DURATION only: pitch is preserved and transients
    stay sharp, because frames are overlap-added at the ORIGINAL sample
    rate and a similarity search aligns each new frame to the waveform
    continuation of the previous one (so attacks are not chopped mid-cycle).

    This replaces the earlier resample() approach, which time-stretched by
    changing playback rate — that slowed attacks and pitched the whole
    percussive band down by the stretch factor.
    """
    import numpy as np

    y = y_P.astype(np.float64)
    n = len(y)

    # Trivial / passthrough cases
    if n < 128 or abs(stretch_factor - 1.0) < 1e-6:
        if len(y) >= target_len:
            return y[:target_len]
        return np.concatenate([y, np.zeros(target_len - len(y))])

    # Frame geometry (even window, 50 % synthesis overlap)
    W    = min(1024, max(128, (n // 16) // 2 * 2))
    if W < 64:
        W = 64
    Hs   = W // 2                                   # synthesis hop
    L    = W - Hs                                   # overlap length
    Ha   = max(1, int(round(Hs / stretch_factor)))  # analysis hop
    seek = max(1, W // 4)                           # similarity search radius
    win  = np.hanning(W)

    out_len = target_len + W
    out = np.zeros(out_len, dtype=np.float64)
    ow  = np.zeros(out_len, dtype=np.float64)

    # First frame copied straight from the input start
    out[:W] += y[:W] * win
    ow[:W]  += win
    prev = 0

    m = 1
    while True:
        s_pos = m * Hs
        if s_pos + W > out_len:
            break
        nominal = m * Ha

        # Reference = how the previously placed frame would naturally continue
        ref = y[prev + Hs: prev + Hs + L]
        if len(ref) < L:
            ref = np.pad(ref, (0, L - len(ref)))

        lo = max(0, nominal - seek)
        hi = min(n - W, nominal + seek)
        if hi < lo:
            break

        seg = y[lo: hi + L]
        if len(seg) < L:
            best_off = lo
        else:
            # Vectorised normalised cross-correlation across the search range
            cc   = np.correlate(seg, ref, mode="valid")        # (hi-lo+1,)
            sq   = seg ** 2
            csum = np.concatenate([[0.0], np.cumsum(sq)])
            energy    = csum[L:] - csum[:-L]                    # window energies
            cand_norm = np.sqrt(np.maximum(energy, 0.0)) + 1e-9
            score    = cc / cand_norm[:len(cc)]
            best_off = lo + int(np.argmax(score))

        frame = y[best_off: best_off + W]
        if len(frame) < W:
            frame = np.pad(frame, (0, W - len(frame)))

        out[s_pos: s_pos + W] += frame * win
        ow[s_pos: s_pos + W]  += win
        prev = best_off
        m += 1

    ow  = np.maximum(ow, 1e-6)
    out = (out / ow)[:target_len]
    if len(out) < target_len:
        out = np.concatenate([out, np.zeros(target_len - len(out))])
    return out.astype(np.float64)


def stretch_percussive_linked(y_P_multi, stretch_factor, target_len):
    """Linked multichannel WSOLA for the percussive component.

    One similarity-search path is derived from a phase-safe reference and the
    SAME analysis offsets / OLA windows are applied to every channel.  This
    preserves inter-channel timing and image stability.  Mono processing keeps
    using stretch_percussive() so the established mono sound is unchanged.
    """
    import numpy as np

    y = np.asarray(y_P_multi, dtype=np.float64)
    if y.ndim == 1:
        return stretch_percussive(y, stretch_factor, target_len)[:, None]
    n, n_ch = y.shape

    if n < 128 or abs(stretch_factor - 1.0) < 1e-6:
        if n >= target_len:
            return y[:target_len].copy()
        return np.vstack([y, np.zeros((target_len - n, n_ch), dtype=np.float64)])

    # Phase-safe reference: preserve the ordinary channel mean, but if that
    # nearly cancels relative to the strongest channel, use that channel only.
    mean_ref = y.mean(axis=1)
    ch_rms = np.sqrt(np.mean(y * y, axis=0) + 1e-18)
    strongest = int(np.argmax(ch_rms))
    mean_rms = float(np.sqrt(np.mean(mean_ref * mean_ref) + 1e-18))
    if ch_rms[strongest] > 1e-12 and mean_rms < 0.10 * ch_rms[strongest]:
        ref_signal = y[:, strongest]
    else:
        ref_signal = mean_ref

    W    = min(1024, max(128, (n // 16) // 2 * 2))
    W    = min(W, n)
    if W % 2:
        W -= 1
    W    = max(64, W)
    Hs   = W // 2
    L    = W - Hs
    Ha   = max(1, int(round(Hs / stretch_factor)))
    seek = max(1, W // 4)
    win  = np.hanning(W)

    out_len = target_len + W
    out = np.zeros((out_len, n_ch), dtype=np.float64)
    ow  = np.zeros(out_len, dtype=np.float64)

    out[:W, :] += y[:W, :] * win[:, None]
    ow[:W]     += win
    prev = 0

    m = 1
    while True:
        s_pos = m * Hs
        if s_pos + W > out_len:
            break
        nominal = m * Ha

        ref = ref_signal[prev + Hs: prev + Hs + L]
        if len(ref) < L:
            ref = np.pad(ref, (0, L - len(ref)))

        lo = max(0, nominal - seek)
        hi = min(n - W, nominal + seek)
        if hi < lo:
            break

        seg = ref_signal[lo: hi + L]
        if len(seg) < L:
            best_off = lo
        else:
            cc   = np.correlate(seg, ref, mode="valid")
            sq   = seg ** 2
            csum = np.concatenate([[0.0], np.cumsum(sq)])
            energy    = csum[L:] - csum[:-L]
            cand_norm = np.sqrt(np.maximum(energy, 0.0)) + 1e-9
            score     = cc / cand_norm[:len(cc)]
            best_off  = lo + int(np.argmax(score))

        frame = y[best_off: best_off + W, :]
        if len(frame) < W:
            frame = np.pad(frame, ((0, W - len(frame)), (0, 0)))

        out[s_pos: s_pos + W, :] += frame * win[:, None]
        ow[s_pos: s_pos + W]     += win
        prev = best_off
        m += 1

    ow = np.maximum(ow, 1e-6)
    out = (out / ow[:, None])[:target_len, :]
    if len(out) < target_len:
        out = np.vstack([out, np.zeros((target_len - len(out), n_ch), dtype=np.float64)])
    return out.astype(np.float64)


# ═══════════════════════════════════════════════════════════════════════════
# Single-channel processing pipeline
# ═══════════════════════════════════════════════════════════════════════════

N_FFT   = 4096
HOP_DIV = 8
MARGIN  = 3.0


def process_channel(y, sr, stretch_factor, n_fft=N_FFT, margin=MARGIN):
    """Process one mono channel. Returns (y_out, h_rms, p_rms)."""
    import numpy as np

    hop        = n_fft // HOP_DIV
    orig_len   = len(y)
    target_len = int(round(orig_len * stretch_factor))

    # STFT
    S = forward_stft(y, n_fft, hop)

    # HPSS
    S_H, S_P = hpss_complex(S, margin=margin)

    # Harmonic: phase vocoder stretch
    S_H_s = phase_vocoder_stretch(S_H, stretch_factor, hop)
    y_H   = inverse_stft(S_H_s, hop, target_len=target_len)

    # Percussive: WSOLA
    y_P   = inverse_stft(S_P, hop, target_len=orig_len)
    y_P_s = stretch_percussive(y_P, stretch_factor, target_len)

    # RMS for stats
    h_rms = float(np.sqrt(np.mean(y_H ** 2) + 1e-12))
    p_rms = float(np.sqrt(np.mean(y_P_s ** 2) + 1e-12))

    # Recombine
    ml    = min(len(y_H), len(y_P_s))
    y_out = y_H[:ml] + y_P_s[:ml]

    return y_out.astype(np.float64), h_rms, p_rms


# ═══════════════════════════════════════════════════════════════════════════
# Stats writer
# ═══════════════════════════════════════════════════════════════════════════

def write_stats(path, stats):
    with open(path, "w") as f:
        for k, v in stats.items():
            f.write("%s=%s\n" % (k, v))


# ═══════════════════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) < 5:
        print("Usage: stretch.py input.wav output.wav stats.txt "
              "stretch_factor [n_fft] [margin]")
        sys.exit(1)

    check_dependencies()

    import numpy as np
    import soundfile as sf

    in_wav         = sys.argv[1]
    out_wav        = sys.argv[2]
    stats_txt      = sys.argv[3]
    stretch_factor = float(sys.argv[4])
    n_fft          = int(sys.argv[5])   if len(sys.argv) > 5 else N_FFT
    margin         = float(sys.argv[6]) if len(sys.argv) > 6 else MARGIN

    if stretch_factor <= 0:
        print("ERROR: stretch_factor must be > 0", file=sys.stderr)
        sys.exit(1)
    n_fft = max(256, min(8192, n_fft))
    # forward_stft uses n_fft bins but inverse_stft re-derives n_fft from the
    # bin count as (n_bins-1)*2, which only round-trips for EVEN n_fft. Snap
    # odd values up so analysis and synthesis windows always match.
    if n_fft % 2 == 1:
        n_fft += 1

    # Load
    print("[HPSS-PV] Loading: %s" % in_wav)
    audio, sr = sf.read(in_wav, always_2d=True, dtype="float64")
    n_ch = audio.shape[1]
    orig_len = audio.shape[0]
    target_len = int(round(orig_len * stretch_factor))

    print("[HPSS-PV] SR=%d  Ch=%d  %.3fs -> %.3fs  (x%.3f)" % (
        sr, n_ch, orig_len / sr, target_len / sr, stretch_factor))
    print("[HPSS-PV] N_FFT=%d  HOP=%d  MARGIN=%.1f" % (
        n_fft, n_fft // HOP_DIV, margin))

    # Process audio. Mono deliberately keeps the established v2.2 path.
    out_chs = []
    h_rms_total = 0.0
    p_rms_total = 0.0
    linked_wsola = 0

    if n_ch == 1:
        print("[HPSS-PV] Channel 1/1...")
        y_out, h_rms, p_rms = process_channel(
            audio[:, 0], sr, stretch_factor, n_fft, margin)
        out_chs.append(y_out)
        h_rms_total = h_rms
        p_rms_total = p_rms
    else:
        # Keep harmonic phase-vocoder processing per channel, but derive ONE
        # WSOLA path for the percussive layer and apply it to all channels.
        # This prevents left/right analysis offsets from drifting apart.
        harmonic_chs = []
        percussive_chs = []
        hop = n_fft // HOP_DIV
        for ch in range(n_ch):
            print("[HPSS-PV] Channel %d/%d decomposition..." % (ch + 1, n_ch))
            y = audio[:, ch]
            S = forward_stft(y, n_fft, hop)
            S_H, S_P = hpss_complex(S, margin=margin)
            S_H_s = phase_vocoder_stretch(S_H, stretch_factor, hop)
            y_H = inverse_stft(S_H_s, hop, target_len=target_len)
            y_P = inverse_stft(S_P, hop, target_len=orig_len)
            harmonic_chs.append(y_H)
            percussive_chs.append(y_P)

        P_multi = np.column_stack(percussive_chs)
        P_stretched = stretch_percussive_linked(P_multi, stretch_factor, target_len)
        linked_wsola = 1

        for ch in range(n_ch):
            y_H = harmonic_chs[ch]
            y_P_s = P_stretched[:, ch]
            ml = min(len(y_H), len(y_P_s))
            out_chs.append((y_H[:ml] + y_P_s[:ml]).astype(np.float64))
            h_rms_total += float(np.sqrt(np.mean(y_H[:ml] ** 2) + 1e-12))
            p_rms_total += float(np.sqrt(np.mean(y_P_s[:ml] ** 2) + 1e-12))

    h_rms_mean = h_rms_total / n_ch
    p_rms_mean = p_rms_total / n_ch

    # Stack channels and normalise
    max_len = max(len(c) for c in out_chs)
    result = np.zeros((max_len, n_ch), dtype=np.float64)
    for i, c in enumerate(out_chs):
        result[:len(c), i] = c

    # Preserve input peak level
    peak_in  = float(np.max(np.abs(audio))) + 1e-9
    peak_out = float(np.max(np.abs(result))) + 1e-9
    result   = result * (peak_in / peak_out)
    result   = np.clip(result, -1.0, 1.0).astype(np.float32)

    out_rms  = float(np.sqrt(np.mean(result.astype(np.float64) ** 2)))
    out_peak = float(np.max(np.abs(result)))

    # Squeeze mono
    if n_ch == 1:
        result = result[:, 0]

    # Write
    # Keep the temporary interchange file floating-point; Praat will import it
    # immediately, so there is no reason to add a PCM16 quantisation pass here.
    sf.write(out_wav, result, sr, subtype="FLOAT")
    print("[HPSS-PV] Wrote: %s" % out_wav)

    # Stats
    in_rms = float(np.sqrt(np.mean(audio.astype(np.float64) ** 2)))
    stats = {
        "stretch_factor":    "%.4f" % stretch_factor,
        "n_fft":             n_fft,
        "hop":               n_fft // HOP_DIV,
        "margin":            "%.1f" % margin,
        "input_duration":    "%.4f" % (orig_len / sr),
        "output_duration":   "%.4f" % (max_len / sr),
        "input_rms":         "%.6f" % in_rms,
        "output_rms":        "%.6f" % out_rms,
        "output_peak":       "%.6f" % out_peak,
        "harmonic_rms":      "%.6f" % h_rms_mean,
        "percussive_rms":    "%.6f" % p_rms_mean,
        "hp_ratio":          "%.4f" % (h_rms_mean / (p_rms_mean + 1e-9)),
        "channels":          n_ch,
        "linked_wsola":      linked_wsola,
    }
    write_stats(stats_txt, stats)
    print("[HPSS-PV] Stats: %s" % stats_txt)
    print("[HPSS-PV] Done.")


if __name__ == "__main__":
    main()
