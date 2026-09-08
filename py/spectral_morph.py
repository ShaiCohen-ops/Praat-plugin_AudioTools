"""
spectral_morph.py  -  CDP-style spectral morphing via phase vocoder

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 5.7.2 (2026)

Usage:
    python spectral_morph.py soundA.wav soundB.wav output.wav
           window_s start_morph_s end_morph_s morph_mode curve_type
           [mix_amount] [length_mode] [debug]

    morph_mode  : 1 = energy-stable log-magnitude (A phase)
                  2 = full complex (blend phase)
                  3 = spectral envelope / formant morph (cepstral)
                  4 = continuous spectral trajectory (log-frequency transport)
    curve_type  : 1 = linear   2 = cosine S-curve   3 = full mix (fixed ratio)
    mix_amount  : 0.0-1.0 (only used with curve_type 3, default 0.5)
    length_mode : 1 = silence-pad shorter to match longer (legacy tail)
                  2 = trim longer to match shorter
                  3 = linear time-stretch shorter to match longer
                      (v4.x legacy; pitches the shorter input)
                  4 = phase-vocoder align shorter to longer (RECOMMENDED;
                      pitch-preserving, prevents endpoint bounce)
    debug       : 0 = off, 1 = write per-frame CSV next to output WAV



Changelog v5.7.2:
    - Added SPECTRAL_MORPH_BACKEND_API = 572 so the Praat wrapper can verify
      that it is paired with a backend that supports PV-align length_mode 4.
      DSP is unchanged from v5.7.

Changelog v5.7:
    - Added length_mode 4: PITCH-PRESERVING PHASE-VOCODER ALIGNMENT. The
      shorter source is stretched to the longer source duration before the
      morph, so both A and B remain defined across the complete morph path.
      This fixes the directional bounce of silence-pad mode when target B is
      shorter: v5.5 deliberately faded back to direct A as B entered padding.
    - The new alignment is the recommended partner for energy-stable
      log-magnitude morphing. It preserves pitch and full output duration while
      retaining every source's complete temporal evolution.
    - Existing length modes 1-3 remain available for compatibility.

Changelog v5.6:
    - Added morph_mode 4: CONTINUOUS SPECTRAL TRAJECTORY. Instead of
      interpolating amplitudes at fixed FFT bins, one-dimensional monotone
      spectral transport moves magnitude mass continuously in log-frequency.
      A 220-Hz component becoming 440 Hz therefore travels through intermediate
      frequencies instead of fading out at 220 while 440 fades in.
    - Mode 4 uses a phase-coherent synthesis state across STFT frames, with
      short circular phase handoffs near m=0 and m=1 so the endpoints remain
      anchored to the real source phases.
    - Transport energy is normalised to the geometric interpolation of the
      source spectral L2 norms, avoiding the severe mid-morph level collapse
      of geometric log-magnitude interpolation on disjoint spectra.
    - Existing modes 1-3 are unchanged for users who want classic
      log-magnitude, complex, or formant-envelope cross-synthesis.

Changelog v5.5:
    - Silence guard is now tied to ARTIFICIAL silence-padding boundaries,
      not threshold-detected end-of-content. Natural trailing silence in a
      same-duration source is therefore preserved as musical content.
    - Debug CSV now reports the actual differential blend weights used by
      the audio path and follows the strongest combined A/B channel.
    - Peak safety is applied once, globally across all output channels,
      preserving multichannel balance when attenuation is required.
    - Output WAV is FLOAT to avoid an unnecessary second PCM16 quantisation.
    - Runtime log reports requested and effective power-of-two FFT window.

Changelog v5.4:
    AUDIO FIX (Python backend): shifted silence-factor ramp.

    Sha's debug CSV revealed that v5.3's silence-boundary math was
    working correctly (b_sil ramped 0 -> 0.25 -> 0.50 -> 0.75 -> 1.0
    across consecutive frames), but the audible "jump" came from a
    different mechanism. In mode 1 (log-magnitude) the geometric mean
    of cello-bin and horn-bin produces small values wherever one input
    has energy and the other doesn't, so during the entire morph the
    output was attenuated to ~ 10% of the inputs' RMS (0.022 vs 0.23).
    When the v5.3 blend kicked in AT the silence boundary, output had
    to climb 15x in ~ 90 ms -- audibly an onset transient.

    v5.4 ends the silence-factor ramp AT the boundary instead of
    centering on it (v5.3 was centered, with sil = 0.5 right at
    the boundary). pre_ramp = 2 * wsize, so the ramp starts ~ 186 ms
    before the silence-pad boundary at default 60 ms window. As the
    other signal naturally fades toward its boundary, the blend
    gradually replaces the attenuated morph with direct A, smoothing
    the amplitude rise over the whole pre-boundary region. By the time
    the silence boundary is actually reached, output is already at
    direct-A level.

    Predicted out_rms trajectory for Sha's data (cello 4.4s, horn
    2.65s, mode 1, cosine, silence-pad):

      v5.3 actual:   0.020 .. 0.022 .. 0.084 .. 0.170 .. 0.257 .. 0.345
                    (max consecutive ratio 3.7x in 23 ms)

      v5.4 predict:  0.024 .. 0.028 .. 0.054 .. 0.080 .. 0.102 .. 0.130
                       .. 0.156 .. 0.187 .. 0.217 .. 0.230
                    (max consecutive ratio 1.93x; smooth amplitude rise
                     over 207 ms, no perceptible onset)

    Same-duration inputs: both boundaries equal len_out, so both a_sil
    and b_sil ramp together over the final 2 * wsize samples; delta = 0
    throughout the differential blend; output bit-identical to v5.0
    (verified).

Changelog v5.3:
    DIAGNOSTICS: per-frame debug CSV (frame, time, RMS, silence factors,
    blend weights, output RMS).
    AUDIO: time-position-based silence factor replacing v5.2 mag-mean
    approach. Differential blend weights restoring v5.0 bit-identical
    behavior on same-duration inputs.

Changelog v5.2:
    Continuous silence blend with log-domain mag-mean ramp (superseded
    by v5.3 time-position approach, which gave a smooth deterministic
    ramp instead of v5.2's near-binary practical behavior).

Changelog v5.1:
    Binary silence guard introduced (superseded by v5.2 / v5.3 / v5.4).

Changelog v5.0:
    gcd-based exact integer ratio in scipy resample_poly when
    sr_a != sr_b. Length-handling default changed from time-stretch
    (v4.x) to silence-pad, new "Length handling" form field exposing
    three modes (silence pad / trim / time stretch legacy).
"""

import sys
import os
import math

# Machine-readable wrapper/backend compatibility token.
SPECTRAL_MORPH_BACKEND_API = 572


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
    """Simple linear interpolation resample to new_len samples.
    NB: This is a crude time-domain stretch — it changes pitch.
    Used only in length_mode=3 (legacy v4.x time-stretch behavior)."""
    import numpy as np
    if len(x) == new_len:
        return x
    old_idx = np.linspace(0, len(x) - 1, new_len)
    return np.interp(old_idx, np.arange(len(x)), x).astype(np.float32)


def _pv_forward_stft(y, n_fft, hop):
    """Centered Hann STFT used only for pitch-preserving length alignment."""
    import numpy as np
    y = np.asarray(y, dtype=np.float64)
    win = hann(n_fft).astype(np.float64)
    n_pad = n_fft // 2
    y_pad = np.concatenate([
        np.zeros(n_pad, dtype=np.float64), y,
        np.zeros(n_pad + n_fft, dtype=np.float64)
    ])
    n_frames = max(1, (len(y_pad) - n_fft) // hop + 1)
    S = np.zeros((n_fft // 2 + 1, n_frames), dtype=np.complex128)
    for fi in range(n_frames):
        st = fi * hop
        S[:, fi] = np.fft.rfft(y_pad[st:st + n_fft] * win)
    return S


def _pv_inverse_stft(S, hop, target_len):
    """OLA-normalised inverse STFT with exact target length."""
    import numpy as np
    n_bins, n_frames = S.shape
    n_fft = (n_bins - 1) * 2
    win = hann(n_fft).astype(np.float64)
    win_sq = win * win
    n_pad = n_fft // 2
    buf_len = n_frames * hop + n_fft
    out_buf = np.zeros(buf_len, dtype=np.float64)
    norm_buf = np.zeros(buf_len, dtype=np.float64)
    for fi in range(n_frames):
        st = fi * hop
        frame = np.fft.irfft(S[:, fi], n=n_fft).real * win
        out_buf[st:st + n_fft] += frame
        norm_buf[st:st + n_fft] += win_sq
    safe = norm_buf > 1e-10
    out_buf[safe] /= norm_buf[safe]
    out_buf[~safe] = 0.0
    out = out_buf[n_pad:]
    if len(out) >= target_len:
        out = out[:target_len]
    else:
        out = np.pad(out, (0, target_len - len(out)))
    return out.astype(np.float32)


def phase_vocoder_align_to_length(x, target_len, n_fft):
    """Pitch-preserving time alignment to exactly ``target_len`` samples.

    This is a conventional phase-vocoder stretch used only to make two source
    timelines coextensive before spectral morphing.  Unlike the legacy linear
    resample it changes duration without changing the FFT-bin frequencies.
    """
    import numpy as np
    x = np.asarray(x, dtype=np.float32)
    target_len = int(target_len)
    if target_len <= 0:
        return np.zeros(0, dtype=np.float32)
    if len(x) == target_len:
        return x.copy()
    if len(x) < 2:
        return np.pad(x, (0, max(0, target_len - len(x))))[:target_len].astype(np.float32)

    stretch = target_len / float(len(x))
    n_fft = int(max(64, n_fft))
    # Keep the alignment STFT sensible for very short sources.
    while n_fft > 64 and n_fft > 2 * len(x):
        n_fft //= 2
    n_fft = max(64, n_fft)
    hop = max(1, n_fft // 4)

    S = _pv_forward_stft(x, n_fft, hop)
    n_bins, n_frames_in = S.shape
    if n_frames_in < 2:
        # Pathological short input: preserving pitch is not meaningful; hold the
        # tiny signal rather than frequency-resampling it.
        reps = int(np.ceil(target_len / float(max(1, len(x)))))
        return np.tile(x, reps)[:target_len].astype(np.float32)

    n_frames_out = max(1, int(math.ceil(n_frames_in * stretch)))
    mag = np.abs(S)
    phase = np.angle(S)
    omega = 2.0 * np.pi * np.arange(n_bins, dtype=np.float64) / n_fft * hop

    dp = np.diff(phase, axis=1) - omega[:, None]
    dp -= 2.0 * np.pi * np.round(dp / (2.0 * np.pi))
    inst = omega[:, None] + dp

    Sout = np.zeros((n_bins, n_frames_out), dtype=np.complex128)
    ph_acc = phase[:, 0].copy()
    for fo in range(n_frames_out):
        fi_f = fo / stretch
        fi_lo = min(int(fi_f), n_frames_in - 1)
        fi_hi = min(fi_lo + 1, n_frames_in - 1)
        alpha = fi_f - fi_lo
        mout = (1.0 - alpha) * mag[:, fi_lo] + alpha * mag[:, fi_hi]
        Sout[:, fo] = mout * np.exp(1j * ph_acc)
        if fi_lo < inst.shape[1]:
            ifreq = (1.0 - alpha) * inst[:, fi_lo]
            if fi_hi < inst.shape[1]:
                ifreq += alpha * inst[:, fi_hi]
            ph_acc += ifreq
        else:
            ph_acc += omega

    out = _pv_inverse_stft(Sout, hop, target_len)

    # Preserve the source's overall RMS through alignment. Phase-vocoder OLA
    # can otherwise lose several dB at larger stretch factors, making the
    # morph trajectory drift in loudness for reasons unrelated to timbre.
    rms_in = float(np.sqrt(np.mean(x.astype(np.float64) ** 2) + 1e-30))
    rms_out = float(np.sqrt(np.mean(out.astype(np.float64) ** 2) + 1e-30))
    if rms_in > 1e-12 and rms_out > 1e-12:
        out = (out * (rms_in / rms_out)).astype(np.float32)
    return out


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
    Estimate spectral envelope via real cepstrum liftering (minimum-phase).
    Returns a smooth envelope of the same length as mag.
    """
    import numpy as np
    log_mag = np.log(mag + 1e-8)
    cep = np.fft.irfft(log_mag)  # real cepstrum
    # lifter: keep only low quefrency, asymmetric for minimum-phase envelope
    win = np.zeros_like(cep)
    win[0] = 1.0
    win[1:order] = 2.0
    env_log = np.fft.rfft(cep * win).real
    return np.exp(env_log).astype(np.float32)



def _circular_phase_interp(a, b, w):
    """Shortest-path circular interpolation between phase arrays."""
    import numpy as np
    w = float(max(0.0, min(1.0, w)))
    delta = np.angle(np.exp(1j * (b.astype(np.float64) - a.astype(np.float64))))
    return (a.astype(np.float64) + w * delta).astype(np.float32)


def spectral_transport_magnitude(mag_a, mag_b, m):
    """Displacement interpolation of spectra along log frequency.

    This is a 1-D monotone optimal-transport coupling of positive-frequency
    magnitude mass. Because the coupling is monotone, harmonic energy does not
    randomly cross in frequency. Each coupled mass element moves on a
    log-frequency path, which is perceptually appropriate for pitch:
        f(m) = f_A ** (1-m) * f_B ** m

    Magnitude is deposited between neighbouring FFT bins, then globally
    rescaled to the geometric interpolation of the two spectral L2 norms.
    Endpoints are exact in magnitude (m=0 -> A, m=1 -> B).
    """
    import numpy as np

    m = float(max(0.0, min(1.0, m)))
    a = np.asarray(mag_a, dtype=np.float64)
    b = np.asarray(mag_b, dtype=np.float64)
    if len(a) != len(b):
        raise ValueError("spectral transport requires equal FFT grids")
    if m <= 1e-12:
        return a.astype(np.float32, copy=True)
    if m >= 1.0 - 1e-12:
        return b.astype(np.float32, copy=True)

    n = len(a)
    out = np.zeros(n, dtype=np.float64)

    # DC has no meaningful log-frequency coordinate.
    out[0] = (1.0 - m) * a[0] + m * b[0]
    if n <= 1:
        return out.astype(np.float32)

    aa = np.maximum(a[1:], 0.0)
    bb = np.maximum(b[1:], 0.0)
    sum_a = float(aa.sum())
    sum_b = float(bb.sum())

    # If either spectrum is effectively silent, transport has no target/source
    # distribution. A linear magnitude bridge is the continuous safe fallback.
    if sum_a <= 1e-20 or sum_b <= 1e-20:
        return ((1.0 - m) * a + m * b).astype(np.float32)

    pa = aa / sum_a
    pb = bb / sum_b
    total_mass = math.exp(
        (1.0 - m) * math.log(sum_a + 1e-30)
        + m * math.log(sum_b + 1e-30)
    )

    # Monotone 1-D transport coupling (two-pointer CDF matching).
    i = 0
    j = 0
    rem_a = float(pa[0])
    rem_b = float(pb[0])
    na = len(pa)
    nb = len(pb)

    while i < na and j < nb:
        mass = rem_a if rem_a < rem_b else rem_b
        if mass > 0.0:
            # Positive-frequency FFT bins are 1..N. Since bin frequency is
            # proportional to bin index, log-frequency interpolation can be
            # performed directly on the positive bin numbers.
            bin_a = float(i + 1)
            bin_b = float(j + 1)
            pos = math.exp(
                (1.0 - m) * math.log(bin_a) + m * math.log(bin_b)
            )
            k0 = int(math.floor(pos))
            frac = pos - k0
            amp = mass * total_mass

            if 0 <= k0 < n:
                out[k0] += amp * (1.0 - frac)
            if frac > 0.0 and 0 <= k0 + 1 < n:
                out[k0 + 1] += amp * frac

        rem_a -= mass
        rem_b -= mass

        if rem_a <= 1e-15:
            i += 1
            if i < na:
                rem_a = float(pa[i])
        if rem_b <= 1e-15:
            j += 1
            if j < nb:
                rem_b = float(pb[j])

    # Keep frame energy on a smooth path. Classic fixed-bin geometric
    # interpolation can collapse badly when A and B occupy different bins;
    # this L2 target avoids that perceptual "hole" without normalising upward
    # to an arbitrary fixed peak.
    norm_a = float(np.linalg.norm(a))
    norm_b = float(np.linalg.norm(b))
    desired = math.exp(
        (1.0 - m) * math.log(norm_a + 1e-30)
        + m * math.log(norm_b + 1e-30)
    )
    norm_out = float(np.linalg.norm(out))
    if norm_out > 1e-20:
        out *= desired / norm_out

    return np.maximum(out, 0.0).astype(np.float32)



# ---------------------------------------------------------------- main morph -

def align_lengths(a, b, length_mode):
    """
    Make a and b the same length according to length_mode.

    length_mode = 1: silence-pad shorter to match longer.
                  No pitch change, but if target B is shorter the legacy
                  endpoint guard can audibly return toward A.
    length_mode = 2: trim longer to match shorter. Both signals active
                  throughout; loses content from the longer one.
    length_mode = 3 (legacy v4.x): linear time-stretch shorter to match longer.
                  Pitches the shorter signal because linear time-domain
                  interpolation is a crude resample. Retained for users
                  who relied on this behavior in v4.x.
    length_mode = 4: handled before this function with phase-vocoder alignment.
    """
    import numpy as np

    if length_mode == 2:
        # Trim longer to match shorter
        len_out = min(len(a), len(b))
        a = a[:len_out]
        b = b[:len_out]
    elif length_mode == 3:
        # v4.x legacy: linear time-stretch
        len_out = max(len(a), len(b))
        a = resample_linear(a, len_out)
        b = resample_linear(b, len_out)
    else:
        # length_mode == 1 (default): silence-pad
        len_out = max(len(a), len(b))
        if len(a) < len_out:
            a = np.concatenate(
                [a, np.zeros(len_out - len(a), dtype=np.float32)])
        if len(b) < len_out:
            b = np.concatenate(
                [b, np.zeros(len_out - len(b), dtype=np.float32)])

    return a, b


def spectral_morph_channel(a, b, sr, window_s, start_morph_s, end_morph_s,
                           morph_mode, curve_type, mix_amount=0.5,
                           length_mode=1, debug_log=None):
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
        1=energy-stable log-magnitude, 2=full-complex, 3=formant/envelope,
        4=continuous spectral trajectory.
    curve_type : int
        1=linear, 2=cosine, 3=full-mix.
    mix_amount : float
        Fixed blend ratio for curve_type 3.
    length_mode : int
        1=silence-pad, 2=trim, 3=legacy resample,
        4=phase-vocoder align (recommended).
    debug_log : list or None
        If a list is passed, per-frame debug rows are appended to it.

    Returns
    -------
    np.ndarray
        Morphed signal (float32).
    """
    import numpy as np

    wsize = next_pow2(int(window_s * sr))
    wsize = max(wsize, 64)
    hop = wsize // 4

    # Preserve original lengths before alignment.
    orig_len_a = len(a)
    orig_len_b = len(b)

    # v5.7: recommended pitch-preserving alignment. Both sources span the
    # complete output timeline, so an earlier endpoint cannot trigger a return
    # to the other source. Existing modes 1-3 remain unchanged.
    if length_mode == 4:
        len_out = max(orig_len_a, orig_len_b)
        if orig_len_a < len_out:
            print("    PV-align A: %.3f s -> %.3f s (x%.3f, pitch-preserving)" %
                  (orig_len_a / float(sr), len_out / float(sr),
                   len_out / float(max(1, orig_len_a))))
            a = phase_vocoder_align_to_length(a, len_out, wsize)
        if orig_len_b < len_out:
            print("    PV-align B: %.3f s -> %.3f s (x%.3f, pitch-preserving)" %
                  (orig_len_b / float(sr), len_out / float(sr),
                   len_out / float(max(1, orig_len_b))))
            b = phase_vocoder_align_to_length(b, len_out, wsize)
    else:
        a, b = align_lengths(a, b, length_mode)
        len_out = len(a)

    win = hann(wsize)
    win_sq = win ** 2

    # v5.5: silence factors are tied to ARTIFICIAL padding boundaries.
    # For trim/time-stretch there is no artificial silence boundary, so both
    # boundaries equal len_out and the differential guard remains inactive.
    if length_mode == 1:
        boundary_a = min(orig_len_a, len_out)
        boundary_b = min(orig_len_b, len_out)
    else:
        # Trim, legacy stretch and v5.7 PV-align all have coextensive sources.
        boundary_a = len_out
        boundary_b = len_out
    boundary_a_pad = boundary_a + wsize // 2
    boundary_b_pad = boundary_b + wsize // 2

    # OLA buffers
    norm = np.zeros(len_out + wsize * 2, dtype=np.float32)
    y = np.zeros(len_out + wsize * 2, dtype=np.float32)

    a_pad = np.pad(a, (wsize // 2, wsize), mode="constant")
    b_pad = np.pad(b, (wsize // 2, wsize), mode="constant")

    nan_warned = False

    # v5.6 mode-4 phase state. Each FFT bin advances coherently at its own
    # center frequency. Energy can therefore travel between bins without the
    # frame-to-frame random/borrowed phase jumps that make a morph sound like
    # alternating crossfades.
    transport_phase = None
    transport_phase_advance = (
        2.0 * np.pi * np.arange(wsize // 2 + 1, dtype=np.float64) * hop / wsize
    )

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

        # v5.4: shifted silence-factor ramp ending AT the boundary.
        # v5.3 centered the ramp on the boundary (sil=0.5 at boundary,
        # sil=0 a half-window before, sil=1 a half-window after). The
        # b_sil ramp in Sha's cello/horn debug CSV worked correctly,
        # but the audible "jump" came from a different mechanism:
        # log-magnitude morph in mode 1 heavily attenuates output
        # THROUGHOUT the morph when the two inputs have different
        # spectra (geometric mean of bin_X cello and bin_X horn is
        # small whenever one has energy and the other doesn't).
        # Sha's debug showed out_rms ~ 0.022 during the morph while
        # A's RMS was ~ 0.23. When the v5.3 blend kicked in AT the
        # silence boundary, output had to climb from 0.022 to 0.345
        # (full A) over a half-window -- audibly a sudden onset.
        #
        # v5.4: end the ramp AT the boundary instead of centering
        # on it, with pre_ramp = 2 * wsize. As the OTHER signal
        # naturally fades toward its silence-pad boundary, the blend
        # gradually replaces the attenuated morph with direct A,
        # smoothing the amplitude rise over ~ 2 * wsize / sr seconds
        # (~ 186 ms at default 60 ms window). By the time the silence
        # boundary is actually reached, output is already at direct-A
        # level -- no jump.
        #
        # For same-duration inputs both boundaries equal len_out, so
        # both a_sil and b_sil ramp together over the final 2*wsize
        # frames. delta = 0 throughout, w_morph = 1 in the differential
        # blend, output is bit-identical to v5.0 (verified by smoke test).
        center = in_pos + wsize // 2
        pre_ramp = 2 * wsize

        def sil_from_boundary(bnd_pad):
            if center >= bnd_pad:
                return 1.0
            if center + pre_ramp <= bnd_pad:
                return 0.0
            return 1.0 - (bnd_pad - center) / float(pre_ramp)

        if length_mode == 1:
            a_sil = sil_from_boundary(boundary_a_pad)
            b_sil = sil_from_boundary(boundary_b_pad)
        else:
            # No artificial padding boundary exists in trim, legacy stretch or
            # PV-align modes. Keep diagnostics semantically honest and the
            # differential endpoint guard fully inactive.
            a_sil = 0.0
            b_sil = 0.0

        # v5.3: DIFFERENTIAL blend weights. Earlier (v5.2 multiplicative)
        # formulation (1-a_sil)(1-b_sil) etc. activated whenever EITHER
        # input was past its boundary, which for same-duration inputs
        # caused the last few frames (where both windows extend into
        # right-padding zeros) to receive blend weights summing to less
        # than 1 -- output differed from the unguarded morph there.
        #
        # Differential: blend only when one input is MORE silent than
        # the other. delta = b_sil - a_sil. delta > 0 means B is more
        # silent (e.g., B was silence-padded and A wasn't) -> blend
        # toward A. delta < 0 means A is more silent -> blend toward B.
        # delta = 0 means both equally silent (or both fully present)
        # -> just use the morph as-is. Same-duration inputs (boundaries
        # equal) -> delta = 0 everywhere -> bit-identical to v5.0.
        delta = b_sil - a_sil
        if delta > 0:
            w_morph    = 1.0 - delta
            w_a_direct = delta
            w_b_direct = 0.0
        elif delta < 0:
            w_morph    = 1.0 + delta
            w_a_direct = 0.0
            w_b_direct = -delta
        else:
            w_morph    = 1.0
            w_a_direct = 0.0
            w_b_direct = 0.0

        if morph_mode == 1:
            # --- energy-stable log-magnitude interpolation, keep A phase ---
            log_a = np.log(mag_a + 1e-8)
            log_b = np.log(mag_b + 1e-8)
            mag_morph = np.exp((1 - m) * log_a + m * log_b)

            # v5.7: geometric fixed-bin interpolation can collapse in level when
            # A and B occupy different bins. Preserve the interpolated spectral
            # L2 energy while leaving the geometric spectral shape intact.
            norm_a = float(np.linalg.norm(mag_a))
            norm_b = float(np.linalg.norm(mag_b))
            desired_norm = math.exp(
                (1.0 - m) * math.log(norm_a + 1e-30)
                + m * math.log(norm_b + 1e-30)
            )
            actual_norm = float(np.linalg.norm(mag_morph))
            if actual_norm > 1e-20:
                mag_morph = mag_morph * (desired_norm / actual_norm)

            mag_out = (w_morph * mag_morph
                       + w_a_direct * mag_a
                       + w_b_direct * mag_b)

            # Phase: keep A's phase unless A is MORE silent than B
            # (asymmetric — same-duration boundaries give delta=0 -> pha_a,
            # preserving v5.0 mode 1 "keep A phase" behavior bit-exactly).
            if delta < 0:
                pha_out = pha_b
            else:
                pha_out = pha_a

        elif morph_mode == 2:
            # --- full complex interpolation ---
            # Linear magnitude interp already handles silence smoothly
            # (mag_out = m * mag_b when mag_a = 0). No guard needed.
            mag_out = (1 - m) * mag_a + m * mag_b
            pha_out = pha_a + m * np.angle(
                np.exp(1j * (pha_b - pha_a).astype(np.float64))
            ).astype(np.float32)

        elif morph_mode == 3:
            # --- spectral envelope / formant morph (CDP-style) ---
            env_a = spectral_envelope(mag_a)
            env_b = spectral_envelope(mag_b)
            fine_a = mag_a / (env_a + 1e-8)

            log_env_a = np.log(env_a + 1e-8)
            log_env_b = np.log(env_b + 1e-8)
            env_out = np.exp((1 - m) * log_env_a + m * log_env_b)
            mag_morph = fine_a * env_out

            # Same differential blend as mode 1 (weights computed above)
            mag_out = (w_morph * mag_morph
                       + w_a_direct * mag_a
                       + w_b_direct * mag_b)

            if delta < 0:
                pha_out = pha_b
            else:
                pha_out = pha_a

        else:
            # --- v5.6 continuous spectral trajectory ---
            # Move spectral magnitude MASS through log frequency instead of
            # changing only the amplitudes of stationary FFT bins.
            mag_morph = spectral_transport_magnitude(mag_a, mag_b, m)
            mag_out = mag_morph.copy()

            if transport_phase is None:
                transport_phase = pha_a.astype(np.float64).copy()
            else:
                transport_phase = (
                    transport_phase + transport_phase_advance + np.pi
                ) % (2.0 * np.pi) - np.pi

            phase_transport = transport_phase.astype(np.float32)

            # Anchor the trajectory to the real endpoint phases over the first
            # and last 8% of the morph. This keeps m=0 audibly A and m=1 audibly
            # B while retaining phase coherence through the central trajectory.
            edge = 0.08
            if m <= 0.0:
                pha_out = pha_a
            elif m < edge:
                u_edge = m / edge
                u_edge = 0.5 - 0.5 * math.cos(math.pi * u_edge)
                pha_out = _circular_phase_interp(pha_a, phase_transport, u_edge)
            elif m > 1.0 - edge:
                u_edge = (m - (1.0 - edge)) / edge
                u_edge = 0.5 - 0.5 * math.cos(math.pi * u_edge)
                pha_out = _circular_phase_interp(phase_transport, pha_b, u_edge)
            elif m >= 1.0:
                pha_out = pha_b
            else:
                pha_out = phase_transport

            # Silence-pad behaviour should stay musically safe. If one source
            # is artificially absent, the existing differential guard fades
            # toward the surviving direct spectrum rather than transporting
            # spectral mass into or out of mathematical silence.
            if abs(delta) > 1e-12:
                mag_out = (w_morph * mag_out
                           + w_a_direct * mag_a
                           + w_b_direct * mag_b)
                if delta < 0:
                    pha_out = _circular_phase_interp(
                        pha_out, pha_b, min(1.0, -delta)
                    )
                else:
                    pha_out = _circular_phase_interp(
                        pha_out, pha_a, min(1.0, delta)
                    )

        # v5.3: numerical safety. Catch any NaN/Inf that the log/exp
        # arithmetic might have produced. nan_to_num replaces in place.
        if not np.all(np.isfinite(mag_out)):
            if debug_log is not None and not nan_warned:
                bad_mag = int(np.sum(~np.isfinite(mag_out)))
                print(f"  WARN: frame {frame_idx} has {bad_mag} non-finite mag_out values "
                      f"(further warnings suppressed)")
                nan_warned = True
            mag_out = np.nan_to_num(mag_out, nan=0.0, posinf=0.0, neginf=0.0)
        if not np.all(np.isfinite(pha_out)):
            pha_out = np.nan_to_num(pha_out, nan=0.0, posinf=0.0, neginf=0.0)

        # v5.3: debug capture. Append a row of per-frame state to the
        # caller-provided log list. Captures the silence factors, blend
        # weights, mean magnitudes of all the spectra in play, and a
        # peak/rms read of the windowed time-domain frame contribution.
        if debug_log is not None:
            frame_center_s = (in_pos + wsize / 2 - wsize // 2) / sr
            a_rms_td = float(np.sqrt(np.mean(fa.astype(np.float64) ** 2)))
            b_rms_td = float(np.sqrt(np.mean(fb.astype(np.float64) ** 2)))
            row = {
                "frame": frame_idx,
                "time_s": frame_center_s,
                "m": m,
                "a_rms_td": a_rms_td,
                "b_rms_td": b_rms_td,
                "a_mag_mean": float(mag_a.mean()),
                "b_mag_mean": float(mag_b.mean()),
                "a_sil": a_sil,
                "b_sil": b_sil,
                "mag_out_mean": float(mag_out.mean()),
                "mag_out_peak": float(mag_out.max()) if mag_out.size > 0 else 0.0,
            }
            if morph_mode in (1, 3, 4):
                # v5.5: report the ACTUAL differential weights used above.
                row["w_morph"] = w_morph
                row["w_a_direct"] = w_a_direct
                row["w_b_direct"] = w_b_direct
                row["mag_morph_mean"] = (
                    float(mag_morph.mean()) if "mag_morph" in locals() else 0.0
                )
            else:
                row["w_morph"] = 1.0
                row["w_a_direct"] = 0.0
                row["w_b_direct"] = 0.0
                row["mag_morph_mean"] = float(mag_out.mean())
            debug_log.append(row)

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

    # v5.5: no per-channel peak scaling here.  Multichannel peak safety is
    # applied once after channels are stacked, preserving their level balance.
    return y.astype(np.float32)


def spectral_morph(audio_a, audio_b, sr, window_s, start_morph_s,
                   end_morph_s, morph_mode, curve_type, mix_amount=0.5,
                   length_mode=1, debug_log=None):
    """Handle mono or multichannel audio (process each channel).
    If debug_log is provided, capture the strongest combined A/B channel
    so diagnostics remain meaningful even when channel 1 is weak or silent."""
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

    debug_ch = 0
    if debug_log is not None and n_ch > 1:
        combined_rms = []
        for ch in range(n_ch):
            ra = float(np.sqrt(np.mean(chs_a[ch].astype(np.float64) ** 2)))
            rb = float(np.sqrt(np.mean(chs_b[ch].astype(np.float64) ** 2)))
            combined_rms.append(ra + rb)
        debug_ch = int(np.argmax(combined_rms))

    out_chs = []
    for ch in range(n_ch):
        print(f"  Processing channel {ch + 1}/{n_ch}...")
        log_for_this_ch = debug_log if ch == debug_ch else None
        before_rows = len(debug_log) if log_for_this_ch is not None else 0
        out_chs.append(spectral_morph_channel(
            chs_a[ch].astype(np.float32),
            chs_b[ch].astype(np.float32),
            sr, window_s, start_morph_s, end_morph_s,
            morph_mode, curve_type, mix_amount, length_mode,
            log_for_this_ch,
        ))
        if log_for_this_ch is not None:
            for row in debug_log[before_rows:]:
                row["channel"] = debug_ch + 1

    if n_ch == 1:
        result = out_chs[0].astype(np.float32, copy=False)
    else:
        max_len = max(len(c) for c in out_chs)
        result = np.zeros((max_len, n_ch), dtype=np.float32)
        for i, c in enumerate(out_chs):
            result[:len(c), i] = c

    # v5.5: attenuation-only GLOBAL peak safety.  One scalar preserves
    # inter-channel balance; quiet material is never normalised upward.
    peak = float(np.max(np.abs(result))) if result.size else 0.0
    if peak > 0.99:
        result = (result * (0.99 / peak)).astype(np.float32)

    return result


# --------------------------------------------------------------------- CLI --

def main():
    if len(sys.argv) not in (9, 10, 11, 12):
        print("Usage: python spectral_morph.py soundA.wav soundB.wav output.wav "
              "window_s start_morph_s end_morph_s morph_mode curve_type "
              "[mix_amount] [length_mode] [debug]")
        print("  morph_mode:  1=log-mag  2=full-complex  3=formant/envelope  4=continuous-trajectory")
        print("  curve_type:  1=linear   2=cosine   3=full-mix (needs mix_amount 0-1)")
        print("  length_mode: 1=silence-pad  2=trim  3=legacy resample  4=PV align (recommended)")
        print("  debug:       0=off (default)  1=write per-frame CSV next to output")
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
    mix_amount = float(sys.argv[9]) if len(sys.argv) >= 10 else 0.5
    length_mode = int(sys.argv[10]) if len(sys.argv) >= 11 else 1
    debug_on = int(sys.argv[11]) if len(sys.argv) >= 12 else 0

    # Validate input files
    for path, label in [(in_a, "A"), (in_b, "B")]:
        if not os.path.isfile(path):
            print(f"ERROR: Input file {label} not found: {path}",
                  file=sys.stderr)
            sys.exit(1)

    # Validate parameters
    if morph_mode not in (1, 2, 3, 4):
        print("ERROR: morph_mode must be 1, 2, 3, or 4", file=sys.stderr)
        sys.exit(1)
    if curve_type not in (1, 2, 3):
        print("ERROR: curve_type must be 1, 2, or 3", file=sys.stderr)
        sys.exit(1)
    if length_mode not in (1, 2, 3, 4):
        print("ERROR: length_mode must be 1, 2, 3, or 4", file=sys.stderr)
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
    # v5.0: exact gcd-based integer ratio instead of
    # Fraction(...).limit_denominator(100). The old code returned coarse
    # rationals (e.g. 11/12 instead of 160/147 for 44100<->48000), which
    # introduced a small pitch shift on B.
    if sr_b != sr_a:
        print(f"  Resampling B from {sr_b} to {sr_a} Hz...")
        try:
            from scipy.signal import resample_poly
            from math import gcd
            g = gcd(sr_a, sr_b)
            L = sr_a // g  # upsample factor
            M = sr_b // g  # downsample factor
            print(f"    Resample ratio: {L}/{M}  (exact)")
            if audio_b.ndim == 1:
                audio_b = resample_poly(audio_b, L, M).astype(np.float32)
            else:
                audio_b = np.stack([
                    resample_poly(audio_b[:, ch], L, M).astype(np.float32)
                    for ch in range(audio_b.shape[1])
                ], axis=1)
        except ImportError:
            print("ERROR: scipy required for sample rate conversion "
                  "(pip install scipy)", file=sys.stderr)
            sys.exit(1)

    audio_a = np.asarray(audio_a, dtype=np.float32)
    audio_b = np.asarray(audio_b, dtype=np.float32)

    mode_names = {1: "log-magnitude", 2: "full-complex", 3: "formant/envelope",
                  4: "continuous spectral trajectory"}
    curve_names = {1: "linear", 2: "cosine", 3: f"full-mix({mix_amount:.2f})"}
    length_names = {1: "silence-pad", 2: "trim-to-shorter",
                    3: "time-stretch (v4.x legacy)",
                    4: "phase-vocoder align"}
    effective_wsize = max(next_pow2(int(window_s * sr_a)), 64)
    effective_ms = 1000.0 * effective_wsize / sr_a
    print(f"  Mode: {mode_names.get(morph_mode, '?')} | "
          f"Curve: {curve_names.get(curve_type, '?')} | "
          f"Window requested: {window_s*1000:.1f} ms | "
          f"FFT: {effective_wsize} samples ({effective_ms:.1f} ms)")
    print(f"  Length handling: {length_names.get(length_mode, '?')}")

    debug_log = [] if debug_on else None

    out = spectral_morph(audio_a, audio_b, sr_a,
                         window_s, start_s, end_s,
                         morph_mode, curve_type, mix_amount, length_mode,
                         debug_log=debug_log)

    sf.write(out_wav, out, sr_a, subtype="FLOAT")
    dur_out = len(out) / sr_a if out.ndim == 1 else len(out) / sr_a
    print(f"OK: wrote {out_wav}  ({dur_out:.2f}s)")

    # ------------------------------------------------------------------
    # Debug: write per-frame CSV next to the output WAV and print a
    # short summary around any silence-boundary transitions.
    # ------------------------------------------------------------------
    if debug_log:
        import csv
        debug_path = os.path.splitext(out_wav)[0] + "_debug.csv"
        # Compute final OLA-normalised output amplitude at each frame's
        # center so the CSV shows what the user will actually hear there.
        # Sample the final `out` array at frame centers.
        wsize_dbg = next_pow2(int(window_s * sr_a))
        wsize_dbg = max(wsize_dbg, 64)
        hop_dbg = wsize_dbg // 4
        debug_ch = int(debug_log[0].get("channel", 1)) - 1
        out_mono = out if out.ndim == 1 else out[:, min(debug_ch, out.shape[1] - 1)]
        for row in debug_log:
            center_smp = int(row["time_s"] * sr_a)
            lo = max(0, center_smp - hop_dbg // 2)
            hi = min(len(out_mono), center_smp + hop_dbg // 2)
            if hi > lo:
                seg = out_mono[lo:hi].astype(np.float64)
                row["out_rms"] = float(np.sqrt(np.mean(seg ** 2)))
                row["out_peak"] = float(np.max(np.abs(seg)))
            else:
                row["out_rms"] = 0.0
                row["out_peak"] = 0.0

        fieldnames = ["frame", "channel", "time_s", "m",
                      "a_rms_td", "b_rms_td",
                      "a_mag_mean", "b_mag_mean",
                      "a_sil", "b_sil",
                      "w_morph", "w_a_direct", "w_b_direct",
                      "mag_morph_mean", "mag_out_mean", "mag_out_peak",
                      "out_rms", "out_peak"]
        with open(debug_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames,
                                    extrasaction="ignore")
            writer.writeheader()
            writer.writerows(debug_log)
        print(f"DEBUG: per-frame log -> {debug_path}")

        # Detect silence-boundary frames (where b_sil or a_sil crosses 0.5)
        # and print a focused summary so user doesn't have to open CSV.
        def find_crossings(key):
            crossings = []
            for i in range(1, len(debug_log)):
                prev = debug_log[i - 1][key]
                curr = debug_log[i][key]
                if (prev < 0.5 and curr >= 0.5) or (prev >= 0.5 and curr < 0.5):
                    crossings.append(i)
            return crossings

        for sil_key, label in [("b_sil", "B"), ("a_sil", "A")]:
            crossings = find_crossings(sil_key)
            for cx in crossings:
                print(f"\nDEBUG: {label} silence-factor 0.5 crossing near "
                      f"t={debug_log[cx]['time_s']:.3f}s (frame {cx})")
                print(f"  {'time_s':>7} {'m':>6} {'a_rms':>8} {'b_rms':>8} "
                      f"{'a_sil':>6} {'b_sil':>6} {'w_m':>6} {'w_a':>6} {'w_b':>6} "
                      f"{'out_rms':>8}")
                lo = max(0, cx - 5)
                hi = min(len(debug_log), cx + 6)
                for j in range(lo, hi):
                    d = debug_log[j]
                    marker = " <-" if j == cx else "   "
                    print(f"  {d['time_s']:7.3f} {d['m']:6.3f} "
                          f"{d['a_rms_td']:8.5f} {d['b_rms_td']:8.5f} "
                          f"{d['a_sil']:6.3f} {d['b_sil']:6.3f} "
                          f"{d.get('w_morph', 1.0):6.3f} "
                          f"{d.get('w_a_direct', 0.0):6.3f} "
                          f"{d.get('w_b_direct', 0.0):6.3f} "
                          f"{d['out_rms']:8.5f}{marker}")


if __name__ == "__main__":
    main()
